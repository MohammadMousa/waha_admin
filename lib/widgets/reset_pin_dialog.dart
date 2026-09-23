import 'package:flutter/material.dart';

/// Quick "Reset PIN" action shared by the Employees and Devices list screens
/// — a lightweight alternative to opening the full Edit screen just to set a
/// new PIN. Returns the new 6-digit PIN, or null if cancelled.
///
/// The entered PIN lives only in this dialog's own TextEditingController —
/// never written to SharedPreferences or any other persistent store, and
/// disposed the moment the dialog closes (human lead, 2026-09-23).
Future<String?> showResetPinDialog(BuildContext context, {required String name}) {
  final pinCtrl = TextEditingController();
  bool obscure = true;

  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSt) => AlertDialog(
        title: const Text('Reset PIN'),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Set a new 6-digit PIN for $name.',
                  style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 14),
              TextField(
                controller: pinCtrl,
                autofocus: true,
                obscureText: obscure,
                keyboardType: TextInputType.number,
                maxLength: 6,
                onChanged: (_) => setSt(() {}),
                decoration: InputDecoration(
                  labelText: 'New PIN',
                  counterText: '',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.pin_outlined),
                  suffixIcon: IconButton(
                    icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => setSt(() => obscure = !obscure),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: pinCtrl.text.trim().length == 6
                ? () => Navigator.pop(ctx, pinCtrl.text.trim())
                : null,
            child: const Text('Reset'),
          ),
        ],
      ),
    ),
  ).whenComplete(pinCtrl.dispose);
}
