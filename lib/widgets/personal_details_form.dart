import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'waha_date_picker.dart';

/// Holds the personal fields of a person's profile (name, phone, email, gender,
/// birth date, language) and knows which of them changed since they were loaded.
class PersonalDetailsController {
  static final _dateFmt = DateFormat('yyyy-MM-dd');

  final firstName = TextEditingController();
  final lastName = TextEditingController();
  final phone = TextEditingController();
  final email = TextEditingController();
  String? gender;
  DateTime? birthDate;
  String? language;
  bool phoneVerified = false;
  Map<String, String> _loaded = {};

  Map<String, String> current() => {
        'firstName': firstName.text.trim(),
        'lastName': lastName.text.trim(),
        'phone': phone.text.trim(),
        'email': email.text.trim(),
        'gender': gender ?? '',
        'birthDate': birthDate == null ? '' : _dateFmt.format(birthDate!),
        'language': language ?? '',
      };

  /// Fills the fields from a profile object and remembers it as the baseline.
  void apply(Map<String, dynamic> p) {
    firstName.text = p['firstName']?.toString() ?? '';
    lastName.text = p['lastName']?.toString() ?? '';
    phone.text = p['phone']?.toString() ?? '';
    email.text = p['email']?.toString() ?? '';
    gender = p['gender']?.toString();
    birthDate = DateTime.tryParse(p['birthDate']?.toString() ?? '');
    language = p['language']?.toString();
    phoneVerified = p['phoneVerified'] == true;
    _loaded = current();
  }

  /// Fields that differ from the loaded values (an empty string clears one).
  Map<String, String> changed() => {
        for (final e in current().entries)
          if (e.value != (_loaded[e.key] ?? '')) e.key: e.value,
      };

  /// For a new person: only the fields that were filled in.
  Map<String, String> filled() => {
        for (final e in current().entries)
          if (e.value.isNotEmpty) e.key: e.value,
      };

  void dispose() {
    firstName.dispose();
    lastName.dispose();
    phone.dispose();
    email.dispose();
  }
}

/// The personal fields, drawn the same way on every screen that edits them.
class PersonalDetailsFields extends StatefulWidget {
  final PersonalDetailsController controller;
  final VoidCallback? onChanged;
  const PersonalDetailsFields({super.key, required this.controller, this.onChanged});

  @override
  State<PersonalDetailsFields> createState() => _PersonalDetailsFieldsState();
}

class _PersonalDetailsFieldsState extends State<PersonalDetailsFields> {
  PersonalDetailsController get c => widget.controller;

  void _changed() {
    setState(() {});
    widget.onChanged?.call();
  }

  Future<void> _pickBirthDate() async {
    final d = await showWahaDatePicker(context, initial: c.birthDate);
    if (d != null) {
      c.birthDate = d;
      _changed();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    InputDecoration deco(String l, {IconData? icon, String? helper}) => InputDecoration(
          labelText: l,
          helperText: helper,
          prefixIcon: icon == null ? null : Icon(icon),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Expanded(
            child: TextField(
              controller: c.firstName,
              maxLength: 100,
              decoration: deco('First name').copyWith(counterText: ''),
              onChanged: (_) => _changed(),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: TextField(
              controller: c.lastName,
              maxLength: 100,
              decoration: deco('Last name').copyWith(counterText: ''),
              onChanged: (_) => _changed(),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: c.phone,
          keyboardType: TextInputType.phone,
          decoration: deco('Phone',
              icon: Icons.phone_outlined,
              helper: c.phoneVerified
                  ? 'Verified'
                  : 'Not verified. Changing the phone clears verification.'),
          onChanged: (_) => _changed(),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: c.email,
          keyboardType: TextInputType.emailAddress,
          decoration: deco('Email', icon: Icons.email_outlined),
          onChanged: (_) => _changed(),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: c.gender,
          decoration: deco('Gender'),
          items: const [
            DropdownMenuItem(value: 'MALE', child: Text('Male')),
            DropdownMenuItem(value: 'FEMALE', child: Text('Female')),
          ],
          onChanged: (v) {
            c.gender = v;
            _changed();
          },
        ),
        const SizedBox(height: 12),
        InkWell(
          onTap: _pickBirthDate,
          child: InputDecorator(
            isEmpty: c.birthDate == null,
            decoration: deco('Birth date', icon: Icons.cake_outlined),
            child: Row(children: [
              Expanded(
                child: Text(c.birthDate == null
                    ? ''
                    : DateFormat('yyyy-MM-dd').format(c.birthDate!)),
              ),
              if (c.birthDate != null)
                InkWell(
                  onTap: () {
                    c.birthDate = null;
                    _changed();
                  },
                  child: Icon(Icons.close, size: 16, color: scheme.outline),
                ),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: c.language,
          decoration: deco('Language'),
          items: const [
            DropdownMenuItem(value: 'ar', child: Text('Arabic')),
            DropdownMenuItem(value: 'en', child: Text('English')),
          ],
          onChanged: (v) {
            c.language = v;
            _changed();
          },
        ),
      ],
    );
  }
}
