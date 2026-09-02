import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../router/routes.dart';
import '../services/api_client.dart';
import '../state/auth_state.dart';
import '../widgets/admin_sidebar.dart';

class IntegrationLogsScreen extends StatefulWidget {
  const IntegrationLogsScreen({super.key});

  @override
  State<IntegrationLogsScreen> createState() => _IntegrationLogsScreenState();
}

class _IntegrationLogsScreenState extends State<IntegrationLogsScreen> {
  String? _entityType;
  String? _status;

  List<Map<String, dynamic>> _items = [];
  int _totalCount = 0;
  int _page       = 0;
  static const _pageSize = 20;

  int  _sortCol = 0;
  bool _sortAsc = false;

  bool    _loading = true;
  String? _error;

  static final _dtFmt = DateFormat('yyyy-MM-dd HH:mm');
  static const _statuses = [null, 'PENDING', 'DONE', 'FAILED', 'SYNCED', 'COMPLETED'];
  static const _types    = [null, 'ORDER', 'PRODUCT', 'CATEGORY'];
  static const _cols = ['#ID', 'Type', 'Entity ID', 'Operation', 'Status', 'Attempts', 'Date', 'Error'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final token = context.read<AuthState>().token;
    if (token == null) { _redirectLogin(); return; }
    try {
      final data = await ApiClient().getIntegrationLogs(
        token, entityType: _entityType, status: _status, page: _page, size: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _items      = (data['items'] as List? ?? []).cast<Map<String, dynamic>>();
        _totalCount = (data['totalCount'] as num?)?.toInt() ?? 0;
        _loading    = false;
      });
    } on ApiException catch (e) {
      if (e.statusCode == 401) { _redirectLogin(); return; }
      if (mounted) setState(() { _error = e.message; _loading = false; });
    }
  }

  void _sort(int col, bool asc) {
    setState(() {
      _sortCol = col;
      _sortAsc = asc;
      final keys = ['id', 'entity_type', 'entity_id', 'operation', 'status', 'attempts', 'created_at', 'last_error'];
      final key = keys[col];
      _items.sort((a, b) {
        dynamic va = a[key], vb = b[key];
        if (va == null && vb == null) return 0;
        if (va == null) return asc ? -1 : 1;
        if (vb == null) return asc ? 1 : -1;
        if (va is num && vb is num) return asc ? va.compareTo(vb) : vb.compareTo(va);
        return asc ? '$va'.compareTo('$vb') : '$vb'.compareTo('$va');
      });
    });
  }

  void _exportCsv() {
    final lines = [
      '#ID,Type,Entity ID,Operation,Status,Attempts,Date,Error',
      ..._items.map((r) {
        final dt = r['created_at'] != null
            ? _dtFmt.format(DateTime.parse(r['created_at'].toString()).toLocal())
            : '';
        return [
          r['id'] ?? '',
          r['entity_type'] ?? '',
          '"${r['entity_id'] ?? ''}"',
          r['operation'] ?? '',
          r['status'] ?? '',
          r['attempts'] ?? 0,
          '"$dt"',
          '"${(r['last_error'] ?? '').toString().replaceAll('"', "'")}"',
        ].join(',');
      }),
    ];
    _download('sync_logs.csv', lines.join('\n'), 'text/csv;charset=utf-8;');
  }

  void _exportPdf() {
    final rows = _items.map((r) {
      final dt = r['created_at'] != null
          ? _dtFmt.format(DateTime.parse(r['created_at'].toString()).toLocal())
          : '—';
      final status = r['status'] ?? '—';
      final color = switch (status) {
        'DONE' || 'SYNCED' || 'COMPLETED' => '#2E7D32',
        'FAILED'  => '#C62828',
        'PENDING' => '#F57C00',
        _         => '#555',
      };
      final err = (r['last_error'] ?? '').toString()
          .replaceAll('&', '&amp;').replaceAll('<', '&lt;');
      return '''<tr>
        <td>${r['id'] ?? ''}</td>
        <td>${r['entity_type'] ?? ''}</td>
        <td style="font-size:11px">${r['entity_id'] ?? ''}</td>
        <td>${r['operation'] ?? ''}</td>
        <td><span style="color:$color;font-weight:600">$status</span></td>
        <td style="text-align:right">${r['attempts'] ?? 0}</td>
        <td>$dt</td>
        <td style="font-size:11px;color:#C62828">$err</td>
      </tr>''';
    }).join('\n');

    final html_str = '''<!DOCTYPE html><html><head><meta charset="utf-8">
<title>Sync Logs</title>
<style>body{font-family:sans-serif;font-size:12px}
table{width:100%;border-collapse:collapse}
th{background:#f5f5f5;padding:6px 8px;text-align:left;border-bottom:2px solid #ddd}
td{padding:5px 8px;border-bottom:1px solid #eee}
@media print{button{display:none}}</style></head>
<body><h2>Sync Logs</h2>
<table><thead><tr><th>#ID</th><th>Type</th><th>Entity ID</th>
<th>Operation</th><th>Status</th><th>Attempts</th><th>Date</th><th>Error</th></tr></thead>
<tbody>$rows</tbody></table>
<script>window.onload=()=>window.print();</script></body></html>''';

    final blob = html.Blob([utf8.encode(html_str)], 'text/html;charset=utf-8');
    final blobUrl = html.Url.createObjectUrlFromBlob(blob);
    html.window.open(blobUrl, '_blank');
  }

  void _download(String name, String content, String mime) {
    final bytes = utf8.encode(content);
    final blob  = html.Blob([bytes], mime);
    final url   = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..setAttribute('download', name)
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  void _showError(BuildContext ctx, Map<String, dynamic> row) {
    final scheme = Theme.of(ctx).colorScheme;
    final fullError = row['last_error']?.toString() ?? '(no error recorded)';
    showDialog(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        title: Row(children: [
          Icon(Icons.error_outline, color: scheme.error, size: 20),
          const SizedBox(width: 8),
          Text('Error — #${row['id']}', style: const TextStyle(fontSize: 16)),
        ]),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (row['entity_type'] != null)
                Text('${row['entity_type']} · ${row['entity_id']} · ${row['operation']}',
                    style: TextStyle(fontSize: 12, color: scheme.outline)),
              const SizedBox(height: 12),
              Container(
                constraints: const BoxConstraints(maxHeight: 320),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.errorContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: scheme.error.withValues(alpha: 0.3)),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    fullError,
                    style: TextStyle(fontSize: 13, color: scheme.onSurface,
                        fontFamily: 'monospace'),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.download_outlined, size: 16),
            label: const Text('Save .txt'),
            onPressed: () {
              _download('error_${row['id']}.txt', fullError, 'text/plain;charset=utf-8;');
            },
          ),
          TextButton.icon(
            icon: const Icon(Icons.copy_outlined, size: 16),
            label: const Text('Copy'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: fullError));
              Navigator.pop(dialogCtx);
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(content: Text('Copied to clipboard')));
            },
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _redirectLogin() {
    context.read<AuthState>().logout();
    Navigator.of(context).pushReplacementNamed(Routes.login);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: Row(
        children: [
          const AdminSidebar(currentRoute: Routes.integrationLogs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(scheme),
                _buildFilters(scheme),
                Expanded(child: _buildTable(scheme)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(ColorScheme scheme) => Container(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        child: Row(
          children: [
            Text('Sync Logs',
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const Spacer(),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(right: 12),
                child: SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            OutlinedButton.icon(
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
              label: const Text('PDF'),
              onPressed: _items.isEmpty ? null : _exportPdf,
              style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              icon: const Icon(Icons.download_outlined, size: 16),
              label: const Text('Export CSV'),
              onPressed: _items.isEmpty ? null : _exportCsv,
              style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.refresh_outlined),
              tooltip: 'Refresh',
              onPressed: _loading ? null : () { _page = 0; _load(); },
            ),
          ],
        ),
      );

  Widget _buildFilters(ColorScheme scheme) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
        child: Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            _LogFilterDrop<String?>(
              value: _entityType, hint: 'All Types',
              items: _types.map((t) => DropdownMenuItem(value: t,
                  child: Text(t ?? 'All Types'))).toList(),
              onChanged: (v) { setState(() { _entityType = v; _page = 0; }); _load(); },
            ),
            _LogFilterDrop<String?>(
              value: _status, hint: 'All Statuses',
              items: _statuses.map((s) => DropdownMenuItem(value: s,
                  child: Text(s ?? 'All Statuses'))).toList(),
              onChanged: (v) { setState(() { _status = v; _page = 0; }); _load(); },
            ),
          ],
        ),
      );

  Widget _buildTable(ColorScheme scheme) {
    if (_error != null) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(_error!, style: TextStyle(color: scheme.error)),
        const SizedBox(height: 16),
        FilledButton(onPressed: _load, child: const Text('Retry')),
      ]));
    }

    final from = _page * _pageSize + 1;
    final to   = ((_page + 1) * _pageSize).clamp(0, _totalCount);

    return Container(
      margin: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_loading) const LinearProgressIndicator(),
          Expanded(
            child: _items.isEmpty && !_loading
                ? Center(child: Text('No logs found',
                    style: TextStyle(color: scheme.outline)))
                : LayoutBuilder(
                    builder: (_, constraints) => SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minWidth: constraints.maxWidth),
                        child: SingleChildScrollView(
                          child: DataTable(
                            columnSpacing: 16,
                            horizontalMargin: 20,
                            sortColumnIndex: _sortCol,
                            sortAscending: _sortAsc,
                            headingRowColor: WidgetStatePropertyAll(
                                scheme.surfaceContainerHighest),
                            dataRowMinHeight: 40,
                            dataRowMaxHeight: 52,
                            columns: List.generate(_cols.length, (i) => DataColumn(
                              numeric: i == 5,
                              label: Text(_cols[i],
                                  style: const TextStyle(fontWeight: FontWeight.w600)),
                              onSort: (c, a) => _sort(c, a),
                            )),
                            rows: _items.map((row) {
                              final dt = row['created_at'] != null
                                  ? _dtFmt.format(DateTime.parse(
                                      row['created_at'].toString()).toLocal())
                                  : '—';
                              final hasError = (row['last_error']?.toString() ?? '').isNotEmpty;
                              return DataRow(cells: [
                                DataCell(Text('${row['id'] ?? ''}')),
                                DataCell(Text('${row['entity_type'] ?? ''}')),
                                DataCell(SizedBox(width: 150,
                                    child: Text('${row['entity_id'] ?? ''}',
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 12)))),
                                DataCell(Text('${row['operation'] ?? '—'}')),
                                DataCell(_LogStatusChip(row['status']?.toString())),
                                DataCell(Text('${row['attempts'] ?? 0}',
                                    textAlign: TextAlign.right)),
                                DataCell(Text(dt, style: const TextStyle(fontSize: 12))),
                                DataCell(Row(children: [
                                  if (hasError) ...[
                                    SizedBox(
                                      width: 140,
                                      child: Text(
                                        row['last_error']?.toString() ?? '',
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontSize: 11, color: scheme.error),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    InkWell(
                                      onTap: () => _showError(context, row),
                                      borderRadius: BorderRadius.circular(4),
                                      child: Padding(
                                        padding: const EdgeInsets.all(4),
                                        child: Icon(Icons.open_in_new,
                                            size: 14, color: scheme.error),
                                      ),
                                    ),
                                  ] else
                                    Text('—', style: TextStyle(color: scheme.outline)),
                                ])),
                              ]);
                            }).toList(),
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
          Divider(height: 1, color: scheme.outlineVariant),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              children: [
                Text(
                  _totalCount == 0
                      ? 'No entries'
                      : 'Showing $from–$to of $_totalCount entries',
                  style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                ),
                const Spacer(),
                _LogPaginationBar(
                  page: _page, totalCount: _totalCount, pageSize: _pageSize,
                  onPage: (p) { setState(() => _page = p); _load(); },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Log status chip ───────────────────────────────────────────────────────────

class _LogStatusChip extends StatelessWidget {
  final String? status;
  const _LogStatusChip(this.status);

  @override
  Widget build(BuildContext context) {
    final s = status?.toUpperCase() ?? '';
    final Color bg = switch (s) {
      'DONE' || 'SYNCED' || 'COMPLETED' => const Color(0xFF2E7D32),
      'PENDING' => const Color(0xFFF57C00),
      'FAILED'  => const Color(0xFFC62828),
      _         => Colors.grey,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: bg.withValues(alpha: 0.4)),
      ),
      child: Text(s.isEmpty ? '—' : s,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: bg)),
    );
  }
}

// ── Filter dropdown ───────────────────────────────────────────────────────────

class _LogFilterDrop<T> extends StatefulWidget {
  final T value;
  final String hint;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  const _LogFilterDrop({required this.value, required this.hint,
      required this.items, required this.onChanged});

  @override
  State<_LogFilterDrop<T>> createState() => _LogFilterDropState<T>();
}

class _LogFilterDropState<T> extends State<_LogFilterDrop<T>> {
  final _ctrl = MenuController();

  String _label() {
    if (widget.value == null) return widget.hint;
    final match = widget.items.where((i) => i.value == widget.value).firstOrNull;
    final child = match?.child;
    if (child is Text) return child.data ?? widget.hint;
    return widget.hint;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MenuAnchor(
      controller: _ctrl,
      alignmentOffset: const Offset(0, 4),
      menuChildren: widget.items.map((item) => MenuItemButton(
        onPressed: () => widget.onChanged(item.value),
        child: item.child,
      )).toList(),
      child: GestureDetector(
        onTap: () => _ctrl.open(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            border: Border.all(color: scheme.outline),
            borderRadius: BorderRadius.circular(8),
            color: scheme.surface,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_label(), style: TextStyle(fontSize: 13,
                  color: widget.value == null
                      ? scheme.onSurfaceVariant : scheme.onSurface)),
              const SizedBox(width: 4),
              Icon(Icons.arrow_drop_down, size: 18, color: scheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Pagination bar ────────────────────────────────────────────────────────────

class _LogPaginationBar extends StatelessWidget {
  final int page;
  final int totalCount;
  final int pageSize;
  final ValueChanged<int> onPage;
  const _LogPaginationBar({required this.page, required this.totalCount,
      required this.pageSize, required this.onPage});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total  = (totalCount / pageSize).ceil();
    if (total <= 1) return const SizedBox.shrink();
    final first = (page - 2).clamp(0, (total - 5).clamp(0, total - 1));
    final last  = (first + 5).clamp(0, total);

    Widget btn(String lbl, {bool selected = false, VoidCallback? onTap}) =>
        GestureDetector(
          onTap: onTap,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            constraints: const BoxConstraints(minWidth: 30),
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: selected ? scheme.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: selected ? null : Border.all(color: scheme.outlineVariant),
            ),
            alignment: Alignment.center,
            child: Text(lbl,
                style: TextStyle(fontSize: 12,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
                    color: selected ? scheme.onPrimary : scheme.onSurface)),
          ),
        );

    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (page > 0) ...[btn('«', onTap: () => onPage(0)), btn('‹', onTap: () => onPage(page - 1))],
      if (first > 0) btn('…'),
      for (int i = first; i < last; i++)
        btn('${i + 1}', selected: i == page, onTap: i == page ? null : () => onPage(i)),
      if (last < total) btn('…'),
      if (page < total - 1) ...[btn('›', onTap: () => onPage(page + 1)), btn('»', onTap: () => onPage(total - 1))],
    ]);
  }
}
