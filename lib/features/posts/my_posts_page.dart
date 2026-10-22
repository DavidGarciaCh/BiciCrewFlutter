import 'package:flutter/material.dart';
import '../../core/utils.dart';
import 'post_editor_page.dart';
import 'post_models.dart';
import 'posts_repository.dart';

class MyPostsPage extends StatefulWidget {
  const MyPostsPage({super.key});

  @override
  State<MyPostsPage> createState() => _MyPostsPageState();
}

class _MyPostsPageState extends State<MyPostsPage> {
  final _repo = PostsRepository.instance;
  List<Post> _posts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await _repo.myPosts();
      if (!mounted) return;
      setState(() {
        _posts = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showMessage(context, errorText(e), error: true);
    }
  }

  String _title(Post p) => switch (p.type) {
        'route_planned' => p.payload['title'] as String? ?? 'Ruta planeada',
        'route_completed' =>
          'Ruta de ${(p.distanceMeters / 1000).toStringAsFixed(2)} km',
        _ => reportCategories[p.payload['category']] ?? 'Novedad',
      };

  String _status(String s) => switch (s) {
        'draft' => 'Borrador',
        'published' => 'Publicada',
        _ => 'Oculta por moderación',
      };

  Future<void> _edit(Post p) async {
    if (p.status == 'hidden') {
      showMessage(
          context, 'Esta publicación fue ocultada por moderación.',
          error: true);
      return;
    }
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => PostEditorPage(post: p)),
    );
    if (ok == true) _load();
  }

  Future<void> _delete(Post p) async {
    final ok = await confirmAction(
      context,
      title: 'Eliminar publicación',
      message: 'Esta acción no se puede deshacer.',
      confirmLabel: 'Eliminar',
    );
    if (!ok || !mounted) return;
    try {
      await _repo.delete(p.id);
      _load();
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mis publicaciones')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _posts.isEmpty
                  ? ListView(children: const [
                      SizedBox(height: 120),
                      Center(child: Text('Aún no tienes publicaciones')),
                    ])
                  : ListView.separated(
                      itemCount: _posts.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final p = _posts[i];
                        final when = p.updatedAt != null
                            ? ' · ${timeAgo(p.updatedAt!)}'
                            : '';
                        return ListTile(
                          leading: Icon(postTypeIcons[p.type]),
                          title: Text(_title(p)),
                          subtitle: Text('${_status(p.status)}$when'
                              '${p.body.isEmpty ? '' : '\n${p.body}'}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis),
                          isThreeLine: p.body.isNotEmpty,
                          trailing: p.status == 'hidden'
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  tooltip: 'Eliminar',
                                  onPressed: () => _delete(p),
                                ),
                          onTap: () => _edit(p),
                        );
                      },
                    ),
            ),
    );
  }
}