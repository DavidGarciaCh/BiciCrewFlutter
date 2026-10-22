import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../../core/supabase_config.dart';
import '../../core/utils.dart';
import '../tracking/data/activity_repository.dart';
import '../tracking/tracking_models.dart';
import 'post_models.dart';
import 'posts_repository.dart';
import 'route_map.dart';

class PostEditorPage extends StatefulWidget {
  final String? type; // al crear
  final Post? post; // al editar
  const PostEditorPage({super.key, this.type, this.post})
      : assert(type != null || post != null);

  @override
  State<PostEditorPage> createState() => _PostEditorPageState();
}

class _PostEditorPageState extends State<PostEditorPage> {
  final _repo = PostsRepository.instance;
  late final String _type = widget.post?.type ?? widget.type!;

  final _body = TextEditingController();
  final _title = TextEditingController();
  final _meeting = TextEditingController();
  final _location = TextEditingController();
  DateTime? _startsAt;
  String _activityType = 'bike';
  String _category = 'road_closed';

  // Ruta completada
  List<LocalActivity> _activities = [];
  String? _activityId;
  List<List<LatLng>> _previewSegments = [];
  bool _loadingActivities = false;

  bool _saving = false;
  bool get _editing => widget.post != null;

  @override
  void initState() {
    super.initState();
    final p = widget.post;
    if (p != null) {
      _body.text = p.body;
      _title.text = p.payload['title'] as String? ?? '';
      _meeting.text = p.payload['meeting_point'] as String? ?? '';
      _location.text = p.payload['location_text'] as String? ?? '';
      _startsAt =
          DateTime.tryParse(p.payload['starts_at'] as String? ?? '')?.toLocal();
      final at = p.payload['activity_type'] as String?;
      if (at != null && ActivityType.values.any((t) => t.name == at)) {
        _activityType = at;
      }
      final cat = p.payload['category'] as String?;
      if (cat != null && reportCategories.containsKey(cat)) _category = cat;
    } else if (_type == 'route_completed') {
      _loadActivities();
    }
  }

  @override
  void dispose() {
    _body.dispose();
    _title.dispose();
    _meeting.dispose();
    _location.dispose();
    super.dispose();
  }

