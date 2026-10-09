import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart' hide ActivityType;
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';

import 'tracking_models.dart';

enum TrackingStatus { idle, running, paused }

class TrackingController extends ChangeNotifier {
  TrackingStatus status = TrackingStatus.idle;
  ActivityType type = ActivityType.run;

  // Una lista de tramos: cada pausa crea un tramo nuevo para no unir
  // con una línea recta el punto donde pausaste con el de reanudar.
  final List<List<LatLng>> segments = [];
  final List<TrackPoint> points = [];
  double distanceMeters = 0;
  // Solo para pruebas en interiores. Poner en false antes del APK final.
  static const bool debugRelaxed = true;
  double? lastAccuracy;
  int discarded = 0;
  /// Hasta aqui se borra. Para el apk final.
  double elevationGain = 0;
  LatLng? currentPosition;
  DateTime? startedAt;

  final Stopwatch _stopwatch = Stopwatch();
  Timer? _ticker;
  StreamSubscription<Position>? _sub;
  TrackPoint? _last;
  double _refAlt = 0;

  Duration get elapsed => _stopwatch.elapsed;

  double get avgSpeedKmh => elapsed.inSeconds > 0
      ? (distanceMeters / 1000) / (elapsed.inSeconds / 3600)
      : 0;

  /// Segundos por kilómetro (null hasta tener algo de distancia)
  double? get paceSecPerKm =>
      distanceMeters > 50 ? elapsed.inSeconds / (distanceMeters / 1000) : null;

  void setType(ActivityType t) {
    type = t;
    notifyListeners();
  }

  /// Ubica al usuario una vez (para centrar el mapa antes de empezar)
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
    distanceMeters = 0;
    elevationGain = 0;
    startedAt = DateTime.now();
    _stopwatch
      ..reset()
      ..start();
    status = TrackingStatus.running;
    _listen();
    _startTicker();
    notifyListeners();
    return null;
  }

  void pause() {
    _stopwatch.stop();
    _sub?.cancel();
    _sub = null;
    _ticker?.cancel();
    status = TrackingStatus.paused;
    notifyListeners();
  }

  void resume() {
    segments.add([]);
    _stopwatch.start();
    status = TrackingStatus.running;
    _listen();
    _startTicker();
    notifyListeners();
  }

  ActivityResult finish() {
    _stopwatch.stop();
    _sub?.cancel();
    _sub = null;
    _ticker?.cancel();
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

  void _startTicker() {
    _ticker?.cancel();
    // Redibuja cada segundo para que el cronómetro avance
    _ticker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => notifyListeners(),
    );
  }

  void _listen() {
    _last = null; // el primer punto tras iniciar/reanudar es solo referencia
    _sub?.cancel();
    _sub = Geolocator.getPositionStream(locationSettings: _settings)
        .listen(_onPosition, onError: (_) {});
  }

  LocationSettings get _settings => AndroidSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: debugRelaxed ? 0 : 5, // metros mínimos entre actualizaciones
    intervalDuration: const Duration(seconds: 2),
    foregroundNotificationConfig: const ForegroundNotificationConfig(
      notificationTitle: 'BiciCrew',
      notificationText: 'Registrando tu actividad…',
      notificationChannelName: 'Registro de actividad',
      enableWakeLock: true,
    ),
  );

  void _onPosition(Position p) {
    currentPosition = LatLng(p.latitude, p.longitude);
    lastAccuracy = p.accuracy;
    if (status != TrackingStatus.running) {
      notifyListeners();
      return;
    }
    // Filtro 1: descartar puntos poco precisos
    if (p.accuracy > (debugRelaxed ? 100 : 30)) {
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
        last.lat,
        last.lng,
        p.latitude,
        p.longitude,
      );
      final dt = p.timestamp.difference(last.time).inMilliseconds / 1000;
      // Filtro 2: descartar saltos imposibles (> 25 m/s = 90 km/h)
      if (dt > 0 && d / dt > 25) return;
      distanceMeters += d;

      // Desnivel: solo cuenta cambios de 3 m o más (el GPS "tiembla")
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
    _sub?.cancel();
    _ticker?.cancel();
    super.dispose();
  }
}
