import 'package:flutter/material.dart';

import '../../../shared/theme/app_theme.dart';
import '../models/property_image.dart';
import '../services/property_api_service.dart';

class PublicLandlordAvatar extends StatelessWidget {
  const PublicLandlordAvatar({
    super.key,
    required this.propertyId,
    required this.summary,
    required this.service,
    this.size = 44,
  });

  final String propertyId;
  final PublicLandlordSummary summary;
  final PropertyApiService service;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initials = summary.displayName
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => String.fromCharCode(part.runes.first).toUpperCase())
        .join();
    final fallback = ColoredBox(
      color: AppPalette.sage,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: FittedBox(
            child: Text(
              initials.isEmpty ? 'L' : initials,
              style: TextStyle(
                color: AppPalette.darkOlive,
                fontSize: size * .32,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
    return Semantics(
      label: '${summary.displayName} profile image',
      image: true,
      excludeSemantics: true,
      child: ClipOval(
        child: SizedBox.square(
          dimension: size,
          child: summary.hasProfileImage
              ? Image.network(
                  service.landlordImageUrl(propertyId),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => fallback,
                )
              : fallback,
        ),
      ),
    );
  }
}
