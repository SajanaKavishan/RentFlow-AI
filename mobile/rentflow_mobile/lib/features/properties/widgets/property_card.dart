import 'package:flutter/material.dart';

import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/shared_widgets.dart';
import '../models/property.dart';
import '../services/property_api_service.dart';
import 'property_photo.dart';

class PropertyCard extends StatelessWidget {
  const PropertyCard({
    super.key,
    required this.property,
    required this.onTap,
    this.propertyApiService,
    this.matchScore,
  });

  final Property property;
  final VoidCallback onTap;
  final PropertyApiService? propertyApiService;
  final int? matchScore;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.base),
    child: Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  PropertyPhoto(
                    propertyId: property.id,
                    propertyApiService: propertyApiService,
                  ),
                  if (matchScore != null)
                    Positioned(
                      top: 12,
                      left: 12,
                      child: StatusChip(
                        label: '$matchScore% match',
                        tone: StatusTone.success,
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: AppSpacing.card,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    property.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    property.city,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'LKR ${property.monthlyRent.toStringAsFixed(0)} / month',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppPalette.darkOlive,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: AppSpacing.md,
                    runSpacing: AppSpacing.sm,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _Fact(Icons.bed_outlined, '${property.bedrooms} beds'),
                      _Fact(
                        Icons.bathtub_outlined,
                        '${property.bathrooms} baths',
                      ),
                      StatusChip(
                        label: property.isAvailable
                            ? 'Available'
                            : 'Unavailable',
                        tone: property.isAvailable
                            ? StatusTone.success
                            : StatusTone.neutral,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Fact extends StatelessWidget {
  const _Fact(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 18, color: AppPalette.olive),
      const SizedBox(width: 5),
      Text(label),
    ],
  );
}
