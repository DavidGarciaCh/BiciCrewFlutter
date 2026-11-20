import 'package:flutter/material.dart';
import '../../core/utils.dart';
import 'moderation_models.dart';
import 'moderation_repository.dart';

Future<void> showReportSheet(
  BuildContext context, {
  String? postId,
  String? userId,
  required String title,
}) async {
  final sent = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) =>
        _ReportSheet(postId: postId, userId: userId, title: title),
  );
  if (sent == true && context.mounted) {
    showMessage(context, 'Reporte enviado. Un administrador lo revisará.');
  }
}

class _ReportSheet extends StatefulWidget {
  final String? postId;
  final String? userId;
  final String title;
  const _ReportSheet({this.postId, this.userId, required this.title});

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  String? _reason;
  final _details = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ModerationRepository.instance.report(
        postId: widget.postId,
        userId: widget.userId,
        reason: _reason!,
        details: _details.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = errorText(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            const Text('¿Cuál es el motivo?'),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: [
                for (final e in reportReasons.entries)
                  ChoiceChip(
                    label: Text(e.value),
                    selected: _reason == e.key,
                    onSelected: (_) => setState(() => _reason = e.key),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _details,
              maxLength: 500,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Detalles (opcional)',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: (_reason == null || _sending) ? null : _send,
                child: _sending
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Enviar reporte'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}