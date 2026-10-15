import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart' hide ActivityType;
import 'package:geolocator_android/geolocator_android.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';
import 'tracking_models.dart';

enum TrackingStatus { idle, running, paused }

/// Solo para diagnóstico: distintas formas de pedirle posiciones al sistema.
enum StreamMode {
  normal('Normal'),
  noNotification('Sin notificación'),
  locationManager('LocationManager');

  final String label;
  const StreamMode(this.label);
}

class _Sample {
  final DateTime time;
  final double distance;
  const _Sample(this.time, this.distance);
}

class TrackingController extends ChangeNotifier {
  // Solo para diagnóstico y pruebas. False por defecto para despliegue final.
  static const bool debugRelaxed = false;

  static const double maxAccuracy = 25; // metros
  static const double minStepMeters = 5; // desplazamiento mínimo entre puntos

  static const _notification = ForegroundNotificationConfig(
    notificationTitle: 'BiciCrew',
    notificationText: 'Registrando tu actividad…',
    notificationChannelName: 'Registro de actividad',
    enableWakeLock: true,
  );

  TrackingStatus status = TrackingStatus.idle;
  ActivityType type = ActivityType.run;
  StreamMode streamMode = StreamMode.normal;

  final List<List<LatLng>> segments = [];
  final List<TrackPoint> points = [];
  double distanceMeters = 0;
  double elevationGain = 0;
  LatLng? currentPosition;
  DateTime? startedAt;

  // ---- Diagnóstico ----
  int streamEvents = 0;
  int pollEvents = 0;
  int discarded = 0;
  double? lastAccuracy;
  String? lastError;
  DateTime? _lastStreamAt;

  final Stopwatch _stopwatch = Stopwatch();
  Timer? _ticker;
  Timer? _poller;
  bool _polling = false;
  StreamSubscription<Position>? _sub;
  TrackPoint? _last;
  double _refAlt = 0;
  final List<_Sample> _window = []; // muestras de los últimos 30 s

  Duration get elapsed => _stopwatch.elapsed;

  double get avgSpeedKmh => elapsed.inSeconds > 0
      ? (distanceMeters / 1000) / (elapsed.inSeconds / 3600)
      : 0;

   /// Ritmo actual (s/km) con los últimos ~45 s de movimiento.
  double? get paceSecPerKm {
    if (_window.length < 2) return null;
    final first = _window.first;
    final last = _window.last;
    // Sin puntos nuevos hace 20 s: estás quieto, sin ritmo
    if (DateTime.now().difference(last.time).inSeconds > 20) return null;
    final dd = last.distance - first.distance;
    final dt = last.time.difference(first.time).inSeconds;
    if (dt < 15 || dd < 20) return null;
    return dt / (dd / 1000);
  }

  int? get secondsSinceStreamEvent => _lastStreamAt == null
      ? null
      : DateTime.now().difference(_lastStreamAt!).inSeconds;

  void setType(ActivityType t) {
    type = t;
    notifyListeners();
  }

  void setStreamMode(StreamMode m) {
    streamMode = m;
    notifyListeners();
  }

