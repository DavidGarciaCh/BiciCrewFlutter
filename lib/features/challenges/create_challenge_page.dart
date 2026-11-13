import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../../core/supabase_config.dart';
import '../../core/utils.dart';
import '../posts/route_map.dart';
import '../tracking/data/activity_repository.dart';
import '../tracking/tracking_models.dart';
import 'challenges_repository.dart';

class CreateChallengePage extends StatefulWidget {
  const CreateChallengePage({super.key});

  @override
  State<CreateChallengePage> createState() => _CreateChallengePageState();
}

class _CreateChallengePageState extends State<CreateChallengePage> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  List<LocalActivity> _activities = [];
  String? _activityId;
  List<List<LatLng>> _preview = [];
  String _visibility = 'public';
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadActivities();
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _loadActivities() async {
    try {
      final uid = supabase.auth.currentUser!.id;
      final all = await ActivityRepository.instance.listFinished(uid);
      if (!mounted) return;
      setState(() {
        // Solo las ya sincronizadas: el servidor necesita tener los puntos
        _activities =
            all.where((a) => a.syncStatus == 'synced').take(15).toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _select(LocalActivity a) async {
    setState(() {
      _activityId = a.id;
      _preview = [];
      if (_title.text.isEmpty) {
        _title.text = 'Ruta de ${a.type.label.toLowerCase()} '
            '(${(a.distanceM / 1000).toStringAsFixed(1)} km)';
      }
    });
    final r = await ActivityRepository.instance.loadResult(a.id);
    if (!mounted || _activityId != a.id) return;
    setState(() => _preview = r?.segments ?? []);
  }

  Future<void> _create() async {
    FocusScope.of(context).unfocus();
    final id = _activityId;
    if (id == null) {
      showMessage(context, 'Elige la actividad que será el desafío', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final challengeId = await ChallengesRepository.instance.create(
        activityId: id,
        title: _title.text.trim(),
        description: _description.text.trim(),
        visibility: _visibility,
      );
      if (!mounted) return;
      Navigator.pop(context, challengeId);
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Crear desafío')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _activities.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Necesitas una actividad sincronizada para crear un desafío.\n'
                        'Finaliza una actividad y espera la nube verde en tu historial.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text('La ruta del desafío',
                          style: Theme.of(context).textTheme.titleSmall),
                      for (final a in _activities)
                        ListTile(
                          selected: a.id == _activityId,
                          leading: Icon(a.id == _activityId
                              ? Icons.check_circle
                              : Icons.circle_outlined),
                          title: Text('${a.type.label} · '
                              '${(a.distanceM / 1000).toStringAsFixed(2)} km'),
                          subtitle: Text(formatDateTime(a.startedAt)),
                          onTap: () => _select(a),
                        ),
                      if (_preview.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        RouteMap(segments: _preview),
                      ],
                      const SizedBox(height: 16),
                      TextField(
                        controller: _title,
                        maxLength: 80,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                            labelText: 'Título', border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _description,
                        maxLength: 500,
                        minLines: 2,
                        maxLines: 5,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                            labelText: 'Descripción (opcional)',
                            border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 12),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                              value: 'public',
                              label: Text('Público'),
                              icon: Icon(Icons.public)),
                          ButtonSegment(
                              value: 'friends',
                              label: Text('Solo amigos'),
                              icon: Icon(Icons.group_outlined)),
                        ],
                        selected: {_visibility},
                        onSelectionChanged: (s) =>
                            setState(() => _visibility = s.first),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _visibility == 'public'
                            ? 'Cualquier usuario podrá ver el punto de inicio y el final de esta ruta.'
                            : 'Solo tus amigos podrán ver y completar este desafío.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _saving ? null : _create,
                        child: _saving
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Crear desafío'),
                      ),
                    ],
                  ),
      ),
    );
  }
}