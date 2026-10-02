import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../shared/theme/app_theme.dart';
import '../models/property_image.dart';
import '../services/property_api_service.dart';
import 'property_photo.dart';

class PropertyDetailsGallery extends StatefulWidget {
  const PropertyDetailsGallery({
    super.key,
    required this.propertyId,
    required this.service,
    required this.saved,
    required this.favoriteBusy,
    required this.favoriteTooltip,
    required this.onBack,
    this.onFavorite,
  });

  final String propertyId;
  final PropertyApiService service;
  final bool saved;
  final bool favoriteBusy;
  final String favoriteTooltip;
  final VoidCallback onBack;
  final VoidCallback? onFavorite;

  @override
  State<PropertyDetailsGallery> createState() => _PropertyDetailsGalleryState();
}

class _PropertyDetailsGalleryState extends State<PropertyDetailsGallery> {
  late Future<List<PropertyImage>> _images;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _loadImages();
  }

  @override
  void didUpdateWidget(PropertyDetailsGallery oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.propertyId != widget.propertyId ||
        oldWidget.service != widget.service) {
      _index = 0;
      _loadImages();
    }
  }

  void _loadImages() {
    _images = widget.service
        .getImages(widget.propertyId)
        .then<List<PropertyImage>>(
          (images) => images,
          onError: (_) => <PropertyImage>[],
        );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SizedBox(
      key: const Key('details-gallery'),
      height: (constraints.maxWidth * 0.62).clamp(210.0, 240.0),
      width: double.infinity,
      child: FutureBuilder<List<PropertyImage>>(
        future: _images,
        builder: (context, snapshot) {
          final images = snapshot.data ?? const <PropertyImage>[];
          return Stack(
            fit: StackFit.expand,
            children: [
              if (images.isEmpty)
                const PropertyPhotoFallback()
              else
                PageView.builder(
                  key: const Key('details-gallery-pages'),
                  itemCount: images.length,
                  onPageChanged: (index) => setState(() => _index = index),
                  itemBuilder: (_, index) => PropertyPhoto(
                    propertyId: widget.propertyId,
                    propertyApiService: widget.service,
                    image: images[index],
                  ),
                ),
              Positioned(
                left: 12,
                top: 12,
                child: _control(
                  key: const Key('details-back'),
                  tooltip: 'Back',
                  onPressed: widget.onBack,
                  child: const Icon(Icons.arrow_back_rounded, size: 20),
                ),
              ),
              Positioned(
                right: 12,
                top: 12,
                child: _control(
                  key: const Key('details-favorite'),
                  tooltip: widget.favoriteTooltip,
                  onPressed: widget.onFavorite,
                  child: widget.favoriteBusy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          widget.saved
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          size: 21,
                        ),
                ),
              ),
              if (images.isNotEmpty)
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12,
                  child: Center(child: _pagination(images.length)),
                ),
            ],
          );
        },
      ),
    ),
  );

  Widget _control({
    required Key key,
    required String tooltip,
    required Widget child,
    VoidCallback? onPressed,
  }) => Material(
    color: AppPalette.white.withValues(alpha: 0.95),
    shape: const CircleBorder(),
    elevation: 0,
    clipBehavior: Clip.antiAlias,
    child: IconButton(
      key: key,
      tooltip: tooltip,
      onPressed: onPressed,
      color: AppPalette.darkOlive,
      style: IconButton.styleFrom(
        minimumSize: const Size(44, 44),
        padding: const EdgeInsets.all(10),
        side: BorderSide.none,
        shape: const CircleBorder(),
      ),
      icon: child,
    ),
  );

  Widget _pagination(int count) {
    final visibleCount = math.min(count, 7);
    final first = (_index - 3).clamp(0, count - visibleCount);
    return Semantics(
      label: 'Photo ${_index + 1} of $count',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var offset = 0; offset < visibleCount; offset++)
                AnimatedContainer(
                  key: ValueKey('details-photo-dot-${first + offset}'),
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  width: first + offset == _index ? 16 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: AppPalette.white.withValues(
                      alpha: first + offset == _index ? 1 : 0.5,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
