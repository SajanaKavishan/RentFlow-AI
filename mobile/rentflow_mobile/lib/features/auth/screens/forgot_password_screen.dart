import 'package:flutter/material.dart';

import '../../../core/validation/recovery_email.dart';
import '../../../shared/theme/app_theme.dart';
import '../controllers/auth_controller.dart';
import '../services/auth_service.dart';
import '../widgets/auth_shell.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail = ''});

  final String initialEmail;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _emailController = TextEditingController(
    text: widget.initialEmail,
  );
  bool _submitting = false;
  bool _confirmed = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || !(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await AuthScope.of(
        context,
      ).requestPasswordReset(email: _emailController.text.trim());
      if (mounted) setState(() => _confirmed = true);
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error =
              'Password reset instructions could not be requested. Please try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => AuthShell(
    showBackButton: true,
    child: Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AuthFieldLabel('ACCOUNT RECOVERY'),
          const SizedBox(height: 6),
          Text(
            _confirmed ? 'Request confirmed' : 'Forgot your password?',
            style: AppTypography.pageTitle,
          ),
          const SizedBox(height: 12),
          if (_confirmed)
            Semantics(
              liveRegion: true,
              child: const Text(
                AuthService.passwordResetConfirmation,
                key: Key('recovery-confirmation'),
                style: AppTypography.body,
              ),
            )
          else ...[
            const Text(
              "Enter the email associated with your RentFlow account. We'll send password reset instructions if the account is eligible.",
              style: AppTypography.body,
            ),
            const SizedBox(height: 20),
            const AuthFieldLabel('Email'),
            const SizedBox(height: 6),
            Semantics(
              label: 'Email',
              child: TextFormField(
                key: const Key('recovery-email'),
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.email],
                autocorrect: false,
                enabled: !_submitting,
                decoration: const InputDecoration(errorMaxLines: 3),
                validator: validateRecoveryEmail,
                onFieldSubmitted: (_) => _submit(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  key: const Key('recovery-error'),
                  style: const TextStyle(color: AppPalette.danger),
                ),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              key: const Key('recovery-submit'),
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? Semantics(
                      label: 'Sending reset instructions',
                      child: const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : const Text(
                      'Send reset instructions',
                      textAlign: TextAlign.center,
                    ),
            ),
          ],
          const SizedBox(height: 12),
          TextButton(
            key: const Key('recovery-back'),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              'Back to sign in',
              textAlign: TextAlign.center,
              style: TextStyle(decoration: TextDecoration.underline),
            ),
          ),
        ],
      ),
    ),
  );
}
