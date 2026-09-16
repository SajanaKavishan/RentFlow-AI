import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/theme/app_theme.dart';

/// Shared presentation for the real login and registration forms.
class AuthShell extends StatelessWidget {
  const AuthShell({
    super.key,
    required this.child,
    this.showBackButton = false,
    this.compactFields = false,
  });

  final Widget child;
  final bool showBackButton;
  final bool compactFields;

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
        isDense: true,
        fillColor: AppPalette.authInput,
        labelStyle: const TextStyle(color: AppPalette.authMuted),
        floatingLabelStyle: const TextStyle(color: AppPalette.authPrimary),
        contentPadding: EdgeInsets.symmetric(
          horizontal: 14,
          vertical: compactFields ? 12 : 14,
        ),
        constraints: BoxConstraints(minHeight: compactFields ? 50 : 56),
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
          minimumSize: const Size.fromHeight(48),
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

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Color(0xFF1C2619),
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
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
                  final isCompact = constraints.maxHeight < 580;
                  final gap = isCompact ? 18.0 : 46.0;
                  return SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 380),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: double.infinity,
                              height: 44,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Semantics(
                                    key: const Key('auth-brand'),
                                    label: 'RentFlow AI',
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            11,
                                          ),
                                          child: Image.asset(
                                            'assets/brand/auth-mark.png',
                                            width: 38,
                                            height: 38,
                                            fit: BoxFit.cover,
                                            excludeFromSemantics: true,
                                          ),
                                        ),
                                        const SizedBox(width: 7),
                                        const Text(
                                          'RentFlow',
                                          style: TextStyle(
                                            color: AppPalette.authCard,
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: -0.7,
                                          ),
                                        ),
                                        Transform.translate(
                                          offset: const Offset(2, -7),
                                          child: const Text(
                                            'AI',
                                            style: TextStyle(
                                              color: AppPalette.authCard,
                                              fontSize: 9,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
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
                            const SizedBox(height: 16),
                            const FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                'Find your perfect home, smarter.',
                                key: Key('auth-hero'),
                                maxLines: 1,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: AppPalette.authCard,
                                  fontSize: 23,
                                  height: 1.15,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.65,
                                ),
                              ),
                            ),
                            SizedBox(height: gap),
                            Theme(
                              data: authTheme,
                              child: Container(
                                key: const Key('auth-card'),
                                width: double.infinity,
                                padding: const EdgeInsets.all(18),
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
                                child: child,
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
      ),
    );
  }
}

class AuthFieldLabel extends StatelessWidget {
  const AuthFieldLabel(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: const TextStyle(
      color: AppPalette.authText,
      fontSize: 12,
      fontWeight: FontWeight.w700,
    ),
  );
}
