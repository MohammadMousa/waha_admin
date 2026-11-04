import 'dart:html' as html;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/employee.dart';
import '../models/store.dart';
import '../router/routes.dart';
import '../services/api_client.dart';
import '../state/auth_state.dart';
import '../utils/code_import.dart';
import '../utils/localized_name.dart';
import '../utils/number_format.dart';
import '../widgets/admin_sidebar.dart';
import '../widgets/error_dialog.dart';
import '../widgets/product_search_field.dart';
import '../widgets/waha_date_picker.dart';

/// Add / edit one coupon, or create a batch of coupons that share one
/// configuration. Pass `couponId` to edit; without it the screen offers a
/// "Single coupon" / "Batch of coupons" switch.
class CouponFormScreen extends StatefulWidget {
  final int? couponId;
  final bool startInBatch;
  const CouponFormScreen({super.key, this.couponId, this.startInBatch = false});

  @override
  State<CouponFormScreen> createState() => _CouponFormScreenState();
}

final _stampFmt = DateFormat("yyyy-MM-dd'T'HH:mm");
final _dateFmt = DateFormat('yyyy-MM-dd');

class _CouponFormScreenState extends State<CouponFormScreen> {
  static const _maxBatch = 500;

  bool get _isEdit => widget.couponId != null;

  // Batch
  late bool _batch = widget.startInBatch;
  bool _randomCodes = false;
  final _codesCtrl = TextEditingController();
  final _countCtrl = TextEditingController(text: '10');
  final _prefixCtrl = TextEditingController();

  // Basics
  final _codeCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  String _type = 'GLOBAL';
  String _mode = 'PERCENTAGE';
  final _valueCtrl = TextEditingController();
  final _maxDiscountCtrl = TextEditingController();

  // Scope
  String _storeScope = 'ALL';
  final Set<int> _storeIds = {};
  final Map<int, String> _products = {};
  int _productFieldKey = 0;

  // Validity and limits
  DateTime? _starts;
  DateTime? _expires;
  final _maxInvoicesCtrl = TextEditingController();
  final _maxInvoicesPerUserCtrl = TextEditingController();
  final _maxAmountCtrl = TextEditingController();
  final _maxAmountPerUserCtrl = TextEditingController();
  final _minOrderCtrl = TextEditingController();

  // Options
  bool _stacking = true;
  bool _enabled = true;
  int? _employeeId;

