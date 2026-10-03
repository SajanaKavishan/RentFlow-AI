import 'package:flutter/material.dart';

import '../../../shared/theme/app_theme.dart';

/// Compact header shared by the tenant viewing list and details.
class ViewingPageHeader extends StatelessWidget {
  const ViewingPageHeader({
    super.key,
    required this.eyebrow,
    required this.title,
  });

  final String eyebrow;
  final String title;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      IconButton(
        tooltip: 'Back',
        onPressed: () => Navigator.of(context).maybePop(),
        style: IconButton.styleFrom(
          foregroundColor: AppPalette.darkOlive,
          backgroundColor: Colors.transparent,
          side: BorderSide.none,
          elevation: 0,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.all(12),
        ),
        icon: const Icon(Icons.arrow_back, size: 24),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              eyebrow.toUpperCase(),
              style: AppTypography.eyebrow.copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppPalette.olive,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: AppTypography.pageTitle.copyWith(
                fontWeight: FontWeight.w600,
                color: AppPalette.darkOlive,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}
