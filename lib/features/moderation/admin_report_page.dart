import 'package:flutter/material.dart';
import '../../core/utils.dart';
import '../posts/post_image.dart';
import '../posts/post_models.dart';
import 'moderation_models.dart';
import 'moderation_repository.dart';

class AdminReportPage extends StatefulWidget {
  final AdminReport report;
  const AdminReportPage({super.key, required this.report});

  @override
  State<AdminReportPage> createState() => _AdminReportPageState();
}

class _AdminReportPageState extends State<AdminReportPage> {
  final _repo = ModerationRepository.instance;
  bool _busy = false;
  AdminReport get r => widget.report;

  /// Devuelve la nota ('' si no escribió ninguna) o null si canceló
  Future<String?> _askNote({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    // No se hace dispose: el diálogo todavía se está cerrando con animación
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLength: 500,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Nota interna (opcional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return ok == true ? controller.text.trim() : null;
  }

  Future<void> _run(Future<void> Function() action, String okMessage) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      showMessage(context, okMessage);
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _dismiss() async {
    final note = await _askNote(
      title: 'Descartar reporte',
      message: 'El reporte se cerrará sin acciones sobre el contenido ni la cuenta.',
      confirmLabel: 'Descartar',
    );
    if (note == null) return;
    await _run(() => _repo.resolveReport(r.id, 'dismiss', note),
        'Reporte descartado');
  }

  Future<void> _hide() async {
    final note = await _askNote(
      title: 'Ocultar publicación',
      message: 'La publicación dejará de verse para todos. Su autor la verá como '
          '"oculta por moderación". Se cerrarán todos los reportes abiertos sobre ella.',
      confirmLabel: 'Ocultar',
    );
    if (note == null) return;
    await _run(() => _repo.resolveReport(r.id, 'hide_post', note),
        'Publicación ocultada');
  }

  Future<void> _suspend() async {
    final note = await _askNote(
      title: 'Suspender cuenta',
      message: 'La cuenta de ${r.targetUserName} dejará de ser visible y no podrá '
          'iniciar sesión. Podrás reactivarla después.',
      confirmLabel: 'Suspender',
    );
    if (note == null) return;
    await _run(() => _repo.resolveReport(r.id, 'suspend_user', note),
        'Cuenta suspendida');
  }

  Future<void> _restore() async {
    final note = await _askNote(
      title: 'Restaurar publicación',
      message: 'La publicación volverá a verse con su fecha original.',
      confirmLabel: 'Restaurar',
    );
    if (note == null) return;
    await _run(() => _repo.restorePost(r.targetPostId!, note),
        'Publicación restaurada');
  }

  Future<void> _reactivate() async {
    final note = await _askNote(
      title: 'Reactivar cuenta',
      message: 'La cuenta de ${r.targetUserName} volverá a estar activa.',
      confirmLabel: 'Reactivar',
    );
    if (note == null) return;
    await _run(() => _repo.reactivateUser(r.targetUserId!, note),
        'Cuenta reactivada');
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 4),
        child: Text(title, style: Theme.of(context).textTheme.titleSmall),
      );

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 110, child: Text(k)),
            Expanded(
                child: Text(v, style: const TextStyle(fontWeight: FontWeight.w600))),
          ],
        ),
      );

  /// Muestra la copia guardada al reportar (evidencia), no el contenido actual
  Widget _evidence() {
    final s = r.snapshot;
    if (!r.isPost) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.person_outline),
          title: Text(r.targetUserName),
          subtitle: Text((s['city'] as String?) ?? ''),
        ),
      );
    }
    final type = s['post_type'] as String? ?? '';
    final payload = s['payload'] is Map
        ? Map<String, dynamic>.from(s['payload'] as Map)
        : <String, dynamic>{};
    final body = (s['body'] as String?) ?? '';
    final image = payload['image_path'] as String?;
    final category = payload['category'] as String?;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(postTypeLabels[type] ?? type,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            if (payload['title'] != null) Text('${payload['title']}'),
            if (payload['meeting_point'] != null)
              Text('Punto de encuentro: ${payload['meeting_point']}'),
            if (category != null) Text(reportCategories[category] ?? category),
            if ((payload['location_text'] as String?)?.isNotEmpty ?? false)
              Text('Ubicación: ${payload['location_text']}'),
            if (payload['distance_meters'] != null)
              Text('Ruta de ${((payload['distance_meters'] as num) / 1000).toStringAsFixed(2)} km'),
            if (body.isNotEmpty)
              Padding(padding: const EdgeInsets.only(top: 8), child: Text(body)),
            if (image != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: PostImage(path: image),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final open = r.status == 'open';
    final postStatus = switch (r.postStatus) {
      'published' => 'Publicada',
      'hidden' => 'Oculta',
      'draft' => 'Borrador',
      _ => 'Eliminada por su autor',
    };
    final canHide = open && r.isPost && r.postStatus == 'published';
    final canSuspend =
        open && r.targetUserId != null && r.targetUserStatus == 'active';
    final canRestore = !open && r.isPost && r.postStatus == 'hidden';
    final canReactivate = !open && r.targetUserStatus == 'suspended';

    return Scaffold(
      appBar: AppBar(title: const Text('Reporte')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _section('Reporte'),
            _kv('Motivo', reportReasons[r.reason] ?? r.reason),
            _kv('Reportó', r.reporterName),
            _kv('Fecha', formatDateTimeLocal(r.createdAt)),
            if (r.details.isNotEmpty) _kv('Detalles', r.details),
            if (r.sameTarget > 0)
              _kv('Otros reportes', '${r.sameTarget} más sobre lo mismo'),
            _section('Contenido reportado'),
            _evidence(),
            _section('Estado actual'),
            if (r.isPost) _kv('Publicación', postStatus),
            _kv('Cuenta de ${r.targetUserName}',
                r.targetUserStatus == 'suspended'
                    ? 'Suspendida'
                    : r.targetUserStatus == 'active'
                        ? 'Activa'
                        : 'No disponible'),
            if (!open) ...[
              _section('Resolución'),
              _kv('Resultado', switch (r.action) {
                'post_hidden' => 'Publicación ocultada',
                'user_suspended' => 'Cuenta suspendida',
                _ => 'Reporte descartado',
              }),
              if (r.reviewedAt != null)
                _kv('Fecha', formatDateTimeLocal(r.reviewedAt!)),
              if (r.adminNote != null) _kv('Nota', r.adminNote!),
            ],
            const SizedBox(height: 20),
            if (open) ...[
              OutlinedButton.icon(
                onPressed: _busy ? null : _dismiss,
                icon: const Icon(Icons.close),
                label: const Text('Descartar reporte'),
              ),
              if (canHide) ...[
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : _hide,
                  icon: const Icon(Icons.visibility_off_outlined),
                  label: const Text('Ocultar publicación'),
                ),
              ],
              if (canSuspend) ...[
                const SizedBox(height: 8),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.error),
                  onPressed: _busy ? null : _suspend,
                  icon: const Icon(Icons.block),
                  label: const Text('Suspender cuenta'),
                ),
              ],
            ] else ...[
              if (canRestore)
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : _restore,
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('Restaurar publicación'),
                ),
              if (canReactivate) ...[
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : _reactivate,
                  icon: const Icon(Icons.lock_open),
                  label: const Text('Reactivar cuenta'),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

String formatDateTimeLocal(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
}