import 'package:flutter/material.dart';

import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/shared_widgets.dart';
import '../models/property.dart';
import '../models/property_preferences.dart';
import '../services/property_api_service.dart';
import 'property_photo.dart';

class PropertyCard extends StatelessWidget {
  const PropertyCard({
    super.key,
    required this.property,
    required this.onTap,
    this.propertyApiService,
    this.matchScore,
    this.saved,
    this.favoritePending = false,
    this.onToggleFavorite,
    this.favoriteUnavailableReason,
  });

  final Property property;
  final VoidCallback onTap;
  final PropertyApiService? propertyApiService;
  final int? matchScore;
  final bool? saved;
  final bool favoritePending;
  final VoidCallback? onToggleFavorite;
  final String? favoriteUnavailableReason;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.base),
    child: Card(
      elevation: 1,
      shadowColor: AppPalette.darkOlive.withValues(alpha: 0.08),
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
                  if (saved != null)
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Semantics(
                        toggled: saved,
                        child: IconButton(
                          key: ValueKey('property-favorite-${property.id}'),
                          tooltip:
                              favoriteUnavailableReason ??
                              (favoritePending
                                  ? 'Updating saved property'
                                  : saved!
                                  ? 'Remove ${property.title} from saved properties'
                                  : 'Save ${property.title}'),
                          onPressed: favoritePending ? null : onToggleFavorite,
                          style: IconButton.styleFrom(
                            backgroundColor: AppPalette.white,
                            disabledBackgroundColor: AppPalette.softCream,
                            minimumSize: const Size(48, 48),
                            foregroundColor: saved!
                                ? AppPalette.danger
                                : AppPalette.darkOlive,
                          ),
                          icon: favoritePending
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(
                                  saved!
                                      ? Icons.favorite_rounded
                                      : Icons.favorite_border_rounded,
                                ),
                        ),
                      ),
                    ),
                  if (matchScore != null &&
                      matchScore! >= 0 &&
                      matchScore! <= 100)
                    Positioned(
                      bottom: 12,
                      left: 12,
                      right: 12,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: StatusChip(
                          label: '$matchScore% Match',
                          tone: StatusTone.success,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _titleAndRent(context),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Icon(
                          Icons.location_on_outlined,
                          size: 15,
                          color: AppPalette.secondaryText,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          [property.city, property.address]
                              .where((value) => value.trim().isNotEmpty)
                              .join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AppPalette.secondaryText),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: AppSpacing.md,
                    runSpacing: AppSpacing.sm,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _Fact(
                        Icons.bed_outlined,
                        property.bedrooms == 0
                            ? 'Studio'
                            : '${property.bedrooms} beds',
                      ),
                      _Fact(
                        Icons.bathtub_outlined,
                        '${property.bathrooms} baths',
                      ),
                      if (property.area != null && property.areaUnit != null)
                        _Fact(
                          Icons.square_foot_outlined,
                          '${_area(property.area!)} ${property.areaUnit}',
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
                  if (property.amenities.isNotEmpty ||
                      property.amenityDetails?.isNotEmpty == true) ...[
                    const SizedBox(height: 10),
                    _amenityPills(),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _titleAndRent(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final title = Text(
        property.title,
        key: ValueKey('property-title-${property.id}'),
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
          height: 1.3,
        ),
      );
      final stacked =
          constraints.maxWidth < 260 ||
          MediaQuery.textScalerOf(context).scale(16) > 20;
      final price = Column(
        crossAxisAlignment: stacked
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.end,
        children: [
          Text(
            'LKR ${_money(property.monthlyRent)}',
            key: ValueKey('property-rent-${property.id}'),
            textAlign: stacked ? TextAlign.start : TextAlign.end,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppPalette.darkOlive,
            ),
          ),
          Text(
            '/ month',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppPalette.secondaryText,
              fontSize: 11,
            ),
          ),
        ],
      );
      if (stacked) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [title, const SizedBox(height: 8), price],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 3, child: title),
          const SizedBox(width: 12),
          Expanded(flex: 2, child: price),
        ],
      );
    },
  );

  Widget _amenityPills() {
    final amenities =
        (property.amenityDetails?.isNotEmpty == true
                ? property.amenityDetails!.map(
                    (item) =>
                        propertyAmenityCatalog[item.canonicalKey] ?? item.name,
                  )
                : property.amenities)
            .where((value) => value.trim().isNotEmpty)
            .toSet()
            .toList();
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final amenity in amenities.take(3))
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppPalette.softCream,
              border: Border.all(color: AppPalette.outline),
              borderRadius: BorderRadius.circular(AppRadii.pill),
            ),
            child: Text(
              amenity,
              style: const TextStyle(
                fontSize: 11,
                color: AppPalette.secondaryText,
              ),
            ),
          ),
        if (amenities.length > 3)
          Text(
            '+${amenities.length - 3} more',
            style: const TextStyle(fontSize: 11, color: AppPalette.olive),
          ),
      ],
    );
  }
}

String _area(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toString();

String _money(double value) => value
    .toStringAsFixed(0)
    .replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (match) => '${match[1]},',
    );

class _Fact extends StatelessWidget {
  const _Fact(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 16, color: AppPalette.olive),
      const SizedBox(width: 5),
      Flexible(
        child: Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: AppPalette.secondaryText),
        ),
      ),
    ],
  );
}
