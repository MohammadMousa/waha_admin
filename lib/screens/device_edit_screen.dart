import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/device.dart';
import '../models/store.dart';
import '../router/routes.dart';
import '../services/api_client.dart';
import '../state/auth_state.dart';
import '../widgets/admin_sidebar.dart';
import '../widgets/error_dialog.dart';

const _kDeviceTypes = ['KIOSK'];

class DeviceEditScreen extends StatefulWidget {
  final Device? device;
  const DeviceEditScreen({super.key, this.device});

  @override
  State<DeviceEditScreen> createState() => _DeviceEditScreenState();
}

class _DeviceEditScreenState extends State<DeviceEditScreen> {
  bool get _isCreate => widget.device == null;

  final _username = TextEditingController();
  final _pinCode = TextEditingController();
  final _name = TextEditingController();
  final _deviceNo = TextEditingController();

  String _deviceType = 'KIOSK';
  bool _enabled = true;
  bool _obscurePin = true;

  List<Store>? _stores;
  final Map<int, String> _shortCodes = {};
  int? _selectedStoreId;
  bool _loadingStores = true;
  bool _saving = false;
  String? _error;
  String? _createdDeviceKey;

  @override
  void initState() {
    super.initState();
    final d = widget.device;
    if (d != null) {
      _username.text = d.username;
      _name.text = d.name ?? '';
      _deviceType = d.deviceType;
      _enabled = d.enabled;
      _selectedStoreId = d.storeId;
      _deviceNo.text = d.deviceNo?.toString() ?? '';
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadStores());
  }

  @override
  void dispose() {
    _username.dispose();
    _pinCode.dispose();
    _name.dispose();
    _deviceNo.dispose();
    super.dispose();
  }

  /// Reads the store's short code (the reference prefix); stores without one
  /// use their id.
  Future<void> _loadShortCode(int? storeId) async {
    if (storeId == null || _shortCodes.containsKey(storeId)) return;
    final token = context.read<AuthState>().token;
    if (token == null) return;
    try {
      final d = await ApiClient().getStoreAdminDetails(storeId, token: token);
      if (mounted) setState(() => _shortCodes[storeId] = (d?['shortCode'] as String?) ?? '');
    } on ApiException catch (_) {}
  }

  Future<void> _loadStores() async {
    final token = context.read<AuthState>().token;
    if (token == null) {
      setState(() => _loadingStores = false);
      return;
    }
    try {
      final stores = await ApiClient().getAdminStores(token);
      if (mounted)
        setState(() {
          _stores = stores;
          _loadingStores = false;
        });
      _loadShortCode(_selectedStoreId);
    } on ApiException catch (_) {
      if (mounted) setState(() => _loadingStores = false);
    }
  }

