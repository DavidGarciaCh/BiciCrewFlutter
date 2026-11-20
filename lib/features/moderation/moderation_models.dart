const reportReasons = {
  'spam': 'Spam o publicidad',
  'inappropriate': 'Contenido inapropiado',
  'harassment': 'Acoso o agresión',
  'false_info': 'Información falsa',
  'dangerous': 'Peligroso o ilegal',
  'other': 'Otro motivo',
};

const supportKinds = {
  'peticion': 'Petición',
  'queja': 'Queja',
  'reclamo': 'Reclamo',
  'sugerencia': 'Sugerencia',
};

const supportStatusLabels = {
  'open': 'Recibida',
  'in_review': 'En revisión',
  'answered': 'Respondida',
  'closed': 'Cerrada',
};

const moderationActionLabels = {
  'report_dismissed': 'Reporte descartado',
  'post_hidden': 'Publicación ocultada',
  'user_suspended': 'Cuenta suspendida',
  'post_restored': 'Publicación restaurada',
  'user_reactivated': 'Cuenta reactivada',
  'support_in_review': 'PQRS en revisión',
  'support_answered': 'PQRS respondida',
  'support_closed': 'PQRS cerrada',
};

Map<String, dynamic> _map(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

class AdminReport {
  final String id;
  final String reason;
  final String details;
  final String status; // open | resolved | dismissed
  final String? action; // none | post_hidden | user_suspended
  final String? adminNote;
  final DateTime createdAt;
  final DateTime? reviewedAt;
  final String reporterName;
  final String? targetPostId;
  final String? targetUserId;
  final String targetUserName;
  final String? targetUserStatus; // active | suspended
  final String? postStatus; // null = ya no existe
  final Map<String, dynamic> snapshot;
  final int sameTarget; // otros reportes abiertos sobre lo mismo

  const AdminReport({
    required this.id,
    required this.reason,
    required this.details,
    required this.status,
    required this.action,
    required this.adminNote,
    required this.createdAt,
    required this.reviewedAt,
    required this.reporterName,
    required this.targetPostId,
    required this.targetUserId,
    required this.targetUserName,
    required this.targetUserStatus,
    required this.postStatus,
    required this.snapshot,
    required this.sameTarget,
  });

  bool get isPost => snapshot['kind'] == 'post' || targetPostId != null;

  factory AdminReport.fromRow(Map<String, dynamic> r) => AdminReport(
        id: r['id'] as String,
        reason: r['reason'] as String,
        details: (r['details'] as String?) ?? '',
        status: r['status'] as String,
        action: r['action'] as String?,
        adminNote: r['admin_note'] as String?,
        createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
        reviewedAt: r['reviewed_at'] == null
            ? null
            : DateTime.parse(r['reviewed_at'] as String).toLocal(),
        reporterName: (r['reporter_name'] as String?) ?? 'Usuario',
        targetPostId: r['target_post_id'] as String?,
        targetUserId: r['target_user_id'] as String?,
        targetUserName: (r['target_user_name'] as String?) ?? 'Usuario',
        targetUserStatus: r['target_user_status'] as String?,
        postStatus: r['post_status'] as String?,
        snapshot: _map(r['snapshot']),
        sameTarget: (r['same_target'] as num?)?.toInt() ?? 0,
      );
}

/// Solicitud PQRS (la usan el usuario y el administrador)
class SupportRequest {
  final String id;
  final String kind;
  final String reason;
  final String details;
  final List<String> attachments;
  final String status;
  final String? adminResponse;
  final DateTime createdAt;
  final DateTime? respondedAt;
  final String? userName; // solo lo trae la vista del administrador

  const SupportRequest({
    required this.id,
    required this.kind,
    required this.reason,
    required this.details,
    required this.attachments,
    required this.status,
    required this.adminResponse,
    required this.createdAt,
    required this.respondedAt,
    this.userName,
  });

  factory SupportRequest.fromRow(Map<String, dynamic> r) => SupportRequest(
        id: r['id'] as String,
        kind: r['kind'] as String,
        reason: r['reason'] as String,
        details: r['details'] as String,
        attachments:
            ((r['attachments'] as List?) ?? const []).map((e) => '$e').toList(),
        status: r['status'] as String,
        adminResponse: r['admin_response'] as String?,
        createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
        respondedAt: r['responded_at'] == null
            ? null
            : DateTime.parse(r['responded_at'] as String).toLocal(),
        userName: r['user_name'] as String?,
      );
}

class ModerationLogEntry {
  final String action;
  final String adminName;
  final String targetName;
  final String? note;
  final DateTime createdAt;
  const ModerationLogEntry({
    required this.action,
    required this.adminName,
    required this.targetName,
    required this.note,
    required this.createdAt,
  });

  factory ModerationLogEntry.fromRow(Map<String, dynamic> r) =>
      ModerationLogEntry(
        action: r['action'] as String,
        adminName: (r['admin_name'] as String?) ?? 'Administrador',
        targetName: (r['target_name'] as String?) ?? '',
        note: r['note'] as String?,
        createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
      );
}