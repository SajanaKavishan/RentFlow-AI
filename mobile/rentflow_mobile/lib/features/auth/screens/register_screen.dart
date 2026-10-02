import 'package:flutter/material.dart';

import '../../../shared/theme/app_theme.dart';
import '../controllers/auth_controller.dart';
import '../models/current_user.dart';
import '../services/auth_service.dart';
import '../widgets/auth_shell.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  static const publicRoles = [UserRole.tenant, UserRole.landlord];

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullName = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  UserRole _role = UserRole.tenant;
  bool _isSubmitting = false;
  bool _obscurePasswords = true;
  String? _error;

  @override
  void dispose() {
    _fullName.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _isSubmitting) return;
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      await AuthScope.of(context).register(
        fullName: _fullName.text.trim(),
        email: _email.text.trim(),
        phoneNumber: _phone.text.trim(),
        password: _password.text,
        role: _role,
      );
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Registration could not be completed.');
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  String? _required(String? value, String message) =>
      value == null || value.trim().isEmpty ? message : null;

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      compactFields: true,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'GET STARTED',
              style: TextStyle(
                color: AppPalette.authPrimary,
                fontSize: AppTypography.captionSize,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 6),
            const Text('Create your account', style: AppTypography.pageTitle),
            const SizedBox(height: 6),
            const Text(
              'Enter your details to begin your rental journey.',
              style: TextStyle(
                color: AppPalette.authMuted,
                fontSize: AppTypography.bodySmallSize,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            const AuthFieldLabel('Full name'),
            const SizedBox(height: 6),
            TextFormField(
              key: const Key('register-name'),
              controller: _fullName,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.name],
              decoration: const InputDecoration(hintText: 'Your full name'),
              validator: (value) => (value?.trim().length ?? 0) < 2
                  ? 'Enter your full name.'
                  : null,
            ),
            const SizedBox(height: 12),
            const AuthFieldLabel('Email'),
            const SizedBox(height: 6),
            TextFormField(
              key: const Key('register-email'),
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(hintText: 'you@example.com'),
              validator: (value) =>
                  value == null ||
                      !RegExp(r'^\S+@\S+\.\S+$').hasMatch(value.trim())
                  ? 'Enter a valid email address.'
                  : null,
            ),
            const SizedBox(height: 12),
            const AuthFieldLabel('Phone number'),
            const SizedBox(height: 6),
            TextFormField(
              key: const Key('register-phone'),
              controller: _phone,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.telephoneNumber],
              decoration: const InputDecoration(hintText: 'Your phone number'),
              validator: (value) =>
                  value == null ||
                      !RegExp(r'^[+\d][\d\s().-]{6,31}$').hasMatch(value.trim())
                  ? 'Enter a valid phone number.'
                  : null,
            ),
            const SizedBox(height: 12),
            const AuthFieldLabel('Account type'),
            const SizedBox(height: 6),
            DropdownButtonFormField<UserRole>(
              key: const Key('register-role'),
              initialValue: _role,
              decoration: const InputDecoration(),
              items: RegisterScreen.publicRoles
                  .map(
                    (role) =>
                        DropdownMenuItem(value: role, child: Text(role.value)),
                  )
                  .toList(growable: false),
              onChanged: _isSubmitting
                  ? null
                  : (role) {
                      if (role != null) setState(() => _role = role);
                    },
            ),
            const SizedBox(height: 12),
            const AuthFieldLabel('Password'),
            const SizedBox(height: 6),
            TextFormField(
              key: const Key('register-password'),
              controller: _password,
              obscureText: _obscurePasswords,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.newPassword],
              decoration: InputDecoration(
                hintText: 'At least 8 characters',
                suffixIcon: IconButton(
                  tooltip: _obscurePasswords
                      ? 'Show passwords'
                      : 'Hide passwords',
                  onPressed: _isSubmitting
                      ? null
                      : () => setState(
                          () => _obscurePasswords = !_obscurePasswords,
                        ),
                  icon: Icon(
                    _obscurePasswords
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
              validator: (value) => (value?.length ?? 0) < 8
                  ? 'Password must be at least 8 characters.'
                  : null,
            ),
            const SizedBox(height: 12),
            const AuthFieldLabel('Confirm password'),
            const SizedBox(height: 6),
            TextFormField(
              key: const Key('register-confirm'),
              controller: _confirmPassword,
              obscureText: _obscurePasswords,
              autofillHints: const [AutofillHints.newPassword],
              decoration: const InputDecoration(
                hintText: 'Repeat your password',
              ),
              validator: (value) =>
                  _required(value, 'Confirm your password.') ??
                  (value != _password.text ? 'Passwords do not match.' : null),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  _error!,
                  key: const Key('auth-error'),
                  softWrap: true,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 14),
            FilledButton(
              key: const Key('register-submit'),
              onPressed: _isSubmitting ? null : _submit,
              child: _isSubmitting
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Create account'),
            ),
            const SizedBox(height: 6),
            TextButton(
              key: const Key('register-login-link'),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                minimumSize: const Size(44, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: _isSubmitting
                  ? null
                  : () => Navigator.of(context).pop(),
              child: const Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'Already registered? ',
                      style: TextStyle(color: AppPalette.authMuted),
                    ),
                    TextSpan(
                      text: 'Sign in',
                      style: TextStyle(
                        color: AppPalette.authPrimary,
                        fontWeight: FontWeight.w700,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ],
                ),
                textAlign: TextAlign.center,
                style: AppTypography.label,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