  Future<void> _save() async {
    final username = _username.text.trim();
    if (username.isEmpty) {
      setState(() => _error = 'Username is required.');
      return;
    }
    if (_isCreate && _pinCode.text.trim().length != 6) {
      setState(() => _error = 'PIN must be exactly 6 digits');
      return;
    }
    if (!_isCreate && _pinCode.text.trim().isNotEmpty && _pinCode.text.trim().length != 6) {
      setState(() => _error = 'PIN must be exactly 6 digits');
      return;
    }
    if (_isCreate && _selectedStoreId == null) {
      setState(() => _error = 'A store is required.');
      return;
    }
    final deviceNo = int.tryParse(_deviceNo.text.trim());
    if (_deviceNo.text.trim().isNotEmpty && (deviceNo == null || deviceNo < 1 || deviceNo > 99)) {
      setState(() => _error = 'Device number must be between 1 and 99.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final token = context.read<AuthState>().token;
    if (token == null) {
      setState(() {
        _saving = false;
        _error = 'Not logged in.';
      });
      return;
    }
    try {
      final api = ApiClient();
      if (_isCreate) {
        final result = await api.createDevice({
          'username': username,
          'pinCode': _pinCode.text.trim(),
          'storeId': _selectedStoreId,
          'name': _name.text.trim().isNotEmpty ? _name.text.trim() : username,
          'deviceType': _deviceType,
          'enabled': _enabled,
          if (deviceNo != null) 'deviceNo': deviceNo,
        }, token: token);
        if (mounted) {
          setState(() {
            _saving = false;
            _createdDeviceKey = result['deviceKey'] as String?;
          });
        }
        return;
      } else {
        await api.patchDevice(widget.device!.id, {
          'enabled': _enabled,
          'name': _name.text.trim().isNotEmpty ? _name.text.trim() : null,
          'deviceType': _deviceType,
          if (_selectedStoreId != null) 'storeId': _selectedStoreId,
          if (deviceNo != null) 'deviceNo': deviceNo,
          if (_pinCode.text.trim().isNotEmpty) 'pinCode': _pinCode.text.trim(),
        }, token: token);
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted)
        setState(() {
          _error = e.message;
          _saving = false;
        });
    }
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
          const AdminSidebar(currentRoute: Routes.devices),
          Expanded(
            child: _createdDeviceKey != null
                ? _buildCreatedPanel(scheme)
                : _buildForm(scheme),
          ),
        ],
      ),
    );
  }

  Widget _buildCreatedPanel(ColorScheme scheme) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
          decoration: BoxDecoration(
            color: scheme.surface,
            border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
          ),
          child: Text(
            'Device Created',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      color: scheme.primary,
                      size: 48,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Device created successfully.',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Store this device key on the kiosk for identification — '
                      'it will not be shown again.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    SelectableText(
                      _createdDeviceKey!,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('Done'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildForm(ColorScheme scheme) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
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
              Text(
                _isCreate ? 'New Device' : 'Edit Device',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              if (!_isCreate && (widget.device?.isLocked ?? false)) ...[
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Locked until ${DateFormat('h:mm a').format(widget.device!.lockedUntil!.toLocal())}',
                    style: const TextStyle(
                        fontSize: 11, color: Colors.red, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
              const Spacer(),
              if (!_loadingStores)
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Save'),
                ),
            ],
          ),
        ),
        Expanded(
          child: _loadingStores
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 540),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _Label('Credentials'),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _username,
                            enabled: _isCreate,
                            autocorrect: false,
                            decoration: const InputDecoration(
                              labelText: 'Username *',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.person_outline),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _pinCode,
                            obscureText: _obscurePin,
                            keyboardType: TextInputType.number,
                            maxLength: 6,
                            decoration: InputDecoration(
                              labelText: _isCreate
                                  ? 'PIN code *'
                                  : 'New PIN (leave blank to keep)',
                              counterText: '',
                              border: const OutlineInputBorder(),
                              prefixIcon: const Icon(Icons.pin_outlined),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePin
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                                onPressed: () =>
                                    setState(() => _obscurePin = !_obscurePin),
                              ),
                            ),
                          ),
                          if (!_isCreate &&
                              widget.device?.deviceKey != null) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.vpn_key_outlined,
                                    size: 18,
                                    color: scheme.outline,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: SelectableText(
                                      'Device key: ${widget.device!.deviceKey}',
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 20),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Enabled'),
                            subtitle: Text(
                              _enabled
                                  ? 'Device can sign in'
                                  : 'Sign-in disabled',
                            ),
                            value: _enabled,
                            onChanged: (v) => setState(() => _enabled = v),
                          ),
                          const Divider(height: 32),
                          _Label('Assignment'),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<int?>(
                            value: _selectedStoreId,
                            decoration: const InputDecoration(
                              labelText: 'Store *',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.store_outlined),
                            ),
                            items: [
                              const DropdownMenuItem<int?>(
                                value: null,
                                child: Text('— none —'),
                              ),
                              ...(_stores ?? []).map(
                                (s) => DropdownMenuItem<int?>(
                                  value: s.id,
                                  child: Text(s.name),
                                ),
                              ),
                            ],
                            onChanged: (v) {
                              setState(() => _selectedStoreId = v);
                              _loadShortCode(v);
                            },
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            value: _deviceType,
                            decoration: const InputDecoration(
                              labelText: 'Device type',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.devices_outlined),
                            ),
                            items: _kDeviceTypes
                                .map(
                                  (t) => DropdownMenuItem(
                                    value: t,
                                    child: Text(t),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) {
                              if (v != null) setState(() => _deviceType = v);
                            },
                          ),
                          const Divider(height: 32),
                          _Label('Order numbers'),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _deviceNo,
                            keyboardType: TextInputType.number,
                            maxLength: 2,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              labelText: 'Device number (1–99)',
                              counterText: '',
                              helperText: _isCreate
                                  ? 'Leave empty to use the lowest free number in the store.'
                                  : 'Must be unique in the store. Moving the device to another store keeps the number only if it is free there.',
                              helperMaxLines: 3,
                              border: const OutlineInputBorder(),
                              prefixIcon: const Icon(Icons.pin_outlined),
                            ),
                          ),
                          const SizedBox(height: 12),
                          _OrderNumberPreview(
                            storeId: _selectedStoreId,
                            shortCode: _shortCodes[_selectedStoreId],
                            deviceNo: int.tryParse(_deviceNo.text.trim()),
                          ),
                          const Divider(height: 32),
                          _Label('Details'),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _name,
                            decoration: const InputDecoration(
                              labelText: 'Display name',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.label_outline),
                            ),
                          ),

                          const SizedBox(height: 40),
                        ],
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
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

/// Shows how this device's order references will look: `<store code>-DD-NNN`.
/// The prefix is the store's short code (or its id when it has none), the
/// device part follows the number being typed, and only that part is set here.
class _OrderNumberPreview extends StatelessWidget {
  final int? storeId;
  final String? shortCode;
  final int? deviceNo;
  const _OrderNumberPreview({required this.storeId, required this.shortCode, required this.deviceNo});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasCode = shortCode != null && shortCode!.isNotEmpty;
    final prefix = hasCode ? shortCode! : (storeId?.toString() ?? '···');
    final device = deviceNo == null ? '··' : deviceNo!.toString().padLeft(2, '0');
    Widget segment(String value, String label, {required bool editable}) => Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: editable ? scheme.primaryContainer : scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: editable ? scheme.primary : scheme.outlineVariant),
              ),
              child: Text(value,
                  style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: editable ? scheme.onPrimaryContainer : scheme.onSurfaceVariant)),
            ),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: editable ? FontWeight.w700 : FontWeight.w400,
                    color: editable ? scheme.primary : scheme.outline)),
          ],
        );
    Widget dash() => Padding(
          padding: const EdgeInsets.fromLTRB(6, 0, 6, 18),
          child: Text('-', style: TextStyle(fontSize: 20, color: scheme.outline)),
        );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Order reference pattern',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 10),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              segment(prefix, hasCode ? 'Store code' : 'Store id', editable: false),
              dash(),
              segment(device, 'Device', editable: true),
              dash(),
              segment('###', 'Serial', editable: false),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Orders taken offline on this device get a reference like this. The first part is the '
            "store's short code (the store id when it has none), the serial counts 001 to 999 on the "
            'kiosk; only the device part is set here.',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
