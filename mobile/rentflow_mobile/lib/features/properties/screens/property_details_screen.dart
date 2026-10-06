import 'package:flutter/material.dart';

import 'package:url_launcher/url_launcher.dart';

import '../../../shared/theme/app_theme.dart';
import '../widgets/amenity_icon.dart';
import '../widgets/public_landlord_identity.dart';
import 'public_landlord_profile_screen.dart';
import '../../../shared/widgets/shared_widgets.dart';
import '../../rental_applications/widgets/application_eligibility_action.dart';
import '../../rental_applications/services/rental_application_api_service.dart';
import '../../viewings/screens/book_viewing_screen.dart';
import '../../viewings/models/viewing.dart';
import '../../viewings/services/viewing_api_service.dart';
import '../controllers/property_discovery_controller.dart';
import '../models/property.dart';
import '../models/property_availability.dart';
import '../models/property_image.dart';
import '../services/property_api_service.dart';
import '../widgets/property_details_gallery.dart';
import '../widgets/landlord_contact_card.dart';
import '../../viewing_reviews/services/viewing_review_api_service.dart';
import '../../viewing_reviews/widgets/public_viewing_reviews.dart';
import '../../viewing_reviews/widgets/viewing_rating_summary.dart';

class PropertyDetailsScreen extends StatefulWidget {
  const PropertyDetailsScreen({
    super.key,
    required this.property,
    required this.propertyApiService,
    this.viewingApiService,
    this.rentalApplicationApiService,
    this.matchScore,
    this.matchReasons = const [],
    this.todayProvider,
  });

  final Property property;
  final PropertyApiService propertyApiService;
  final ViewingApiService? viewingApiService;
  final RentalApplicationApiService? rentalApplicationApiService;
  final int? matchScore;
  final List<String> matchReasons;
  final DateTime Function()? todayProvider;

  @override
  State<PropertyDetailsScreen> createState() => _PropertyDetailsScreenState();
}

class _PropertyDetailsScreenState extends State<PropertyDetailsScreen> {
  late Property _property;
  late Future<PublicLandlordSummary?> _landlord;
  late Future<Map<String, dynamic>> _propertyReviews, _landlordReviews;
  final _reviewSection = GlobalKey();
  late final PropertyDiscoveryController _favorites;
  bool _isVerifying = true;
  bool _verificationFailed = false;
  bool _viewingStatusLoading = true;
  bool _hasExistingViewing = false;
  int _contactRefreshVersion = 0;
  bool _descriptionExpanded = false;

  int? get _score {
    final score = widget.matchScore;
    return score != null && score >= 0 && score <= 100 ? score : null;
  }

  String get _address => [
    _property.address,
    _property.city,
  ].where((part) => part.trim().isNotEmpty).join(', ');

  @override
  void initState() {
    super.initState();
    _property = widget.property;
    _landlord = widget.propertyApiService
        .getLandlordSummary(_property.id)
        .then<PublicLandlordSummary?>((value) => value, onError: (_) => null);
    _favorites = PropertyDiscoveryController(widget.propertyApiService)
      ..addListener(_favoritesChanged);
    _favorites.loadFavorites();
    _refreshProperty();
    _refreshViewingStatus();
  }

  @override
  void dispose() {
    _favorites.removeListener(_favoritesChanged);
    _favorites.dispose();
    super.dispose();
  }

  void _favoritesChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _refreshProperty() async {
    _refreshReviews();
    setState(() => _contactRefreshVersion++);
    if (!_isVerifying || _verificationFailed) {
      setState(() {
        _isVerifying = true;
        _verificationFailed = false;
      });
    }

    try {
      final property = await widget.propertyApiService.getPropertyById(
        _property.id,
      );
      if (mounted) {
        setState(() {
          _property = property;
          _isVerifying = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isVerifying = false;
          _verificationFailed = true;
        });
      }
    }
  }

