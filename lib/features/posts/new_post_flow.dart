import 'package:flutter/material.dart';
import 'post_editor_page.dart';
import 'post_models.dart';

const _typeHints = {
  'route_completed': 'Comparte una actividad ya sincronizada',
  'route_planned': 'Invita a tus amigos a una salida',
  'report': 'Avisa de vías cerradas o problemas de tránsito',
};

/// Elige el tipo y abre el editor. Devuelve true si se guardó algo.
Future<bool> startNewPost(BuildContext context,
    {List<String> communityIds = const []}) async {
  final type = await showModalBottomSheet<String>(
    context: context,
    builder: (_) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ListTile(title: Text('¿Qué quieres publicar?')),
          for (final e in postTypeLabels.entries)
            ListTile(
              leading: Icon(postTypeIcons[e.key]),
              title: Text(e.value),
              subtitle: Text(_typeHints[e.key] ?? ''),
              onTap: () => Navigator.pop(context, e.key),
            ),
        ],
      ),
    ),
  );
  if (type == null || !context.mounted) return false;
  final ok = await Navigator.push<bool>(
    context,
    MaterialPageRoute(
      builder: (_) =>
          PostEditorPage(type: type, initialCommunityIds: communityIds),
    ),
  );
  return ok == true;
}