import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/utils.dart';
import 'social_repository.dart';

Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: Text(message),
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
  return ok == true;
}

class PersonTile extends StatelessWidget {
  final Person person;
  final VoidCallback onChanged;
  const PersonTile({super.key, required this.person, required this.onChanged});

  SocialRepository get _repo => SocialRepository.instance;

  Future<void> _run(BuildContext context, Future<void> Function() action,
      String okMessage) async {
    try {
      await action();
      if (context.mounted) showMessage(context, okMessage);
      onChanged();
    } on PostgrestException catch (e) {
      if (context.mounted) showMessage(context, e.message, error: true);
    } catch (_) {
      if (context.mounted) {
        showMessage(context, 'Error de conexión. Intenta de nuevo.',
            error: true);
      }
    }
  }

  Future<void> _removeFriend(BuildContext context) async {
    final ok = await confirmAction(
      context,
      title: 'Eliminar amigo',
      message: '¿Eliminar a ${person.fullName} de tus amigos?',
      confirmLabel: 'Eliminar',
    );
    if (ok && context.mounted) {
      await _run(context, () => _repo.remove(person.id), 'Amistad eliminada');
    }
  }

  Future<void> _block(BuildContext context) async {
    final ok = await confirmAction(
      context,
      title: 'Bloquear usuario',
      message: '${person.fullName} no podrá verte ni interactuar contigo, y tú '
          'tampoco con esa persona. Si eran amigos, la amistad se eliminará.',
      confirmLabel: 'Bloquear',
    );
    if (ok && context.mounted) {
      await _run(context, () => _repo.block(person.id), 'Usuario bloqueado');
    }
  }

  Widget _menu(BuildContext context, {bool canRemove = false}) {
    return PopupMenuButton<String>(
      onSelected: (v) {
        if (v == 'remove') _removeFriend(context);
        if (v == 'block') _block(context);
      },
      itemBuilder: (_) => [
        if (canRemove)
          const PopupMenuItem(value: 'remove', child: Text('Eliminar amigo')),
        const PopupMenuItem(value: 'block', child: Text('Bloquear')),
      ],
    );
  }

  Widget _trailing(BuildContext context) {
    switch (person.relation) {
      case 'blocked':
        return TextButton(
          onPressed: () => _run(context, () => _repo.unblock(person.id),
              'Usuario desbloqueado'),
          child: const Text('Desbloquear'),
        );
      case 'friend':
        return _menu(context, canRemove: true);
      case 'incoming':
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.check_circle, color: Colors.green),
              tooltip: 'Aceptar',
              onPressed: () => _run(
                  context,
                  () => _repo.respond(person.requestId!, accept: true),
                  'Ahora son amigos'),
            ),
            IconButton(
              icon: const Icon(Icons.cancel_outlined),
              tooltip: 'Rechazar',
              onPressed: () => _run(
                  context,
                  () => _repo.respond(person.requestId!, accept: false),
                  'Solicitud rechazada'),
            ),
            _menu(context),
          ],
        );
      case 'outgoing':
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: () => _run(context, () => _repo.remove(person.id),
                  'Solicitud cancelada'),
              child: const Text('Cancelar'),
            ),
            _menu(context),
          ],
        );
      default: // none
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton.tonal(
              onPressed: () => _run(context,
                  () => _repo.sendRequest(person.id), 'Solicitud enviada'),
              child: const Text('Agregar'),
            ),
            _menu(context),
          ],
        );
    }
  }

  String? get _label => switch (person.relation) {
        'friend' => 'Amigos',
        'incoming' => 'Quiere ser tu amigo',
        'outgoing' => 'Solicitud enviada',
        'blocked' => 'Bloqueado',
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      if (person.city != null && person.city!.isNotEmpty) person.city!,
      if (_label != null) _label!,
    ].join(' · ');
    return ListTile(
      leading: CircleAvatar(child: Text(person.initial)),
      title: Text(person.fullName),
      subtitle: subtitle.isEmpty ? null : Text(subtitle),
      trailing: _trailing(context),
    );
  }
}