  Future<void> _refreshViewingStatus() async {
    final api = widget.viewingApiService;
    if (api == null) {
      if (mounted) {
        setState(() => _viewingStatusLoading = false);
      }
      return;
    }

    setState(() => _viewingStatusLoading = true);
    try {
      final viewings = await api.getMyViewings();
      if (!mounted) return;
      final hasExistingViewing = viewings.any(
        (viewing) =>
            viewing.propertyId == _property.id &&
            viewing.status != ViewingStatus.rejected &&
            viewing.status != ViewingStatus.cancelled,
      );
      setState(() {
        _hasExistingViewing = hasExistingViewing;
        _viewingStatusLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _viewingStatusLoading = false);
    }
  }

  void _refreshReviews() {
    final api = ViewingReviewApiService(widget.propertyApiService.apiClient);
    _propertyReviews = api.publicSummary(_property.id);
    _landlordReviews = api.publicSummary(_property.id, landlord: true);
    // Optional sections may not mount (for example, when identity is unavailable).
    // Attach error listeners immediately; mounted builders still receive failures.
    for (final request in [_propertyReviews, _landlordReviews]) {
      request.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    }
  }

  void _showReviews() {
    final target = _reviewSection.currentContext;
    if (target != null) {
      Scrollable.ensureVisible(
        target,
        alignment: 0,
        duration: const Duration(milliseconds: 300),
      );
    }
  }

  Future<void> _toggleFavorite() async {
    final success = await _favorites.toggleFavorite(_property);
    if (mounted && !success) {
      AppSnackbars.show(
        context,
        message: 'Could not update this saved property. Please try again.',
      );
    }
  }

  Future<void> _openViewing() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => BookViewingScreen(
          propertyId: _property.id,
          propertyTitle: _property.title,
          property: _property,
          propertyApiService: widget.propertyApiService,
          viewingApiService: widget.viewingApiService,
        ),
      ),
    );
    if (mounted) {
      await Future.wait([_refreshProperty(), _refreshViewingStatus()]);
    }
  }

  Future<void> _openMaps() async {
    final latitude = _property.latitude;
    final longitude = _property.longitude;
    final hasCoordinates =
        latitude != null &&
        longitude != null &&
        latitude.isFinite &&
        longitude.isFinite &&
        latitude >= -90 &&
        latitude <= 90 &&
        longitude >= -180 &&
        longitude <= 180;
    final query = hasCoordinates ? '$latitude,$longitude' : _address;
    if (query.isEmpty) return;
    final placeId = _property.googlePlaceId?.trim();
    final uri = Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': query,
      if (placeId != null && placeId.isNotEmpty) 'query_place_id': placeId,
    });
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {
      // Keep the details usable when no external Maps app can be opened.
    }
    if (mounted) AppSnackbars.show(context, message: 'Unable to open Maps.');
  }

  @override
  Widget build(BuildContext context) {
    final saved = _favorites.favorites.contains(_property.id);
    final favoritePending = _favorites.favoritePending.contains(_property.id);
    final canSave =
        saved ||
        (_property.isAvailable && !_isVerifying && !_verificationFailed);
    final favoriteError = _favorites.favoritesError != null;
    return Scaffold(
      backgroundColor: AppPalette.white,
      body: SafeArea(
        bottom: false,
        child: ListView(
          key: const Key('details-scroll'),
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            PropertyDetailsGallery(
              propertyId: _property.id,
              service: widget.propertyApiService,
              saved: saved,
              favoriteBusy: favoritePending || _favorites.favoritesLoading,
              favoriteTooltip: favoriteError
                  ? 'Retry saved properties'
                  : !_favorites.favoritesReady
                  ? 'Loading saved properties'
                  : !canSave
                  ? 'Only available properties can be saved'
                  : saved
                  ? 'Unsave property'
                  : 'Save property',
              onBack: () => Navigator.of(context).maybePop(),
              onFavorite: favoriteError
                  ? _favorites.loadFavorites
                  : _favorites.favoritesReady && !favoritePending && canSave
                  ? _toggleFavorite
                  : null,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _property.title,
                    key: const Key('details-title'),
                    style: AppTypography.pageTitle,
                  ),
                  const SizedBox(height: 7),
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
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          _address,
                          key: const Key('details-address'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: AppTypography.bodySmallSize,
                            height: 1.4,
                            color: AppPalette.secondaryText,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _rentSummary(),
                  ViewingRatingSummary(
                    key: const Key('details-property-rating'),
                    summary: _propertyReviews,
                    onTap: _showReviews,
                  ),
                  const SizedBox(height: 12),
                  _facts(),
                  const SizedBox(height: 14),
                  _availability(),
                  _amenities(),
                  _about(),
                  PublicViewingReviews(
                    key: _reviewSection,
                    summary: _propertyReviews,
                    propertyId: _property.id,
                    api: ViewingReviewApiService(
                      widget.propertyApiService.apiClient,
                    ),
                  ),
                  _matchReasons(),
                  const SizedBox(height: 22),
                  _heading('Location'),
                  const SizedBox(height: 10),
                  _location(),
                  const SizedBox(height: 22),
                  _landlordSummary(),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _bottomActions(),
    );
  }

  Widget _rentSummary() => _surface(
    key: const Key('details-rent-summary'),
    color: AppPalette.softCream,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final rent = Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: 'Rs. ${_formatMoney(_property.monthlyRent)}',
                style: const TextStyle(
                  fontSize: AppTypography.sectionTitleSize,
                  fontWeight: FontWeight.w700,
                  color: AppPalette.olive,
                ),
              ),
              const TextSpan(
                text: ' /mo',
                style: TextStyle(
                  fontSize: AppTypography.labelSize,
                  color: AppPalette.secondaryText,
                ),
              ),
            ],
          ),
          key: const Key('details-rent'),
        );
        if (_score == null) return rent;
        if (constraints.maxWidth < 280 ||
            MediaQuery.textScalerOf(context).scale(23) > 28) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [rent, const SizedBox(height: 12), _matchSummary()],
          );
        }
        return Row(
          children: [
            Expanded(child: rent),
            const SizedBox(width: 14),
            SizedBox(width: 100, child: _matchSummary()),
          ],
        );
      },
    ),
  );

  Widget _matchSummary() => Semantics(
    label: 'AI Match',
    value: '$_score percent',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const Text(
          'AI Match',
          style: TextStyle(
            fontSize: AppTypography.captionSize,
            color: AppPalette.secondaryText,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: LinearProgressIndicator(
                key: const Key('details-match-progress'),
                value: _score! / 100,
                minHeight: 5,
                borderRadius: BorderRadius.circular(4),
                color: AppPalette.olive,
                backgroundColor: AppPalette.outline,
              ),
            ),
            const SizedBox(width: 7),
            Text(
              '$_score%',
              style: const TextStyle(
                fontSize: AppTypography.cardTitleSize,
                fontWeight: FontWeight.w700,
                color: AppPalette.olive,
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _facts() {
    final area = _property.area;
    final unit = _property.areaUnit?.trim();
    final areaLabel = area != null && unit != null && unit.isNotEmpty
        ? '${_formatNumber(area)} ${_areaUnit(unit)}'
        : 'Area not listed';
    final areaType = switch (_property.areaType) {
      'LandArea' => 'Land area',
      'FloorArea' => 'Floor area',
      _ => null,
    };
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _fact(
              'beds',
              Icons.bed_outlined,
              '${_property.bedrooms} Beds',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _fact(
              'baths',
              Icons.bathtub_outlined,
              '${_property.bathrooms} Baths',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _fact(
              'area',
              Icons.straighten_rounded,
              areaLabel,
              caption: area != null ? areaType : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _fact(String key, IconData icon, String value, {String? caption}) =>
      Container(
        key: ValueKey('details-fact-$key'),
        constraints: const BoxConstraints(minHeight: 72),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        decoration: _decoration(AppPalette.softCream),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 21, color: AppPalette.olive),
            const SizedBox(height: 6),
            Text(
              value,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: AppTypography.bodySmallSize,
                height: 1.25,
                fontWeight: FontWeight.w600,
                color: AppPalette.primaryText,
              ),
            ),
            if (caption != null) ...[
              const SizedBox(height: 3),
              Text(
                caption,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: AppTypography.captionSize,
                  color: AppPalette.secondaryText,
                ),
              ),
            ],
          ],
        ),
      );

  Widget _availability() {
    final availability = PropertyAvailability.fromProperty(
      _property,
      today: widget.todayProvider?.call(),
    );
    final available = availability != PropertyAvailability.unavailable;
    final statusColor = switch (availability) {
      PropertyAvailability.availableNow => AppPalette.success,
      PropertyAvailability.availableSoon => AppPalette.olive,
      PropertyAvailability.unavailable => AppPalette.secondaryText,
    };
    final date = _property.availableFrom;
    final value = !available
        ? 'Currently unavailable'
        : date == null
        ? 'Available now'
        : MaterialLocalizations.of(context).formatShortDate(date);
    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: statusColor,
            borderRadius: BorderRadius.circular(9),
          ),
          child: const Icon(
            Icons.calendar_today_outlined,
            size: 18,
            color: AppPalette.white,
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                available && date != null ? 'Available from' : 'Availability',
                style: const TextStyle(
                  fontSize: AppTypography.captionSize,
                  color: AppPalette.secondaryText,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                style: const TextStyle(
                  fontSize: AppTypography.bodySize,
                  height: 1.25,
                  fontWeight: FontWeight.w600,
                  color: AppPalette.primaryText,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    final status = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(shape: BoxShape.circle, color: statusColor),
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            availability.label,
            style: TextStyle(
              fontSize: AppTypography.captionSize,
              fontWeight: FontWeight.w600,
              color: statusColor,
            ),
          ),
        ),
      ],
    );
    return _surface(
      key: const Key('details-availability'),
      color: availability == PropertyAvailability.availableNow
          ? AppPalette.sage.withValues(alpha: 0.4)
          : AppPalette.softCream,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 280 ||
              MediaQuery.textScalerOf(context).scale(14) > 18) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                content,
                const SizedBox(height: 8),
                Align(alignment: Alignment.centerRight, child: status),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: content),
              const SizedBox(width: 10),
              status,
            ],
          );
        },
      ),
    );
  }

  Widget _amenities() {
    final canonicalKeys = {
      for (final detail
          in _property.amenityDetails ?? <PropertyAmenityDetail>[])
        detail.name.trim(): detail.canonicalKey,
    };
    final items = <String>{
      ...?_property.amenityDetails
          ?.map((detail) => detail.name.trim())
          .where((name) => name.isNotEmpty),
      ..._property.amenities
          .map((name) => name.trim())
          .where((name) => name.isNotEmpty),
    };
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heading('Amenities'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final name in items)
                Container(
                  key: ValueKey('details-amenity-$name'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppPalette.softCream,
                    border: Border.all(
                      color: AppPalette.outline.withValues(alpha: 0.6),
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AmenityIcon(
                        name: name,
                        canonicalKey: canonicalKeys[name],
                        size: 17,
                        color: AppPalette.olive,
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          name,
                          style: const TextStyle(
                            fontSize: AppTypography.labelSize,
                            fontWeight: FontWeight.w500,
                            color: AppPalette.primaryText,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  bool get _hasTerms =>
      _property.advertisedSecurityDeposit != null ||
      _property.preferredLeaseTermMonths != null ||
      _property.petPolicy != null ||
      _property.petPolicyNotes != null ||
      (_property.includedUtilities?.isNotEmpty ?? false);

  Widget _about() {
    final description = _property.description;
    if (description.trim().isEmpty && !_hasTerms) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _heading('About this property'),
          const SizedBox(height: 10),
          if (description.trim().isNotEmpty)
            LayoutBuilder(
              builder: (context, constraints) {
                const style = TextStyle(
                  fontSize: AppTypography.bodySize,
                  height: 1.45,
                  color: AppPalette.secondaryText,
                );
                final painter = TextPainter(
                  text: TextSpan(text: description, style: style),
                  maxLines: 4,
                  textDirection: Directionality.of(context),
                  textScaler: MediaQuery.textScalerOf(context),
                )..layout(maxWidth: constraints.maxWidth);
                final needsExpansion = painter.didExceedMaxLines;
                painter.dispose();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      description,
                      key: const Key('details-description'),
                      style: style,
                      maxLines: _descriptionExpanded ? null : 4,
                      overflow: _descriptionExpanded
                          ? TextOverflow.visible
                          : TextOverflow.ellipsis,
                    ),
                    if (needsExpansion)
                      TextButton(
                        key: const Key('details-read-more'),
                        onPressed: () => setState(
                          () => _descriptionExpanded = !_descriptionExpanded,
                        ),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(44, 36),
                          alignment: Alignment.centerLeft,
                        ),
                        child: Text(
                          _descriptionExpanded ? 'Read less' : 'Read more',
                          style: const TextStyle(
                            fontSize: AppTypography.labelSize,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          if (_hasTerms) _listingTerms(),
        ],
      ),
    );
  }

  Widget _listingTerms() => ExpansionTile(
    key: const Key('details-listing-terms'),
    tilePadding: EdgeInsets.zero,
    childrenPadding: const EdgeInsets.only(bottom: 4),
    shape: const Border(),
    collapsedShape: const Border(),
    title: const Text(
      'Listing preferences',
      style: TextStyle(
        fontSize: AppTypography.bodySize,
        fontWeight: FontWeight.w600,
      ),
    ),
    children: [
      if (_property.advertisedSecurityDeposit != null)
        _term(
          'Advertised security deposit',
          'LKR ${_formatMoney(_property.advertisedSecurityDeposit!)}',
        ),
      if (_property.preferredLeaseTermMonths != null)
        _term(
          'Preferred lease term',
          '${_property.preferredLeaseTermMonths} months',
        ),
      if (_property.petPolicy != null)
        _term('Pet policy', _petPolicyLabel(_property.petPolicy!)),
      if (_property.petPolicyNotes != null)
        _term('Pet policy notes', _property.petPolicyNotes!),
      if (_property.includedUtilities?.isNotEmpty ?? false)
        _term('Included utilities', _property.includedUtilities!.join(', ')),
    ],
  );

  Widget _term(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: AppTypography.labelSize,
              fontWeight: FontWeight.w600,
              color: AppPalette.primaryText,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: AppTypography.bodySize,
              color: AppPalette.secondaryText,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _matchReasons() {
    final reasons = widget.matchReasons
        .where((reason) => reason.trim().isNotEmpty)
        .take(3)
        .toList();
    if (reasons.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heading('Why this matches'),
          const SizedBox(height: 10),
          for (final reason in reasons)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.check_circle_outline,
                      size: 16,
                      color: AppPalette.olive,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      reason,
                      style: const TextStyle(
                        fontSize: AppTypography.bodySmallSize,
                        height: 1.4,
                        color: AppPalette.secondaryText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _location() => Material(
    color: AppPalette.softCream,
    shape: RoundedRectangleBorder(
      side: const BorderSide(color: AppPalette.outline),
      borderRadius: BorderRadius.circular(14),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      key: const Key('details-open-maps'),
      onTap:
          _address.isNotEmpty ||
              (_property.latitude != null && _property.longitude != null)
          ? _openMaps
          : null,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(
                Icons.location_on_outlined,
                size: 27,
                color: AppPalette.olive,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _address,
                    style: const TextStyle(
                      fontSize: AppTypography.bodySmallSize,
                      height: 1.4,
                      color: AppPalette.primaryText,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Row(
                    children: [
                      Flexible(
                        child: Text(
                          'Open in Maps',
                          style: TextStyle(
                            fontSize: AppTypography.labelSize,
                            fontWeight: FontWeight.w600,
                            color: AppPalette.olive,
                          ),
                        ),
                      ),
                      SizedBox(width: 5),
                      Icon(
                        Icons.open_in_new_rounded,
                        size: 14,
                        color: AppPalette.olive,
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

  Widget _landlordSummary() => _surface(
    key: const Key('details-landlord'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading('Listed by'),
        const SizedBox(height: 12),
        FutureBuilder<PublicLandlordSummary?>(
          future: _landlord,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const LinearProgressIndicator(minHeight: 2);
            }
            final summary = snapshot.data;
            if (summary == null || summary.displayName.trim().isEmpty) {
              return const Text(
                'Landlord details unavailable',
                style: TextStyle(
                  fontSize: AppTypography.bodySmallSize,
                  color: AppPalette.secondaryText,
                ),
              );
            }
            return Semantics(
              button: true,
              label: 'View other properties by ${summary.displayName}',
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadii.small),
                  onTap: () async {
                    await Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => PublicLandlordProfileScreen(
                          propertyId: _property.id,
                          propertyApiService: widget.propertyApiService,
                        ),
                      ),
                    );
                    if (mounted) {
                      setState(() {
                        _contactRefreshVersion++;
                        _refreshReviews();
                      });
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: PublicLandlordIdentity(
                      propertyId: _property.id,
                      summary: summary,
                      service: widget.propertyApiService,
                      reviews: _landlordReviews,
                      ratingKey: const Key('details-landlord-rating'),
                      action: const Row(
                        children: [
                          Flexible(
                            child: Text(
                              'View other properties',
                              style: TextStyle(
                                color: AppPalette.olive,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          SizedBox(width: 5),
                          Icon(
                            Icons.arrow_forward,
                            size: 16,
                            color: AppPalette.olive,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        LandlordContactCard(
          propertyId: _property.id,
          service: widget.propertyApiService,
          refreshVersion: _contactRefreshVersion,
        ),
      ],
    ),
  );

  Widget _bottomActions() => Container(
    key: const Key('details-cta-bar'),
    decoration: BoxDecoration(
      color: AppPalette.white,
      border: const Border(top: BorderSide(color: AppPalette.outline)),
      boxShadow: [
        BoxShadow(
          color: AppPalette.darkOlive.withValues(alpha: 0.04),
          blurRadius: 12,
          offset: const Offset(0, -3),
        ),
      ],
    ),
    child: SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: _isVerifying
          ? const SizedBox(
              height: 52,
              child: Center(
                child: Text(
                  'Checking current availability...',
                  style: AppTypography.bodySmall,
                ),
              ),
            )
          : _verificationFailed
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Current availability could not be verified.',
                  textAlign: TextAlign.center,
                  style: AppTypography.bodySmall,
                ),
                TextButton(
                  onPressed: _refreshProperty,
                  child: const Text('Try again'),
                ),
              ],
            )
          : !_property.isAvailable
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'This property is currently unavailable for viewings or applications.',
                  textAlign: TextAlign.center,
                  style: AppTypography.bodySmall,
                ),
                ApplicationEligibilityAction(
                  allowNew: false,
                  showIneligibleReason: false,
                  key: ValueKey(
                    'application-eligibility-$_contactRefreshVersion',
                  ),
                  propertyId: _property.id,
                  propertyTitle: _property.title,
                  apiService:
                      widget.rentalApplicationApiService ??
                      RentalApplicationApiService(
                        widget.propertyApiService.apiClient,
                      ),
                ),
              ],
            )
          : IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: OutlinedButton(
                      key: const Key('details-book-viewing'),
                      onPressed: _viewingStatusLoading || _hasExistingViewing
                          ? null
                          : _openViewing,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(44, 52),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 12,
                        ),
                        side: const BorderSide(color: AppPalette.olive),
                        foregroundColor: AppPalette.olive,
                        disabledForegroundColor: AppPalette.secondaryText
                            .withValues(alpha: 0.55),
                        backgroundColor: _hasExistingViewing
                            ? AppPalette.softCream
                            : null,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        _hasExistingViewing
                            ? 'Viewing booked'
                            : _viewingStatusLoading
                            ? 'Checking viewing status...'
                            : 'Book Viewing',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: AppTypography.bodyLargeSize,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ApplicationEligibilityAction(
                      showIneligibleReason: false,
                      key: ValueKey(
                        'application-eligibility-$_contactRefreshVersion',
                      ),
                      propertyId: _property.id,
                      propertyTitle: _property.title,
                      apiService:
                          widget.rentalApplicationApiService ??
                          RentalApplicationApiService(
                            widget.propertyApiService.apiClient,
                          ),
                    ),
                  ),
                ],
              ),
            ),
    ),
  );

  Widget _heading(String title) => Text(
    title,
    style: const TextStyle(
      fontSize: AppTypography.sectionTitleSize,
      height: 1.25,
      fontWeight: FontWeight.w700,
      color: AppPalette.primaryText,
    ),
  );
  BoxDecoration _decoration(Color color) => BoxDecoration(
    color: color,
    border: Border.all(color: AppPalette.outline.withValues(alpha: 0.7)),
    borderRadius: BorderRadius.circular(14),
  );
  Widget _surface({
    Key? key,
    Color color = AppPalette.white,
    required Widget child,
  }) => Container(
    key: key,
    padding: const EdgeInsets.all(14),
    decoration: _decoration(color),
    child: child,
  );
}

String _formatMoney(double value) {
  final parts =
      (value == value.roundToDouble()
              ? value.toStringAsFixed(0)
              : value.toStringAsFixed(2))
          .split('.');
  parts[0] = parts[0].replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  return parts.join('.');
}

String _formatNumber(double value) =>
    value == value.roundToDouble() ? _formatMoney(value) : value.toString();
String _areaUnit(String unit) => switch (unit.toLowerCase()) {
  'sqft' => 'sq ft',
  'sqm' => 'sq m',
  'perch' => 'perches',
  _ => unit,
};
String _petPolicyLabel(String value) => switch (value) {
  'Allowed' => 'Pets allowed',
  'NotAllowed' => 'Pets not allowed',
  'Conditional' => 'Pets considered with conditions',
  _ => value,
};
