import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/utils.dart';
import '../posts/new_post_flow.dart';
import '../posts/post_card.dart';
import '../posts/post_models.dart';
import '../posts/posts_repository.dart';
import 'communities_repository.dart';
import 'community_models.dart';

class CommunityPage extends StatefulWidget {
  final String communityId;
  const CommunityPage({super.key, required this.communityId});

  @override
  State<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends State<CommunityPage> {
  static const _pageSize = 15;
  final _repo = CommunitiesRepository.instance;
  final _postsRepo = PostsRepository.instance;
  final _scroll = ScrollController();
  Community? _c;
  final List<Post> _posts = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load();
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

  Future<void> _load() async {
    try {
      final c = await _repo.get(widget.communityId);
      // Las publicaciones solo las ven los miembros
      final page = c.isMember
          ? await _postsRepo.feed(communityId: c.id, pageSize: _pageSize)
          : <Post>[];
      if (!mounted) return;
      setState(() {
        _c = c;
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
    final c = _c;
    if (c == null || !c.isMember || _loadingMore || !_hasMore || _posts.isEmpty) {
      return;
    }
    setState(() => _loadingMore = true);
    try {
      final page = await _postsRepo.feed(
        communityId: c.id,
        olderThan: _posts.last.publishedAt,
        pageSize: _pageSize,
      );
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

  Future<void> _join() async {
    setState(() => _busy = true);
    try {
      await _repo.join(widget.communityId);
      await _load();
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leave() async {
    final c = _c!;
    final ok = await confirmAction(
      context,
      title: 'Salir de la comunidad',
      message: 'Dejarás de ver las publicaciones de «${c.name}» y las tuyas '
          'compartidas allí dejarán de mostrarse en ella.'
          '${c.isPrivate ? '\n\nEs una comunidad privada: necesitarás el código para volver.' : ''}',
      confirmLabel: 'Salir',
    );
    if (!ok || !mounted) return;
    try {
      await _repo.leave(c.id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    }
  }

  Future<void> _deleteCommunity() async {
    final c = _c!;
    final ok = await confirmAction(
      context,
      title: 'Eliminar comunidad',
      message: 'Se eliminará «${c.name}» para todos sus integrantes. '
          'Esta acción no se puede deshacer.',
      confirmLabel: 'Eliminar',
    );
    if (!ok || !mounted) return;
    try {
      await _repo.delete(c.id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    }
  }

  Future<void> _share() async {
    final c = _c!;
    final text = 'Te invito a unirte a «${c.name}» en BiciCrew.\n'
        'Código de invitación: ${c.inviteCode}\n'
        'En la app: Comunidades → ícono de llave → "Unirme con código".';
    await SharePlus.instance
        .share(ShareParams(text: text, subject: 'Invitación a ${c.name}'));
  }

  Future<void> _copyCode() async {
    await Clipboard.setData(ClipboardData(text: _c!.inviteCode ?? ''));
    if (mounted) showMessage(context, 'Código copiado');
  }

  void _showMembers() {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: SizedBox(
          height: 420,
          child: FutureBuilder<List<Member>>(
            future: _repo.members(widget.communityId),
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(child: Text(errorText(snap.error!)));
              }
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final members = snap.data!;
              return ListView(
                children: [
                  ListTile(
                    title: Text('Integrantes (${members.length})',
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                  for (final m in members)
                    ListTile(
                      leading: CircleAvatar(child: Text(m.name[0].toUpperCase())),
                      title: Text(m.name),
                      subtitle: m.role == 'owner' ? const Text('Creador') : null,
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _newPost() async {
    final ok = await startNewPost(context, communityIds: [_c!.id]);
    if (ok) _load();
  }

  Widget _header(Community c) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(c.name, style: theme.textTheme.headlineSmall),
            if (c.description.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(c.description),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                Chip(
                  avatar: Icon(communityActivityIcons[c.activityType], size: 18),
                  label: Text(communityActivityLabels[c.activityType] ?? ''),
                ),
                if (c.city != null && c.city!.isNotEmpty)
                  Chip(
                    avatar: const Icon(Icons.place_outlined, size: 18),
                    label: Text(c.city!),
                  ),
                if (c.isPrivate)
                  const Chip(
                    avatar: Icon(Icons.lock_outline, size: 18),
                    label: Text('Privada'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${c.memberCount} ${c.memberCount == 1 ? 'integrante' : 'integrantes'}'
              ' · creada por ${c.creatorName ?? '—'}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (!c.isMember)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _join,
                  icon: const Icon(Icons.group_add),
                  label: const Text('Unirme'),
                ),
              )
            else
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _share,
                    icon: const Icon(Icons.person_add_alt),
                    label: const Text('Invitar'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _copyCode,
                    icon: const Icon(Icons.key),
                    label: const Text('Copiar código'),
                  ),
                  TextButton.icon(
                    onPressed: _showMembers,
                    icon: const Icon(Icons.groups_outlined),
                    label: const Text('Integrantes'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _note(String text) => Padding(
        padding: const EdgeInsets.all(24),
        child: Text(text, textAlign: TextAlign.center),
      );

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return Scaffold(
      appBar: AppBar(
        title: Text(c?.name ?? 'Comunidad'),
        actions: [
          if (c != null && c.isMember)
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'leave') _leave();
                if (v == 'delete') _deleteCommunity();
              },
              itemBuilder: (_) => [
                if (c.isOwner)
                  const PopupMenuItem(
                      value: 'delete', child: Text('Eliminar comunidad'))
                else
                  const PopupMenuItem(
                      value: 'leave', child: Text('Salir de la comunidad')),
              ],
            ),
        ],
      ),
      floatingActionButton: (c != null && c.isMember)
          ? FloatingActionButton.extended(
              onPressed: _newPost,
              icon: const Icon(Icons.edit),
              label: const Text('Publicar aquí'),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null || c == null
              ? Center(child: _note(_error ?? 'No se pudo cargar'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.only(bottom: 88),
                    itemCount: 1 +
                        _posts.length +
                        (!c.isMember || _posts.isEmpty || _hasMore ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (i == 0) return _header(c);
                      final idx = i - 1;
                      if (idx < _posts.length) {
                        return PostCard(
                            key: ValueKey(_posts[idx].id), post: _posts[idx]);
                      }
                      if (!c.isMember) {
                        return _note(
                            'Únete para ver y compartir publicaciones en esta comunidad.');
                      }
                      if (_posts.isEmpty) {
                        return _note(
                            'Aún no hay publicaciones.\n¡Sé el primero en compartir algo!');
                      }
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    },
                  ),
                ),
    );
  }
}