import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class RouteMap extends StatelessWidget {
  final List<List<LatLng>> segments;
  final double height;
  const RouteMap({super.key, required this.segments, this.height = 180});

  @override
  Widget build(BuildContext context) {
    final all = segments.expand((s) => s).toList();
    if (all.length < 2) {
      return SizedBox(
          height: height, child: const Center(child: Text('Sin ruta')));
    }
    return SizedBox(
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: FlutterMap(
          options: MapOptions(
            initialCameraFit: CameraFit.bounds(
              bounds: LatLngBounds.fromPoints(all),
              padding: const EdgeInsets.all(24),
              maxZoom: 17,
            ),
            interactionOptions:
                const InteractionOptions(flags: InteractiveFlag.none),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.tunombre.bicicrew',
            ),
            PolylineLayer(
              polylines: [
                for (final s in segments)
                  if (s.length > 1)
                    Polyline(
                        points: s,
                        strokeWidth: 4,
                        color: Colors.green.shade700),
              ],
            ),
          ],
        ),
      ),
    );
  }
}