import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/supabase_config.dart';
import 'activity_repository.dart';
import 'dart:math';

/// Sube a Supabase las actividades guardadas en el celular.
class SyncService {
  SyncService._();
  static final SyncService instance = SyncService._();

  final _repo = ActivityRepository.instance;

  /// true mientras se está sincronizando
  final ValueNotifier<bool> syncing = ValueNotifier(false);

  /// Aumenta al terminar cada sincronización (las listas lo escuchan para refrescarse)
  final ValueNotifier<int> version = ValueNotifier(0);

  StreamSubscription<List<ConnectivityResult>>? _connSub;
  bool _running = false;
  bool _restoring = false;

  /// Descarga de Supabase las actividades que no están en este celular
  /// (por ejemplo, tras reinstalar la app). Devuelve cuántas recuperó.
  Future<int> restoreFromServer() async {
    final user = supabase.auth.currentUser;
    if (user == null || _restoring) return 0;
    _restoring = true;
    var restored = 0;
    try {
      // 1) Solo los ids: es una consulta liviana
      final rows = await supabase
          .from('activities')
          .select('id')
          .eq('user_id', user.id)
          .order('started_at', ascending: false)
          .limit(500);
      final local = await _repo.localIds(user.id);
      final missing = rows
          .map((r) => r['id'] as String)
          .where((id) => !local.contains(id))
          .toList();

      // 2) Las que faltan, de 10 en 10 (cada una trae sus puntos GPS)
      for (var i = 0; i < missing.length; i += 10) {
        final chunk = missing.sublist(i, min(i + 10, missing.length));
        final data = await supabase
            .from('activities')
            .select('id, type, started_at, ended_at, duration_seconds, '
                'distance_meters, elevation_gain_meters, points')
            .inFilter('id', chunk);
        for (final a in data) {
          await _repo.insertFromServer(user.id, a);
          restored++;
        }
      }
    } catch (_) {
      // Sin red: se reintentará al abrir la app o cuando vuelva la conexión
    } finally {
      _restoring = false;
      if (restored > 0) version.value++; // el historial se refresca solo
    }
    return restored;
  }

  /// Llamar una vez con sesión iniciada. Es seguro llamarlo varias veces.
  /// Llamar una vez con sesión iniciada. Es seguro llamarlo varias veces.
  void start() {
    _connSub ??= Connectivity().onConnectivityChanged.listen((results) {
      // Volvió alguna red: sube lo pendiente y recupera lo que falte
      if (results.any((r) => r != ConnectivityResult.none)) {
        syncPending().then((_) => restoreFromServer());
      }
    });
    syncPending().then((_) => restoreFromServer());
  }

  /// Devuelve cuántas actividades se subieron en esta pasada.
  Future<int> syncPending() async {
    final user = supabase.auth.currentUser;
    if (user == null || _running) return 0;
    _running = true;
    syncing.value = true;
    var uploaded = 0;
    try {
      final pending = await _repo.pendingForSync(user.id);
      for (final a in pending) {
        try {
          final payload = await _buildPayload(a, user.id);
          if (payload == null) {
            await _repo.markError(a.id, 'La actividad no tiene puntos suficientes');
            continue;
          }
          // ignoreDuplicates: si el servidor ya tiene este id, no hace nada.
          // Así un reintento nunca duplica la actividad (RNF-16).
          await supabase
              .from('activities')
              .upsert(payload, onConflict: 'id', ignoreDuplicates: true);
          await _repo.markSynced(a.id);
          uploaded++;
        } on PostgrestException catch (e) {
          // El servidor respondió y rechazó: es un error real, se muestra
          await _repo.markError(a.id, e.message);
        } catch (_) {
          // Sin red / tiempo agotado: queda pendiente y se reintentará
          break;
        }
      }
    } finally {
      _running = false;
      syncing.value = false;
      version.value++;
    }
    return uploaded;
  }

  Future<Map<String, dynamic>?> _buildPayload(
      LocalActivity a, String userId) async {
    final rows = await _repo.pointsRaw(a.id);
    if (rows.length < 2) return null;

    double r6(num v) => (v * 1000000).round() / 1000000; // ~11 cm de resolución
    final route =
        rows.map((p) => '${r6(p['lng'] as num)} ${r6(p['lat'] as num)}').join(',');
    final ended =
        a.endedAt ?? a.startedAt.add(Duration(seconds: a.durationS));

    return {
      'id': a.id,
      'user_id': userId,
      'type': a.type.name,
      'started_at': a.startedAt.toUtc().toIso8601String(),
      'ended_at': ended.toUtc().toIso8601String(),
      'duration_seconds': a.durationS,
      'distance_meters': a.distanceM,
      'elevation_gain_meters': a.elevationM,
      // PostGIS: formato "SRID;LINESTRING(lng lat, lng lat, ...)"
      'route': 'SRID=4326;LINESTRING($route)',
      'points': rows
          .map((p) => [
                r6(p['lat'] as num),
                r6(p['lng'] as num),
                (p['alt'] as num).round(),
                (p['accuracy'] as num).round(),
                p['time'],
                p['segment'],
              ])
          .toList(),
    };
  }
}