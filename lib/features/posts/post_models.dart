import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../tracking/tracking_models.dart';

const postTypeLabels = {
  'route_completed': 'Ruta completada',
  'route_planned': 'Ruta planeada',
  'report': 'Novedad / reporte',
};

const postTypeIcons = {
  'route_completed': Icons.route,
  'route_planned': Icons.event,
  'report': Icons.warning_amber_rounded,
};

const reportCategories = {
  'road_closed': 'Vía cerrada',
  'traffic': 'Problema de tránsito',
  'hazard': 'Peligro en la vía',
  'other': 'Otro',
};

const reportCategoryIcons = {
  'road_closed': Icons.block,
  'traffic': Icons.traffic,
  'hazard': Icons.report_problem_outlined,
  'other': Icons.info_outline,
};

class Post {
  final String id;
  final String authorId;
  final String authorName;
  final String type;
  final String status; // draft | published | hidden
  final String body;
  final String? activityId;
  final Map<String, dynamic> payload;
  final DateTime? publishedAt;
  final DateTime? updatedAt;
  int likeCount;
  int commentCount;
  bool likedByMe;
  String? myAttendance; // going | interested | null
  int goingCount;
  int interestedCount;

  Post({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.type,
    required this.status,
    required this.body,
    required this.activityId,
    required this.payload,
    required this.publishedAt,
    required this.updatedAt,
    this.likeCount = 0,
    this.commentCount = 0,
    this.likedByMe = false,
    this.myAttendance = null,
    this.goingCount = 0,
    this.interestedCount = 0,
  });

  static DateTime? _date(dynamic v) =>
      v == null ? null : DateTime.parse(v as String).toLocal();

  static Map<String, dynamic> _map(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  /// Fila devuelta por la función get_feed (siempre publicada)
  factory Post.fromFeed(Map<String, dynamic> r) => Post(
        id: r['id'] as String,
        authorId: r['author_id'] as String,
        authorName: (r['author_name'] as String?) ?? '',
        type: r['type'] as String,
        status: 'published',
        body: (r['body'] as String?) ?? '',
        activityId: r['activity_id'] as String?,
        payload: _map(r['payload']),
        publishedAt: _date(r['published_at']),
        updatedAt: null,
        likeCount: (r['like_count'] as num?)?.toInt() ?? 0,
        commentCount: (r['comment_count'] as num?)?.toInt() ?? 0,
        likedByMe: r['liked_by_me'] as bool? ?? false,
        myAttendance: r['my_attendance'] as String?,
        goingCount: (r['going_count'] as num?)?.toInt() ?? 0,
        interestedCount: (r['interested_count'] as num?)?.toInt() ?? 0,
      );

  /// Fila de la tabla posts (para "Mis publicaciones")
  factory Post.fromTable(Map<String, dynamic> r) => Post(
        id: r['id'] as String,
        authorId: r['author_id'] as String,
        authorName: '',
        type: r['type'] as String,
        status: r['status'] as String,
        body: (r['body'] as String?) ?? '',
        activityId: r['activity_id'] as String?,
        payload: _map(r['payload']),
        publishedAt: _date(r['published_at']),
        updatedAt: _date(r['updated_at']),
      );

  // ---- Datos de "ruta completada" ----
  double get distanceMeters =>
      (payload['distance_meters'] as num?)?.toDouble() ?? 0;
  int get durationSeconds => (payload['duration_seconds'] as num?)?.toInt() ?? 0;
  double get elevationGain =>
      (payload['elevation_gain_meters'] as num?)?.toDouble() ?? 0;
    /// Ruta de la imagen en Storage (solo novedades)
  String? get imagePath {
    final v = payload['image_path'];
    return v is String && v.isNotEmpty ? v : null;
  }

  ActivityType? get activityType {
    final name = payload['activity_type'];
    return ActivityType.values.where((t) => t.name == name).firstOrNull;
  }

  /// El trazado llega como [[lat, lng, tramo], ...]; se separa en tramos
  /// para no dibujar una línea recta sobre las pausas.
  List<List<LatLng>> get routeSegments {
    final raw = payload['route'];
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
}

class Comment {
  final String id;
  final String authorId;
  final String authorName;
  final String body;
  final DateTime createdAt;
  const Comment({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.body,
    required this.createdAt,
  });

  factory Comment.fromRow(Map<String, dynamic> r) {
    final a = r['author'];
    final first = a is Map ? (a['first_name'] as String? ?? '') : '';
    final last = a is Map ? (a['last_name'] as String? ?? '') : '';
    final name = '$first $last'.trim();
    return Comment(
      id: r['id'] as String,
      authorId: r['author_id'] as String,
      authorName: name.isEmpty ? 'Usuario' : name,
      body: r['body'] as String,
      createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
    );
  }
}

class Attendee {
  final String name;
  final String status; // going | interested
  final DateTime createdAt;
  const Attendee(
      {required this.name, required this.status, required this.createdAt});

  factory Attendee.fromRow(Map<String, dynamic> r) {
    final u = r['user'];
    final first = u is Map ? (u['first_name'] as String? ?? '') : '';
    final last = u is Map ? (u['last_name'] as String? ?? '') : '';
    final name = '$first $last'.trim();
    return Attendee(
      name: name.isEmpty ? 'Usuario' : name,
      status: r['status'] as String,
      createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
    );
  }
}