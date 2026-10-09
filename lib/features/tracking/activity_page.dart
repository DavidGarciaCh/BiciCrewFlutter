import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart' hide ActivityType;
import 'package:latlong2/latlong.dart';

import '../../core/utils.dart';
import 'activity_summary_page.dart';
import 'tracking_controller.dart';
import 'tracking_models.dart';

class ActivityPage extends StatefulWidget {
  const ActivityPage({super.key});

  @override
  State<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends State<ActivityPage> {
  static const _fallbackCenter = LatLng(3.4516, -76.5320); // Cali
  final _ctrl = TrackingController();
  final _map = MapController();
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_followUser);
    _ctrl.locateOnce();
  }

  @override
  void dispose() {
    _ctrl.removeListener(_followUser);
    _ctrl.dispose();
    super.dispose();
  }

  void _followUser() {
    final pos = _ctrl.currentPosition;
    if (pos != null && _mapReady) {
      _map.move(pos, _map.camera.zoom);
    }
  }

  Future<void> _start() async {
    final error = await _ctrl.start();
    if (error != null && mounted) _showPermissionDialog(error);
  }

  void _showPermissionDialog(String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('No se puede iniciar'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
          TextButton(
            onPressed: () {
              Geolocator.openAppSettings();
              Navigator.pop(context);
            },
            child: const Text('Abrir ajustes'),
          ),
        ],
      ),
    );
  }

  Future<void> _finish() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('¿Finalizar actividad?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Seguir'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Finalizar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final result = _ctrl.finish();
    if (result.points.length < 2) {
      showMessage(
        context,
        'Actividad demasiado corta, no se registró.',
        error: true,
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ActivitySummaryPage(result: result)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _ctrl,
      builder: (context, _) {
        final pos = _ctrl.currentPosition;
        return Stack(
          children: [
            FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: pos ?? _fallbackCenter,
                initialZoom: 16,
                onMapReady: () {
                  _mapReady = true;
                  final p = _ctrl.currentPosition;
                  if (p != null) _map.move(p, 16);
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.tunombre.bicicrew',
                ),
                PolylineLayer(
                  polylines: [
                    for (final s in _ctrl.segments)
                      if (s.length > 1)
                        Polyline(
                          points: s,
                          strokeWidth: 5,
                          color: Colors.green.shade700,
                        ),
                  ],
                ),
                if (pos != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: pos,
                        width: 24,
                        height: 24,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.blue,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: SafeArea(child: _buildPanel(context)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPanel(BuildContext context) {
    final c = _ctrl;
    final isIdle = c.status == TrackingStatus.idle;
    return Card(
      elevation: 6,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isIdle) ...[
              SegmentedButton<ActivityType>(
                segments: [
                  for (final t in ActivityType.values)
                    ButtonSegment(
                      value: t,
                      label: Text(t.label),
                      icon: Icon(t.icon),
                    ),
                ],
                selected: {c.type},
                onSelectionChanged: (s) => c.setType(s.first),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _start,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Iniciar actividad'),
                ),
              ),
            ] else ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _stat('Tiempo', formatDuration(c.elapsed)),
                  _stat(
                    'Distancia',
                    '${(c.distanceMeters / 1000).toStringAsFixed(2)} km',
                  ),
                  c.type == ActivityType.bike
                      ? _stat(
                          'Velocidad',
                          '${c.avgSpeedKmh.toStringAsFixed(1)} km/h',
                        )
                      : _stat('Ritmo', '${formatPace(c.paceSecPerKm)} /km'),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Desnivel +${c.elevationGain.toStringAsFixed(0)} m',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (TrackingController.debugRelaxed)
              Text(
                'DEBUG · puntos: ${c.points.length} · '
                'precisión: ${c.lastAccuracy?.toStringAsFixed(0) ?? "-"} m · '
                'descartados: ${c.discarded}',
                style: const TextStyle(fontSize: 11, color: Colors.orange),
              ),
              if (c.status == TrackingStatus.paused)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text('EN PAUSA'),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: c.status == TrackingStatus.running
                          ? c.pause
                          : c.resume,
                      icon: Icon(
                        c.status == TrackingStatus.running
                            ? Icons.pause
                            : Icons.play_arrow,
                      ),
                      label: Text(
                        c.status == TrackingStatus.running
                            ? 'Pausar'
                            : 'Reanudar',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.error,
                      ),
                      onPressed: _finish,
                      icon: const Icon(Icons.stop),
                      label: const Text('Finalizar'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
