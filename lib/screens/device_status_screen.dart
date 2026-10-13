import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../router/routes.dart';
import '../services/api_client.dart';
import '../state/auth_state.dart';
import '../widgets/admin_sidebar.dart';
import '../widgets/error_dialog.dart';
import '../utils/number_format.dart';

/// Read-only online/offline dashboard for devices, backed by
/// GET /api/admin/device-status. `online` is server-computed from the last
/// heartbeat vs. `heartbeatMinutes` (null when monitoring is off or the
/// device was never seen — shown as "Unknown").
class DeviceStatusScreen extends StatefulWidget {
  const DeviceStatusScreen({super.key});

  @override
  State<DeviceStatusScreen> createState() => _DeviceStatusScreenState();
}

enum _OnlineFilter { all, online, offline, unknown }

class _DeviceStatusScreenState extends State<DeviceStatusScreen> {
  List<Map<String, dynamic>> _items = [];
  int? _heartbeatMinutes;
  bool? _monitoring;
  DateTime? _serverTime;
  bool _loading = true;
  String? _error;

  _OnlineFilter _filter = _OnlineFilter.all;
  int _sortCol = 0;
  bool _sortAsc = true;

  static final _dtFmt = DateFormat('yyyy-MM-dd HH:mm');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _redirectLogin() {
    context.read<AuthState>().logout();
    Navigator.of(context).pushReplacementNamed(Routes.login);
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final token = context.read<AuthState>().token;
    if (token == null) { _redirectLogin(); return; }
    try {
      final data = await ApiClient().getDeviceStatus(token);
      if (!mounted) return;
      setState(() {
        _items = (data['items'] as List? ?? []).cast<Map<String, dynamic>>();
        _heartbeatMinutes = (data['heartbeatMinutes'] as num?)?.toInt();
        _monitoring = data['monitoring'] as bool?;
        _serverTime = data['serverTime'] != null ? DateTime.tryParse(data['serverTime'].toString()) : null;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (e.statusCode == 401) { _redirectLogin(); return; }
      if (mounted) setState(() { _error = e.message; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  List<Map<String, dynamic>> get _filtered {
    final list = _items.where((d) {
      switch (_filter) {
        case _OnlineFilter.all:
          return true;
        case _OnlineFilter.online:
          return d['online'] == true;
        case _OnlineFilter.offline:
          return d['online'] == false;
        case _OnlineFilter.unknown:
          return d['online'] == null;
      }
    }).toList();

    int cmp(Map<String, dynamic> a, Map<String, dynamic> b) {
      switch (_sortCol) {
        case 0:
          return (a['name'] ?? a['username'] ?? '').toString().compareTo((b['name'] ?? b['username'] ?? '').toString());
        case 1:
          return (a['storeName'] ?? '').toString().compareTo((b['storeName'] ?? '').toString());
        case 2:
          // Online first, then unknown, then offline (longest offline last).
          final ra = a['online'] == true ? 0 : (a['online'] == null ? 1 : 2);
          final rb = b['online'] == true ? 0 : (b['online'] == null ? 1 : 2);
          if (ra != rb) return ra.compareTo(rb);
          return ((a['offlineMinutes'] as num?) ?? 0).compareTo((b['offlineMinutes'] as num?) ?? 0);
        case 3:
          final la = a['lastSeenAt']?.toString() ?? '';
          final lb = b['lastSeenAt']?.toString() ?? '';
          return la.compareTo(lb);
        default:
          return 0;
      }
    }
    list.sort((a, b) => _sortAsc ? cmp(a, b) : cmp(b, a));
    return list;
  }

  void _sort(int col) {
    setState(() {
      if (_sortCol == col) {
        _sortAsc = !_sortAsc;
      } else {
        _sortCol = col;
        _sortAsc = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      showErrorDialogLater(context, _error!);
      _error = null;
    }
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: Row(
        children: [
          const AdminSidebar(currentRoute: Routes.deviceStatus),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                  child: Row(
                    children: [
                      Text('Device Status',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(width: 12),
                      if (_monitoring == false)
                        _InfoChip('Monitoring off', Colors.grey)
                      else if (_heartbeatMinutes != null)
                        _InfoChip('Heartbeat: every ${fmtCount(_heartbeatMinutes)}m', scheme.primary),
                      const Spacer(),
                      if (_serverTime != null)
                        Text('as of ${_dtFmt.format(_serverTime!.toLocal())}',
                            style: TextStyle(fontSize: 12, color: scheme.outline)),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        tooltip: 'Refresh',
                        onPressed: _load,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: Row(
                    children: [
                      Text('Filter:', style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
                      const SizedBox(width: 8),
                      DropdownButton<_OnlineFilter>(
                        value: _filter,
                        underline: const SizedBox.shrink(),
                        items: const [
                          DropdownMenuItem(value: _OnlineFilter.all, child: Text('All')),
                          DropdownMenuItem(value: _OnlineFilter.online, child: Text('Online')),
                          DropdownMenuItem(value: _OnlineFilter.offline, child: Text('Offline')),
                          DropdownMenuItem(value: _OnlineFilter.unknown, child: Text('Unknown')),
                        ],
                        onChanged: (v) { if (v != null) setState(() => _filter = v); },
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _buildTableArea(scheme),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableArea(ColorScheme scheme) {
    final rows = _filtered;
    final cols = ['Device', 'Store', 'Status', 'Last Seen', 'App Version', 'Last Order'];
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: rows.isEmpty
          ? const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('No devices found.')))
          : LayoutBuilder(
              builder: (_, constraints) => SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: SingleChildScrollView(
                    child: DataTable(
                      columnSpacing: 20,
                      horizontalMargin: 20,
                      headingRowColor: WidgetStatePropertyAll(scheme.surfaceContainerHighest),
                      dataRowMinHeight: 44,
                      dataRowMaxHeight: 56,
                      sortColumnIndex: _sortCol <= 3 ? _sortCol : null,
                      sortAscending: _sortAsc,
                      columns: [
                        for (var i = 0; i < 4; i++)
                          DataColumn(
                            label: Text(cols[i], style: const TextStyle(fontWeight: FontWeight.w600)),
                            onSort: (c, a) => _sort(c),
                          ),
                        DataColumn(label: Text(cols[4], style: const TextStyle(fontWeight: FontWeight.w600))),
                        DataColumn(label: Text(cols[5], style: const TextStyle(fontWeight: FontWeight.w600))),
                      ],
                      rows: rows.map((d) {
                        final name = (d['name'] ?? d['username'] ?? '—').toString();
                        final lastSeen = d['lastSeenAt'] != null
                            ? _dtFmt.format(DateTime.parse(d['lastSeenAt'].toString()).toLocal())
                            : '—';
                        return DataRow(cells: [
                          DataCell(SizedBox(width: 160, child: Text(name, overflow: TextOverflow.ellipsis))),
                          DataCell(SizedBox(width: 140,
                              child: Text(d['storeName']?.toString() ?? '—', overflow: TextOverflow.ellipsis))),
                          DataCell(_OnlineBadge(online: d['online'] as bool?, offlineMinutes: (d['offlineMinutes'] as num?)?.toInt())),
                          DataCell(Text(lastSeen)),
                          DataCell(Text(d['appVersion']?.toString() ?? '—')),
                          DataCell(_LastOrderCell(
                            lastOrderAt: d['lastOrderAt']?.toString(),
                            lastOrderStatus: d['lastOrderStatus']?.toString(),
                          )),
                        ]);
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final Color color;
  const _InfoChip(this.label, this.color);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
        child: Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
      );
}

class _OnlineBadge extends StatelessWidget {
  final bool? online;
  final int? offlineMinutes;
  const _OnlineBadge({required this.online, required this.offlineMinutes});

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String label;
    if (online == true) {
      color = const Color(0xFF2E7D32);
      label = 'Online';
    } else if (online == false) {
      color = const Color(0xFFC62828);
      label = offlineMinutes != null ? 'Offline ${fmtDuration(offlineMinutes)}' : 'Offline';
    } else {
      color = Colors.grey;
      label = 'Unknown';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }
}

class _LastOrderCell extends StatelessWidget {
  final String? lastOrderAt;
  final String? lastOrderStatus;
  const _LastOrderCell({required this.lastOrderAt, required this.lastOrderStatus});

  static final _dtFmt = DateFormat('yyyy-MM-dd HH:mm');

  @override
  Widget build(BuildContext context) {
    if (lastOrderAt == null) return const Text('—');
    final dt = DateTime.tryParse(lastOrderAt!);
    final label = dt != null ? _dtFmt.format(dt.toLocal()) : lastOrderAt!;
    final scheme = Theme.of(context).colorScheme;
    Color statusColor;
    switch (lastOrderStatus) {
      case 'PAID':
        statusColor = const Color(0xFF2E7D32);
        break;
      case 'PENDING':
        statusColor = const Color(0xFFF57C00);
        break;
      case 'CANCELLED':
        statusColor = const Color(0xFFC62828);
        break;
      default:
        statusColor = scheme.outline;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(fontSize: 13)),
        if (lastOrderStatus != null) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(lastOrderStatus!.toLowerCase(),
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: statusColor)),
          ),
        ],
      ],
    );
  }
}
