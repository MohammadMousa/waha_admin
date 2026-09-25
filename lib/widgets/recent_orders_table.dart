import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../utils/number_format.dart';

class RecentOrdersTable extends StatelessWidget {
  final List<Map<String, dynamic>> orders;
  const RecentOrdersTable({super.key, required this.orders});

  static final _dateFmt = DateFormat('MMM d, h:mm a');

  String _branchName(Map<String, dynamic> o) {
    final raw = o['store_display_name'];
    if (raw != null) {
      try {
        final m = (raw is Map)
            ? Map<String, dynamic>.from(raw)
            : Map<String, dynamic>.from(
                jsonDecode(raw.toString()) as Map);
        return (m['en'] ?? m['ar'] ?? '').toString().trim();
      } catch (_) {}
    }
    return (o['store_name'] ?? '—').toString();
  }

  String _displayId(Map<String, dynamic> o) {
    final displayId = o['display_id'];
    if (displayId != null) return '#$displayId';
    final id = (o['id'] ?? '').toString();
    return '#${id.length > 8 ? '${id.substring(0, 8)}…' : id}';
  }

  String _date(Map<String, dynamic> o) {
    final raw = o['created_at'];
    if (raw == null) return '—';
    try {
      return _dateFmt.format(DateTime.parse(raw.toString()).toLocal());
    } catch (_) {
      return raw.toString();
    }
  }

  void _exportCsv() {
    final lines = [
      '#,Branch,Date,Total,Currency,Status',
      ...orders.map((o) => [
            _displayId(o),
            '"${_branchName(o)}"',
            _date(o),
            fmtMoney(o['total']),
            o['currency'] ?? 'SAR',
            o['status'] ?? '',
          ].join(',')),
    ];
    final bytes = utf8.encode(lines.join('\n'));
    final blob = html.Blob([bytes], 'text/csv;charset=utf-8;');
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..setAttribute('download', 'recent_orders.csv')
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Recent Orders',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const Spacer(),
                FilledButton.icon(
                  icon: const Icon(Icons.upload_outlined, size: 16),
                  label: const Text('Export', style: TextStyle(fontSize: 13)),
                  onPressed: orders.isEmpty ? null : _exportCsv,
                  style: FilledButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Header row
            _buildRow(
              id: '#',
              branch: 'Branch',
              date: 'Date',
              total: 'Total',
              status: 'Status',
              isHeader: true,
              scheme: scheme,
            ),
            const Divider(height: 1),
            if (orders.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text('No recent orders',
                      style: TextStyle(color: scheme.outline)),
                ),
              )
            else
              ...orders.map((o) => Column(
                    children: [
                      _buildRow(
                        id: _displayId(o),
                        branch: _branchName(o),
                        date: _date(o),
                        total: '${fmtMoney(o['total'])} ${o['currency'] ?? 'SAR'}',
                        status: '${o['status'] ?? ''}',
                        isHeader: false,
                        scheme: scheme,
                        statusValue: o['status'] as String?,
                      ),
                      const Divider(height: 1),
                    ],
                  )),
          ],
        ),
      ),
    );
  }

  Widget _buildRow({
    required String id,
    required String branch,
    required String date,
    required String total,
    required String status,
    required bool isHeader,
    required ColorScheme scheme,
    String? statusValue,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: _cell(id, isHeader, scheme),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Center(child: _cell(branch, isHeader, scheme)),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: _cell(date, isHeader, scheme),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Center(child: _cell(total, isHeader, scheme)),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: Center(
              child: isHeader
                  ? _cell(status, true, scheme)
                  : _StatusBadge(statusValue ?? ''),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cell(String text, bool header, ColorScheme scheme) => Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: header ? FontWeight.w600 : FontWeight.normal,
          color: header ? scheme.onSurfaceVariant : null,
        ),
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      );

}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge(this.status);

  @override
  Widget build(BuildContext context) {
    final s = status.toUpperCase();
    final (bg, fg) = switch (s) {
      'PAID' || 'DONE' => (Colors.green.shade50, Colors.green.shade700),
      'PENDING' => (Colors.orange.shade50, Colors.orange.shade700),
      'CANCELLED' => (Colors.red.shade50, Colors.red.shade700),
      _ => (Colors.grey.shade100, Colors.grey.shade700),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        s,
        style: TextStyle(fontSize: 11, color: fg, fontWeight: FontWeight.w600),
      ),
    );
  }
}
