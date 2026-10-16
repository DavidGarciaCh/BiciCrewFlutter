import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

enum ActivityType {
  run('Correr', Icons.directions_run),
  bike('Bicicleta', Icons.directions_bike),
  walk('Caminar', Icons.directions_walk);

  final String label;
  final IconData icon;
  const ActivityType(this.label, this.icon);
}

class TrackPoint {
  final double lat;
  final double lng;
  final double alt;
  final double accuracy;
  final DateTime time;
  const TrackPoint({
    required this.lat,
    required this.lng,
    required this.alt,
    required this.accuracy,
    required this.time,
  });
}

/// Resultado de una actividad terminada
class ActivityResult {
  final String id;
  final ActivityType type;
  final DateTime startedAt;
  final DateTime endedAt;
  final Duration duration;
  final double distanceMeters;
  final double elevationGain;
  final List<List<LatLng>> segments;
  final List<TrackPoint> points;
  const ActivityResult({
    required this.id,
    required this.type,
    required this.startedAt,
    required this.endedAt,
    required this.duration,
    required this.distanceMeters,
    required this.elevationGain,
    required this.segments,
    required this.points,
  });

  double get avgSpeedKmh => duration.inSeconds > 0
      ? (distanceMeters / 1000) / (duration.inSeconds / 3600)
      : 0;
}

String formatDuration(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
}

/// Ritmo en min/km a partir de segundos por kilómetro
String formatPace(double? secondsPerKm) {
  if (secondsPerKm == null || secondsPerKm.isInfinite || secondsPerKm > 3600) {
    return '--:--';
  }
  final total = secondsPerKm.round();
  return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
}

String formatDateTime(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
}