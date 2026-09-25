import 'package:flutter/material.dart';

/// Blocking error dialog: the user must click OK, so an error can't be missed
/// the way a toast can (human lead's UI/UX rule, 2026-09-25). Use this for
/// every error; toasts are only for harmless success notices.
Future<void> showErrorDialog(BuildContext context, String message,
    {String title = 'Error'}) {
  final scheme = Theme.of(context).colorScheme;
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      icon: Icon(Icons.error_outline, color: scheme.error, size: 32),
      title: Text(title),
      content: SelectableText(message),
      actions: [
        FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
      ],
    ),
  );
}

/// For forms that keep an `_error` string: call from the top of `build`, then
/// clear the field, so every error set via setState pops up as a blocking
/// dialog exactly once instead of an inline line the user can overlook.
void showErrorDialogLater(BuildContext context, String message) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (context.mounted) showErrorDialog(context, message);
  });
}
