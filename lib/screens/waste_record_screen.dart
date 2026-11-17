import 'dart:convert';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../router/routes.dart';
import '../services/api_client.dart';
import '../state/auth_state.dart';
import '../utils/localized_name.dart';
import '../utils/number_format.dart';
import '../utils/xlsx_reader.dart';
import '../widgets/admin_sidebar.dart';
import '../widgets/error_dialog.dart';
import '../widgets/form_page.dart';
import '../widgets/product_search_field.dart';
import '../widgets/waha_date_picker.dart';
import '../widgets/waha_filter_controls.dart';

/// One choice in a dropdown (id + label).
class WasteChoice {
  final Object? value;
  final String label;
  const WasteChoice(this.value, this.label);
}

class _Line {
  final int productId;
  final String name;
  final String? barcode;
  final TextEditingController qty = TextEditingController(text: '1');
  _Line(this.productId, this.name, this.barcode);
}

/// Record one waste: branch, reason, date, optional employee/notes, product lines.
class WasteRecordScreen extends StatefulWidget {
  final List<WasteChoice> branches;
  final List<WasteChoice> reasons;
  final List<WasteChoice> employees;
  const WasteRecordScreen({
    super.key, required this.branches, required this.reasons, required this.employees,
  });

  @override
  State<WasteRecordScreen> createState() => _WasteRecordScreenState();
}

class _WasteRecordScreenState extends State<WasteRecordScreen> {
  int? _branchId;
  String? _reason;
  int? _employeeId;
  DateTime _date = DateTime.now();
  final _notes = TextEditingController();
  final _lines = <_Line>[];
  final Map<int, num> _stock = {};
  int _searchKey = 0;
  bool _saving = false;
  // One per form: a second tap or a retry can never save the waste twice.
  final String _clientRef = _newRef();

  static String _newRef() {
    final r = Random.secure();
    return 'adm-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}-'
        '${List.generate(8, (_) => r.nextInt(36).toRadixString(36)).join()}';
  }

  @override
  void dispose() {
    _notes.dispose();
    _scanCtrl.dispose();
    _scanFocus.dispose();
    for (final l in _lines) { l.qty.dispose(); }
    super.dispose();
  }

  bool get _isToday {
    final n = DateTime.now();
    return _date.year == n.year && _date.month == n.month && _date.day == n.day;
  }