  Map<String, dynamic>? _usage;
  List<Store> _stores = [];
  List<Employee> _employees = [];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _codesCtrl.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  @override
  void dispose() {
    for (final c in [
      _codesCtrl, _countCtrl, _prefixCtrl, _codeCtrl, _nameCtrl, _valueCtrl, _maxDiscountCtrl,
      _maxInvoicesCtrl, _maxInvoicesPerUserCtrl, _maxAmountCtrl, _maxAmountPerUserCtrl, _minOrderCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _redirectLogin() {
    context.read<AuthState>().logout();
    Navigator.of(context).pushReplacementNamed(Routes.login);
  }

  String _numText(dynamic v) => v == null ? '' : v.toString();

  Future<void> _init() async {
    final token = context.read<AuthState>().token;
    if (token == null) { _redirectLogin(); return; }
    final api = ApiClient();
    try {
      _stores = await api.getAdminStores(token);
    } catch (_) {}
    try {
      _employees = await api.getEmployees(token);
    } catch (_) {}
    if (_isEdit) {
      try {
        final c = await api.getCoupon(widget.couponId!, token);
        _codeCtrl.text = c['code']?.toString() ?? '';
        _nameCtrl.text = c['name']?.toString() ?? '';
        _type = c['type']?.toString() ?? 'GLOBAL';
        _mode = c['discountMode']?.toString() ?? 'PERCENTAGE';
        _valueCtrl.text = _numText(c['discountValue']);
        _maxDiscountCtrl.text = _numText(c['maxDiscountPerOrder']);
        _storeScope = c['storeScope']?.toString() ?? 'ALL';
        _storeIds.addAll((c['storeIds'] as List? ?? []).map((e) => (e as num).toInt()));
        _starts = DateTime.tryParse(c['startsAt']?.toString() ?? '');
        _expires = DateTime.tryParse(c['expiresAt']?.toString() ?? '');
        _maxInvoicesCtrl.text = _numText(c['maxInvoices']);
        _maxInvoicesPerUserCtrl.text = _numText(c['maxInvoicesPerUser']);
        _maxAmountCtrl.text = _numText(c['maxAmount']);
        _maxAmountPerUserCtrl.text = _numText(c['maxAmountPerUser']);
        _minOrderCtrl.text = _numText(c['minimumOrderAmount']);
        _stacking = c['allowStackingWithOffers'] != false;
        _enabled = c['enabled'] == true;
        _employeeId = (c['employeeId'] as num?)?.toInt();
        _usage = c['usage'] as Map<String, dynamic>?;
        final ids = (c['productIds'] as List? ?? []).map((e) => (e as num).toInt()).toList();
        final names = await Future.wait(ids.map((id) async {
          try {
            final p = await api.getProductDetail(id);
            return parseLocalizedName(p['name'], fallback: '#$id');
          } catch (_) {
            return '#$id';
          }
        }));
        for (var i = 0; i < ids.length; i++) {
          _products[ids[i]] = names[i];
        }
      } on ApiException catch (e) {
        if (!mounted) return;
        if (e.statusCode == 401) { _redirectLogin(); return; }
        Navigator.pop(context);
        showErrorDialog(context, e.message);
        return;
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  // ── Codes (batch) ──────────────────────────────────────────────────────────

  ({List<String> codes, List<String> invalid, List<String> duplicates}) _analyseCodes() {
    final codes = splitCodes(_codesCtrl.text);
    final seen = <String>{};
    final duplicates = <String>{};
    for (final c in codes) {
      if (!seen.add(c.toLowerCase())) duplicates.add(c);
    }
    return (
      codes: codes,
      invalid: codes.where((c) => !isValidCode(c)).toSet().toList(),
      duplicates: duplicates.toList(),
    );
  }

  Future<void> _importFile() async {
    try {
      final picked = await FilePicker.platform
          .pickFiles(type: FileType.custom, allowedExtensions: ['csv', 'txt', 'xlsx'], withData: true);
      final file = picked?.files.firstOrNull;
      final bytes = file?.bytes;
      if (file == null || bytes == null || !mounted) return;
      final text = readCodesFile(file.name, bytes);
      if (text.isEmpty) {
        showErrorDialog(context, 'No codes found in "${file.name}".');
        return;
      }
      final current = _codesCtrl.text.trim();
      _codesCtrl.text = current.isEmpty ? text : '$current\n$text';
    } catch (e) {
      if (mounted) showErrorDialog(context, 'Could not read the file: $e');
    }
  }

  // ── Save ───────────────────────────────────────────────────────────────────

  num? _num(TextEditingController c) => num.tryParse(c.text.trim());
  int? _int(TextEditingController c) => int.tryParse(c.text.trim());

  Map<String, dynamic> _config() => {
        'name': _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
        'type': _type,
        'discountMode': _mode,
        'discountValue': _num(_valueCtrl),
        'maxDiscountPerOrder': _num(_maxDiscountCtrl),
        'storeScope': _storeScope,
        'storeIds': _storeScope == 'SOME' ? _storeIds.toList() : <int>[],
        'productIds': _type == 'PRODUCT' ? _products.keys.toList() : <int>[],
        'startsAt': _starts == null ? null : _stampFmt.format(_starts!),
        'expiresAt': _expires == null ? null : _stampFmt.format(_expires!),
        'maxInvoices': _int(_maxInvoicesCtrl),
        'maxInvoicesPerUser': _int(_maxInvoicesPerUserCtrl),
        'maxAmount': _num(_maxAmountCtrl),
        'maxAmountPerUser': _num(_maxAmountPerUserCtrl),
        'minimumOrderAmount': _num(_minOrderCtrl),
        'allowStackingWithOffers': _stacking,
        'employeeId': _employeeId,
        'enabled': _enabled,
      };

  Future<void> _save() async {
    final token = context.read<AuthState>().token;
    if (token == null) { _redirectLogin(); return; }
    final body = _config();
    if (_batch) {
      if (_randomCodes) {
        final count = int.tryParse(_countCtrl.text.trim());
        if (count == null || count < 1 || count > _maxBatch) {
          showErrorDialog(context, 'How many must be between 1 and $_maxBatch.');
          return;
        }
        body['count'] = count;
        body['prefix'] = _prefixCtrl.text.trim();
      } else {
        final a = _analyseCodes();
        final problems = <String>[
          if (a.codes.isEmpty) 'Add at least one code.',
          if (a.codes.length > _maxBatch)
            'A batch holds up to $_maxBatch codes; you have ${fmtCount(a.codes.length)}. Split it into several batches.',
          if (a.invalid.isNotEmpty)
            'Invalid codes (2–50 letters, digits, dot, dash or underscore):\n${a.invalid.join(', ')}',
          if (a.duplicates.isNotEmpty) 'Repeated codes:\n${a.duplicates.join(', ')}',
        ];
        if (problems.isNotEmpty) {
          showErrorDialog(context, problems.join('\n\n'));
          return;
        }
        body['codes'] = a.codes.join(', ');
      }
    } else {
      body['code'] = _codeCtrl.text.trim();
    }
    setState(() => _saving = true);
    try {
      final api = ApiClient();
      if (_batch) {
        final created = await api.generateCoupons(body, token: token);
        if (!mounted) return;
        setState(() => _saving = false);
        await showDialog<void>(context: context, builder: (_) => _CreatedDialog(created));
        if (mounted) Navigator.pop(context, true);
      } else {
        await api.saveCoupon(body, id: widget.couponId, token: token);
        if (mounted) Navigator.pop(context, true);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      if (e.statusCode == 401) { _redirectLogin(); return; }
      showErrorDialog(context, e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showErrorDialog(context, 'Request failed: $e');
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = _isEdit ? 'Edit coupon' : (_batch ? 'New batch of coupons' : 'New coupon');
    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: Row(
        children: [
          const AdminSidebar(currentRoute: Routes.coupons),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_back),
                              tooltip: 'Back',
                              onPressed: _saving ? null : () => Navigator.pop(context),
                            ),
                            const SizedBox(width: 8),
                            Text(title,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.w700)),
                            const Spacer(),
                            TextButton(
                                onPressed: _saving ? null : () => Navigator.pop(context),
                                child: const Text('Cancel')),
                            const SizedBox(width: 8),
                            FilledButton.icon(
                              onPressed: _saving ? null : _save,
                              icon: _saving
                                  ? const SizedBox(
                                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.check),
                              label: Text(_batch ? 'Create coupons' : (_isEdit ? 'Save changes' : 'Create coupon')),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 960),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (_usage != null) _usageCard(scheme),
                                  _codeSection(scheme),
                                  _discountSection(scheme),
                                  _scopeSection(scheme),
                                  _validitySection(scheme),
                                  _limitsSection(scheme),
                                  _optionsSection(scheme),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _section(ColorScheme scheme, String title, List<Widget> children, {String? hint}) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            if (hint != null) ...[
              const SizedBox(height: 4),
              Text(hint, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            ],
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      );

  Widget _row(List<Widget> children) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: 16),
            Expanded(child: children[i]),
          ],
        ],
      );

  static const _gap = SizedBox(height: 16);

  Widget _text(TextEditingController c, String label,
          {String? helper, bool money = false, bool digits = false, int? maxLines = 1, TextInputType? type}) =>
      TextField(
        controller: c,
        maxLines: maxLines,
        minLines: maxLines == null ? 6 : null,
        keyboardType: type ?? (digits ? TextInputType.number : (money ? const TextInputType.numberWithOptions(decimal: true) : null)),
        inputFormatters: [
          if (digits) FilteringTextInputFormatter.digitsOnly,
          if (money) FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
        ],
        decoration: InputDecoration(labelText: label, helperText: helper, helperMaxLines: 3, border: const OutlineInputBorder()),
      );

  Widget _usageCard(ColorScheme scheme) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: scheme.primaryContainer.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Wrap(
          spacing: 32,
          runSpacing: 8,
          children: [
            _stat('Paid orders', fmtCount(_usage!['paidUses'])),
            _stat('Pending orders', fmtCount(_usage!['pendingOrders'])),
            _stat('Discount given (excl. VAT)', fmtMoney(_usage!['totalDiscountGiven'])),
          ],
        ),
      );

  Widget _stat(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12)),
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        ],
      );

  // Code(s)
  Widget _codeSection(ColorScheme scheme) {
    return _section(scheme, _batch ? 'Codes' : 'Code', [
      if (!_isEdit) ...[
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, icon: Icon(Icons.confirmation_number_outlined), label: Text('Single coupon')),
            ButtonSegment(value: true, icon: Icon(Icons.library_add_outlined), label: Text('Batch of coupons')),
          ],
          selected: {_batch},
          onSelectionChanged: (s) => setState(() => _batch = s.first),
        ),
        _gap,
      ],
      if (!_batch)
        _text(_codeCtrl, 'Code',
            helper: '2–50 letters, digits, dot, dash or underscore. Not case sensitive; unique in your organization.')
      else ...[
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, icon: Icon(Icons.edit_note), label: Text('My own codes')),
            ButtonSegment(value: true, icon: Icon(Icons.auto_awesome_outlined), label: Text('Random codes')),
          ],
          selected: {_randomCodes},
          onSelectionChanged: (s) => setState(() => _randomCodes = s.first),
        ),
        _gap,
        if (_randomCodes)
          _row([
            _text(_countCtrl, 'How many', digits: true, helper: '1 to $_maxBatch'),
            _text(_prefixCtrl, 'Prefix', helper: 'Optional, e.g. SUMMER- before each random code'),
          ])
        else ...[
          _text(_codesCtrl, 'Codes',
              maxLines: null,
              helper: 'Separate codes with commas, spaces or new lines, or import a file. Up to $_maxBatch codes.'),
          const SizedBox(height: 8),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _importFile,
                icon: const Icon(Icons.upload_file, size: 18),
                label: const Text('Import CSV, TXT or XLSX'),
              ),
              const SizedBox(width: 8),
              if (_codesCtrl.text.isNotEmpty)
                TextButton.icon(
                  onPressed: () => _codesCtrl.clear(),
                  icon: const Icon(Icons.clear, size: 18),
                  label: const Text('Clear'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          _codesSummary(scheme),
        ],
      ],
      _gap,
      _text(_nameCtrl, 'Name',
          helper: _batch
              ? 'Optional label shown on reports; every coupon in the batch gets it.'
              : 'Optional label shown on reports and receipts.'),
    ]);
  }

  Widget _codesSummary(ColorScheme scheme) {
    final a = _analyseCodes();
    final problems = <String>[
      if (a.codes.length > _maxBatch) 'More than $_maxBatch codes',
      if (a.invalid.isNotEmpty) '${fmtCount(a.invalid.length)} invalid: ${a.invalid.take(20).join(', ')}${a.invalid.length > 20 ? '…' : ''}',
      if (a.duplicates.isNotEmpty) '${fmtCount(a.duplicates.length)} repeated: ${a.duplicates.take(20).join(', ')}${a.duplicates.length > 20 ? '…' : ''}',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${fmtCount(a.codes.length)} codes', style: const TextStyle(fontWeight: FontWeight.w600)),
        for (final p in problems) Text(p, style: TextStyle(color: scheme.error, fontSize: 12)),
      ],
    );
  }

  // Discount
  Widget _discountSection(ColorScheme scheme) => _section(scheme, 'Discount', [
        _row([
          DropdownButtonFormField<String>(
            initialValue: _mode,
            decoration: const InputDecoration(labelText: 'Discount type', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'PERCENTAGE', child: Text('Percentage')),
              DropdownMenuItem(value: 'AMOUNT', child: Text('Fixed amount')),
            ],
            onChanged: (v) => setState(() => _mode = v ?? 'PERCENTAGE'),
          ),
          _text(_valueCtrl, _mode == 'PERCENTAGE' ? 'Percentage (1–100)' : 'Amount', money: true),
        ]),
        _gap,
        _row([
          _text(_maxDiscountCtrl, 'Max discount per order', money: true, helper: 'Empty = no cap'),
          const SizedBox.shrink(),
        ]),
      ]);

  // Products and branches
  Widget _scopeSection(ColorScheme scheme) => _section(scheme, 'Where it works', [
        _row([
          DropdownButtonFormField<String>(
            initialValue: _type,
            decoration: InputDecoration(
              labelText: 'Applies to',
              helperText: _isEdit ? 'Cannot change after creation.' : null,
              border: const OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'GLOBAL', child: Text('Whole order')),
              DropdownMenuItem(value: 'PRODUCT', child: Text('Selected products')),
            ],
            onChanged: _isEdit ? null : (v) => setState(() => _type = v ?? 'GLOBAL'),
          ),
          DropdownButtonFormField<String>(
            initialValue: _storeScope,
            decoration: const InputDecoration(labelText: 'Branches', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'ALL', child: Text('All branches')),
              DropdownMenuItem(value: 'SOME', child: Text('Selected branches')),
            ],
            onChanged: (v) => setState(() => _storeScope = v ?? 'ALL'),
          ),
        ]),
        if (_type == 'PRODUCT') ...[
          _gap,
          const Text('Products', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          if (_products.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final e in _products.entries)
                  InputChip(label: Text(e.value), onDeleted: () => setState(() => _products.remove(e.key))),
              ],
            ),
          const SizedBox(height: 6),
          ProductSearchField(
            key: ValueKey(_productFieldKey),
            width: 360,
            hintText: 'Search product to add…',
            onSearch: (query) async {
              final token = context.read<AuthState>().token;
              if (token == null) return [];
              return ApiClient().getAdminProducts(token, search: query);
            },
            labelBuilder: (p) => parseLocalizedName(p['name']),
            onSelected: (p) {
              if (p == null) return;
              setState(() {
                _products[(p['id'] as num).toInt()] = parseLocalizedName(p['name']);
                _productFieldKey++;
              });
            },
          ),
        ],
        if (_storeScope == 'SOME') ...[
          _gap,
          const Text('Branches', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final s in _stores)
                FilterChip(
                  label: Text(s.label()),
                  selected: _storeIds.contains(s.id),
                  onSelected: (on) => setState(() => on ? _storeIds.add(s.id) : _storeIds.remove(s.id)),
                ),
            ],
          ),
        ],
      ]);

  Widget _dateField(String label, DateTime? value, bool start) => InkWell(
        onTap: () async {
          final d = await showWahaDatePicker(context, initial: value, allowFuture: true);
          if (d != null) {
            setState(() => start
                ? _starts = DateTime(d.year, d.month, d.day, 0, 0)
                : _expires = DateTime(d.year, d.month, d.day, 23, 59));
          }
        },
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            helperText: 'Empty = no ${start ? 'start' : 'end'} date',
            border: const OutlineInputBorder(),
            suffixIcon: value == null
                ? const Icon(Icons.calendar_today_outlined, size: 18)
                : IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () => setState(() => start ? _starts = null : _expires = null),
                  ),
          ),
          child: Text(value == null ? '' : _dateFmt.format(value)),
        ),
      );

  Widget _validitySection(ColorScheme scheme) => _section(scheme, 'Validity', [
        _row([_dateField('Starts', _starts, true), _dateField('Expires', _expires, false)]),
      ]);

  Widget _limitsSection(ColorScheme scheme) => _section(
        scheme,
        'Limits',
        [
          _row([
            _text(_maxInvoicesCtrl, 'Max invoices in total', digits: true, helper: 'Paid orders using this coupon'),
            _text(_maxInvoicesPerUserCtrl, 'Max invoices per user', digits: true),
          ]),
          _gap,
          _row([
            _text(_maxAmountCtrl, 'Max discount given in total', money: true, helper: 'Excludes VAT'),
            _text(_maxAmountPerUserCtrl, 'Max discount given per user', money: true),
          ]),
          _gap,
          _row([
            _text(_minOrderCtrl, 'Minimum order amount', money: true),
            const SizedBox.shrink(),
          ]),
        ],
        hint: 'Leave a limit empty for no limit.',
      );

  Widget _optionsSection(ColorScheme scheme) => _section(scheme, 'Options', [
        DropdownButtonFormField<int?>(
          initialValue: _employeeId,
          isExpanded: true,
          decoration: const InputDecoration(
              labelText: 'Employee', helperText: 'Optional: credit the coupon to one employee in reports', border: OutlineInputBorder()),
          items: [
            const DropdownMenuItem<int?>(value: null, child: Text('None')),
            for (final e in _employees) DropdownMenuItem<int?>(value: e.id, child: Text(e.displayName)),
          ],
          onChanged: (v) => setState(() => _employeeId = v),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Allow together with automatic offers'),
          subtitle: const Text('When off, the coupon is refused on orders that already get an offer.'),
          value: _stacking,
          onChanged: (v) => setState(() => _stacking = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Enabled'),
          value: _enabled,
          onChanged: (v) => setState(() => _enabled = v),
        ),
      ]);
}

/// Shown after a batch is created: every code, with copy and CSV download.
class _CreatedDialog extends StatelessWidget {
  final List<Map<String, dynamic>> created;
  const _CreatedDialog(this.created);

  @override
  Widget build(BuildContext context) {
    final codes = created.map((c) => c['code'].toString()).toList();
    final text = codes.join('\n');
    return AlertDialog(
      title: Text('${fmtCount(codes.length)} coupons created'),
      content: SizedBox(
        width: 480,
        height: 360,
        child: SingleChildScrollView(child: SelectableText(text)),
      ),
      actions: [
        TextButton.icon(
          icon: const Icon(Icons.copy, size: 18),
          label: const Text('Copy all'),
          onPressed: () => Clipboard.setData(ClipboardData(text: text)),
        ),
        TextButton.icon(
          icon: const Icon(Icons.download, size: 18),
          label: const Text('Download CSV'),
          onPressed: () {
            final url = html.Url.createObjectUrlFromBlob(
                html.Blob(['code\n$text\n'], 'text/csv;charset=utf-8'));
            html.AnchorElement(href: url)
              ..setAttribute('download', 'coupon-codes.csv')
              ..click();
            html.Url.revokeObjectUrl(url);
          },
        ),
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
      ],
    );
  }
}