  Future<void> _loadActivities() async {
    setState(() => _loadingActivities = true);
    try {
      final uid = supabase.auth.currentUser!.id;
      final all = await ActivityRepository.instance.listFinished(uid);
      if (!mounted) return;
      setState(() {
        // Solo las ya sincronizadas: el servidor necesita tenerlas
        _activities =
            all.where((a) => a.syncStatus == 'synced').take(8).toList();
        _loadingActivities = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingActivities = false);
    }
  }

  Future<void> _selectActivity(String id) async {
    setState(() {
      _activityId = id;
      _previewSegments = [];
    });
    final r = await ActivityRepository.instance.loadResult(id);
    if (!mounted || _activityId != id) return;
    setState(() => _previewSegments = r?.segments ?? []);
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final initial = (_startsAt != null && _startsAt!.isAfter(now))
        ? _startsAt!
        : now.add(const Duration(days: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return;
    setState(() => _startsAt =
        DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Map<String, dynamic> _buildPayload() {
    switch (_type) {
      case 'route_planned':
        return {
          'title': _title.text.trim(),
          'meeting_point': _meeting.text.trim(),
          'starts_at': _startsAt?.toUtc().toIso8601String(),
          'activity_type': _activityType,
        };
      case 'report':
        return {'category': _category, 'location_text': _location.text.trim()};
      default:
        return {}; // ruta completada: el servidor arma el contenido
    }
  }

  Future<void> _save({required bool publish}) async {
    FocusScope.of(context).unfocus();
    final status = publish ? 'published' : 'draft';
    setState(() => _saving = true);
    try {
      if (_editing) {
        await _repo.update(widget.post!.id,
            status: status, body: _body.text.trim(), payload: _buildPayload());
      } else {
        await _repo.create(
          type: _type,
          status: status,
          body: _body.text.trim(),
          activityId: _activityId,
          payload: _buildPayload(),
        );
      }
      if (!mounted) return;
      showMessage(context, publish ? 'Publicación guardada' : 'Borrador guardado');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---------- Campos según el tipo ----------
  List<Widget> _typeFields() {
    switch (_type) {
      case 'route_completed':
        if (_editing) {
          return [
            const Text('La actividad de una publicación no se puede cambiar.'),
            const SizedBox(height: 8),
            RouteMap(segments: widget.post!.routeSegments),
          ];
        }
        if (_loadingActivities) {
          return [const LinearProgressIndicator()];
        }
        if (_activities.isEmpty) {
          return [
            const Text(
              'No tienes actividades sincronizadas. Finaliza una actividad y '
              'espera a que aparezca con la nube verde en tu historial.',
            ),
          ];
        }
        return [
          Text('Elige la actividad', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          for (final a in _activities)
            ListTile(
              selected: a.id == _activityId,
              leading: Icon(a.id == _activityId
                  ? Icons.check_circle
                  : Icons.circle_outlined),
              title: Text('${a.type.label} · '
                  '${(a.distanceM / 1000).toStringAsFixed(2)} km'),
              subtitle: Text(formatDateTime(a.startedAt)),
              onTap: () => _selectActivity(a.id),
            ),
          if (_previewSegments.isNotEmpty) ...[
            const SizedBox(height: 8),
            RouteMap(segments: _previewSegments),
          ],
        ];

      case 'route_planned':
        return [
          TextField(
            controller: _title,
            maxLength: 100,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
                labelText: 'Título de la ruta', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _meeting,
            maxLength: 200,
            decoration: const InputDecoration(
                labelText: 'Punto de encuentro',
                prefixIcon: Icon(Icons.place_outlined),
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.event),
            label: Text(_startsAt == null
                ? 'Elegir fecha y hora'
                : formatDateTime(_startsAt!)),
            onPressed: _pickDateTime,
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: [
              for (final t in ActivityType.values)
                ButtonSegment(
                    value: t.name, label: Text(t.label), icon: Icon(t.icon)),
            ],
            selected: {_activityType},
            onSelectionChanged: (s) => setState(() => _activityType = s.first),
          ),
        ];

      default: // report
        return [
          Wrap(
            spacing: 8,
            children: [
              for (final e in reportCategories.entries)
                ChoiceChip(
                  avatar: Icon(reportCategoryIcons[e.key], size: 18),
                  label: Text(e.value),
                  selected: _category == e.key,
                  onSelected: (_) => setState(() => _category = e.key),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _location,
            maxLength: 200,
            decoration: const InputDecoration(
                labelText: 'Ubicación (calle, barrio, referencia)',
                prefixIcon: Icon(Icons.place_outlined),
                border: OutlineInputBorder()),
          ),
        ];
    }
  }

  String get _bodyLabel => switch (_type) {
        'route_completed' => 'Cuéntanos algo sobre tu ruta (opcional)',
        'route_planned' => 'Descripción (opcional)',
        _ => 'Describe la novedad',
      };

  @override
  Widget build(BuildContext context) {
    final published = widget.post?.status == 'published';
    return Scaffold(
      appBar: AppBar(
        title: Text(_editing
            ? 'Editar publicación'
            : postTypeLabels[_type] ?? 'Nueva publicación'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ..._typeFields(),
            const SizedBox(height: 12),
            TextField(
              controller: _body,
              maxLength: 2000,
              minLines: 3,
              maxLines: 8,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                  labelText: _bodyLabel, border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : () => _save(publish: false),
                    child: Text(published ? 'Pasar a borrador' : 'Guardar borrador'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _saving ? null : () => _save(publish: true),
                    child: _saving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(published ? 'Guardar cambios' : 'Publicar'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}