  Future<void> locateOnce() async {
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }
      if (!await Geolocator.isLocationServiceEnabled()) return;
      final p = await Geolocator.getCurrentPosition();
      currentPosition = LatLng(p.latitude, p.longitude);
      lastAccuracy = p.accuracy;
      notifyListeners();
    } catch (_) {}
  }

  /// Devuelve null si todo salió bien, o un mensaje de error.
  Future<String?> start() async {
    final error = await _ensurePermissions();
    if (error != null) return error;

    segments
      ..clear()
      ..add([]);
    points.clear();
    _window.clear();
    distanceMeters = 0;
    elevationGain = 0;
    streamEvents = 0;
    pollEvents = 0;
    discarded = 0;
    lastError = null;
    _lastStreamAt = null;
    startedAt = DateTime.now();
    _stopwatch
      ..reset()
      ..start();
    status = TrackingStatus.running;
    _listen();
    _startTicker();
    _startPoller();
    notifyListeners();
    return null;
  }

  void pause() {
    _stopwatch.stop();
    _stopSources();
    status = TrackingStatus.paused;
    notifyListeners();
  }

  void resume() {
    segments.add([]);
    _window.clear();
    _stopwatch.start();
    status = TrackingStatus.running;
    _listen();
    _startTicker();
    _startPoller();
    notifyListeners();
  }

  ActivityResult finish() {
    _stopwatch.stop();
    _stopSources();
    final result = ActivityResult(
      type: type,
      startedAt: startedAt ?? DateTime.now(),
      endedAt: DateTime.now(),
      duration: elapsed,
      distanceMeters: distanceMeters,
      elevationGain: elevationGain,
      segments: segments.map((s) => List<LatLng>.of(s)).toList(),
      points: List<TrackPoint>.of(points),
    );
    status = TrackingStatus.idle;
    notifyListeners();
    return result;
  }

  // ---------- Internos ----------

  void _stopSources() {
    _sub?.cancel();
    _sub = null;
    _ticker?.cancel();
    _poller?.cancel();
    _polling = false;
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker =
        Timer.periodic(const Duration(seconds: 1), (_) => notifyListeners());
  }

  void _listen() {
    _last = null; // el primer punto tras iniciar/reanudar es solo referencia
    _sub?.cancel();
    _sub = Geolocator.getPositionStream(locationSettings: _settings).listen(
      (p) {
        streamEvents++;
        _lastStreamAt = DateTime.now();
        _onPosition(p);
      },
      onError: (Object e) {
        lastError = e.toString();
        notifyListeners();
      },
    );
  }

  /// Respaldo: si el stream lleva más de 4 s sin entregar nada, pedimos la
  /// posición actual de forma directa. No lanza una consulta nueva si la
  /// anterior sigue pendiente.
  void _startPoller() {
    _poller?.cancel();
    _poller = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (status != TrackingStatus.running || _polling) return;
      final since = secondsSinceStreamEvent;
      if (since != null && since < 4) return; // el stream está vivo
      _polling = true;
      try {
        final p = await Geolocator.getCurrentPosition(
          locationSettings: AndroidSettings(
            accuracy: LocationAccuracy.best,
            timeLimit: const Duration(seconds: 5),
          ),
        );
        pollEvents++;
        _onPosition(p);
      } catch (e) {
        lastError = e.toString();
        notifyListeners();
      } finally {
        _polling = false;
      }
    });
  }

  LocationSettings get _settings {
    const interval = Duration(seconds: 2);
    final filter = debugRelaxed ? 0 : 5;
    switch (streamMode) {
      case StreamMode.noNotification:
        return AndroidSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: filter,
          intervalDuration: interval,
        );
      case StreamMode.locationManager:
        return AndroidSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: filter,
          intervalDuration: interval,
          forceLocationManager: true,
          foregroundNotificationConfig: _notification,
        );
      case StreamMode.normal:
        return AndroidSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: filter,
          intervalDuration: interval,
          foregroundNotificationConfig: _notification,
        );
    }
  }

  void _onPosition(Position p) {
    currentPosition = LatLng(p.latitude, p.longitude);
    lastAccuracy = p.accuracy;
    if (status != TrackingStatus.running) {
      notifyListeners();
      return;
    }
    // Filtro 1: descartar puntos poco precisos
    if (p.accuracy > maxAccuracy) {
      discarded++;
      notifyListeners();
      return;
    }

    final point = TrackPoint(
      lat: p.latitude,
      lng: p.longitude,
      alt: p.altitude,
      accuracy: p.accuracy,
      time: p.timestamp,
    );

    final last = _last;
    if (last != null) {
      final d = Geolocator.distanceBetween(
          last.lat, last.lng, p.latitude, p.longitude);
      // Filtro 2: ignorar movimientos pequeños (el GPS "tiembla" estando
      // quieto). No se actualiza _last, así el movimiento real se acumula
      // hasta superar el mínimo.
      if (d < minStepMeters) {
        notifyListeners();
        return;
      }
      final dt = p.timestamp.difference(last.time).inMilliseconds / 1000;
      // Filtro 3: descartar saltos imposibles (> 25 m/s = 90 km/h)
      if (dt > 0 && d / dt > 25) {
        discarded++;
        notifyListeners();
        return;
      }
      distanceMeters += d;

      if ((p.altitude - _refAlt).abs() >= 3) {
        if (p.altitude > _refAlt) elevationGain += p.altitude - _refAlt;
        _refAlt = p.altitude;
      }
    } else {
      _refAlt = p.altitude;
    }

    _last = point;
    points.add(point);
    segments.last.add(LatLng(p.latitude, p.longitude));

    _window.add(_Sample(p.timestamp, distanceMeters));
    _window.removeWhere(
        (s) => p.timestamp.difference(s.time).inSeconds > 45);
    notifyListeners();
  }

  Future<String?> _ensurePermissions() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return 'Activa el GPS (ubicación) de tu celular e inténtalo de nuevo.';
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied) {
      return 'Necesitamos el permiso de ubicación para registrar tu actividad.';
    }
    if (perm == LocationPermission.deniedForever) {
      return 'El permiso de ubicación está bloqueado. Actívalo en Ajustes → '
          'Apps → BiciCrew → Permisos.';
    }
    await Permission.notification.request();
    return null;
  }

  @override
  void dispose() {
    _stopSources();
    super.dispose();
  }
}