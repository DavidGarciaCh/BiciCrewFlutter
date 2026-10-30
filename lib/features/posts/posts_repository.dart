import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/supabase_config.dart';
import '../../core/utils.dart';
import 'post_models.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

class PostsRepository {
  PostsRepository._();
  static final PostsRepository instance = PostsRepository._();

  // ---------- Feed ----------
  Future<List<Post>> feed({
    DateTime? olderThan,
    int pageSize = 15,
    String? communityId,
    String? search,
  }) async {
    final data = await supabase.rpc('get_feed', params: {
      'older_than': olderThan?.toUtc().toIso8601String(),
      'page_size': pageSize,
      'community_filter': communityId,
      'search_term': search,
    }) as List;
    return data
        .map((r) => Post.fromFeed(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<List<Post>> myPosts() async {
    final uid = supabase.auth.currentUser!.id;
    final rows = await supabase
        .from('posts')
        .select()
        .eq('author_id', uid)
        .order('updated_at', ascending: false);
    return rows.map((r) => Post.fromTable(r)).toList();
  }

  // ---------- Comunidades de una publicación ----------
  Future<List<String>> postCommunityIds(String postId) async {
    final rows = await supabase
        .from('post_communities')
        .select('community_id')
        .eq('post_id', postId);
    return rows.map((r) => r['community_id'] as String).toList();
  }

  Future<void> setPostCommunities(String postId, List<String> ids) async {
    await supabase.rpc('set_post_communities',
        params: {'p_post_id': postId, 'p_community_ids': ids});
  }

    // ---------- Imágenes (Storage) ----------
  static const _bucket = 'post-images';

  /// Sube la imagen a {mi_id}/{uuid}.{ext} y devuelve la ruta
  Future<String> uploadImage(XFile file) async {
    final name = file.name.toLowerCase();
    final ext = const ['jpg', 'jpeg', 'png', 'webp']
        .where((e) => name.endsWith('.$e'))
        .firstOrNull;
    if (ext == null) {
      throw const AppException('Formato no admitido. Usa JPG, PNG o WebP.');
    }
    final bytes = await file.readAsBytes();
    if (bytes.length > 2 * 1024 * 1024) {
      throw const AppException('La imagen supera los 2 MB. Elige una más liviana.');
    }
    final mime = switch (ext) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };
    final path = '${supabase.auth.currentUser!.id}/${const Uuid().v4()}.$ext';
    await supabase.storage.from(_bucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: mime, upsert: false),
        );
    return path;
  }

  /// Borra una imagen; si falla no interrumpe nada (queda huérfana)
  Future<void> deleteImage(String path) async {
    try {
      await supabase.storage.from(_bucket).remove([path]);
    } catch (_) {}
  }

  // ---------- Asistencia a rutas planeadas ----------
  /// status: 'going' | 'interested' | 'none'
  Future<void> setAttendance(String postId, String status) async {
    await supabase.rpc('set_attendance',
        params: {'p_post_id': postId, 'new_status': status});
  }

  /// Solo el organizador recibe filas (lo garantiza la RLS)
  Future<List<Attendee>> attendees(String postId) async {
    final rows = await supabase
        .from('post_attendance')
        .select('status, created_at, '
            'user:profiles!post_attendance_user_id_fkey(first_name, last_name)')
        .eq('post_id', postId)
        .order('created_at', ascending: true);
    return rows.map((r) => Attendee.fromRow(r)).toList();
  }

  // ---------- Crear, editar, eliminar ----------
  Future<void> create({
    required String type,
    required String status,
    required String body,
    String? activityId,
    Map<String, dynamic> payload = const {},
  }) async {
    await supabase.from('posts').insert({
      'type': type,
      'status': status,
      'body': body,
      if (activityId != null) 'activity_id': activityId,
      'payload': payload,
    });
  }

  Future<void> update(
    String id, {
    required String status,
    required String body,
    required Map<String, dynamic> payload,
  }) async {
    final res = await supabase
        .from('posts')
        .update({'status': status, 'body': body, 'payload': payload})
        .eq('id', id)
        .select();
    if (res.isEmpty) {
      throw const AppException('No se pudo actualizar la publicación');
    }
  }

  Future<void> delete(String id, {String? imagePath}) async {
    final res = await supabase.from('posts').delete().eq('id', id).select();
    if (res.isEmpty) {
      throw const AppException('No se pudo eliminar la publicación');
    }
    if (imagePath != null) await deleteImage(imagePath);
  }

  // ---------- Me gusta ----------
  Future<void> like(String postId) async {
    try {
      await supabase.from('post_likes').insert({'post_id': postId});
    } on PostgrestException catch (e) {
      if (e.code != '23505') rethrow; // 23505 = ya tenías el me gusta
    }
  }

  Future<void> unlike(String postId) async {
    await supabase
        .from('post_likes')
        .delete()
        .eq('post_id', postId)
        .eq('user_id', supabase.auth.currentUser!.id);
  }

  // ---------- Comentarios ----------
  Future<List<Comment>> comments(String postId) async {
    final rows = await supabase
        .from('post_comments')
        .select('id, author_id, body, created_at, '
            'author:profiles!post_comments_author_id_fkey(first_name, last_name)')
        .eq('post_id', postId)
        .order('created_at', ascending: true);
    return rows.map((r) => Comment.fromRow(r)).toList();
  }

  Future<void> addComment(String postId, String body) async {
    await supabase
        .from('post_comments')
        .insert({'post_id': postId, 'body': body});
  }

  Future<void> deleteComment(String id) async {
    await supabase.from('post_comments').delete().eq('id', id);
  }
}