import 'package:bicicrew/features/social/search_user_page.dart';
import 'package:flutter/material.dart';
import 'person_tile.dart';
import 'social_repository.dart';

class FriendsPage extends StatefulWidget {
  const FriendsPage({super.key});

  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage> {
  final _repo = SocialRepository.instance;
  List<Person> _rels = [];
  List<Person> _blocked = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results =
          await Future.wait([_repo.relationships(), _repo.blocked()]);
      if (!mounted) return;
      setState(() {
        _rels = results[0];
        _blocked = results[1];
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Widget _tile(Person p) => PersonTile(
        key: ValueKey('${p.relation}-${p.id}'),
        person: p,
        onChanged: _load,
      );

  Widget _empty(String text) => RefreshIndicator(
        onRefresh: _load,
        child: ListView(children: [
          const SizedBox(height: 120),
          Center(child: Text(text)),
        ]),
      );

  Widget _header(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall),
      );

  Widget _friendsTab(List<Person> friends) {
    if (friends.isEmpty) {
      return _empty('Aún no tienes amigos.\nUsa la lupa para buscar personas.');
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(children: friends.map(_tile).toList()),
    );
  }

  Widget _requestsTab(List<Person> incoming, List<Person> outgoing) {
    if (incoming.isEmpty && outgoing.isEmpty) {
      return _empty('No tienes solicitudes pendientes');
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(children: [
        if (incoming.isNotEmpty) ...[
          _header('Recibidas'),
          ...incoming.map(_tile),
        ],
        if (outgoing.isNotEmpty) ...[
          _header('Enviadas'),
          ...outgoing.map(_tile),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final friends = _rels.where((p) => p.relation == 'friend').toList();
    final incoming = _rels.where((p) => p.relation == 'incoming').toList();
    final outgoing = _rels.where((p) => p.relation == 'outgoing').toList();

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Amigos'),
          actions: [
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: 'Buscar personas',
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SearchUsersPage()),
                );
                _load(); // al volver, se refresca por si hubo cambios
              },
            ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(text: 'Amigos (${friends.length})'),
              Tab(text: 'Solicitudes (${incoming.length})'),
              const Tab(text: 'Bloqueados'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('No se pudo cargar:\n$_error',
                              textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          FilledButton(
                              onPressed: _load, child: const Text('Reintentar')),
                        ],
                      ),
                    ),
                  )
                : TabBarView(
                    children: [
                      _friendsTab(friends),
                      _requestsTab(incoming, outgoing),
                      _blocked.isEmpty
                          ? _empty('No has bloqueado a nadie')
                          : RefreshIndicator(
                              onRefresh: _load,
                              child: ListView(
                                  children: _blocked.map(_tile).toList()),
                            ),
                    ],
                  ),
      ),
    );
  }
}