  String get _dateText =>
      '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate() async {
    final d = await showWahaDatePicker(context, initial: _date);
    if (d != null) setState(() => _date = d);
  }

  Future<void> _loadStock(int productId) async {
    final token = context.read<AuthState>().token;
    final branch = _branchId;
    if (token == null || branch == null) return;
    try {
      final d = await ApiClient().getInventoryStock(token, branchId: branch, productId: productId, size: 5);
      final items = (d['items'] as List? ?? []).cast<Map<String, dynamic>>();
      final q = items.isEmpty ? 0 : ((items.first['quantity'] as num?) ?? 0);
      if (mounted && _branchId == branch) setState(() => _stock[productId] = q);
    } catch (_) {
      // Stock is only a hint; recording works without it.
    }
  }

  void _reloadAllStock() {
    _stock.clear();
    for (final l in _lines) { _loadStock(l.productId); }
  }

  void _addProduct(Map<String, dynamic> p, {int qty = 1}) {
    final id = (p['id'] as num).toInt();
    final existing = _lines.where((l) => l.productId == id);
    setState(() {
      if (existing.isNotEmpty) {
        final q = int.tryParse(existing.first.qty.text) ?? 0;
        existing.first.qty.text = '${q + qty}';
      } else {
        final bc = p['barcode'] ?? ((p['barcodes'] as List?)?.isNotEmpty == true ? (p['barcodes'] as List).first : null);
        _lines.add(_Line(id, parseLocalizedName(p['name']), bc?.toString())..qty.text = '$qty');
        _loadStock(id);
      }
      _searchKey++; // clears the search box for the next product
    });
  }

  final _scanCtrl = TextEditingController();
  final _scanFocus = FocusNode();
  bool _importing = false;

  /// Finds one product for a scanned/typed barcode or a name; null if none or unclear.
  Future<Map<String, dynamic>?> _resolve(String text) async {
    final p = await _resolveOnce(text);
    // Excel drops leading zeros of numeric barcodes (012000057380 -> 12000057380): retry with them.
    if (p == null && RegExp(r'^\d{6,}$').hasMatch(text.trim())) {
      for (var z = 1; z <= 2; z++) {
        final q = await _resolveBarcodeOnly('${'0' * z}${text.trim()}');
        if (q != null) return q;
      }
    }
    return p;
  }

  Future<Map<String, dynamic>?> _resolveBarcodeOnly(String code) async {
    final token = context.read<AuthState>().token;
    if (token == null) return null;
    final results = await ApiClient().getAdminProducts(token, search: code);
    for (final r in results) {
      if ('${r['barcode'] ?? ''}' == code) return r;
    }
    return null;
  }

  Future<Map<String, dynamic>?> _resolveOnce(String text) async {
    final token = context.read<AuthState>().token;
    if (token == null) return null;
    final results = await ApiClient().getAdminProducts(token, search: text);
    final t = text.trim().toLowerCase();
    for (final r in results) {
      if ('${r['barcode'] ?? ''}'.toLowerCase() == t) return r;
    }
    for (final r in results) {
      if (parseLocalizedName(r['name']).trim().toLowerCase() == t) return r;
    }
    return results.length == 1 ? results.first : null;
  }

  Future<void> _scan(String text) async {
    final v = text.trim();
    if (v.isEmpty) return;
    _scanCtrl.clear();
    try {
      final p = await _resolve(v);
      if (!mounted) return;
      if (p == null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No single product found for "$v".')));
      } else {
        _addProduct(p);
      }
    } on ApiException catch (e) {
      if (mounted) showErrorDialog(context, e.message);
    }
    _scanFocus.requestFocus();
  }

  List<String> _splitCsv(String line) {
    final out = <String>[];
    final b = StringBuffer();
    var q = false;
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (c == '"') {
        if (q && i + 1 < line.length && line[i + 1] == '"') { b.write('"'); i++; } else { q = !q; }
      } else if ((c == ',' || c == ';' || c == '\t') && !q) {
        out.add(b.toString().trim());
        b.clear();
      } else {
        b.write(c);
      }
    }
    out.add(b.toString().trim());
    return out;
  }

  /// A CSV, text or Excel file: one product per line (barcode or name), optional quantity second.
  /// A first row with "barcode"/"name"/"quantity" headings is understood too.
  Future<void> _importFile() async {
    final picked = await FilePicker.platform
        .pickFiles(type: FileType.custom, allowedExtensions: ['csv', 'txt', 'xlsx'], withData: true);
    final bytes = picked?.files.firstOrNull?.bytes;
    if (bytes == null || !mounted) return;
    final isXlsx = picked!.files.first.name.toLowerCase().endsWith('.xlsx');
    List<List<String>> rows;
    try {
      rows = isXlsx
          ? readXlsxRows(bytes).where((r) => r.any((c) => c.isNotEmpty)).toList()
          : const LineSplitter().convert(utf8.decode(bytes, allowMalformed: true))
              .map(_splitCsv).where((r) => r.any((c) => c.isNotEmpty)).toList();
    } catch (_) {
      showErrorDialog(context, 'This file could not be read.');
      return;
    }
    if (rows.isEmpty) return;
    var idCol = 0, qtyCol = 1;
    final head = rows.first.map((c) => c.toLowerCase()).toList();
    final hb = head.indexWhere((c) => c.contains('barcode'));
    final hn = head.indexWhere((c) => c == 'name' || c == 'product' || c.contains('product'));
    final hq = head.indexWhere((c) => c.contains('qty') || c.contains('quantity'));
    if (hb >= 0 || hn >= 0 || hq >= 0) {
      idCol = hb >= 0 ? hb : (hn >= 0 ? hn : 0);
      qtyCol = hq >= 0 ? hq : -1;
      rows = rows.sublist(1);
    }
    setState(() => _importing = true);
    final missing = <String>[];
    var added = 0;
    try {
      for (final r in rows) {
        if (idCol >= r.length || r[idCol].isEmpty) continue;
        final qty = (qtyCol >= 0 && qtyCol < r.length) ? (int.tryParse(r[qtyCol]) ?? 1) : 1;
        final p = await _resolve(r[idCol]);
        if (!mounted) return;
        if (p == null) { missing.add(r[idCol]); } else { _addProduct(p, qty: qty < 1 ? 1 : qty); added++; }
      }
    } on ApiException catch (e) {
      if (mounted) showErrorDialog(context, e.message);
    } finally {
      if (mounted) setState(() => _importing = false);
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Import finished'),
        content: Text('$added product${added == 1 ? '' : 's'} added.'
            '${missing.isEmpty ? '' : '\n\nNot found or unclear (${missing.length}):\n${missing.take(30).join('\n')}${missing.length > 30 ? '\n…' : ''}'}'
            '\n\nCheck the quantities, then save.'),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
      ),
    );
  }

  String? _problem() {
    if (_branchId == null) return 'Choose a branch.';
    if (_reason == null) return 'Choose a reason.';
    if (_lines.isEmpty) return 'Add at least one product.';
    for (final l in _lines) {
      final q = int.tryParse(l.qty.text.trim());
      if (q == null || q <= 0) return 'Quantity of "${l.name}" must be a whole number above 0.';
    }
    return null;
  }

  Future<void> _save() async {
    final problem = _problem();
    if (problem != null) { showErrorDialog(context, problem); return; }
    final token = context.read<AuthState>().token;
    if (token == null) return;
    final when = _isToday ? DateTime.now() : DateTime(_date.year, _date.month, _date.day, 12);
    setState(() => _saving = true);
    try {
      await ApiClient().createWaste(token, {
        'branchId': _branchId,
        'reason': _reason,
        'items': [for (final l in _lines) {'productId': l.productId, 'quantity': int.parse(l.qty.text.trim())}],
        'date': when.toUtc().toIso8601String(),
        if (_employeeId != null) 'employeeId': _employeeId,
        if (_notes.text.trim().isNotEmpty) 'notes': _notes.text.trim(),
        'clientRef': _clientRef,
      });
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) { setState(() => _saving = false); showErrorDialog(context, e.message); }
    } catch (e) {
      if (mounted) { setState(() => _saving = false); showErrorDialog(context, e.toString()); }
    }
  }

  Widget _labeled(String label, Widget child) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 6),
          child,
        ]),
      );

  Widget _choiceDropdown<T>(T value, String hint, List<WasteChoice> choices, ValueChanged<T?> onChanged,
          {bool allowNone = false}) =>
      WahaFilterDropdown<T?>(
        value: value,
        hint: hint,
        expand: true,
        fillColor: Theme.of(context).colorScheme.surface,
        items: [
          if (allowNone) DropdownMenuItem<T?>(value: null, child: Text(hint)),
          for (final c in choices) DropdownMenuItem<T?>(value: c.value as T?, child: Text(c.label)),
        ],
        onChanged: onChanged,
      );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AdminSidebar(currentRoute: Routes.inventoryWastes),
          Expanded(
            child: Column(children: [
              FormPageHeader(title: 'Record waste', saving: _saving, onSave: _save, saveLabel: 'Save waste'),
              Expanded(
                child: FormPageBody(children: [
                  const FormSectionLabel('WASTE'),
                  const SizedBox(height: 12),
                  _labeled('Branch', _choiceDropdown<int>(_branchId ?? -1, 'Select branch', widget.branches, (v) {
                    setState(() => _branchId = v == -1 ? null : v);
                    _reloadAllStock();
                  }, allowNone: false)),
                  _labeled('Reason', _choiceDropdown<String>(_reason ?? '', 'Select reason', widget.reasons,
                      (v) => setState(() => _reason = (v == null || v.isEmpty) ? null : v))),
                  _labeled(
                    'Date',
                    InkWell(
                      onTap: _pickDate,
                      borderRadius: kWahaFilterControlRadius,
                      child: InputDecorator(
                        decoration: const InputDecoration(suffixIcon: Icon(Icons.calendar_today_outlined, size: 18)),
                        child: Text(_dateText),
                      ),
                    ),
                  ),
                  _labeled('Employee (optional)',
                      _choiceDropdown<int>(_employeeId ?? -1, 'No employee', widget.employees,
                          (v) => setState(() => _employeeId = v == -1 ? null : v), allowNone: false)),
                  _labeled('Notes (optional)',
                      TextField(controller: _notes, maxLines: 2, maxLength: 500)),
                  const SizedBox(height: 8),
                  const FormSectionLabel('PRODUCTS'),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _scanCtrl,
                        focusNode: _scanFocus,
                        onSubmitted: _scan,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.qr_code_scanner, size: 20),
                          hintText: 'Scan a barcode (or type it) and press Enter',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      icon: _importing
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.upload_file_outlined, size: 18),
                      label: const Text('Import list'),
                      onPressed: _importing ? null : _importFile,
                    ),
                  ]),
                  const SizedBox(height: 10),
                  ProductSearchField(
                    key: ValueKey(_searchKey),
                    hintText: 'Or search by name…',
                    width: 360,
                    onSearch: (q) async {
                      final t = context.read<AuthState>().token;
                      return t == null ? [] : ApiClient().getAdminProducts(t, search: q);
                    },
                    labelBuilder: (p) => parseLocalizedName(p['name']),
                    onSelected: (p) { if (p != null) _addProduct(p); },
                  ),
                  const SizedBox(height: 12),
                  if (_lines.isEmpty)
                    Text('No products yet.', style: TextStyle(color: scheme.onSurfaceVariant))
                  else
                    for (final l in _lines) _lineRow(l, scheme),
                ]),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _lineRow(_Line l, ColorScheme scheme) {
    final q = int.tryParse(l.qty.text.trim()) ?? 0;
    final stock = _stock[l.productId];
    final over = stock != null && q > stock;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            if (l.barcode != null)
              Text(l.barcode!, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            if (_branchId != null && stock != null)
              Text(
                over
                    ? 'Only ${fmtCount(stock)} in stock — the stock will go below zero.'
                    : 'In stock: ${fmtCount(stock)}',
                style: TextStyle(fontSize: 12, color: over ? Colors.orange.shade800 : scheme.onSurfaceVariant),
              ),
          ]),
        ),
        SizedBox(
          width: 90,
          child: TextField(
            controller: l.qty,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            decoration: const InputDecoration(isDense: true, hintText: 'Qty'),
            onChanged: (_) => setState(() {}),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close, size: 18),
          tooltip: 'Remove',
          onPressed: () => setState(() { _lines.remove(l); l.qty.dispose(); }),
        ),
      ]),
    );
  }
}
