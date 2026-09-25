import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/employee.dart';
import '../models/store.dart';
import '../router/routes.dart';
import '../services/api_client.dart';
import '../state/auth_state.dart';
import '../widgets/admin_sidebar.dart';
import '../widgets/resource_picker_modal.dart';
import '../widgets/error_dialog.dart';

const _kAssignablePosRoles = ['CASHIER', 'OPERATOR', 'BRANCH_ADMIN'];
const _kGenders = ['MALE', 'FEMALE'];

class EmployeeEditScreen extends StatefulWidget {
  final Employee? employee;
  const EmployeeEditScreen({super.key, this.employee});

  @override
  State<EmployeeEditScreen> createState() => _EmployeeEditScreenState();
}

class _EmployeeEditScreenState extends State<EmployeeEditScreen> {
  bool get _isCreate => widget.employee == null;

  // Org-wide asset bucket for avatar uploads — same real org slug the
  // branch picker below is already fetching, same mechanism landing pages
  // use for global (no-branch) resource scope.
  String? get _orgSlug => _stores?.firstOrNull?.orgSlug;

  final _username = TextEditingController();
  final _pinCode = TextEditingController();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _notes = TextEditingController();

  static final _dateFmt = DateFormat('yyyy-MM-dd');

  String? _role; // null = no POS role assigned
  String? _gender;
  DateTime? _birthDate;
  DateTime? _hiredAt;
  bool _enabled = true;
  bool _obscurePin = true;
  int? _avatarResourceId;

