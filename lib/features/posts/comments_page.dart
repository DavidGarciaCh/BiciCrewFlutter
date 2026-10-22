import 'package:flutter/material.dart';
import '../../core/supabase_config.dart';
import '../../core/utils.dart';
import 'post_models.dart';
import 'posts_repository.dart';

class CommentsPage extends StatefulWidget {
  final Post post;
  final void Function(int count) onCountChanged;
  const CommentsPage(
      {super.key, required this.post, required this.onCountChanged});

  @override
  State<CommentsPage> createState() => _CommentsPageState();
}

class _CommentsPageState extends State<CommentsPage> {
  final _repo = PostsRepository.instance;
  final _controller = TextEditingController();
  List<Comment> _comments = [];
  bool _loading = true;
  bool _sending = false;

  String get _uid => supabase.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await _repo.comments(widget.post.id);
      if (!mounted) return;
      setState(() {
        _comments = list;
        _loading = false;
      });
      widget.onCountChanged(list.length);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showMessage(context, errorText(e), error: true);
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _repo.addComment(widget.post.id, text);
      _controller.clear();
      await _load();
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _delete(Comment c) async {
    final ok = await confirmAction(
      context,
      title: 'Eliminar comentario',
      message: '¿Quieres eliminar este comentario?',
      confirmLabel: 'Eliminar',
    );
    if (!ok || !mounted) return;
    try {
      await _repo.deleteComment(c.id);
      await _load();
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final postOwner = widget.post.authorId == _uid;
    return Scaffold(
      appBar: AppBar(title: const Text('Comentarios')),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _comments.isEmpty
                    ? const Center(child: Text('Sé el primero en comentar'))
                    : ListView.separated(
                        itemCount: _comments.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final c = _comments[i];
                          final canDelete = c.authorId == _uid || postOwner;
                          return ListTile(
                            leading: CircleAvatar(
                                child: Text(c.authorName[0].toUpperCase())),
                            title: Text(c.authorName),
                            subtitle: Text('${c.body}\n${timeAgo(c.createdAt)}'),
                            isThreeLine: true,
                            trailing: canDelete
                                ? IconButton(
                                    icon: const Icon(Icons.delete_outline),
                                    tooltip: 'Eliminar',
                                    onPressed: () => _delete(c),
                                  )
                                : null,
                          );
                        },
                      ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      maxLength: 500,
                      minLines: 1,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'Escribe un comentario',
                        border: OutlineInputBorder(),
                        counterText: '',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: const Icon(Icons.send),
                    tooltip: 'Enviar',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}