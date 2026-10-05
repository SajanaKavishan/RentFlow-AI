import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Foregrounds for Profile and its existing editors, without changing the app theme.
class ProfileSurface extends StatelessWidget {
  const ProfileSurface({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        textTheme: theme.textTheme.copyWith(
          bodyMedium: theme.textTheme.bodyMedium?.copyWith(
            color: AppPalette.primaryText,
          ),
          bodySmall: theme.textTheme.bodySmall?.copyWith(
            color: AppPalette.neutral,
          ),
        ),
        inputDecorationTheme: theme.inputDecorationTheme.copyWith(
          labelStyle: AppTypography.bodySmall.copyWith(
            color: AppPalette.neutral,
          ),
          floatingLabelStyle: AppTypography.label.copyWith(
            color: AppPalette.darkOlive,
          ),
          hintStyle: AppTypography.body.copyWith(color: AppPalette.neutral),
          helperStyle: AppTypography.bodySmall.copyWith(
            color: AppPalette.neutral,
          ),
          counterStyle: AppTypography.caption.copyWith(
            color: AppPalette.neutral,
          ),
        ),
      ),
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: AppPalette.primaryText),
        child: child,
      ),
    );
  }
}

/// A bare Back action and one wrapping title, including at enlarged text sizes.
AppBar profilePageAppBar(
  BuildContext context, {
  required String title,
  String backLabel = 'Back to Profile',
  bool canGoBack = true,
}) {
  final textScaler = MediaQuery.textScalerOf(context);
  final titleStyle = AppTypography.pageTitle.copyWith(
    color: AppPalette.primaryText,
  );
  final layout = TextPainter(
    text: TextSpan(text: title, style: titleStyle),
    textDirection: Directionality.of(context),
    textScaler: textScaler,
  )..layout(maxWidth: math.max(1, MediaQuery.sizeOf(context).width - 80));
  final height = math.max(kToolbarHeight, layout.height + AppSpacing.lg);
  layout.dispose();
  return AppBar(
    toolbarHeight: height,
    titleSpacing: AppSpacing.sm,
    leading: IconButton(
      tooltip: backLabel,
      onPressed: canGoBack ? () => Navigator.of(context).pop() : null,
      icon: const Icon(Icons.arrow_back),
    ),
    title: DefaultTextStyle(
      style: titleStyle,
      softWrap: true,
      overflow: TextOverflow.visible,
      child: Text(title, style: titleStyle, textScaler: textScaler),
    ),
  );
}
