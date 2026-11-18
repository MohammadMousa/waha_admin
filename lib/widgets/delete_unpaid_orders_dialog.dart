import 'package:flutter/material.dart';

import '../services/api_client.dart';

/// Deletes unpaid orders older than N days (optionally for one branch).
/// Shows the count first and asks for confirmation. Returns true if anything
/// was deleted.
class DeleteUnpaidOrdersDialog extends StatefulWidget {
  final String token;
  final List<({int id, String label})> branches;
  const DeleteUnpaidOrdersDialog({super.key, required this.token, required this.branches});

  @override
  State<DeleteUnpaidOrdersDialog> createState() => _DeleteUnpaidOrdersDialogState();
}

class _DeleteUnpaidOrdersDialogState extends State<DeleteUnpaidOrdersDialog> {
  final _daysCtrl = TextEditingController(text: '30');
  int? _branchId;
  int? _count;
  bool _busy = false;
  String? _error;
  String? _result;
  bool _deleted = false;

  @override
  void dispose() {
    _daysCtrl.dispose();
    super.dispose();
  }

  int? get _days {
    final d = int.tryParse(_daysCtrl.text.trim());
    return (d != null && d >= 1) ? d : null;
  }

  Future<void> _check() async {
    final d = _days;
    if (d == null) { setState(() => _error = 'Enter a number of days (1 or more).'); return; }
    setState(() { _busy = true; _error = null; _result = null; _count = null; });
    try {
      final c = await ApiClient().countUnpaidOrders(widget.token, olderThanDays: d, branchId: _branchId);
      if (mounted) setState(() => _count = c);
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiException ? e.message : e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final d = _days;
    if (d == null) return;
    setState(() { _busy = true; _error = null; });
    try {
      final r = await ApiClient().deleteUnpaidOrders(widget.token, olderThanDays: d, branchId: _branchId);
      final del = (r['deleted'] as num?)?.toInt() ?? 0;
      final skipped = (r['skipped'] as num?)?.toInt() ?? 0;
      if (mounted) {
        setState(() {
          _deleted = _deleted || del > 0;
          _count = null;
          _result = 'Deleted $del unpaid order(s)' + (skipped > 0 ? ', skipped $skipped (paid or payment in progress).' : '.');
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiException ? e.message : e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Delete unpaid orders'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Deletes orders that were never paid. Paid orders are never deleted.'),
            const SizedBox(height: 16),
            TextField(
              controller: _daysCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Older than (days)',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() { _count = null; _result = null; }),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int?>(
              value: _branchId,
              decoration: const InputDecoration(labelText: 'Branch', border: OutlineInputBorder()),
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('All branches')),
                for (final b in widget.branches) DropdownMenuItem<int?>(value: b.id, child: Text(b.label)),
              ],
              onChanged: _busy ? null : (v) => setState(() { _branchId = v; _count = null; _result = null; }),
            ),
            const SizedBox(height: 16),
            if (_busy) const LinearProgressIndicator(),
            if (_count != null)
              Text(
                _count == 0
                    ? 'No unpaid orders match.'
                    : '$_count unpaid order(s) will be deleted. This cannot be undone.',
                style: TextStyle(fontWeight: FontWeight.w600, color: _count == 0 ? null : scheme.error),
              ),
            if (_result != null) Text(_result!, style: const TextStyle(fontWeight: FontWeight.w600)),
            if (_error != null) Text(_error!, style: TextStyle(color: scheme.error)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, _deleted), child: const Text('Close')),
        if (_count != null && _count! > 0)
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: scheme.error),
            onPressed: _busy ? null : _delete,
            child: Text('Delete $_count'),
          )
        else
          FilledButton(onPressed: _busy ? null : _check, child: const Text('Check count')),
      ],
    );
  }
}
