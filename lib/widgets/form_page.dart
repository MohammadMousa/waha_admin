import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/api_client.dart';
import 'adaptive_shell.dart';

/// One look for every edit page (employee, account, my profile): a header bar
/// with back / title / save, then a centered column with the picture first.
const double kFormMaxWidth = 640;

/// Section title used on every form page.
class FormSectionLabel extends StatelessWidget {
  final String text;
  const FormSectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
      );
}

class FormPageHeader extends StatelessWidget {
  final String title;
  final Widget? badge;
  final bool showSave;
  final bool saving;
  final VoidCallback? onSave;
  final String saveLabel;

  const FormPageHeader({
    super.key,
    required this.title,
    this.badge,
    this.showSave = true,
    this.saving = false,
    this.onSave,
    this.saveLabel = 'Save',
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.fromLTRB(pagePad(context), 16, pagePad(context), 16),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 8),
          Text(title,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700)),
          if (badge != null) ...[const SizedBox(width: 10), badge!],
          const Spacer(),
          if (showSave)
            FilledButton(
              onPressed: saving ? null : onSave,
              child: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(saveLabel),
            ),
        ],
      ),
    );
  }
}

/// Scrolling, centered column of fixed width.
class FormPageBody extends StatelessWidget {
  final List<Widget> children;
  const FormPageBody({super.key, required this.children});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kFormMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [...children, const SizedBox(height: 40)],
            ),
          ),
        ),
      );
}

/// The big centered picture with its edit badge, then Add / Change / Remove.
class PersonAvatar extends StatelessWidget {
  final int? avatarId;
  final Uint8List? pendingBytes;
  final bool busy;
  final VoidCallback onPick;
  final VoidCallback onRemove;
  final double size;

  const PersonAvatar({
    super.key,
    required this.avatarId,
    required this.onPick,
    required this.onRemove,
    this.pendingBytes,
    this.busy = false,
    this.size = 96,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final has = pendingBytes != null || avatarId != null;
    final ImageProvider? image = pendingBytes != null
        ? MemoryImage(pendingBytes!)
        : (avatarId == null ? null : NetworkImage(ApiClient().resourceUrl(avatarId!)));
    return Column(
      children: [
        GestureDetector(
          onTap: busy ? null : onPick,
          child: Stack(
            children: [
              CircleAvatar(
                radius: size / 2,
                backgroundColor: scheme.surfaceContainerHighest,
                foregroundImage: image,
                onForegroundImageError: has ? (_, __) {} : null,
                child: Icon(Icons.person_outline, size: size * 0.42, color: scheme.onSurfaceVariant),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: CircleAvatar(
                  radius: 14,
                  backgroundColor: scheme.primary,
                  child: busy
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: scheme.onPrimary))
                      : Icon(Icons.edit, size: 14, color: scheme.onPrimary),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(onPressed: busy ? null : onPick, child: Text(has ? 'Change photo' : 'Add photo')),
            if (has) TextButton(onPressed: busy ? null : onRemove, child: const Text('Remove photo')),
          ],
        ),
      ],
    );
  }
}
