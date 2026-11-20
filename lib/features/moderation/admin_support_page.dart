import 'package:flutter/material.dart';
import '../../core/utils.dart';
import '../posts/post_image.dart';
import 'moderation_models.dart';
import 'moderation_repository.dart';

class AdminSupportPage extends StatefulWidget {
  final SupportRequest request;
  const AdminSupportPage({super.key, required this.request});

  @override
  State<AdminSupportPage> createState() => _AdminSupportPageState();
}

class _AdminSupportPageState extends State<AdminSupportPage> {
  final _response = TextEditingController();
  late String _status =
      widget.request.status == 'open' ? 'in_review' : widget.request.status;
  bool _saving = false;
  SupportRequest get s => widget.request;

  @override
  void initState() {
    super.initState();
    _response.text = s.adminResponse ?? '';
  }

  @override
  void dispose() {
    _response.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    try {
      await ModerationRepository.instance
          .respondSupport(s.id, _status, _response.text.trim());
      if (!mounted) return;
      showMessage(context, 'Solicitud actualizada');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(supportKinds[s.kind] ?? 'Solicitud')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(s.reason, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('${s.userName ?? ''} · ${timeAgo(s.createdAt)}',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            Text(s.details),
            for (final path in s.attachments)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: PostImage(
                    path: path, bucket: 'support-attachments', height: 200),
              ),
            const SizedBox(height: 20),
            Text('Estado', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: [
                for (final e in const {
                  'in_review': 'En revisión',
                  'answered': 'Respondida',
                  'closed': 'Cerrada',
                }.entries)
                  ChoiceChip(
                    label: Text(e.value),
                    selected: _status == e.key,
                    onSelected: (_) => setState(() => _status = e.key),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _response,
              maxLength: 1000,
              minLines: 3,
              maxLines: 8,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Respuesta para el usuario',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }
}