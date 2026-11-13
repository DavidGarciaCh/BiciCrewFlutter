import 'package:latlong2/latlong.dart';
import '../../core/route_utils.dart';
import '../../core/supabase_config.dart';
import '../tracking/tracking_models.dart';

class Challenge {
  final String id;
  final String title;
  final String description;
  final String activityType;
  final double distanceMeters;
  final double elevationGain;
  final String visibility; // public | friends
  final String createdBy;
  final String creatorName;
  final DateTime createdAt;
  final int participants;
  final double? avgSeconds;
  final int? bestSeconds;
  final int? myBestSeconds;
  final int? myPosition;
  final List<List<LatLng>> segments; // solo en el detalle
  final String? reason;

  const Challenge({
    required this.id,
    required this.title,
    required this.description,
    required this.activityType,
    required this.distanceMeters,
    required this.elevationGain,
    required this.visibility,
    required this.createdBy,
    required this.creatorName,
    required this.createdAt,
    required this.participants,
    required this.avgSeconds,
    required this.bestSeconds,
    required this.myBestSeconds,
    required this.myPosition,
    required this.segments,
    required this.reason,
  });

  ActivityType get type => ActivityType.values.byName(activityType);
  bool get isMine => createdBy == supabase.auth.currentUser?.id;

  factory Challenge.fromRow(Map<String, dynamic> r) => Challenge(
        id: r['id'] as String,
        title: r['title'] as String,
        description: (r['description'] as String?) ?? '',
        activityType: r['activity_type'] as String,
        distanceMeters: (r['distance_meters'] as num).toDouble(),
        elevationGain: (r['elevation_gain_meters'] as num?)?.toDouble() ?? 0,
        visibility: r['visibility'] as String,
        createdBy: r['created_by'] as String,
        creatorName: (r['creator_name'] as String?) ?? 'Usuario',
        createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
        participants: (r['participants'] as num?)?.toInt() ?? 0,
        avgSeconds: (r['avg_seconds'] as num?)?.toDouble(),
        bestSeconds: (r['best_seconds'] as num?)?.toInt(),
        myBestSeconds: (r['my_best_seconds'] as num?)?.toInt(),
        myPosition: (r['my_position'] as num?)?.toInt(),
        segments: parseRouteSegments(r['preview']),
        reason: r['reason'] as String?,
      );
}

class RankingEntry {
  final int position;
  final String userId;
  final String name;
  final int durationSeconds;
  final DateTime completedAt;
  const RankingEntry({
    required this.position,
    required this.userId,
    required this.name,
    required this.durationSeconds,
    required this.completedAt,
  });

  factory RankingEntry.fromRow(Map<String, dynamic> r) => RankingEntry(
        position: (r['rank_pos'] as num).toInt(),
        userId: r['user_id'] as String,
        name: (r['name'] as String?) ?? 'Usuario',
        durationSeconds: (r['duration_seconds'] as num).toInt(),
        completedAt: DateTime.parse(r['completed_at'] as String).toLocal(),
      );
}

class AttemptResult {
  final int durationSeconds;
  final int position;
  final int participants;
  final bool personalBest;
  const AttemptResult({
    required this.durationSeconds,
    required this.position,
    required this.participants,
    required this.personalBest,
  });

  factory AttemptResult.fromJson(Map<String, dynamic> j) => AttemptResult(
        durationSeconds: (j['duration_seconds'] as num).toInt(),
        position: (j['position'] as num).toInt(),
        participants: (j['participants'] as num).toInt(),
        personalBest: j['personal_best'] as bool? ?? false,
      );
}