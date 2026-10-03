import 'package:flutter/material.dart';
import '../../core/validation/phone_number.dart';
import '../../features/auth/models/current_user.dart';
import '../theme/app_theme.dart';

class PublicContactEditor extends StatefulWidget {
  const PublicContactEditor({
    super.key,
    required this.loadUser,
    required this.save,
  });
  final Future<CurrentUser> Function() loadUser;
  final Future<CurrentUser> Function(CurrentUser, String, bool) save;

  @override
  State<PublicContactEditor> createState() => _PublicContactEditorState();
}

class _PublicContactEditorState extends State<PublicContactEditor> {
  final _phone = TextEditingController();
  CurrentUser? _user;
  bool _enabled = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final user = await widget.loadUser();
      if (!mounted) return;
      if (user.role != UserRole.landlord) throw const FormatException();
      setState(() {
        _user = user;
        _phone.text = user.publicContactPhone ?? '';
        _enabled = user.publicContactEnabled;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Unable to load public contact settings.');
      }
    }
  }

  Future<void> _save() async {
    final user = _user;
    if (user == null || _saving) return;
    if ((_enabled || _phone.text.trim().isNotEmpty) &&
        usablePhoneNumber(_phone.text) == null) {
      setState(
        () => _error =
            'Enter a valid public contact number (7 to 15 digits, maximum 32 characters).',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.save(user, _phone.text.trim(), _enabled);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Your public contact could not be updated. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: AppSpacing.page.add(
        EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Public contact', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'Let tenants contact you with questions about your property listings.',
          ),
          const SizedBox(height: AppSpacing.base),
          if (_user == null && _error == null) const LinearProgressIndicator(),
          TextField(
            controller: _phone,
            enabled: _user != null && !_saving,
            maxLength: 32,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Public contact number',
            ),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _enabled,
            onChanged: _user == null || _saving
                ? null
                : (value) => setState(() => _enabled = value ?? false),
            title: const Text('Show my contact number on my property listings'),
          ),
          const Text(
            'Your account phone remains private. Only this public contact number is shown when you enable it.',
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.base),
              child: Text(
                _error!,
                style: const TextStyle(color: AppPalette.danger),
              ),
            ),
          const SizedBox(height: AppSpacing.base),
          FilledButton(
            onPressed: _user == null || _saving ? null : _save,
            child: Text(_saving ? 'Saving…' : 'Save'),
          ),
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    ),
  );
}
