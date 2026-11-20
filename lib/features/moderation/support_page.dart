import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/utils.dart';
import '../posts/post_image.dart';
import 'moderation_models.dart';
import 'moderation_repository.dart';

class SupportPage extends StatefulWidget {
  const SupportPage({super.key});

  @override
  State<SupportPage> createState() => _SupportPageState();
}

class _SupportPageState extends State<SupportPage> {
  final _repo = ModerationRepository.instance;
  List<SupportRequest> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await _repo.mySupport();
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showMessage(context, errorText(e), error: true);
    }
  }

  Future<void> _new() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const SupportFormPage()),
    );
    if (ok == true) {
      if (mounted) showMessage(context, 'Solicitud enviada. Te responderemos aquí.');
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ayuda y soporte')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _new,
        icon: const Icon(Icons.add),
        label: const Text('Nueva solicitud'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _items.isEmpty
                  ? ListView(children: const [
                      SizedBox(height: 120),
                      Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No has enviado solicitudes.\n'
                          'Usa el botón para enviar una petición, queja, reclamo o sugerencia.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ])
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 88),
                      itemCount: _items.length,
                      itemBuilder: (_, i) {
                        final r = _items[i];
                        return ExpansionTile(
                          leading: const Icon(Icons.support_agent),
                          title: Text(r.reason),
                          subtitle: Text(
                              '${supportKinds[r.kind]} · ${supportStatusLabels[r.status]} · ${timeAgo(r.createdAt)}'),
                          expandedAlignment: Alignment.centerLeft,
                          expandedCrossAxisAlignment: CrossAxisAlignment.start,
                          childrenPadding:
                              const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          children: [
                            Text(r.details),
                            for (final path in r.attachments)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: PostImage(
                                    path: path,
                                    bucket: 'support-attachments',
                                    height: 160),
                              ),
                            if (r.adminResponse != null)
                              Container(
                                width: double.infinity,
                                margin: const EdgeInsets.only(top: 12),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primaryContainer,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Respuesta del equipo',
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 4),
                                    Text(r.adminResponse!),
                                  ],
                                ),
                              ),
                          ],
                        );
                      },
                    ),
            ),
    );
  }
}

class SupportFormPage extends StatefulWidget {
  const SupportFormPage({super.key});

  @override
  State<SupportFormPage> createState() => _SupportFormPageState();
}

class _SupportFormPageState extends State<SupportFormPage> {
  final _repo = ModerationRepository.instance;
  final _picker = ImagePicker();
  final _reason = TextEditingController();
  final _details = TextEditingController();
  String _kind = 'sugerencia';
  final List<XFile> _files = [];
  bool _sending = false;

  @override
  void dispose() {
    _reason.dispose();
    _details.dispose();
    super.dispose();
  }

  Future<void> _addImage() async {
    if (_files.length >= 3) {
      showMessage(context, 'Máximo 3 adjuntos', error: true);
      return;
    }
    try {
      final f = await _picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 1600,
          maxHeight: 1600,
          imageQuality: 80);
      if (f != null && mounted) setState(() => _files.add(f));
    } catch (_) {
      if (mounted) {
        showMessage(context, 'No se pudo abrir la galería', error: true);
      }
    }
  }

  Future<void> _send() async {
    FocusScope.of(context).unfocus();
    setState(() => _sending = true);
    final uploaded = <String>[];
    try {
      for (final f in _files) {
        uploaded.add(await _repo.uploadAttachment(f));
      }
      // Las reglas (longitudes, límite diario) las valida el servidor
      await _repo.createSupport(
        kind: _kind,
        reason: _reason.text.trim(),
        details: _details.text.trim(),
        attachments: uploaded,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      for (final p in uploaded) {
        await _repo.deleteAttachment(p); // no dejamos archivos huérfanos
      }
      if (mounted) showMessage(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nueva solicitud')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Wrap(
              spacing: 8,
              children: [
                for (final e in supportKinds.entries)
                  ChoiceChip(
                    label: Text(e.value),
                    selected: _kind == e.key,
                    onSelected: (_) => setState(() => _kind = e.key),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _reason,
              maxLength: 100,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                  labelText: 'Razón (resumen corto)',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _details,
              maxLength: 2000,
              minLines: 5,
              maxLines: 10,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                  labelText: 'Cuéntanos con detalle',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            Text('Adjuntos (opcional, máx. 3)',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < _files.length; i++)
                  Chip(
                    avatar: const Icon(Icons.image_outlined, size: 18),
                    label: SizedBox(
                      width: 110,
                      child: Text(_files[i].name, overflow: TextOverflow.ellipsis),
                    ),
                    onDeleted: _sending
                        ? null
                        : () => setState(() => _files.removeAt(i)),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.attach_file, size: 18),
                  label: const Text('Adjuntar imagen'),
                  onPressed: _sending ? null : _addImage,
                ),
              ],
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _sending ? null : _send,
              child: _sending
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Enviar solicitud'),
            ),
          ],
        ),
      ),
    );
  }
}