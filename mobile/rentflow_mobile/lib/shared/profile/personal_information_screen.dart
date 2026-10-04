import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/validation/phone_number.dart';
import '../../features/auth/controllers/auth_controller.dart';
import '../../features/auth/models/current_user.dart';
import '../../features/auth/models/profile_image_file.dart';
import '../../features/auth/services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/shared_widgets.dart';
import 'profile_avatar.dart';

typedef ProfileImagePicker = Future<ProfileImageFile?> Function();

class PersonalInformationScreen extends StatefulWidget {
  const PersonalInformationScreen({
    super.key,
    required this.user,
    this.imagePicker,
  });
  final CurrentUser user;
  final ProfileImagePicker? imagePicker;

  @override
  State<PersonalInformationScreen> createState() =>
      _PersonalInformationScreenState();
}

class _PersonalInformationScreenState extends State<PersonalInformationScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late CurrentUser _saved;
  ProfileImageFile? _selected;
  bool _saving = false;
  bool _picking = false;
  String? _error;
  String? _success;

  bool get _accountChanged =>
      _name.text.trim() != _saved.fullName.trim() ||
      _phone.text.trim() != _saved.phoneNumber.trim();
  bool get _dirty => _accountChanged || _selected != null;
  bool get _busy => _saving || _picking;

  @override
  void initState() {
    super.initState();
    _saved = widget.user;
    _name = TextEditingController(text: _saved.fullName)..addListener(_edited);
    _phone = TextEditingController(text: _saved.phoneNumber)
      ..addListener(_edited);
  }

  void _edited() => setState(() => _success = null);

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<ProfileImageFile?> _pickImage() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
    );
    if (file == null) return null;
    final size = await file.length();
    if (size <= 0 || size > ProfileImageFile.maximumBytes) {
      throw const AuthException('Choose a photo between 1 byte and 5 MB.');
    }
    return ProfileImageFile(name: file.name, bytes: await file.readAsBytes());
  }

  Future<void> _choosePhoto() async {
    if (_busy) return;
    setState(() {
      _picking = true;
      _error = null;
      _success = null;
    });
    try {
      final image = await (widget.imagePicker ?? _pickImage)();
      if (!mounted || image == null) return;
      final error = image.validate();
      setState(() {
        if (error == null) _selected = image;
        _error = error;
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is AuthException
              ? error.message
              : 'Unable to choose a photo. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _save() async {
    if (_busy || !_dirty || !_form.currentState!.validate()) return;
    final auth = AuthScope.of(context);
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
      _success = null;
    });
    var accountSaved = false;
    try {
      if (_accountChanged) {
        final updated = await auth.updateProfile(
          fullName: _name.text.trim(),
          phoneNumber: _phone.text.trim(),
        );
        accountSaved = true;
        if (!mounted) return;
        _saved = updated;
        _name.text = updated.fullName;
        _phone.text = updated.phoneNumber;
      }
      if (_selected != null) {
        final updated = await auth.uploadProfileImage(_selected!);
        if (!mounted) return;
        _saved = updated;
        _selected = null;
        _name.text = updated.fullName;
        _phone.text = updated.phoneNumber;
      }
      if (mounted) setState(() => _success = 'Profile updated successfully.');
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = accountSaved
              ? 'Your profile information was saved, but the photo upload failed. Try saving again to upload your photo.'
              : error is AuthException
              ? error.message
              : 'Your profile could not be updated. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthScope.of(context).currentUser ?? _saved;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Back to Profile',
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back),
          ),
          title: const Text('PROFILE', style: AppTypography.eyebrow),
        ),
        body: AuthenticatedPage(
          maxWidth: 580,
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Personal information',
                  style: AppTypography.pageTitle,
                ),
                const SizedBox(height: AppSpacing.lg),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Profile photo',
                        style: AppTypography.cardTitle,
                      ),
                      const SizedBox(height: AppSpacing.base),
                      Wrap(
                        spacing: AppSpacing.base,
                        runSpacing: AppSpacing.md,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          ProfileAvatar(user: user, preview: _selected?.bytes),
                          OutlinedButton.icon(
                            onPressed: _busy ? null : _choosePhoto,
                            icon: const Icon(
                              Icons.add_a_photo_outlined,
                              size: 18,
                            ),
                            label: Text(
                              _picking ? 'Choosing photo…' : 'Change photo',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      const Text(
                        'JPEG, PNG, or WEBP. Maximum 5 MB.',
                        style: AppTypography.bodySmall,
                      ),
                      if (_selected != null)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.sm),
                          child: Text(
                            'Selected: ${_selected!.name}',
                            style: AppTypography.bodySmall,
                          ),
                        ),
                      const SizedBox(height: AppSpacing.lg),
                      TextFormField(
                        key: const Key('profile-full-name'),
                        controller: _name,
                        enabled: !_busy,
                        maxLength: 200,
                        textCapitalization: TextCapitalization.words,
                        autofillHints: const [AutofillHints.name],
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Full name',
                          errorMaxLines: 3,
                        ),
                        validator: (value) {
                          final name = (value ?? '').trim();
                          return name.length < 2 || name.length > 200
                              ? 'Full name must be between 2 and 200 characters.'
                              : null;
                        },
                      ),
                      const SizedBox(height: AppSpacing.base),
                      TextFormField(
                        key: const Key('profile-email'),
                        initialValue: user.email,
                        readOnly: true,
                        enabled: !_busy,
                        enableInteractiveSelection: true,
                        decoration: const InputDecoration(
                          labelText: 'Email (read-only)',
                          helperText:
                              'Your account email cannot be changed here.',
                          helperMaxLines: 3,
                          filled: true,
                          fillColor: AppPalette.softCream,
                          suffixIcon: Icon(Icons.lock_outline, size: 18),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      TextFormField(
                        key: const Key('profile-phone-number'),
                        controller: _phone,
                        enabled: !_busy,
                        maxLength: 32,
                        keyboardType: TextInputType.phone,
                        autofillHints: const [AutofillHints.telephoneNumber],
                        decoration: const InputDecoration(
                          labelText: 'Phone number',
                          errorMaxLines: 3,
                        ),
                        validator: (value) => isValidProfilePhone(value ?? '')
                            ? null
                            : 'Enter a valid phone number (7–32 characters).',
                      ),
                    ],
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.base),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        _error!,
                        style: AppTypography.body.copyWith(
                          color: AppPalette.danger,
                        ),
                      ),
                    ),
                  ),
                if (_success != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.base),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        _success!,
                        style: AppTypography.body.copyWith(
                          color: AppPalette.success,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: AppSpacing.lg),
                FilledButton(
                  key: const Key('profile-save'),
                  onPressed: _dirty && !_busy ? _save : null,
                  child: Text(_saving ? 'Saving changes…' : 'Save changes'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
