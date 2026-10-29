import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void showMessage(BuildContext context, String text, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(text),
      backgroundColor: error ? Theme.of(context).colorScheme.error : null,
    ),
  );
}

/// Error con un mensaje ya listo para mostrar al usuario
class AppException implements Exception {
  final String message;
  const AppException(this.message);
}

/// Convierte cualquier error en un texto comprensible (RNF-02).
/// Los mensajes del servidor (trigger/funciones SQL) ya vienen en español.
String errorText(Object e) {
  if (e is PostgrestException) return e.message;
  if (e is AppException) return e.message;
  if (e is StorageException) {
    return 'No se pudo subir la imagen. Revisa tu conexión e inténtalo de nuevo.';
  }
  return 'Error de conexión. Intenta de nuevo.';
}

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

String timeAgo(DateTime d) {
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return 'ahora';
  if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'hace ${diff.inHours} h';
  if (diff.inDays < 7) return 'hace ${diff.inDays} d';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year}';
}