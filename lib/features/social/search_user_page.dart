import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/utils.dart';
import 'person_tile.dart';
import 'social_repository.dart';

class SearchUsersPage extends StatefulWidget {
  const SearchUsersPage({super.key});

  @override
  State<SearchUsersPage> createState() => _SearchUsersPageState();
}

class _SearchUsersPageState extends State<SearchUsersPage> {
  final _repo = SocialRepository.instance;
  final _controller = TextEditingController();
  Timer? _debounce;
  List<Person> _results = [];
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
        _results = [];
        _query = q;
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final r = await _repo.search(q);
      if (!mounted || q != _controller.text.trim()) return; // respuesta vieja
      setState(() {
        _results = r;
        _query = q;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      showMessage(context, 'No se pudo buscar. Intenta de nuevo.', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (_query.length < 2) {
      body = const Center(child: Text('Escribe al menos 2 letras'));
    } else if (_loading && _results.isEmpty) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_results.isEmpty) {
      body = Center(child: Text('Sin resultados para "$_query"'));
    } else {
      body = ListView(
        children: _results
            .map((p) => PersonTile(
                  key: ValueKey('${p.relation}-${p.id}'),
                  person: p,
                  onChanged: () => _search(_controller.text.trim()),
                ))
            .toList(),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          onChanged: _onChanged,
          decoration: const InputDecoration(
            hintText: 'Buscar personas por nombre',
            border: InputBorder.none,
          ),
        ),
      ),
      body: body,
    );
  }
}