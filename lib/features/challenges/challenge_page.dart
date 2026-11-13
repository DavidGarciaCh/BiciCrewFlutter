import 'package:flutter/material.dart';
import '../../core/supabase_config.dart';
import '../../core/utils.dart';
import '../posts/route_map.dart';
import '../tracking/data/activity_repository.dart';
import '../tracking/tracking_models.dart';
import 'challenge_models.dart';
import 'challenge_tile.dart';
import 'challenges_repository.dart';

class ChallengePage extends StatefulWidget {
  final String challengeId;
  const ChallengePage({super.key, required this.challengeId});

  @override
  State<ChallengePage> createState() => _ChallengePageState();
}

class _ChallengePageState extends State<ChallengePage> {
  final _repo = ChallengesRepository.instance;
  Challenge? _c;
  List<RankingEntry> _ranking = [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  String get _uid => supabase.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final (c, ranking) = await (
        _repo.get(widget.challengeId),
        _repo.ranking(widget.challengeId),
      ).wait;
      if (!mounted) return;
      setState(() {
        _c = c;
        _ranking = ranking;
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

  Future<void> _register() async {
    final c = _c!;
    List<LocalActivity> options = [];
    try {
      final all = await ActivityRepository.instance.listFinished(_uid);
      options = all
          .where((a) => a.syncStatus == 'synced' && a.type.name == c.activityType)
          .take(15)
          .toList();
    } catch (_) {}
    if (!mounted) return;
    if (options.isEmpty) {
      showMessage(
        context,
        'No tienes actividades sincronizadas de tipo ${c.type.label}. '
        'Finaliza una y espera la nube verde en tu historial.',
        error: true,
      );
      return;
    }

    final chosen = await showModalBottomSheet<LocalActivity>(
      context: context,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('¿Con qué actividad completaste el desafío?')),
            for (final a in options)
              ListTile(
                leading: Icon(a.type.icon),
                title: Text('${(a.distanceM / 1000).toStringAsFixed(2)} km · '
                    '${formatDuration(Duration(seconds: a.durationS))}'),
                subtitle: Text(formatDateTime(a.startedAt)),
                onTap: () => Navigator.pop(context, a),
              ),
          ],
        ),
      ),
    );
    if (chosen == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final r = await _repo.submit(c.id, chosen.id);
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('¡Desafío completado!'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Tiempo: ${formatSeconds(r.durationSeconds)}',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text('Puesto #${r.position} de ${r.participants}'),
              if (r.personalBest) ...[
                const SizedBox(height: 8),
                const Text('¡Nueva marca personal!'),
              ],
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Genial'),
            ),
          ],
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      // El motivo del rechazo es largo: se muestra en un diálogo, no en un aviso
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('No se pudo validar'),
          content: Text(errorText(e)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final ok = await confirmAction(
      context,
      title: 'Eliminar desafío',
      message: 'Se eliminará el desafío con todos los resultados registrados. '
          'Esta acción no se puede deshacer.',
      confirmLabel: 'Eliminar',
    );
    if (!ok || !mounted) return;
    try {
      await _repo.delete(widget.challengeId);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    }
  }

  Widget _statRow(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(label)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      );

  Widget _rankTile(RankingEntry e) {
    final mine = e.userId == _uid;
    final medal = switch (e.position) {
      1 => Colors.amber,
      2 => Colors.blueGrey.shade300,
      3 => Colors.brown.shade300,
      _ => null,
    };
    return ListTile(
      tileColor: mine ? Theme.of(context).colorScheme.primaryContainer : null,
      leading: medal != null
          ? Icon(Icons.emoji_events, color: medal, size: 32)
          : CircleAvatar(
              radius: 16,
              child: Text('${e.position}', style: const TextStyle(fontSize: 13))),
      title: Text(mine ? '${e.name} (tú)' : e.name),
      subtitle: Text(timeAgo(e.completedAt)),
      trailing: Text(formatSeconds(e.durationSeconds),
          style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return Scaffold(
      appBar: AppBar(
        title: Text(c?.title ?? 'Desafío'),
        actions: [
          if (c != null && c.isMine)
            PopupMenuButton<String>(
              onSelected: (_) => _delete(),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'delete', child: Text('Eliminar desafío')),
              ],
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null || c == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error ?? 'No se pudo cargar'),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                    children: [
                      RouteMap(segments: c.segments, height: 220),
                      const SizedBox(height: 12),
                      Text(c.title, style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 4),
                      Text('Creado por ${c.isMine ? 'ti' : c.creatorName}',
                          style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          Chip(
                              avatar: Icon(c.type.icon, size: 18),
                              label: Text(c.type.label)),
                          Chip(
                              avatar: const Icon(Icons.straighten, size: 18),
                              label: Text(
                                  '${(c.distanceMeters / 1000).toStringAsFixed(2)} km')),
                          Chip(
                              avatar: const Icon(Icons.terrain, size: 18),
                              label:
                                  Text('+${c.elevationGain.toStringAsFixed(0)} m')),
                          Chip(
                              avatar: Icon(
                                  c.visibility == 'public'
                                      ? Icons.public
                                      : Icons.group_outlined,
                                  size: 18),
                              label: Text(c.visibility == 'public'
                                  ? 'Público'
                                  : 'Solo amigos')),
                        ],
                      ),
                      if (c.description.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(c.description),
                        ),
                      const SizedBox(height: 12),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            children: [
                              _statRow(Icons.groups_outlined, 'Participantes',
                                  '${c.participants}'),
                              _statRow(
                                  Icons.timer_outlined,
                                  'Tiempo promedio de la comunidad',
                                  c.avgSeconds == null
                                      ? '—'
                                      : formatSeconds(c.avgSeconds!)),
                              _statRow(
                                  Icons.bolt,
                                  'Mejor tiempo',
                                  c.bestSeconds == null
                                      ? '—'
                                      : formatSeconds(c.bestSeconds!)),
                              _statRow(
                                  Icons.person_outline,
                                  'Tu mejor tiempo',
                                  c.myBestSeconds == null
                                      ? 'Aún no participas'
                                      : '${formatSeconds(c.myBestSeconds!)} · #${c.myPosition}'),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _busy ? null : _register,
                        icon: _busy
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.flag),
                        label: const Text('Registrar mi resultado'),
                      ),
                      const SizedBox(height: 16),
                      Text('Clasificación',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 4),
                      if (_ranking.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('Nadie ha completado este desafío todavía.'),
                        )
                      else
                        for (final e in _ranking) _rankTile(e),
                    ],
                  ),
                ),
    );
  }
}