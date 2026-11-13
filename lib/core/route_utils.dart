import 'package:latlong2/latlong.dart';

/// Convierte [[lat, lng, tramo], ...] en una lista de tramos,
/// para no dibujar una línea recta sobre las pausas.
List<List<LatLng>> parseRouteSegments(dynamic raw) {
  if (raw is! List) return [];
  final segments = <List<LatLng>>[];
  int? current;
  for (final p in raw) {
    if (p is! List || p.length < 3) continue;
    final seg = (p[2] as num?)?.toInt() ?? 0;
    if (seg != current) {
      segments.add([]);
      current = seg;
    }
    segments.last
        .add(LatLng((p[0] as num).toDouble(), (p[1] as num).toDouble()));
  }
  return segments;
}