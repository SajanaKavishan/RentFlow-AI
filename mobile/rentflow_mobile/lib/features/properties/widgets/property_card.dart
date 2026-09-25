import 'package:flutter/material.dart';

import '../../../shared/theme/app_theme.dart';
import '../models/property.dart';

class PropertyCard extends StatelessWidget {
  const PropertyCard({
    super.key,
    required this.property,
    required this.onTap,
  });

  final Property property;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PropertyImagePlaceholder(
              isAvailable: property.isAvailable,
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          property.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      const SizedBox(width: 12),
                      _AvailabilityBadge(
                        isAvailable: property.isAvailable,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        size: 17,
                        color: AppPalette.olive,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          property.city,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'LKR ${property.monthlyRent.toStringAsFixed(0)} / month',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: AppPalette.darkOlive,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      _PropertyFact(
                        icon: Icons.bed_outlined,
                        label: '${property.bedrooms} Beds',
                      ),
                      const SizedBox(width: 18),
                      _PropertyFact(
                        icon: Icons.bathtub_outlined,
                        label: '${property.bathrooms} Baths',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
class _PropertyImagePlaceholder extends StatelessWidget {
  const _PropertyImagePlaceholder({
    required this.isAvailable,
  });

  final bool isAvailable;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 170,
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppPalette.sage,
      ),
      child: Stack(
        children: [
          const Center(
            child: Icon(
              Icons.home_work_outlined,
              size: 58,
              color: AppPalette.darkOlive,
            ),
          ),
          Positioned(
            top: 14,
            left: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 7,
              ),
              decoration: BoxDecoration(
                color: AppPalette.darkOlive,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'RentFlow Home',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
class _AvailabilityBadge extends StatelessWidget {
  const _AvailabilityBadge({
    required this.isAvailable,
  });

  final bool isAvailable;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: isAvailable
            ? AppPalette.sage
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        isAvailable ? 'Available' : 'Unavailable',
        style: const TextStyle(
          color: AppPalette.darkOlive,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _PropertyFact extends StatelessWidget {
  const _PropertyFact({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          icon,
          size: 18,
          color: AppPalette.olive,
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}