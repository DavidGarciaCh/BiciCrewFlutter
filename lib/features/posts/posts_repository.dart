import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/supabase_config.dart';
import '../../core/utils.dart';
import 'post_models.dart';

class PostsRepository {
  PostsRepository._();
  static final PostsRepository instance = PostsRepository._();

  // ---------- Feed ----------
  Future<List<Post>> feed({DateTime? olderThan, int pageSize = 15}) async {
    final data = await supabase.rpc('get_feed', params: {
      'older_than': olderThan?.toUtc().toIso8601String(),
      'page_size': pageSize,
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

  Future<void> delete(String id) async {
    final res = await supabase.from('posts').delete().eq('id', id).select();
    if (res.isEmpty) {
      throw const AppException('No se pudo eliminar la publicación');
    }
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