  List<Store>? _stores;
  List<int> _selectedBranchIds = [];
  List<int> _originalBranchIds = [];
  bool _loadingStores = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.employee;
    if (e != null) {
      _username.text = e.username;
      _firstName.text = e.firstName ?? '';
      _lastName.text = e.lastName ?? '';
      _email.text = e.email ?? '';
      _phone.text = e.phone ?? '';
      _address.text = e.address ?? '';
      _notes.text = e.notes ?? '';
      _role = e.roleName;
      _gender = e.gender;
      _enabled = e.enabled;
      _avatarResourceId = e.avatarResourceId;
      _birthDate = e.birthDate != null ? DateTime.tryParse(e.birthDate!) : null;
      _hiredAt = e.hiredAt != null ? DateTime.tryParse(e.hiredAt!) : null;
      _selectedBranchIds = List.of(e.branchIds);
      _originalBranchIds = List.of(e.branchIds);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadStores());
  }

  @override
  void dispose() {
    _username.dispose();
    _pinCode.dispose();
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _phone.dispose();
    _address.dispose();
    _notes.dispose();
    super.dispose();
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
    } on ApiException catch (_) {
      if (mounted) setState(() => _loadingStores = false);
    }
  }

  Future<void> _pickBirthDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(2000),
      firstDate: DateTime(1940),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _birthDate = picked);
  }

  Future<void> _pickHiredAt() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _hiredAt ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _hiredAt = picked);
  }

  Future<void> _pickAvatar() async {
    final token = context.read<AuthState>().token;
    if (token == null) return;
    final orgSlug = _orgSlug;
    if (orgSlug == null) {
      showErrorDialog(context, 'No organization found for this account');
      return;
    }
    final result = await showImageSourcePicker(
      context,
      orgSlug: orgSlug,
      token: token,
      entityType: 'employee',
    );
    if (result == null || !mounted) return;
    setState(() => _avatarResourceId = result.resourceId);
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
    if (_role != null && _selectedBranchIds.isEmpty) {
      setState(
        () => _error = 'At least one branch is required when assigning a role.',
      );
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
    final roleStoreId = _selectedBranchIds.isNotEmpty
        ? _selectedBranchIds.first
        : null;
    try {
      final api = ApiClient();
      int employeeId;
      if (_isCreate) {
        employeeId = await api.createEmployee({
          'username': username,
          'pinCode': _pinCode.text.trim(),
          'enabled': _enabled,
          if (_firstName.text.trim().isNotEmpty)
            'firstName': _firstName.text.trim(),
          if (_lastName.text.trim().isNotEmpty)
            'lastName': _lastName.text.trim(),
          if (_gender != null) 'gender': _gender,
          if (_birthDate != null) 'birthDate': _dateFmt.format(_birthDate!),
          if (_email.text.trim().isNotEmpty) 'email': _email.text.trim(),
          if (_phone.text.trim().isNotEmpty) 'phone': _phone.text.trim(),
          if (_hiredAt != null) 'hiredAt': _dateFmt.format(_hiredAt!),
          if (_address.text.trim().isNotEmpty) 'address': _address.text.trim(),
          if (_notes.text.trim().isNotEmpty) 'notes': _notes.text.trim(),
          if (_avatarResourceId != null) 'avatarResourceId': _avatarResourceId,
          if (_role != null) 'role': _role,
          if (roleStoreId != null) 'storeId': roleStoreId,
        }, token: token);
      } else {
        employeeId = widget.employee!.id;
        await api.patchEmployee(employeeId, {
          'enabled': _enabled,
          'firstName': _firstName.text.trim().isNotEmpty
              ? _firstName.text.trim()
              : null,
          'lastName': _lastName.text.trim().isNotEmpty
              ? _lastName.text.trim()
              : null,
          'gender': _gender,
          if (_birthDate != null) 'birthDate': _dateFmt.format(_birthDate!),
          'email': _email.text.trim().isNotEmpty ? _email.text.trim() : null,
          'phone': _phone.text.trim().isNotEmpty ? _phone.text.trim() : null,
          if (_hiredAt != null) 'hiredAt': _dateFmt.format(_hiredAt!),
          'address': _address.text.trim().isNotEmpty
              ? _address.text.trim()
              : null,
          'notes': _notes.text.trim().isNotEmpty ? _notes.text.trim() : null,
          if (_avatarResourceId != null) 'avatarResourceId': _avatarResourceId,
          if (_pinCode.text.trim().isNotEmpty) 'pinCode': _pinCode.text.trim(),
          if (_role != null) ...{'role': _role, 'storeId': roleStoreId},
        }, token: token);
      }
      // Sync branch assignments (INSERT IGNORE server-side, so re-adding the
      // role's own store here is harmless).
      final added = _selectedBranchIds.where(
        (id) => !_originalBranchIds.contains(id),
      );
      final removed = _originalBranchIds.where(
        (id) => !_selectedBranchIds.contains(id),
      );
      await Future.wait([
        ...added.map(
          (id) => api.addEmployeeStore(employeeId, id, token: token),
        ),
        ...removed.map(
          (id) => api.removeEmployeeStore(employeeId, id, token: token),
        ),
      ]);
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
          const AdminSidebar(currentRoute: Routes.employees),
          Expanded(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    border: Border(
                      bottom: BorderSide(color: scheme.outlineVariant),
                    ),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _isCreate ? 'New Employee' : 'Edit Employee',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (!_isCreate && (widget.employee?.isLocked ?? false)) ...[
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'Locked until ${DateFormat('h:mm a').format(widget.employee!.lockedUntil!.toLocal())}',
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
                                  _Label('Avatar'),
                                  const SizedBox(height: 12),
                                  Center(
                                    child: GestureDetector(
                                      onTap: _pickAvatar,
                                      child: Stack(
                                        children: [
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              48,
                                            ),
                                            child: Container(
                                              width: 96,
                                              height: 96,
                                              color: scheme
                                                  .surfaceContainerHighest,
                                              child: Icon(
                                                Icons.person_outline,
                                                size: 40,
                                                color: scheme.onSurfaceVariant,
                                              ),
                                            ),
                                          ),
                                          Positioned(
                                            bottom: 0,
                                            right: 0,
                                            child: CircleAvatar(
                                              radius: 14,
                                              backgroundColor: scheme.primary,
                                              child: Icon(
                                                Icons.edit,
                                                size: 14,
                                                color: scheme.onPrimary,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 24),
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
                                      prefixIcon: const Icon(
                                        Icons.pin_outlined,
                                      ),
                                      suffixIcon: IconButton(
                                        icon: Icon(
                                          _obscurePin
                                              ? Icons.visibility_outlined
                                              : Icons.visibility_off_outlined,
                                        ),
                                        onPressed: () => setState(
                                          () => _obscurePin = !_obscurePin,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  SwitchListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text('Enabled'),
                                    subtitle: Text(
                                      _enabled
                                          ? 'Can sign in to POS'
                                          : 'Sign-in disabled',
                                    ),
                                    value: _enabled,
                                    onChanged: (v) =>
                                        setState(() => _enabled = v),
                                  ),
                                  const Divider(height: 32),
                                  _Label('Role & Branches'),
                                  const SizedBox(height: 12),
                                  DropdownButtonFormField<String?>(
                                    value: _role,
                                    decoration: const InputDecoration(
                                      labelText: 'Role',
                                      border: OutlineInputBorder(),
                                      prefixIcon: Icon(Icons.badge_outlined),
                                    ),
                                    items: [
                                      const DropdownMenuItem<String?>(
                                        value: null,
                                        child: Text('No role assigned'),
                                      ),
                                      ..._kAssignablePosRoles.map(
                                        (r) => DropdownMenuItem(
                                          value: r,
                                          child: Text(r),
                                        ),
                                      ),
                                    ],
                                    onChanged: (v) => setState(() => _role = v),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Branches',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      for (final id in _selectedBranchIds)
                                        InputChip(
                                          label: Text(_storeName(id)),
                                          onDeleted: () => setState(
                                            () => _selectedBranchIds.remove(id),
                                          ),
                                        ),
                                      _AddBranchButton(
                                        stores: (_stores ?? [])
                                            .where(
                                              (s) => !_selectedBranchIds
                                                  .contains(s.id),
                                            )
                                            .toList(),
                                        onSelected: (id) => setState(
                                          () => _selectedBranchIds.add(id),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const Divider(height: 32),
                                  _Label('Personal Info'),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: _firstName,
                                    decoration: const InputDecoration(
                                      labelText: 'First name',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: _lastName,
                                    decoration: const InputDecoration(
                                      labelText: 'Last name',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  DropdownButtonFormField<String?>(
                                    value: _gender,
                                    decoration: const InputDecoration(
                                      labelText: 'Gender',
                                      border: OutlineInputBorder(),
                                      prefixIcon: Icon(Icons.wc_outlined),
                                    ),
                                    items: [
                                      const DropdownMenuItem<String?>(
                                        value: null,
                                        child: Text('Not specified'),
                                      ),
                                      ..._kGenders.map(
                                        (g) => DropdownMenuItem(
                                          value: g,
                                          child: Text(
                                            g[0] + g.substring(1).toLowerCase(),
                                          ),
                                        ),
                                      ),
                                    ],
                                    onChanged: (v) =>
                                        setState(() => _gender = v),
                                  ),
                                  const SizedBox(height: 12),
                                  _DateField(
                                    label: 'Birth date',
                                    value: _birthDate,
                                    onTap: _pickBirthDate,
                                  ),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: _email,
                                    keyboardType: TextInputType.emailAddress,
                                    decoration: const InputDecoration(
                                      labelText: 'Email',
                                      border: OutlineInputBorder(),
                                      prefixIcon: Icon(Icons.email_outlined),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: _phone,
                                    keyboardType: TextInputType.phone,
                                    decoration: const InputDecoration(
                                      labelText: 'Phone',
                                      border: OutlineInputBorder(),
                                      prefixIcon: Icon(Icons.phone_outlined),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  _DateField(
                                    label: 'Employee since',
                                    value: _hiredAt,
                                    onTap: _pickHiredAt,
                                  ),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: _address,
                                    minLines: 2,
                                    maxLines: 4,
                                    decoration: const InputDecoration(
                                      labelText: 'Address',
                                      border: OutlineInputBorder(),
                                      prefixIcon: Icon(
                                        Icons.location_on_outlined,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: _notes,
                                    minLines: 2,
                                    maxLines: 4,
                                    decoration: const InputDecoration(
                                      labelText: 'Notes',
                                      border: OutlineInputBorder(),
                                      prefixIcon: Icon(Icons.notes_outlined),
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
            ),
          ),
        ],
      ),
    );
  }

  String _storeName(int id) {
    final match = (_stores ?? []).where((s) => s.id == id).firstOrNull;
    return match?.label() ?? '#$id';
  }
}

class _AddBranchButton extends StatelessWidget {
  final List<Store> stores;
  final ValueChanged<int> onSelected;
  const _AddBranchButton({required this.stores, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (stores.isEmpty) return const SizedBox.shrink();
    return PopupMenuButton<int>(
      onSelected: onSelected,
      itemBuilder: (_) => stores
          .map((s) => PopupMenuItem(value: s.id, child: Text(s.label())))
          .toList(),
      child: Chip(
        avatar: Icon(Icons.add, size: 18, color: scheme.primary),
        label: const Text('Add branch'),
        backgroundColor: scheme.surfaceContainerHighest,
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final VoidCallback onTap;
  static final _fmt = DateFormat('MMM d, yyyy');

  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          prefixIcon: const Icon(Icons.calendar_today_outlined),
        ),
        child: Text(value != null ? _fmt.format(value!) : 'Not set'),
      ),
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
