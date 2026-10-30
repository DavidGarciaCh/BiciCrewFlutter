import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/utils.dart';
import '../communities/communities_repository.dart';
import '../communities/community_models.dart';
import '../communities/community_widgets.dart';
import '../posts/post_card.dart';
import '../posts/post_models.dart';
import '../posts/posts_repository.dart';
import '../social/person_tile.dart';
import '../social/social_repository.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<Person> _people = [];
  List<Community> _communities = [];
  List<Post> _posts = [];
  bool _loading = false;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce =
        Timer(const Duration(milliseconds: 400), () => _search(text.trim()));
  }

  Future<void> _search(String q) async {
    if (q.length < 2) {
      setState(() {
        _people = [];
        _communities = [];
        _posts = [];
        _query = q;
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final (people, communities, posts) = await (
        SocialRepository.instance.search(q),
        CommunitiesRepository.instance.search(q),
        PostsRepository.instance.feed(search: q, pageSize: 20),
      ).wait;
      if (!mounted || q != _controller.text.trim()) return; // respuesta vieja
      setState(() {
        _people = people;
        _communities = communities;
        _posts = posts;
        _query = q;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showMessage(context, errorText(e), error: true);
    }
  }

  Widget _tab(Widget Function() content, int count) {
    if (_query.length < 2) {
      return const Center(child: Text('Escribe al menos 2 letras'));
    }
    if (_loading && count == 0) {
      return const Center(child: CircularProgressIndicator());
    }
    if (count == 0) return Center(child: Text('Sin resultados para "$_query"'));
    return content();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: TextField(
            controller: _controller,
            autofocus: true,
            onChanged: _onChanged,
            decoration: const InputDecoration(
              hintText: 'Buscar por nombre',
              border: InputBorder.none,
            ),
          ),
          bottom: TabBar(tabs: [
            Tab(text: 'Personas (${_people.length})'),
            Tab(text: 'Comunidades (${_communities.length})'),
            Tab(text: 'Publicaciones (${_posts.length})'),
          ]),
        ),
        body: TabBarView(children: [
          _tab(
            () => ListView(
              children: _people
                  .map((p) => PersonTile(
                        key: ValueKey('${p.relation}-${p.id}'),
                        person: p,
                        onChanged: () => _search(_controller.text.trim()),
                      ))
                  .toList(),
            ),
            _people.length,
          ),
          _tab(
            () => ListView(
              children: _communities
                  .map((c) => CommunityTile(
                        key: ValueKey(c.id),
                        community: c,
                        onChanged: () => _search(_controller.text.trim()),
                      ))
                  .toList(),
            ),
            _communities.length,
          ),
          _tab(
            () => ListView.builder(
              padding: const EdgeInsets.only(top: 6, bottom: 24),
              itemCount: _posts.length,
              itemBuilder: (_, i) =>
                  PostCard(key: ValueKey(_posts[i].id), post: _posts[i]),
            ),
            _posts.length,
          ),
        ]),
      ),
    );
  }
}