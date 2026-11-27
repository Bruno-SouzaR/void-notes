import 'package:flutter/material.dart';
import '../theme/void_theme.dart';

/// Single owner of the delete confirmation: same copy, same colours, every surface.
///
/// The card grid and the note detail both call this, so the dialog cannot drift between them.
Future<bool> confirmDeleteDialog(
  BuildContext context, {
  required String noteTitle,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: VoidTheme.surface,
      title: const Text(
        'Excluir nota?',
        style: TextStyle(color: VoidTheme.textPrimary),
      ),
      content: Text(
        noteTitle,
        style: const TextStyle(color: VoidTheme.textSecondary),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Excluir', style: TextStyle(color: VoidTheme.success)),
        ),
      ],
    ),
  );

  return confirmed ?? false;
}
