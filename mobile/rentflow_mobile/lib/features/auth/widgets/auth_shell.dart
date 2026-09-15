import 'package:flutter/material.dart';

import '../../../shared/theme/app_theme.dart';

/// Shared presentation for the real login and registration forms.
class AuthShell extends StatelessWidget {
  const AuthShell({
    super.key,
    required this.child,
    this.showBackButton = false,
  });

  final Widget child;
  final bool showBackButton;

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadii.authField),
      borderSide: const BorderSide(color: AppPalette.authBorder),
    );
    final focusedBorder = border.copyWith(
      borderSide: const BorderSide(color: AppPalette.authPrimary, width: 1.5),
    );
    final authTheme = Theme.of(context).copyWith(
      colorScheme: Theme.of(context).colorScheme.copyWith(
        primary: AppPalette.authPrimary,
        onPrimary: AppPalette.authCard,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppPalette.authInput,
        labelStyle: const TextStyle(color: AppPalette.authMuted),
        floatingLabelStyle: const TextStyle(color: AppPalette.authPrimary),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: border,
        enabledBorder: border,
        focusedBorder: focusedBorder,
        errorBorder: border.copyWith(
          borderSide: const BorderSide(color: AppPalette.danger),
        ),
        focusedErrorBorder: focusedBorder.copyWith(
          borderSide: const BorderSide(color: AppPalette.danger, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          backgroundColor: AppPalette.authPrimary,
          foregroundColor: AppPalette.authCard,
          disabledBackgroundColor: AppPalette.authPressed,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.authField),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppPalette.authPrimary,
          minimumSize: const Size(44, 44),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/auth/residence.png',
              key: const Key('auth-background'),
              fit: BoxFit.cover,
              alignment: Alignment.center,
              excludeFromSemantics: true,
            ),
          ),
          const Positioned.fill(child: ColoredBox(color: Color(0xB81C2619))),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isCompact = constraints.maxHeight < 650;
                final gap = showBackButton
                    ? (isCompact ? 12.0 : 24.0)
                    : (isCompact ? 16.0 : 56.0);
                return SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            height: 60,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Image.asset(
                                  'assets/brand/wordmark.png',
                                  key: const Key('auth-brand'),
                                  width: 172,
                                  fit: BoxFit.contain,
                                  semanticLabel: 'RentFlow AI',
                                ),
                                if (showBackButton)
                                  Positioned(
                                    left: 0,
                                    child: IconButton(
                                      tooltip: 'Back to sign in',
                                      onPressed: () =>
                                          Navigator.of(context).pop(),
                                      icon: const Icon(
                                        Icons.arrow_back_rounded,
                                      ),
                                      color: AppPalette.authCard,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          SizedBox(height: gap),
                          Theme(
                            data: authTheme,
                            child: Container(
                              key: const Key('auth-card'),
                              width: double.infinity,
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: AppPalette.authCard,
                                borderRadius: BorderRadius.circular(
                                  AppRadii.authCard,
                                ),
                                border: Border.all(
                                  color: AppPalette.authBorder,
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x420F140D),
                                    blurRadius: 42,
                                    offset: Offset(0, 18),
                                  ),
                                ],
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: Container(
                                      width: 36,
                                      height: 4,
                                      decoration: BoxDecoration(
                                        color: AppPalette.authSage,
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                  child,
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
