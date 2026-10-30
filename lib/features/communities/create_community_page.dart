import 'package:flutter/material.dart';
import '../../core/utils.dart';
import 'communities_repository.dart';
import 'community_models.dart';

class CreateCommunityPage extends StatefulWidget {
  const CreateCommunityPage({super.key});

  @override
  State<CreateCommunityPage> createState() => _CreateCommunityPageState();
}

class _CreateCommunityPageState extends State<CreateCommunityPage> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _city = TextEditingController();
  String _activityType = 'any';
  bool _isPrivate = false;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _city.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    try {
      // Las reglas (longitudes, máximo de comunidades) las valida el servidor
      final id = await CommunitiesRepository.instance.create(
        name: _name.text.trim(),
        description: _description.text.trim(),
        activityType: _activityType,
        city: _city.text.trim(),
        isPrivate: _isPrivate,
      );
      if (!mounted) return;
      Navigator.pop(context, id);
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Crear comunidad')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _name,
              maxLength: 60,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                  labelText: 'Nombre', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _description,
              maxLength: 500,
              minLines: 3,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                  labelText: 'Descripción (opcional)',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            Text('Tipo de actividad',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: [
                for (final e in communityActivityLabels.entries)
                  ChoiceChip(
                    avatar: Icon(communityActivityIcons[e.key], size: 18),
                    label: Text(e.value),
                    selected: _activityType == e.key,
                    onSelected: (_) => setState(() => _activityType = e.key),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _city,
              maxLength: 80,
              decoration: const InputDecoration(
                labelText: 'Ciudad (opcional)',
                prefixIcon: Icon(Icons.place_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Comunidad privada'),
              subtitle: const Text(
                  'No aparece en búsquedas ni sugerencias. Solo se entra con el código de invitación.'),
              value: _isPrivate,
              onChanged: (v) => setState(() => _isPrivate = v),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _create,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Crear comunidad'),
            ),
          ],
        ),
      ),
    );
  }
}