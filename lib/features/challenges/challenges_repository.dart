import '../../core/supabase_config.dart';
import '../../core/utils.dart';
import 'challenge_models.dart';

class ChallengesRepository {
  ChallengesRepository._();
  static final ChallengesRepository instance = ChallengesRepository._();

  List<Challenge> _list(dynamic data) => (data as List)
      .map((r) => Challenge.fromRow(Map<String, dynamic>.from(r as Map)))
      .toList();

  /// scope: recommended | explore | mine
  Future<List<Challenge>> list(String scope) async =>
      _list(await supabase.rpc('get_challenges', params: {'p_scope': scope}));

  Future<Challenge> get(String id) async {
    final list = _list(await supabase
        .rpc('get_challenges', params: {'p_scope': 'one', 'p_id': id}));
    if (list.isEmpty) throw const AppException('Desafío no encontrado');
    return list.first;
  }

  Future<List<RankingEntry>> ranking(String id) async {
    final data = await supabase
        .rpc('challenge_ranking', params: {'p_challenge_id': id}) as List;
    return data
        .map((r) => RankingEntry.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// Devuelve el id del desafío creado
  Future<String> create({
    required String activityId,
    required String title,
    required String description,
    required String visibility,
  }) async {
    final id = await supabase.rpc('create_challenge', params: {
      'p_activity_id': activityId,
      'p_title': title,
      'p_description': description,
      'p_visibility': visibility,
    });
    return id as String;
  }

  Future<AttemptResult> submit(String challengeId, String activityId) async {
    final r = await supabase.rpc('submit_challenge_attempt', params: {
      'p_challenge_id': challengeId,
      'p_activity_id': activityId,
    });
    return AttemptResult.fromJson(Map<String, dynamic>.from(r as Map));
  }

  Future<void> delete(String id) async {
    await supabase.rpc('delete_challenge', params: {'p_id': id});
  }
}