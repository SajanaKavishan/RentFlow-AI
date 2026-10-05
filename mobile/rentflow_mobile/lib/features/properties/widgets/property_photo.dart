import 'package:flutter/material.dart';

import '../../../shared/theme/app_theme.dart';
import '../models/property_image.dart';
import '../services/property_api_service.dart';

class PropertyPhoto extends StatelessWidget {
  const PropertyPhoto({
    super.key,
    required this.propertyId,
    required this.propertyApiService,
    this.image,
  });

  final String propertyId;
  final PropertyApiService? propertyApiService;
  final PropertyImage? image;

  @override
  Widget build(BuildContext context) {
    final service = propertyApiService;
    if (service == null) return const PropertyPhotoFallback();
    if (image != null) return _resolvedPhoto(service, image!);
    return FutureBuilder<List<PropertyImage>>(
      future: service.getImages(propertyId),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const PropertyPhotoFallback();
        }
        return _resolvedPhoto(service, snapshot.data!.first);
      },
    );
  }

  Widget _resolvedPhoto(PropertyApiService service, PropertyImage chosen) =>
      FutureBuilder<String?>(
        future: service.getImageUrl(propertyId, chosen.id),
        builder: (context, snapshot) {
          final url = snapshot.data;
          if (url == null) return const PropertyPhotoFallback();
          return Image.network(
            url,
            key: ValueKey('property-photo-${chosen.id}'),
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (_, _, _) => const PropertyPhotoFallback(),
          );
        },
      );
}

class PropertyPhotoFallback extends StatelessWidget {
  const PropertyPhotoFallback({super.key});

  @override
  Widget build(BuildContext context) => const ColoredBox(
    key: ValueKey('property-photo-fallback'),
    color: AppPalette.sage,
    child: Center(
      child: Icon(
        Icons.home_work_outlined,
        size: 54,
        color: AppPalette.darkOlive,
      ),
    ),
  );
}
