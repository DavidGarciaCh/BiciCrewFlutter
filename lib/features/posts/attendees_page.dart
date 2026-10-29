import 'package:flutter/material.dart';
import '../../core/utils.dart';
import 'post_models.dart';
import 'posts_repository.dart';

class AttendeesPage extends StatefulWidget {
  final Post post;
  const AttendeesPage({super.key, required this.post});

  @override
  State<AttendeesPage> createState() => _AttendeesPageState();
}

class _AttendeesPageState extends State<AttendeesPage> {
  List<Attendee> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await PostsRepository.instance.attendees(widget.post.id);
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showMessage(context, errorText(e), error: true);
    }
  }

  Widget _section(String title, List<Attendee> list) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('$title (${list.length})',
                style: Theme.of(context).textTheme.titleSmall),
          ),
          if (list.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text('Nadie todavía'),
            ),
          for (final a in list)
            ListTile(
              leading: CircleAvatar(child: Text(a.name[0].toUpperCase())),
              title: Text(a.name),
              subtitle: Text(timeAgo(a.createdAt)),
            ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final going = _items.where((a) => a.status == 'going').toList();
    final interested = _items.where((a) => a.status == 'interested').toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Asistentes')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(children: [
                _section('Irán', going),
                _section('Interesados', interested),
              ]),
            ),
    );
  }
}