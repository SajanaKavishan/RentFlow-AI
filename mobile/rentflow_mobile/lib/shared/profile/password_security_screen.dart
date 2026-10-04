import 'package:flutter/material.dart';

import '../../core/validation/password_policy.dart';
import '../../features/auth/controllers/auth_controller.dart';
import '../../features/auth/services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/shared_widgets.dart';
import 'profile_page.dart';

class PasswordSecurityScreen extends StatefulWidget {
  const PasswordSecurityScreen({super.key});

  @override
  State<PasswordSecurityScreen> createState() => _PasswordSecurityScreenState();
}

class _PasswordSecurityScreenState extends State<PasswordSecurityScreen> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmation = TextEditingController();
  final _hidden = [true, true, true];
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _newPassword.addListener(_edited);
  }

  void _edited() => setState(() {});

  @override
  void dispose() {
    _current.dispose();
    _newPassword.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving || !_form.currentState!.validate()) return;
    final auth = AuthScope.of(context);
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await auth.changePassword(
        currentPassword: _current.text,
        newPassword: _newPassword.text,
        newPasswordConfirmation: _confirmation.text,
      );
      if (!mounted) return;
      _current.clear();
      _newPassword.clear();
      _confirmation.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Your password was changed successfully.'),
        ),
      );
      Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is AuthException
              ? error.message
              : 'Unable to change your password. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field({
    required int index,
    required String label,
    required String id,
    required TextEditingController controller,
    required FormFieldValidator<String> validator,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(label, style: AppTypography.body),
      const SizedBox(height: AppSpacing.sm),
      Semantics(
        label: label,
        child: TextFormField(
          key: Key(id),
          controller: controller,
          enabled: !_saving,
          obscureText: _hidden[index],
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: TextInputType.visiblePassword,
          autofillHints: [
            index == 0 ? AutofillHints.password : AutofillHints.newPassword,
          ],
          textInputAction: index == 2
              ? TextInputAction.done
              : TextInputAction.next,
          onFieldSubmitted: index == 2 ? (_) => _submit() : null,
          validator: validator,
          decoration: InputDecoration(
            fillColor: AppPalette.white,
            errorMaxLines: 4,
            suffixIcon: IconButton(
              tooltip:
                  '${_hidden[index] ? 'Show' : 'Hide'} ${label.toLowerCase()}',
              onPressed: _saving
                  ? null
                  : () => setState(() => _hidden[index] = !_hidden[index]),
              icon: Icon(
                _hidden[index]
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
            ),
          ),
        ),
      ),
    ],
  );

  Widget _requirement(String label, bool met) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.sm),
    child: Semantics(
      label: '$label: ${met ? 'met' : 'not yet met'}',
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            met ? Icons.check_circle_outline : Icons.radio_button_unchecked,
            size: 18,
            color: met ? AppPalette.olive : AppPalette.secondaryText,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(label, style: AppTypography.bodySmall)),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final policy = PasswordPolicy(_newPassword.text);
    return ProfileSurface(
      child: PopScope(
        canPop: !_saving,
        child: Scaffold(
          appBar: profilePageAppBar(
            context,
            title: 'Password & security',
            canGoBack: !_saving,
          ),
          body: AuthenticatedPage(
            maxWidth: 580,
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Change password',
                          style: AppTypography.sectionTitle,
                        ),
                        const SizedBox(height: AppSpacing.base),
                        _field(
                          index: 0,
                          label: 'Current password',
                          id: 'password-current',
                          controller: _current,
                          validator: (value) => (value ?? '').trim().isEmpty
                              ? 'Enter your current password.'
                              : null,
                        ),
                        const SizedBox(height: AppSpacing.base),
                        _field(
                          index: 1,
                          label: 'New password',
                          id: 'password-new',
                          controller: _newPassword,
                          validator: (value) => PasswordPolicy(
                            value ?? '',
                          ).validate(currentPassword: _current.text),
                        ),
                        const SizedBox(height: AppSpacing.base),
                        _field(
                          index: 2,
                          label: 'Confirm new password',
                          id: 'password-confirmation',
                          controller: _confirmation,
                          validator: (value) => (value ?? '').isEmpty
                              ? 'Confirm your new password.'
                              : value != _newPassword.text
                              ? 'New password and confirmation must match.'
                              : null,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.base),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Password requirements',
                          style: AppTypography.cardTitle,
                        ),
                        _requirement('8–128 characters', policy.hasLength),
                        _requirement(
                          'An uppercase letter',
                          policy.hasUppercase,
                        ),
                        _requirement('A lowercase letter', policy.hasLowercase),
                        _requirement('A number', policy.hasNumber),
                        _requirement('A special character', policy.hasSpecial),
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
                          key: const Key('password-error'),
                          style: AppTypography.body.copyWith(
                            color: AppPalette.danger,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: AppSpacing.lg),
                  Semantics(
                    liveRegion: _saving,
                    child: FilledButton(
                      key: const Key('password-submit'),
                      onPressed: _saving ? null : _submit,
                      child: Text(
                        _saving ? 'Changing password…' : 'Change password',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
