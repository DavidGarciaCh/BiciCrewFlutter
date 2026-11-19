import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' hide ActivityType;
import 'package:uuid/uuid.dart';
import '../../core/supabase_config.dart';
import '../../core/utils.dart';
import 'activity_summary_page.dart';
import 'data/activity_repository.dart';
import 'data/sync_service.dart';
import 'tracking_controller.dart';
import 'tracking_models.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final _repo = ActivityRepository.instance;
  final _sync = SyncService.instance;
  List<LocalActivity> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _sync.version.addListener(_load); // se refresca al terminar cada sincronización
    _load();
    _sync.syncPending();
  }

  @override
  void dispose() {
    _sync.version.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;
    final list = await _repo.listFinished(uid);
    if (!mounted) return;
    setState(() {
      _items = list;
      _loading = false;
    });
  }

  Future<void> _refresh() async {
    await _sync.syncPending();
    final n = await _sync.restoreFromServer();
    await _load();
    if (n > 0 && mounted) {
      showMessage(context, 'Se recuperaron $n actividades de tu cuenta');
    }
  }
  Future<void> _open(LocalActivity a) async {
    final result = await _repo.loadResult(a.id);
    if (result == null || !mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ActivitySummaryPage(result: result)),
    );
  }

  // ---------- Solo pruebas: crea actividades simuladas ----------
  Future<void> _createTest({
    bool interrupted = false,
    int secondsPerPoint = 6,
    double latOffset = 0,
  }) async {
    final uid = supabase.auth.currentUser!.id;
    final id = const Uuid().v4();
    final start = DateTime.now()
        .subtract(Duration(seconds: 120 * secondsPerPoint + 300));
    await _repo.create(
        id: id, userId: uid, type: ActivityType.walk, startedAt: start);

    double lat = 3.4516 + latOffset, lng = -76.5320, dist = 0;
    for (var i = 1; i <= 120; i++) {
      final nlat = lat + 0.00005;
      final nlng = lng + 0.00003;
      dist += Geolocator.distanceBetween(lat, lng, nlat, nlng);
      lat = nlat;
      lng = nlng;
      await _repo.addPoint(
        activityId: id,
        segment: 0,
        point: TrackPoint(
          lat: lat,
          lng: lng,
          alt: 1000 + i * 0.1,
          accuracy: 5,
          time: start.add(Duration(seconds: i * secondsPerPoint)),
        ),
        durationS: i * secondsPerPoint,
        distanceM: dist,
        elevationM: 12,
      );
    }
    if (!interrupted) {
      await _repo.finish(id,
          endedAt: start.add(Duration(seconds: 120 * secondsPerPoint)),
          durationS: 120 * secondsPerPoint,
          distanceM: dist,
          elevationM: 12);
      _sync.syncPending();
    }
    await _load();
    if (mounted) {
      showMessage(
          context,
          interrupted
              ? 'Actividad "interrumpida" creada. Cierra la app y ábrela de nuevo.'
              : 'Actividad de prueba creada');
    }
  }

  Widget _syncIcon(LocalActivity a) {
    switch (a.syncStatus) {
      case 'synced':
        return const Icon(Icons.cloud_done, color: Colors.green);
      case 'error':
        return IconButton(
          icon: const Icon(Icons.error_outline, color: Colors.red),
          onPressed: () =>
              showMessage(context, a.syncError ?? 'Error', error: true),
        );
      default:
        return const Icon(Icons.cloud_upload_outlined, color: Colors.orange);
    }
  }

  String _syncLabel(String s) => switch (s) {
        'synced' => 'Sincronizada',
        'error' => 'Error al sincronizar',
        _ => 'Pendiente de sincronizar',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis actividades'),
        actions: [
          if (TrackingController.debugRelaxed)
            PopupMenuButton<String>(
              icon: const Icon(Icons.bug_report),
              tooltip: 'Pruebas',
              onSelected: (v) => switch (v) {
                'fast' => _createTest(secondsPerPoint: 3),
                'slow' => _createTest(secondsPerPoint: 9),
                'far' => _createTest(latOffset: 0.01),
                'interrupted' => _createTest(interrupted: true),
                _ => _createTest(),
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'normal', child: Text('Actividad de prueba (normal)')),
                PopupMenuItem(value: 'fast', child: Text('Actividad de prueba (rápida)')),
                PopupMenuItem(value: 'slow', child: Text('Actividad de prueba (lenta)')),
                PopupMenuItem(value: 'far', child: Text('Actividad de prueba (otra ruta)')),
                PopupMenuItem(value: 'interrupted', child: Text('Simular actividad interrumpida')),
              ],
            ),
          ValueListenableBuilder<bool>(
            valueListenable: _sync.syncing,
            builder: (_, syncing, __) => syncing
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.sync),
                    tooltip: 'Sincronizar',
                    onPressed: _refresh,
                  ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: _items.isEmpty
                  ? ListView(children: const [
                      SizedBox(height: 120),
                      Center(child: Text('Aún no tienes actividades')),
                    ])
                  : ListView.separated(
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final a = _items[i];
                        return ListTile(
                          leading: Icon(a.type.icon),
                          title: Text(
                            '${(a.distanceM / 1000).toStringAsFixed(2)} km · '
                            '${formatDuration(Duration(seconds: a.durationS))}',
                          ),
                          subtitle: Text(
                            '${a.type.label} · ${formatDateTime(a.startedAt)}\n'
                            '${_syncLabel(a.syncStatus)}',
                          ),
                          isThreeLine: true,
                          trailing: _syncIcon(a),
                          onTap: () => _open(a),
                        );
                      },
                    ),
            ),
    );
  }
}