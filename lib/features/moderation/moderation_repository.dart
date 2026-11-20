import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../core/supabase_config.dart';
import '../../core/utils.dart';
import 'moderation_models.dart';

class ModerationRepository {
  ModerationRepository._();
  static final ModerationRepository instance = ModerationRepository._();

  static const _bucket = 'support-attachments';

  // ---------- Usuarios ----------
  Future<void> report({
    String? postId,
    String? userId,
    required String reason,
    String details = '',
  }) async {
    await supabase.rpc('create_report', params: {
      'p_post_id': postId,
      'p_user_id': userId,
      'p_reason': reason,
      'p_details': details,
    });
  }

  Future<List<SupportRequest>> mySupport() async {
    final rows = await supabase
        .from('support_requests')
        .select('id, kind, reason, details, attachments, status, '
            'admin_response, created_at, responded_at')
        .eq('user_id', supabase.auth.currentUser!.id)
        .order('created_at', ascending: false);
    return rows.map((r) => SupportRequest.fromRow(r)).toList();
  }

  Future<void> createSupport({
    required String kind,
    required String reason,
    required String details,
    required List<String> attachments,
  }) async {
    await supabase.rpc('create_support_request', params: {
      'p_kind': kind,
      'p_reason': reason,
      'p_details': details,
      'p_attachments': attachments,
    });
  }

  /// Sube un adjunto a {mi_id}/{uuid}.{ext} y devuelve la ruta
  Future<String> uploadAttachment(XFile file) async {
    final name = file.name.toLowerCase();
    final ext = const ['jpg', 'jpeg', 'png', 'webp']
        .where((e) => name.endsWith('.$e'))
        .firstOrNull;
    if (ext == null) {
      throw const AppException('Formato no admitido. Usa JPG, PNG o WebP.');
    }
    final bytes = await file.readAsBytes();
    if (bytes.length > 3 * 1024 * 1024) {
      throw const AppException('Cada adjunto debe pesar menos de 3 MB.');
    }
    final mime = switch (ext) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };
    final path = '${supabase.auth.currentUser!.id}/${const Uuid().v4()}.$ext';
    await supabase.storage.from(_bucket).uploadBinary(path, bytes,
        fileOptions: FileOptions(contentType: mime, upsert: false));
    return path;
  }

  Future<void> deleteAttachment(String path) async {
    try {
      await supabase.storage.from(_bucket).remove([path]);
    } catch (_) {}
  }

  // ---------- Administración ----------
  Future<List<AdminReport>> adminReports(String status) async {
    final data = await supabase
        .rpc('admin_list_reports', params: {'p_status': status}) as List;
    return data
        .map((r) => AdminReport.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// action: dismiss | hide_post | suspend_user
  Future<void> resolveReport(String id, String action, String note) async {
    await supabase.rpc('admin_resolve_report',
        params: {'p_report_id': id, 'p_action': action, 'p_note': note});
  }

  Future<void> restorePost(String postId, String note) async {
    await supabase.rpc('admin_restore_post',
        params: {'p_post_id': postId, 'p_note': note});
  }

  Future<void> reactivateUser(String userId, String note) async {
    await supabase.rpc('admin_reactivate_user',
        params: {'p_user_id': userId, 'p_note': note});
  }

  Future<List<SupportRequest>> adminSupport(String status) async {
    final data = await supabase
        .rpc('admin_list_support', params: {'p_status': status}) as List;
    return data
        .map((r) =>
            SupportRequest.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<void> respondSupport(String id, String status, String response) async {
    await supabase.rpc('admin_respond_support', params: {
      'p_id': id,
      'p_status': status,
      'p_response': response,
    });
  }

  Future<List<ModerationLogEntry>> adminLog() async {
    final data = await supabase.rpc('admin_moderation_log') as List;
    return data
        .map((r) =>
            ModerationLogEntry.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
  }
}