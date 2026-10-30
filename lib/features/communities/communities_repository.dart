import '../../core/supabase_config.dart';
import '../../core/utils.dart';
import 'community_models.dart';

class CommunitiesRepository {
  CommunitiesRepository._();
  static final CommunitiesRepository instance = CommunitiesRepository._();

  List<Community> _list(dynamic data) => (data as List)
      .map((r) => Community.fromRow(Map<String, dynamic>.from(r as Map)))
      .toList();

  Future<List<Community>> mine() async =>
      _list(await supabase.rpc('my_communities'));

  Future<List<Community>> suggested() async =>
      _list(await supabase.rpc('suggested_communities'));

  Future<List<Community>> search(String term) async =>
      _list(await supabase.rpc('search_communities', params: {'term': term}));

  Future<Community> get(String id) async {
    final list = _list(await supabase.rpc('get_community', params: {'p_id': id}));
    if (list.isEmpty) throw const AppException('Comunidad no encontrada');
    return list.first;
  }

  /// Devuelve el id de la comunidad creada
  Future<String> create({
    required String name,
    required String description,
    required String activityType,
    required String city,
    required bool isPrivate,
  }) async {
    final id = await supabase.rpc('create_community', params: {
      'p_name': name,
      'p_description': description,
      'p_activity_type': activityType,
      'p_city': city,
      'p_is_private': isPrivate,
    });
    return id as String;
  }

  Future<void> join(String id) async {
    await supabase.rpc('join_community', params: {'p_id': id});
  }

  /// Devuelve el id de la comunidad a la que te uniste
  Future<String> joinByCode(String code) async {
    final id = await supabase.rpc('join_by_code', params: {'p_code': code});
    return id as String;
  }

  Future<void> leave(String id) async {
    await supabase.rpc('leave_community', params: {'p_id': id});
  }

  Future<void> delete(String id) async {
    await supabase.rpc('delete_community', params: {'p_id': id});
  }

  Future<List<Member>> members(String id) async {
    final rows = await supabase
        .from('community_members')
        .select('role, joined_at, '
            'user:profiles!community_members_user_id_fkey!inner(first_name, last_name)')
        .eq('community_id', id)
        .order('joined_at', ascending: true);
    return rows.map((r) => Member.fromRow(r)).toList();
  }
}