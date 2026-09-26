// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/device.dart';
import '../router/routes.dart';
import '../services/api_client.dart';
import '../state/auth_state.dart';
import '../utils/number_format.dart';
import '../widgets/admin_sidebar.dart';
import '../widgets/error_dialog.dart';
import '../widgets/waha_date_picker.dart';
import '../widgets/waha_filter_controls.dart';
import '../widgets/waha_pagination_bar.dart';

/// Admin view of the text trace logs uploaded by kiosk devices: newest first,
/// filter by device/date, open in a new tab, multi-select delete.
class DeviceLogsScreen extends StatefulWidget {
  const DeviceLogsScreen({super.key});

  @override
  State<DeviceLogsScreen> createState() => _DeviceLogsScreenState();
}

class _DeviceLogsScreenState extends State<DeviceLogsScreen> {
  static const _pageSize = 20;
  static final _dtFmt = DateFormat('yyyy-MM-dd HH:mm');

  List<Device> _devices = [];
  int? _deviceId;
  DateTimeRange? _range;

  List<Map<String, dynamic>> _items = [];
  int _totalCount = 0;
  int _totalSize = 0;
  int? _retentionDays;
  int _page = 0;
  final Set<int> _selected = {};

  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadDevices();
      _load();
    });
  }

  String? get _token => context.read<AuthState>().token;

  void _redirectLogin() {
    context.read<AuthState>().logout();
    Navigator.of(context).pushReplacementNamed(Routes.login);
  }

  Future<void> _loadDevices() async {
    final token = _token;
    if (token == null) return;
    try {
      final list = await ApiClient().getDevices(token);
      if (mounted) setState(() => _devices = list);
    } catch (_) {
      // The filter just stays empty; the logs list reports its own errors.
    }
  }

  Future<void> _load() async {
    final token = _token;
    if (token == null) { _redirectLogin(); return; }
    setState(() { _loading = true; _error = null; });
    try {
      final r = _range;
      final data = await ApiClient().getDeviceLogs(
        token,
        page: _page,
        size: _pageSize,
        deviceId: _deviceId,
        from: r == null ? null : DateTime(r.start.year, r.start.month, r.start.day),
        to: r == null ? null : DateTime(r.end.year, r.end.month, r.end.day, 23, 59, 59, 999),
      );
      if (!mounted) return;
      setState(() {
        _items = (data['items'] as List? ?? []).cast<Map<String, dynamic>>();
        _totalCount = (data['totalCount'] as num?)?.toInt() ?? 0;
        _totalSize = (data['totalSizeBytes'] as num?)?.toInt() ?? 0;
        _retentionDays = (data['retentionDays'] as num?)?.toInt();
        _selected.clear();
        _loading = false;
      });
    } on ApiException catch (e) {
      if (e.statusCode == 401) { _redirectLogin(); return; }
      if (mounted) setState(() { _error = e.message; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _resetAndLoad() {
    _page = 0;
    _load();
  }

  Future<void> _pickRange() async {
    final picked = await showWahaDateRangePicker(context, initial: _range);
    if (picked == null || !mounted) return;
    setState(() => _range = picked);
    _resetAndLoad();
  }

  String _fmtRange(DateTimeRange r) {
    final f = DateFormat('yyyy-MM-dd');
    return '${f.format(r.start)} → ${f.format(r.end)}';
  }

  String _date(dynamic raw) {
    if (raw == null) return '—';
    try {
      return _dtFmt.format(DateTime.parse(raw.toString()).toLocal());
    } catch (_) {
      return raw.toString();
    }
  }

  // Opens the log in a new tab. The file needs the admin token, so it is
  // fetched here and shown through a blob URL — the token never goes in a URL.
  // The tab is opened first (inside the click) so the browser doesn't block it.
  Future<void> _open(Map<String, dynamic> row) async {
    final token = _token;
    if (token == null) return;
    final tab = html.window.open('about:blank', '_blank');
    try {
      final text = await ApiClient().getDeviceLogText((row['id'] as num).toInt(), token: token);
      final blob = html.Blob([text], 'text/plain;charset=utf-8');
      final url = html.Url.createObjectUrlFromBlob(blob);
      tab.location.href = url;
    } catch (e) {
      tab.close();
      if (mounted) {
        showErrorDialog(context, e is ApiException ? e.message : 'Could not open log: $e');
      }
    }
  }

  Future<void> _deleteSelected() async {
    final token = _token;
    if (token == null || _selected.isEmpty) return;
    final chosen = _items.where((r) => _selected.contains((r['id'] as num).toInt())).toList();
    final size = chosen.fold<int>(0, (a, r) => a + ((r['sizeBytes'] as num?)?.toInt() ?? 0));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${fmtCount(chosen.length)} logs?'),
        content: Text(
            'This permanently deletes ${fmtCount(chosen.length)} log '
            '${chosen.length == 1 ? 'file' : 'files'} (${fmtSize(size)}). It cannot be undone.'),
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
    if (ok != true || !mounted) return;
    try {
      final deleted = await ApiClient().deleteDeviceLogs(_selected.toList(), token: token);
      if (!mounted) return;
      if (deleted < chosen.length) {
        await showErrorDialog(context,
            'Deleted ${fmtCount(deleted)} of ${fmtCount(chosen.length)} logs. The rest could not be deleted.');
      }
    } on ApiException catch (e) {
      if (e.statusCode == 401) { _redirectLogin(); return; }
      if (mounted) await showErrorDialog(context, e.message);
    } catch (e) {
      if (mounted) await showErrorDialog(context, 'Delete failed: $e');
    }
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: Row(
        children: [
          const AdminSidebar(currentRoute: Routes.deviceLogs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _header(scheme),
                _filters(scheme),
                Expanded(child: _table(scheme)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(ColorScheme scheme) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        child: Row(
          children: [
            Text('Device logs',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(width: 16),
            if (_totalCount > 0)
              Text('${fmtCount(_totalCount)} logs · ${fmtSize(_totalSize)}',
                  style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
            const Spacer(),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(right: 12),
                child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            if (_selected.isNotEmpty)
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: scheme.error),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: Text('Delete ${fmtCount(_selected.length)}'),
                onPressed: _deleteSelected,
              ),
            IconButton(
              icon: const Icon(Icons.refresh_outlined),
              tooltip: 'Refresh',
              onPressed: _loading ? null : _resetAndLoad,
            ),
          ],
        ),
      );

  Widget _filters(ColorScheme scheme) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
        child: Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            WahaFilterDropdown<int?>(
              value: _deviceId,
              hint: 'All devices',
              items: [
                const DropdownMenuItem(value: null, child: Text('All devices')),
                ..._devices.map((d) => DropdownMenuItem(value: d.id, child: Text(d.displayName))),
              ],
              onChanged: (v) {
                setState(() => _deviceId = v);
                _resetAndLoad();
              },
            ),
            SizedBox(
              height: kWahaFilterControlHeight,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.date_range_outlined, size: 18),
                label: Text(_range == null ? 'Any date' : _fmtRange(_range!),
                    style: const TextStyle(fontSize: kWahaFilterControlFontSize)),
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: kWahaFilterControlRadius),
                ),
                onPressed: _pickRange,
              ),
            ),
            if (_range != null)
              TextButton(
                onPressed: () {
                  setState(() => _range = null);
                  _resetAndLoad();
                },
                child: const Text('Clear date'),
              ),
            if (_retentionDays != null)
              Text('Logs are deleted automatically after ${fmtCount(_retentionDays)} days.',
                  style: TextStyle(fontSize: 12, color: scheme.outline)),
          ],
        ),
      );

  Widget _table(ColorScheme scheme) {
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!, style: TextStyle(color: scheme.error)),
          const SizedBox(height: 16),
          FilledButton(onPressed: _load, child: const Text('Retry')),
        ]),
      );
    }

    final from = _page * _pageSize + 1;
    final to = ((_page + 1) * _pageSize).clamp(0, _totalCount);

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
                ? Center(child: Text('No logs found', style: TextStyle(color: scheme.outline)))
                : LayoutBuilder(
                    builder: (_, box) => SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minWidth: box.maxWidth),
                        child: SingleChildScrollView(
                          child: DataTable(
                            showCheckboxColumn: true,
                            onSelectAll: (v) => setState(() {
                              if (v == true) {
                                _selected.addAll(_items.map((r) => (r['id'] as num).toInt()));
                              } else {
                                _selected.clear();
                              }
                            }),
                            columnSpacing: 24,
                            horizontalMargin: 20,
                            headingRowColor: WidgetStatePropertyAll(scheme.surfaceContainerHighest),
                            columns: const [
                              DataColumn(label: Text('Date', style: TextStyle(fontWeight: FontWeight.w600))),
                              DataColumn(label: Text('Device', style: TextStyle(fontWeight: FontWeight.w600))),
                              DataColumn(label: Text('Store', style: TextStyle(fontWeight: FontWeight.w600))),
                              DataColumn(
                                  numeric: true,
                                  label: Text('Size', style: TextStyle(fontWeight: FontWeight.w600))),
                              DataColumn(label: Text('')),
                            ],
                            rows: _items.map((row) {
                              final id = (row['id'] as num).toInt();
                              return DataRow(
                                selected: _selected.contains(id),
                                onSelectChanged: (v) => setState(() {
                                  if (v == true) {
                                    _selected.add(id);
                                  } else {
                                    _selected.remove(id);
                                  }
                                }),
                                cells: [
                                  DataCell(Text(_date(row['createdAt']))),
                                  DataCell(Text('${row['deviceName'] ?? row['deviceId'] ?? '—'}')),
                                  DataCell(Text('${row['storeName'] ?? '—'}')),
                                  DataCell(Text(fmtSize(row['sizeBytes']))),
                                  DataCell(TextButton.icon(
                                    icon: const Icon(Icons.open_in_new, size: 16),
                                    label: const Text('Open'),
                                    onPressed: () => _open(row),
                                  )),
                                ],
                              );
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
                      : 'Showing ${fmtCount(from)}–${fmtCount(to)} of ${fmtCount(_totalCount)} entries',
                  style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                ),
                const Spacer(),
                WahaPaginationBar(
                  page: _page,
                  totalCount: _totalCount,
                  pageSize: _pageSize,
                  onPage: (p) {
                    setState(() => _page = p);
                    _load();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
