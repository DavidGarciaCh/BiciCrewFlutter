import 'package:flutter/material.dart';
import 'challenge_models.dart';
import 'challenge_page.dart';
import 'challenge_tile.dart';
import 'challenges_repository.dart';
import 'create_challenge_page.dart';

class ChallengesPage extends StatefulWidget {
  const ChallengesPage({super.key});

  @override
  State<ChallengesPage> createState() => _ChallengesPageState();
}

class _ChallengesPageState extends State<ChallengesPage> {
  final _repo = ChallengesRepository.instance;
  List<Challenge> _recommended = [];
  List<Challenge> _explore = [];
  List<Challenge> _mine = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final (rec, exp, mine) = await (
        _repo.list('recommended'),
        _repo.list('explore'),
        _repo.list('mine'),
      ).wait;
      if (!mounted) return;
      setState(() {
        _recommended = rec;
        _explore = exp;
        _mine = mine;
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
      MaterialPageRoute(builder: (_) => const CreateChallengePage()),
    );
    if (id == null || !mounted) return;
    await _load();
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ChallengePage(challengeId: id)),
    );
    _load();
  }

  Widget _list(List<Challenge> items, String emptyText) {
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
              itemBuilder: (_, i) => ChallengeTile(
                key: ValueKey(items[i].id),
                challenge: items[i],
                onChanged: _load,
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Desafíos'),
          bottom: const TabBar(tabs: [
            Tab(text: 'Para ti'),
            Tab(text: 'Explorar'),
            Tab(text: 'Míos'),
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
                    _list(_recommended,
                        'Aún no hay desafíos recomendados.\nCrea uno a partir de una de tus actividades.'),
                    _list(_explore, 'Todavía no hay desafíos disponibles.'),
                    _list(_mine,
                        'No has creado ni completado desafíos.\nUsa el botón Crear.'),
                  ]),
      ),
    );
  }
}