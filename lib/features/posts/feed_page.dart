import 'package:flutter/material.dart';
import '../../core/utils.dart';
import '../social/friends_page.dart';
import 'my_posts_page.dart';
import 'post_card.dart';
import 'post_editor_page.dart';
import 'post_models.dart';
import 'posts_repository.dart';

class FeedPage extends StatefulWidget {
  const FeedPage({super.key});

  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  static const _pageSize = 15;
  final _repo = PostsRepository.instance;
  final _scroll = ScrollController();
  final List<Post> _posts = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _loadFirst();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  Future<void> _loadFirst() async {
    try {
      final page = await _repo.feed(pageSize: _pageSize);
      if (!mounted) return;
      setState(() {
        _posts
          ..clear()
          ..addAll(page);
        _hasMore = page.length == _pageSize;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = errorText(e);
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _loading || _posts.isEmpty) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _repo.feed(
          olderThan: _posts.last.publishedAt, pageSize: _pageSize);
      if (!mounted) return;
      setState(() {
        _posts.addAll(page);
        _hasMore = page.length == _pageSize;
      });
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  String _hint(String type) => switch (type) {
        'route_completed' => 'Comparte una actividad ya sincronizada',
        'route_planned' => 'Invita a tus amigos a una salida',
        _ => 'Avisa de vías cerradas o problemas de tránsito',
      };

  Future<void> _newPost() async {
    final type = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('¿Qué quieres publicar?')),
            for (final e in postTypeLabels.entries)
              ListTile(
                leading: Icon(postTypeIcons[e.key]),
                title: Text(e.value),
                subtitle: Text(_hint(e.key)),
                onTap: () => Navigator.pop(context, e.key),
              ),
          ],
        ),
      ),
    );
    if (type == null || !mounted) return;
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => PostEditorPage(type: type)),
    );
    if (ok == true) _loadFirst();
  }

  Future<void> _edit(Post p) async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => PostEditorPage(post: p)),
    );
    if (ok == true) _loadFirst();
  }

  Future<void> _delete(Post p) async {
    final ok = await confirmAction(
      context,
      title: 'Eliminar publicación',
      message: 'Se eliminará la publicación con sus me gusta y comentarios. '
          'Esta acción no se puede deshacer.',
      confirmLabel: 'Eliminar',
    );
    if (!ok || !mounted) return;
    try {
      await _repo.delete(p.id);
      if (!mounted) return;
      setState(() => _posts.removeWhere((x) => x.id == p.id));
      showMessage(context, 'Publicación eliminada');
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    }
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('No se pudo cargar el feed:\n$_error',
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                  onPressed: () {
                    setState(() => _loading = true);
                    _loadFirst();
                  },
                  child: const Text('Reintentar')),
            ],
          ),
        ),
      );
    }
    if (_posts.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadFirst,
        child: ListView(children: const [
          SizedBox(height: 120),
          Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Tu feed está vacío.\nAgrega amigos o publica algo para empezar.',
              textAlign: TextAlign.center,
            ),
          ),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadFirst,
      child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.only(top: 6, bottom: 88),
        itemCount: _posts.length + (_hasMore ? 1 : 0),
        itemBuilder: (_, i) {
          if (i >= _posts.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final p = _posts[i];
          return PostCard(
            key: ValueKey(p.id),
            post: p,
            onEdit: _edit,
            onDelete: _delete,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BiciCrew'),
        actions: [
          IconButton(
            icon: const Icon(Icons.people_outline),
            tooltip: 'Amigos',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const FriendsPage())),
          ),
          IconButton(
            icon: const Icon(Icons.article_outlined),
            tooltip: 'Mis publicaciones',
            onPressed: () async {
              await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const MyPostsPage()));
              _loadFirst();
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newPost,
        icon: const Icon(Icons.edit),
        label: const Text('Publicar'),
      ),
      body: _body(),
    );
  }
}