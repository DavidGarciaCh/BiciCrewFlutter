import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/supabase_config.dart';

class Person {
  final String id;
  final String firstName;
  final String lastName;
  final String? city;
  /// none | friend | incoming | outgoing | blocked
  final String relation;
  final String? requestId;

  const Person({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.city,
    required this.relation,
    required this.requestId,
  });

  String get fullName => '$firstName $lastName'.trim();
  String get initial => fullName.isEmpty ? '?' : fullName[0].toUpperCase();

  factory Person.fromRow(Map<String, dynamic> r, {String? relation}) => Person(
        id: r['user_id'] as String,
        firstName: r['first_name'] as String? ?? '',
        lastName: r['last_name'] as String? ?? '',
        city: r['city'] as String?,
        relation: relation ?? r['relation'] as String? ?? 'none',
        requestId: r['request_id'] as String?,
      );
}

class SocialRepository {
  SocialRepository._();
  static final SocialRepository instance = SocialRepository._();

  List<Person> _people(dynamic data, {String? relation}) => (data as List)
      .map((r) => Person.fromRow(Map<String, dynamic>.from(r as Map),
          relation: relation))
      .toList();

  Future<List<Person>> relationships() async =>
      _people(await supabase.rpc('my_relationships'));

  Future<List<Person>> blocked() async =>
      _people(await supabase.rpc('my_blocked_users'), relation: 'blocked');

  Future<List<Person>> search(String term) async =>
      _people(await supabase.rpc('search_users', params: {'term': term}));

  Future<void> sendRequest(String id) async {
    await supabase.rpc('send_friend_request', params: {'target_id': id});
  }

  Future<void> respond(String requestId, {required bool accept}) async {
    await supabase.rpc('respond_friend_request',
        params: {'request_id': requestId, 'accept': accept});
  }

  /// Elimina una amistad o cancela una solicitud enviada
  Future<void> remove(String id) async {
    await supabase.rpc('remove_friendship', params: {'other_id': id});
  }

  Future<void> block(String id) async {
    await supabase.rpc('block_user', params: {'target_id': id});
  }

  Future<void> unblock(String id) async {
    await supabase.rpc('unblock_user', params: {'target_id': id});
  }
}