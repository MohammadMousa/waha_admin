import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../models/category.dart';
import '../router/routes.dart';
import '../services/api_client.dart';
import '../state/auth_state.dart';
import '../widgets/admin_sidebar.dart';
import '../widgets/resource_picker_modal.dart';

class CategoryEditScreen extends StatefulWidget {
  final Category category;
  final String storeSlug;
  const CategoryEditScreen({super.key, required this.category, required this.storeSlug});

  @override
  State<CategoryEditScreen> createState() => _CategoryEditScreenState();
}

class _CategoryEditScreenState extends State<CategoryEditScreen> {
  late final TextEditingController _nameArCtrl;
  late final TextEditingController _nameEnCtrl;
  int? _imageResourceId;
  String? _imageUrl;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final cat = widget.category;
    _nameArCtrl = TextEditingController(text: cat.name['ar'] as String? ?? '');
    _nameEnCtrl = TextEditingController(text: cat.name['en'] as String? ?? '');
    _imageResourceId = cat.imageResourceId;
  }

  @override
  void dispose() {
    _nameArCtrl.dispose();
    _nameEnCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final token = context.read<AuthState>().token;
    if (token == null) return;
    final result = await showImageSourcePicker(context,
        orgSlug: widget.storeSlug, token: token, entityType: 'category');
    if (result == null || !mounted) return;
    setState(() {
      _imageResourceId = result.resourceId;
      _imageUrl = result.publicUrl;
    });
  }

  Future<void> _save() async {
    final token = context.read<AuthState>().token;
    if (token == null) return;
    setState(() { _saving = true; _error = null; });
    try {
      await ApiClient().patchCategory(
        widget.category.id,
        {
          'name': {'ar': _nameArCtrl.text.trim(), 'en': _nameEnCtrl.text.trim()},
          if (_imageResourceId != null) 'imageResourceId': _imageResourceId,
        },
        token: token,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _saving = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: Row(
        children: [
          const AdminSidebar(currentRoute: Routes.categories),
          Expanded(
            child: Column(
              children: [
                // Header bar
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
                      Text('Edit Category',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const Spacer(),
                      FilledButton(
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const SizedBox(width: 18, height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2,
                                    color: Colors.white))
                            : const Text('Save'),
                      ),
                    ],
                  ),
                ),
                // Form body
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 540),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Center(
                              child: GestureDetector(
                                onTap: _pickImage,
                                child: Stack(
                                  children: [
                                    CircleAvatar(
                                      radius: 52,
                                      backgroundColor: scheme.surfaceContainerHighest,
                                      backgroundImage: _imageUrl != null
                                          ? NetworkImage('${AppConfig.apiBaseUrl}$_imageUrl')
                                          : (_imageResourceId != null
                                              ? NetworkImage('${AppConfig.apiBaseUrl}/api/resources/$_imageResourceId')
                                              : null),
                                      child: (_imageUrl == null && _imageResourceId == null)
                                          ? Icon(Icons.category_outlined, size: 40,
                                              color: scheme.onSurfaceVariant)
                                          : null,
                                    ),
                                    Positioned(
                                      bottom: 0, right: 0,
                                      child: CircleAvatar(
                                        radius: 16,
                                        backgroundColor: scheme.primary,
                                        child: Icon(Icons.edit, size: 16, color: scheme.onPrimary),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 28),
                            Text('Name', style: Theme.of(context).textTheme.titleSmall),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _nameArCtrl,
                              textDirection: TextDirection.rtl,
                              decoration: const InputDecoration(
                                  labelText: 'Arabic', border: OutlineInputBorder()),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _nameEnCtrl,
                              decoration: const InputDecoration(
                                  labelText: 'English', border: OutlineInputBorder()),
                            ),
                            if (_error != null) ...[
                              const SizedBox(height: 16),
                              Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                            ],
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
}
