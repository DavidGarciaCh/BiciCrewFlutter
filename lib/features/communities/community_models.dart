import 'package:flutter/material.dart';

const communityActivityLabels = {
  'any': 'Todas las actividades',
  'run': 'Correr',
  'bike': 'Bicicleta',
  'walk': 'Caminar',
};

const communityActivityIcons = {
  'any': Icons.all_inclusive,
  'run': Icons.directions_run,
  'bike': Icons.directions_bike,
  'walk': Icons.directions_walk,
};

class Community {
  final String id;
  final String name;
  final String description;
  final String activityType;
  final String? city;
  final bool isPrivate;
  final int memberCount;
  final bool isMember;
  final String? reason; // por qué se sugiere
  // Solo en el detalle (get_community)
  final String? creatorName;
  final String? role; // owner | member
  final String? inviteCode; // solo para miembros

  const Community({
    required this.id,
    required this.name,
    required this.description,
    required this.activityType,
    required this.city,
    required this.isPrivate,
    required this.memberCount,
    required this.isMember,
    this.reason,
    this.creatorName,
    this.role,
    this.inviteCode,
  });

  bool get isOwner => role == 'owner';

  factory Community.fromRow(Map<String, dynamic> r) => Community(
        id: r['id'] as String,
        name: r['name'] as String,
        description: (r['description'] as String?) ?? '',
        activityType: (r['activity_type'] as String?) ?? 'any',
        city: r['city'] as String?,
        isPrivate: r['is_private'] as bool? ?? false,
        memberCount: (r['member_count'] as num?)?.toInt() ?? 0,
        isMember: r['is_member'] as bool? ?? false,
        reason: r['reason'] as String?,
        creatorName: r['creator_name'] as String?,
        role: r['role'] as String?,
        inviteCode: r['invite_code'] as String?,
      );
}

class Member {
  final String name;
  final String role;
  final DateTime joinedAt;
  const Member({required this.name, required this.role, required this.joinedAt});

  factory Member.fromRow(Map<String, dynamic> r) {
    final u = r['user'];
    final first = u is Map ? (u['first_name'] as String? ?? '') : '';
    final last = u is Map ? (u['last_name'] as String? ?? '') : '';
    final name = '$first $last'.trim();
    return Member(
      name: name.isEmpty ? 'Usuario' : name,
      role: r['role'] as String,
      joinedAt: DateTime.parse(r['joined_at'] as String).toLocal(),
    );
  }
}