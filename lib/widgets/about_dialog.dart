import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/app_config.dart';
import '../services/app_info.dart';

/// "About" pop-up: version, build number, build time and API host, with a
/// Copy button.
Future<void> showAboutInfoDialog(BuildContext context) async {
  final text = 'app:     Waha Admin\n'
      'version: ${AppInfo.version}\n'
      'build:   ${AppInfo.buildNumber}\n'
      'built:   ${AppInfo.buildTime}\n'
      'host:    ${AppConfig.apiBaseUrl}';
  var copied = false;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSt) => AlertDialog(
        title: const Text('About'),
        content: SelectableText(
          text,
          textDirection: TextDirection.ltr,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              setSt(() => copied = true);
            },
            child: Text(copied ? 'Copied' : 'Copy'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    ),
  );
}
