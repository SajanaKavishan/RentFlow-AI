import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/shared_widgets.dart';
import '../models/property.dart';
import '../controllers/property_discovery_controller.dart';
import '../models/property_image.dart';
import '../services/property_api_service.dart';
import '../widgets/property_card.dart';
import '../widgets/public_landlord_identity.dart';
import '../widgets/landlord_contact_card.dart';
import 'property_details_screen.dart';
import '../../viewing_reviews/services/viewing_review_api_service.dart';
import '../../viewing_reviews/widgets/viewing_rating_summary.dart';

class PublicLandlordProfileScreen extends StatefulWidget {
  const PublicLandlordProfileScreen({
    super.key,
    required this.propertyId,
    required this.propertyApiService,
  });
  final String propertyId;
  final PropertyApiService propertyApiService;

  @override
  State<PublicLandlordProfileScreen> createState() =>
      _PublicLandlordProfileScreenState();
}

class _PublicLandlordProfileScreenState
    extends State<PublicLandlordProfileScreen> {
  PublicLandlordSummary? _summary;
  List<Property>? _properties;
  bool _profileError = false;
  bool _listingsError = false;
  int _loadVersion = 0;
  late Future<Map<String, dynamic>> _landlordReviews;
  late final PropertyDiscoveryController _favorites;

  @override
  void initState() {
    super.initState();
    _favorites = PropertyDiscoveryController(widget.propertyApiService);
    _favorites.addListener(_favoriteChanged);
    _load();
  }

  Future<void> _load() async {
    final version = ++_loadVersion;
    _landlordReviews = ViewingReviewApiService(
      widget.propertyApiService.apiClient,
    ).publicSummary(widget.propertyId, landlord: true);
    _landlordReviews.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    setState(() {
      _summary = null;
      _properties = null;
      _profileError = false;
      _listingsError = false;
    });
    try {
      final summary = await widget.propertyApiService.getLandlordSummary(
        widget.propertyId,
      );
      if (summary.displayName.isEmpty || summary.memberSinceYear == null) {
        throw const FormatException('Invalid public landlord summary.');
      }
      if (!mounted || version != _loadVersion) return;
      setState(() => _summary = summary);
    } catch (_) {
      if (mounted && version == _loadVersion) {
        setState(() => _profileError = true);
      }
      return;
    }
    _loadFavorites();
    try {
      final properties = await widget.propertyApiService.getLandlordProperties(
        widget.propertyId,
      );
      if (properties.any((property) => !property.isAvailable)) {
        throw const FormatException('Invalid public landlord listings.');
      }
      if (mounted && version == _loadVersion) {
        // This route is anchored to the property the tenant just viewed.
        setState(
          () => _properties = properties
              .where(
                (property) =>
                    property.id.toLowerCase() !=
                    widget.propertyId.toLowerCase(),
              )
              .toList(),
        );
      }
    } catch (_) {
      if (mounted && version == _loadVersion) {
        setState(() => _listingsError = true);
      }
    }
  }

  void _favoriteChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _favorites.removeListener(_favoriteChanged);
    _favorites.dispose();
    super.dispose();
  }

  Future<void> _loadFavorites() => _favorites.loadFavorites();

  Future<void> _toggleFavorite(Property property) async {
    final succeeded = await _favorites.toggleFavorite(property);
    if (!succeeded && mounted) {
      AppSnackbars.show(
        context,
        message: 'Could not update this saved property. Please try again.',
        tone: SnackTone.error,
      );
    }
  }

  Future<void> _openProperty(Property property) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => PropertyDetailsScreen(
          property: property,
          propertyApiService: widget.propertyApiService,
        ),
      ),
    );
    if (mounted) await _load();
  }

  Widget _identityCard() => AppCard(
    key: const Key('landlord-listings-identity'),
    color: AppPalette.white,
    padding: const EdgeInsets.all(AppSpacing.md),
    child: PublicLandlordIdentity(
      propertyId: widget.propertyId,
      summary: _summary!,
      service: widget.propertyApiService,
      reviews: _landlordReviews,
      ratingKey: const Key('landlord-identity-rating'),
    ),
  );

  double _headerHeight(BuildContext context) {
    final title = TextPainter(
      text: const TextSpan(
        text: 'Other properties',
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          height: 1.2,
        ),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: math.max(1, MediaQuery.sizeOf(context).width - 88));
    final height = title.height;
    title.dispose();
    return math.max(
      kToolbarHeight,
      height + MediaQuery.textScalerOf(context).scale(11) * 1.3 + 20,
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppPalette.background,
    appBar: AppBar(
      toolbarHeight: _headerHeight(context),
      leading: BackButton(onPressed: () => Navigator.of(context).maybePop()),
      title: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'LANDLORD',
            style: AppTypography.eyebrow.copyWith(color: AppPalette.olive),
          ),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'Other properties',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
        ],
      ),
    ),
    body: SafeArea(
      top: false,
      child: _profileError
          ? SharedState(
              title: 'Landlord properties unavailable',
              message: 'This profile could not be found or loaded.',
              icon: Icons.person_off_outlined,
              actionLabel: 'Try again',
              onAction: _load,
            )
          : _summary == null
          ? const LoadingState(
              title: 'Loading landlord properties',
              message: 'Getting landlord details.',
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(AppSpacing.base),
                children: [
                  _identityCard(),
                  LandlordContactCard(
                    propertyId: widget.propertyId,
                    service: widget.propertyApiService,
                    refreshVersion: _loadVersion,
                  ),
                  const SizedBox(height: AppSpacing.base),
                  FutureBuilder<Map<String, dynamic>>(
                    future: _landlordReviews,
                    builder: (context, snapshot) {
                      final data = snapshot.data;
                      if (snapshot.connectionState != ConnectionState.done ||
                          snapshot.hasError ||
                          data == null ||
                          (data['reviewCount'] as int) == 0) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.base),
                        child: ViewingReviewSummaryContent(
                          data: data,
                          title: 'Landlord experience',
                        ),
                      );
                    },
                  ),

                  if (_properties != null && !_listingsError) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '${_properties!.length} available ${_properties!.length == 1 ? 'property' : 'properties'}',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppPalette.secondaryText,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.base),
                  if (_listingsError)
                    SharedState(
                      title: 'Properties unavailable',
                      message: 'Unable to load this landlord’s properties.',
                      icon: Icons.cloud_off_outlined,
                      actionLabel: 'Try again',
                      onAction: _load,
                      compact: true,
                    )
                  else if (_properties == null)
                    const Padding(
                      padding: EdgeInsets.all(AppSpacing.lg),
                      child: LoadingState(
                        title: 'Loading properties',
                        message: 'Getting available listings.',
                        compact: true,
                      ),
                    )
                  else if (_properties!.isEmpty)
                    const AppCard(
                      child: Text(
                        'No other properties are currently available.',
                      ),
                    )
                  else
                    for (final property in _properties!)
                      PropertyCard(
                        property: property,
                        propertyApiService: widget.propertyApiService,
                        onTap: () => _openProperty(property),
                        saved: _favorites.favoritesReady
                            ? _favorites.favorites.contains(property.id)
                            : null,
                        favoritePending: _favorites.favoritePending.contains(
                          property.id,
                        ),
                        onToggleFavorite: _favorites.favoritesReady
                            ? () => _toggleFavorite(property)
                            : null,
                      ),
                ],
              ),
            ),
    ),
  );
}
