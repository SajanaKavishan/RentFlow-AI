import 'package:flutter/material.dart';

import '../../../shared/theme/app_theme.dart';
import '../../viewing_reviews/widgets/viewing_rating_summary.dart';
import '../models/property_image.dart';
import '../services/property_api_service.dart';
import 'public_landlord_avatar.dart';

/// The same public identity and real review aggregate on both landlord surfaces.
class PublicLandlordIdentity extends StatelessWidget {
  const PublicLandlordIdentity({
    super.key,
    required this.propertyId,
    required this.summary,
    required this.service,
    required this.reviews,
    this.ratingKey,
    this.action,
  });

  final String propertyId;
  final PublicLandlordSummary summary;
  final PropertyApiService service;
  final Future<Map<String, dynamic>> reviews;
  final Key? ratingKey;
  final Widget? action;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final avatar = PublicLandlordAvatar(
        propertyId: propertyId,
        summary: summary,
        service: service,
        size: 56,
      );
      final identity = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            summary.displayName,
            style: AppTypography.identityName.copyWith(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppPalette.primaryText,
            ),
          ),
          if (summary.memberSinceYear != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Member since ${summary.memberSinceYear}',
              style: AppTypography.bodySmall.copyWith(
                color: AppPalette.secondaryText,
              ),
            ),
          ],
          ViewingRatingSummary(key: ratingKey, summary: reviews, compact: true),
          if (action != null) ...[
            const SizedBox(height: AppSpacing.sm),
            action!,
          ],
        ],
      );
      if (constraints.maxWidth < 240 ||
          MediaQuery.textScalerOf(context).scale(14) > 21) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            avatar,
            const SizedBox(height: AppSpacing.sm),
            identity,
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          avatar,
          const SizedBox(width: AppSpacing.md),
          Expanded(child: identity),
        ],
      );
    },
  );
}
