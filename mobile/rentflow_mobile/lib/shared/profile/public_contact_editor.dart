import 'package:flutter/material.dart';
import '../../core/validation/phone_number.dart';
import '../../features/auth/models/current_user.dart';
import '../theme/app_theme.dart';
import 'profile_page.dart';

enum _ContactPhoneSource { profile, different }

class PublicContactEditor extends StatefulWidget {
  const PublicContactEditor({
    super.key,
    required this.loadUser,
    required this.save,
    this.maintenance = false,
  });
  final Future<CurrentUser> Function() loadUser;
  final Future<CurrentUser> Function(CurrentUser, String, bool) save;
  final bool maintenance;

  @override
  State<PublicContactEditor> createState() => _PublicContactEditorState();
}

class _PublicContactEditorState extends State<PublicContactEditor> {
  final _phone = TextEditingController();
  CurrentUser? _user;
  bool _enabled = false;
  _ContactPhoneSource _source = _ContactPhoneSource.profile;
  bool _saving = false;
  String? _error;
  String get _title => widget.maintenance ? 'Work contact' : 'Public contact';
  String? _storedPhone(CurrentUser user) => widget.maintenance
      ? user.maintenanceContactPhone
      : user.publicContactPhone;
  bool _storedEnabled(CurrentUser user) => widget.maintenance
      ? user.maintenanceContactEnabled
      : user.publicContactEnabled;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final user = await widget.loadUser();
      if (!mounted) return;
      if (user.role !=
          (widget.maintenance
              ? UserRole.maintenanceTechnician
              : UserRole.landlord)) {
        throw const FormatException();
      }
      setState(() {
        _user = user;
        _phone.text = _storedPhone(user) ?? '';
        final storedPhone = (_storedPhone(user) ?? '').trim();
        _source = storedPhone.isEmpty || storedPhone == user.phoneNumber.trim()
            ? _ContactPhoneSource.profile
            : _ContactPhoneSource.different;
        _enabled = _storedEnabled(user);
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Unable to load ${_title.toLowerCase()} settings.',
        );
      }
    }
  }

  Future<void> _save() async {
    final user = _user;
    if (user == null || _saving) return;
    if (_enabled &&
        _source == _ContactPhoneSource.profile &&
        usablePhoneNumber(user.phoneNumber) == null) {
      setState(
        () => _error =
            'Add a profile phone number first, or use a different number.',
      );
      return;
    }
    // Source choice is edit state, never a live reference to the private phone.
    final publicPhone = _source == _ContactPhoneSource.different
        ? _phone.text.trim()
        : _enabled
        ? user.phoneNumber.trim()
        : (_storedPhone(user) ?? '').trim();
    if ((_enabled || publicPhone.isNotEmpty) &&
        usablePhoneNumber(publicPhone) == null) {
      setState(
        () => _error =
            'Enter a valid ${widget.maintenance ? 'work' : 'public'} contact number (7 to 15 digits, maximum 32 characters).',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.save(user, publicPhone, _enabled);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Your ${_title.toLowerCase()} could not be updated. Please try again.',
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
  Widget build(BuildContext context) => ProfileSurface(
    child: SafeArea(
      child: SingleChildScrollView(
        padding: AppSpacing.page.add(
          EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Back to Profile',
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    _title,
                    style: AppTypography.pageTitle.copyWith(
                      color: AppPalette.primaryText,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              widget.maintenance
                  ? 'Let tenants contact you about maintenance requests assigned to you.'
                  : 'Let tenants contact you with questions about your property listings.',
            ),
            const SizedBox(height: AppSpacing.base),
            if (_user == null && _error == null)
              const LinearProgressIndicator(),
            Text(
              'Which number would you like to publish?',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            RadioGroup<_ContactPhoneSource>(
              groupValue: _source,
              onChanged: (source) {
                if (source != null && _user != null && !_saving) {
                  setState(() => _source = source);
                }
              },
              child: Column(
                children: [
                  RadioListTile<_ContactPhoneSource>(
                    contentPadding: EdgeInsets.zero,
                    value: _ContactPhoneSource.profile,
                    enabled: _user != null && !_saving,
                    title: const Text('Use my profile phone number'),
                    subtitle: Text(
                      usablePhoneNumber(_user?.phoneNumber) ??
                          'Add a profile phone number first, or use a different number.',
                    ),
                  ),
                  RadioListTile<_ContactPhoneSource>(
                    contentPadding: EdgeInsets.zero,
                    value: _ContactPhoneSource.different,
                    enabled: _user != null && !_saving,
                    title: const Text('Use a different number'),
                  ),
                ],
              ),
            ),
            if (_source == _ContactPhoneSource.different)
              Padding(
                padding: const EdgeInsets.only(left: AppSpacing.base),
                child: TextField(
                  controller: _phone,
                  enabled: _user != null && !_saving,
                  maxLength: 32,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText:
                        '${widget.maintenance ? 'Work' : 'Public'} contact number',
                    hintText:
                        'Enter ${widget.maintenance ? 'work' : 'public'} contact number',
                  ),
                ),
              ),
            const SizedBox(height: AppSpacing.base),
            const Divider(),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _enabled,
              onChanged: _user == null || _saving
                  ? null
                  : (value) => setState(() => _enabled = value),
              title: Text(
                widget.maintenance
                    ? 'Share work contact with assigned tenants'
                    : 'Show contact number on my property listings',
              ),
            ),
            const Text(
              'Your profile phone stays private unless you explicitly choose to use it here.',
            ),
            if (widget.maintenance) ...[
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'Saving copies your chosen number. Later profile phone changes do not change your work contact.',
              ),
            ],
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
    ),
  );
}
