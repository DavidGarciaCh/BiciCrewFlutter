import 'package:flutter/material.dart';
import '../../core/utils.dart';
import 'communities_repository.dart';
import 'community_models.dart';
import 'community_page.dart';

/// Fila de una comunidad: sirve para mis comunidades, sugerencias y búsqueda
class CommunityTile extends StatelessWidget {
  final Community community;
  final VoidCallback onChanged;
  const CommunityTile(
      {super.key, required this.community, required this.onChanged});

  Future<void> _join(BuildContext context) async {
    try {
      await CommunitiesRepository.instance.join(community.id);
      if (context.mounted) showMessage(context, 'Te uniste a ${community.name}');
      onChanged();
    } catch (e) {
      if (context.mounted) showMessage(context, errorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = community;
    final info = [
      communityActivityLabels[c.activityType] ?? '',
      if (c.city != null && c.city!.isNotEmpty) c.city!,
      '${c.memberCount} ${c.memberCount == 1 ? 'integrante' : 'integrantes'}',
    ].join(' · ');

    return ListTile(
      leading: CircleAvatar(
        child: Icon(communityActivityIcons[c.activityType] ?? Icons.groups),
      ),
      title: Row(
        children: [
          Flexible(child: Text(c.name, overflow: TextOverflow.ellipsis)),
          if (c.isPrivate)
            const Padding(
              padding: EdgeInsets.only(left: 6),
              child: Icon(Icons.lock_outline, size: 16),
            ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(info),
          if (c.reason != null)
            Text(c.reason!,
                style: TextStyle(
                    fontSize: 12, color: Theme.of(context).colorScheme.primary)),
        ],
      ),
      trailing: c.isMember
          ? const Icon(Icons.check_circle, color: Colors.green)
          : c.isPrivate
              ? null
              : FilledButton.tonal(
                  onPressed: () => _join(context),
                  child: const Text('Unirme'),
                ),
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => CommunityPage(communityId: c.id)),
        );
        onChanged();
      },
    );
  }
}

/// Pide un código de invitación y entra a la comunidad
Future<void> showJoinByCodeDialog(BuildContext context,
    {VoidCallback? onJoined}) async {
  // No se hace dispose: el diálogo todavía se está cerrando con animación
  final controller = TextEditingController();
  final code = await showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Unirme con código'),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 16,
        textCapitalization: TextCapitalization.characters,
        decoration: const InputDecoration(
          hintText: 'Código de invitación',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: const Text('Unirme'),
        ),
      ],
    ),
  );
  if (code == null || code.isEmpty || !context.mounted) return;
  try {
    final id = await CommunitiesRepository.instance.joinByCode(code);
    if (!context.mounted) return;
    showMessage(context, 'Te uniste a la comunidad');
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CommunityPage(communityId: id)),
    );
    onJoined?.call();
  } catch (e) {
    if (context.mounted) showMessage(context, errorText(e), error: true);
  }
}