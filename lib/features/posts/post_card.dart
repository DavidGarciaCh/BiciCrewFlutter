import 'package:flutter/material.dart';
import '../../core/supabase_config.dart';
import '../../core/utils.dart';
import '../tracking/tracking_models.dart';
import 'comments_page.dart';
import 'post_models.dart';
import 'posts_repository.dart';
import 'route_map.dart';
import 'attendees_page.dart';
import 'post_image.dart';

class PostCard extends StatefulWidget {
  final Post post;
  final void Function(Post post)? onEdit;
  final void Function(Post post)? onDelete;
  const PostCard({super.key, required this.post, this.onEdit, this.onDelete});

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  final _repo = PostsRepository.instance;
  bool _busy = false;
  bool _attendBusy = false;
  Post get _post => widget.post;

  Future<void> _setAttendance(String status) async {
    if (_attendBusy) return;
    final post = _post;
    final previous = post.myAttendance;
    // Tocar la marca activa la quita
    final next = previous == status ? 'none' : status;
    setState(() {
      _attendBusy = true;
      post.myAttendance = next == 'none' ? null : next;
    });
    try {
      await _repo.setAttendance(post.id, next);
    } catch (e) {
      if (!mounted) return;
      setState(() => post.myAttendance = previous);
      showMessage(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _attendBusy = false);
    }
  }

  Widget _attendButton(String status, String label, IconData icon) {
    final selected = _post.myAttendance == status;
    final onPressed = _attendBusy ? null : () => _setAttendance(status);
    return selected
        ? FilledButton.icon(
            onPressed: onPressed, icon: Icon(icon), label: Text(label))
        : OutlinedButton.icon(
            onPressed: onPressed, icon: Icon(icon), label: Text(label));
  }

  Widget _attendance(DateTime? starts, bool mine) {
    final p = _post;
    if (mine) {
      // El organizador ve los contadores y la lista
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          children: [
            const Icon(Icons.groups_outlined, size: 18),
            const SizedBox(width: 6),
            Expanded(
                child: Text(
                    '${p.goingCount} irán · ${p.interestedCount} interesados')),
            TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => AttendeesPage(post: p)),
              ),
              child: const Text('Ver lista'),
            ),
          ],
        ),
      );
    }
    final started = starts != null && starts.isBefore(DateTime.now());
    if (started) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text('Esta ruta ya comenzó',
            style: Theme.of(context).textTheme.bodySmall),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Expanded(child: _attendButton('going', 'Voy', Icons.check_circle_outline)),
          const SizedBox(width: 8),
          Expanded(
              child: _attendButton('interested', 'Me interesa', Icons.star_outline)),
        ],
      ),
    );
  }

  Future<void> _toggleLike() async {
    if (_busy) return;
    final post = _post;
    final wasLiked = post.likedByMe;
    setState(() {
      _busy = true;
      post.likedByMe = !wasLiked;
      post.likeCount += wasLiked ? -1 : 1;
    });
    try {
      if (wasLiked) {
        await _repo.unlike(post.id);
      } else {
        await _repo.like(post.id);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        post.likedByMe = wasLiked;
        post.likeCount += wasLiked ? 1 : -1;
      });
      showMessage(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openComments() {
    final post = _post;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CommentsPage(
          post: post,
          onCountChanged: (n) {
            post.commentCount = n;
            if (mounted) setState(() {});
          },
        ),
      ),
    );
  }

  Widget _stat(String label, String value) => Expanded(
        child: Column(
          children: [
            FittedBox(
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold)),
            ),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );

  Widget _infoRow(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 6),
            Expanded(child: Text(text)),
          ],
        ),
      );

  Widget _completed() {
    final p = _post;
    final km = p.distanceMeters / 1000;
    final speed =
        p.durationSeconds > 0 ? km / (p.durationSeconds / 3600) : 0.0;
    final type = p.activityType;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (type != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              Icon(type.icon, size: 18),
              const SizedBox(width: 6),
              Text(type.label),
            ]),
          ),
        RouteMap(segments: p.routeSegments),
        const SizedBox(height: 8),
        Row(children: [
          _stat('Distancia', '${km.toStringAsFixed(2)} km'),
          _stat('Tiempo', formatDuration(Duration(seconds: p.durationSeconds))),
          _stat('Vel. prom.', '${speed.toStringAsFixed(1)} km/h'),
          _stat('Desnivel', '+${p.elevationGain.toStringAsFixed(0)} m'),
        ]),
      ],
    );
  }

   Widget _planned() {
    final p = _post;
    final title = p.payload['title'] as String? ?? '';
    final meeting = p.payload['meeting_point'] as String? ?? '';
    final starts =
        DateTime.tryParse(p.payload['starts_at'] as String? ?? '')?.toLocal();
    final type = p.activityType;
    final mine = p.authorId == supabase.auth.currentUser?.id;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
        _infoRow(Icons.place_outlined, meeting),
        if (starts != null) _infoRow(Icons.schedule, formatDateTime(starts)),
        if (type != null) _infoRow(type.icon, type.label),
        _attendance(starts, mine),
      ],
    );
  }

  Widget _report() {
    final p = _post;
    final cat = p.payload['category'] as String? ?? 'other';
    final loc = p.payload['location_text'] as String? ?? '';
    final img = p.imagePath;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Chip(
          avatar: Icon(reportCategoryIcons[cat] ?? Icons.info_outline, size: 18),
          label: Text(reportCategories[cat] ?? 'Otro'),
        ),
        if (loc.isNotEmpty) _infoRow(Icons.place_outlined, loc),
        if (img != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: PostImage(path: img),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = _post;
    final mine = p.authorId == supabase.auth.currentUser?.id;
    final theme = Theme.of(context);
    final name = p.authorName.isEmpty ? 'Usuario' : p.authorName;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(child: Text(name[0].toUpperCase())),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(mine ? '$name (tú)' : name,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text(
                        '${postTypeLabels[p.type] ?? p.type}'
                        '${p.publishedAt != null ? ' · ${timeAgo(p.publishedAt!)}' : ''}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (mine)
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'edit') widget.onEdit?.call(p);
                      if (v == 'delete') widget.onDelete?.call(p);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Editar')),
                      PopupMenuItem(value: 'delete', child: Text('Eliminar')),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 10),
            switch (p.type) {
              'route_completed' => _completed(),
              'route_planned' => _planned(),
              _ => _report(),
            },
            if (p.body.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(p.body),
              ),
            const Divider(height: 20),
            Row(
              children: [
                IconButton(
                  icon: Icon(
                    p.likedByMe ? Icons.favorite : Icons.favorite_border,
                    color: p.likedByMe ? Colors.red : null,
                  ),
                  tooltip: 'Me gusta',
                  onPressed: _toggleLike,
                ),
                Text('${p.likeCount}'),
                const SizedBox(width: 12),
                IconButton(
                  icon: const Icon(Icons.chat_bubble_outline),
                  tooltip: 'Comentarios',
                  onPressed: _openComments,
                ),
                Text('${p.commentCount}'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
