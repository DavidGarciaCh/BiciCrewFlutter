import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'tracking_models.dart';

class ActivitySummaryPage extends StatelessWidget {
  final ActivityResult result;
  const ActivitySummaryPage({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final all = result.segments.expand((s) => s).toList();
    final canFit = all.length >= 2;
    return Scaffold(
      appBar: AppBar(title: Text('Resumen · ${result.type.label}')),
      body: Column(
        children: [
          Expanded(
            child: FlutterMap(
              options: MapOptions(
                initialCenter: all.isNotEmpty ? all.first : const LatLng(3.4516, -76.5320),
                initialZoom: 16,
                initialCameraFit: canFit
                    ? CameraFit.bounds(
                        bounds: LatLngBounds.fromPoints(all),
                        padding: const EdgeInsets.all(32),
                      )
                    : null,
                interactionOptions:
                    const InteractionOptions(flags: InteractiveFlag.all),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.davidgarcia.bicicrew',
                ),
                PolylineLayer(
                  polylines: [
                    for (final s in result.segments)
                      if (s.length > 1)
                        Polyline(
                          points: s,
                          strokeWidth: 5,
                          color: Colors.green.shade700,
                        ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _row('Duración', formatDuration(result.duration)),
                _row('Distancia',
                    '${(result.distanceMeters / 1000).toStringAsFixed(2)} km'),
                _row('Velocidad promedio',
                    '${result.avgSpeedKmh.toStringAsFixed(1)} km/h'),
                _row(
                  'Ritmo promedio',
                  result.distanceMeters > 50
                      ? '${formatPace(result.duration.inSeconds / (result.distanceMeters / 1000))} /km'
                      : '--:--',
                ),
                _row('Desnivel positivo',
                    '${result.elevationGain.toStringAsFixed(0)} m'),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cerrar'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label),
            Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      );
}