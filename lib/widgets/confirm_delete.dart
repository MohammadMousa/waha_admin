import 'package:flutter/material.dart';

import '../services/api_client.dart';
import 'error_dialog.dart';

/// Asks the user to confirm a permanent delete, runs [action], and shows any
/// refusal from the server in a blocking error dialog.
/// Returns true only when the item was actually deleted.
Future<bool> confirmAndDelete(
  BuildContext context, {
  required String title,
  required String message,
  required Future<void> Function() action,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return false;
  try {
    await action();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Deleted'), duration: Duration(seconds: 2)),
      );
    }
    return true;
  } on ApiException catch (e) {
    if (context.mounted) await showErrorDialog(context, e.message);
    return false;
  } catch (e) {
    if (context.mounted) await showErrorDialog(context, 'Delete failed: $e');
    return false;
  }
}
