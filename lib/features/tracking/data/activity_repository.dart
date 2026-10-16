import 'package:latlong2/latlong.dart';
import 'package:sqflite/sqflite.dart';
import '../tracking_models.dart';
import 'local_db.dart';

/// Fila de una actividad guardada en el celular.
class LocalActivity {
  final String id;
  final ActivityType type;
  final String status; // recording | finished
  final DateTime startedAt;
  final DateTime? endedAt;
  final int durationS;
  final double distanceM;
  final double elevationM;
  final String syncStatus; // pending | synced | error
  final String? syncError;

  const LocalActivity({
    required this.id,
    required this.type,
    required this.status,
    required this.startedAt,
    required this.endedAt,
    required this.durationS,
    required this.distanceM,
    required this.elevationM,
    required this.syncStatus,
    required this.syncError,
  });

  factory LocalActivity.fromRow(Map<String, Object?> r) {
    final ended = r['ended_at'] as int?;
    return LocalActivity(
      id: r['id'] as String,
      type: ActivityType.values.byName(r['type'] as String),
      status: r['status'] as String,
      startedAt: DateTime.fromMillisecondsSinceEpoch(r['started_at'] as int),
      endedAt:
          ended == null ? null : DateTime.fromMillisecondsSinceEpoch(ended),
      durationS: r['duration_s'] as int,
      distanceM: (r['distance_m'] as num).toDouble(),
      elevationM: (r['elevation_gain_m'] as num).toDouble(),
      syncStatus: r['sync_status'] as String,
      syncError: r['sync_error'] as String?,
    );
  }
}

class ActivityRepository {
  ActivityRepository._();
  static final ActivityRepository instance = ActivityRepository._();

  Future<Database> get _db => LocalDb.instance.db;

  /// Crea la actividad en estado "recording" al pulsar Iniciar.
  Future<void> create({
    required String id,
    required String userId,
    required ActivityType type,
    required DateTime startedAt,
  }) async {
    final db = await _db;
    await db.insert('activities', {
      'id': id,
      'user_id': userId,
      'type': type.name,
      'status': 'recording',
      'started_at': startedAt.millisecondsSinceEpoch,
    });
  }

  /// Guarda un punto y los totales actuales en la misma transacción.
  /// Así, si la app muere, los totales guardados coinciden con los puntos.
  Future<void> addPoint({
    required String activityId,
    required int segment,
    required TrackPoint point,
    required int durationS,
    required double distanceM,
    required double elevationM,
  }) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.insert('points', {
        'activity_id': activityId,
        'segment': segment,
        'lat': point.lat,
        'lng': point.lng,
        'alt': point.alt,
        'accuracy': point.accuracy,
        'time': point.time.millisecondsSinceEpoch,
      });
      await txn.update(
        'activities',
        {
          'duration_s': durationS,
          'distance_m': distanceM,
          'elevation_gain_m': elevationM,
        },
        where: 'id = ?',
        whereArgs: [activityId],
      );
    });
  }

  /// Marca la actividad como terminada y pendiente de sincronizar.
  Future<void> finish(
    String id, {
    required DateTime endedAt,
    required int durationS,
    required double distanceM,
    required double elevationM,
  }) async {
    final db = await _db;
    await db.update(
      'activities',
      {
        'status': 'finished',
        'ended_at': endedAt.millisecondsSinceEpoch,
        'duration_s': durationS,
        'distance_m': distanceM,
        'elevation_gain_m': elevationM,
        'sync_status': 'pending',
        'sync_error': null,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> delete(String id) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete('points', where: 'activity_id = ?', whereArgs: [id]);
      await txn.delete('activities', where: 'id = ?', whereArgs: [id]);
    });
  }

  /// Actividad que quedó "recording": la app se cerró sin finalizarla.
  Future<LocalActivity?> findRecording(String userId) async {
    final db = await _db;
    final rows = await db.query(
      'activities',
      where: "user_id = ? AND status = 'recording'",
      whereArgs: [userId],
      orderBy: 'started_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : LocalActivity.fromRow(rows.first);
  }

  /// Cierra una actividad interrumpida con lo que alcanzó a guardarse.
  /// Devuelve false (y la borra) si tenía menos de 2 puntos.
  Future<bool> recoverInterrupted(String id) async {
    final db = await _db;
    final count = Sqflite.firstIntValue(await db.rawQuery(
            'SELECT COUNT(*) FROM points WHERE activity_id = ?', [id])) ??
        0;
    if (count < 2) {
      await delete(id);
      return false;
    }
    final lastTime = Sqflite.firstIntValue(await db.rawQuery(
        'SELECT MAX(time) FROM points WHERE activity_id = ?', [id]));
    await db.update(
      'activities',
      {'status': 'finished', 'ended_at': lastTime, 'sync_status': 'pending'},
      where: 'id = ?',
      whereArgs: [id],
    );
    return true;
  }

  Future<List<LocalActivity>> listFinished(String userId) async {
    final db = await _db;
    final rows = await db.query(
      'activities',
      where: "user_id = ? AND status = 'finished'",
      whereArgs: [userId],
      orderBy: 'started_at DESC',
    );
    return rows.map(LocalActivity.fromRow).toList();
  }

  /// Terminadas y aún no confirmadas por el servidor (pendientes o con error).
  Future<List<LocalActivity>> pendingForSync(String userId) async {
    final db = await _db;
    final rows = await db.query(
      'activities',
      where: "user_id = ? AND status = 'finished' AND sync_status != 'synced'",
      whereArgs: [userId],
      orderBy: 'started_at ASC',
    );
    return rows.map(LocalActivity.fromRow).toList();
  }

  Future<List<Map<String, Object?>>> pointsRaw(String activityId) async {
    final db = await _db;
    return db.query('points',
        where: 'activity_id = ?', whereArgs: [activityId], orderBy: 'id ASC');
  }

  Future<void> markSynced(String id) async {
    final db = await _db;
    await db.update('activities', {'sync_status': 'synced', 'sync_error': null},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> markError(String id, String message) async {
    final db = await _db;
    await db.update('activities', {'sync_status': 'error', 'sync_error': message},
        where: 'id = ?', whereArgs: [id]);
  }

  /// Reconstruye una actividad completa (con sus tramos) para mostrar el resumen.
  Future<ActivityResult?> loadResult(String id) async {
    final db = await _db;
    final rows =
        await db.query('activities', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    final a = LocalActivity.fromRow(rows.first);

    final segments = <List<LatLng>>[];
    final points = <TrackPoint>[];
    int? currentSegment;
    for (final r in await pointsRaw(id)) {
      final seg = r['segment'] as int;
      if (seg != currentSegment) {
        segments.add([]);
        currentSegment = seg;
      }
      final lat = (r['lat'] as num).toDouble();
      final lng = (r['lng'] as num).toDouble();
      segments.last.add(LatLng(lat, lng));
      points.add(TrackPoint(
        lat: lat,
        lng: lng,
        alt: (r['alt'] as num).toDouble(),
        accuracy: (r['accuracy'] as num).toDouble(),
        time: DateTime.fromMillisecondsSinceEpoch(r['time'] as int),
      ));
    }

    return ActivityResult(
      id: a.id,
      type: a.type,
      startedAt: a.startedAt,
      endedAt: a.endedAt ?? a.startedAt.add(Duration(seconds: a.durationS)),
      duration: Duration(seconds: a.durationS),
      distanceMeters: a.distanceM,
      elevationGain: a.elevationM,
      segments: segments,
      points: points,
    );
  }
}