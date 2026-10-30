import 'package:flutter/material.dart';
import '../search/search_page.dart';
import 'communities_repository.dart';
import 'community_models.dart';
import 'community_page.dart';
import 'community_widgets.dart';
import 'create_community_page.dart';

class CommunitiesPage extends StatefulWidget {
  const CommunitiesPage({super.key});

  @override
  State<CommunitiesPage> createState() => _CommunitiesPageState();
}

class _CommunitiesPageState extends State<CommunitiesPage> {
  final _repo = CommunitiesRepository.instance;
  List<Community> _mine = [];
  List<Community> _suggested = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final (mine, suggested) = await (_repo.mine(), _repo.suggested()).wait;
      if (!mounted) return;
      setState(() {
        _mine = mine;
        _suggested = suggested;
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

  Future<void> _create() async {
    final id = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const CreateCommunityPage()),
    );
    if (id == null || !mounted) return;
    await _load();
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CommunityPage(communityId: id)),
    );
    _load();
  }

  Widget _list(List<Community> items, String emptyText) {
    return RefreshIndicator(
      onRefresh: _load,
      child: items.isEmpty
          ? ListView(children: [
              const SizedBox(height: 100),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(emptyText, textAlign: TextAlign.center),
              ),
            ])
          : ListView.separated(
              padding: const EdgeInsets.only(bottom: 88),
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) => CommunityTile(
                key: ValueKey(items[i].id),
                community: items[i],
                onChanged: _load,
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Comunidades'),
          actions: [
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: 'Buscar',
              onPressed: () async {
                await Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const SearchPage()));
                _load();
              },
            ),
            IconButton(
              icon: const Icon(Icons.vpn_key_outlined),
              tooltip: 'Unirme con código',
              onPressed: () => showJoinByCodeDialog(context, onJoined: _load),
            ),
          ],
          bottom: const TabBar(tabs: [
            Tab(text: 'Mis comunidades'),
            Tab(text: 'Para ti'),
          ]),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _create,
          icon: const Icon(Icons.add),
          label: const Text('Crear'),
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
                              onPressed: _load,
                              child: const Text('Reintentar')),
                        ],
                      ),
                    ),
                  )
                : TabBarView(children: [
                    _list(_mine,
                        'Aún no perteneces a ninguna comunidad.\nMira la pestaña "Para ti" o crea una.'),
                    _list(_suggested,
                        'No hay sugerencias por ahora.\nCrea la primera comunidad o usa un código de invitación.'),
                  ]),
      ),
    );
  }
}