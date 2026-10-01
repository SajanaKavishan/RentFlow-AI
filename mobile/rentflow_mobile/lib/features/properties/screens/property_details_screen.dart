import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/shared_widgets.dart';
import '../../rental_applications/screens/rental_application_form_screen.dart';
import '../../rental_applications/services/rental_application_api_service.dart';
import '../../viewings/screens/book_viewing_screen.dart';
import '../../viewings/services/viewing_api_service.dart';
import '../models/property.dart';
import '../models/property_image.dart';
import '../services/property_api_service.dart';
import '../widgets/property_photo.dart';

class PropertyDetailsScreen extends StatefulWidget {
  const PropertyDetailsScreen({
    super.key,
    required this.property,
    required this.propertyApiService,
    this.viewingApiService,
    this.rentalApplicationApiService,
    this.matchScore,
    this.matchReasons = const [],
  });

  final Property property;
  final PropertyApiService propertyApiService;
  final ViewingApiService? viewingApiService;
  final RentalApplicationApiService? rentalApplicationApiService;
  final int? matchScore;
  final List<String> matchReasons;

  @override
  State<PropertyDetailsScreen> createState() => _PropertyDetailsScreenState();
}

class _PropertyDetailsScreenState extends State<PropertyDetailsScreen> {
  late Property _property;
  late Future<List<PropertyImage>> _images;
  late Future<PublicLandlordSummary?> _landlord;
  int _imageIndex = 0;
  bool _isVerifying = true;
  bool _verificationFailed = false;

  @override
  void initState() {
    super.initState();
    _property = widget.property;
    _images = widget.propertyApiService
        .getImages(_property.id)
        .then<List<PropertyImage>>((value) => value, onError: (_) => []);
    _landlord = widget.propertyApiService
        .getLandlordSummary(_property.id)
        .then<PublicLandlordSummary?>((value) => value, onError: (_) => null);
    _refreshProperty();
  }

  Future<void> _refreshProperty() async {
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

  void _openViewing() => Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => BookViewingScreen(
        propertyId: _property.id,
        propertyTitle: _property.title,
        viewingApiService: widget.viewingApiService,
      ),
    ),
  );

  void _openApplication() => Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => RentalApplicationFormScreen(
        propertyId: _property.id,
        propertyTitle: _property.title,
        rentalApplicationApiService: widget.rentalApplicationApiService,
      ),
    ),
  );

  Future<void> _openMaps() async {
    final property = _property;
    final coordinates = property.latitude != null && property.longitude != null
        ? '${property.latitude},${property.longitude}'
        : null;
    final address = [
      property.address,
      property.city,
    ].where((part) => part.trim().isNotEmpty).join(', ');
    final query = coordinates ?? address;
    if (query.isEmpty) return;
    final uri = Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': query,
    });
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {
      // Show a consistent failure message if a maps app cannot be opened.
    }
    if (mounted) {
      AppSnackbars.show(context, message: 'Unable to open Maps.');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Property details')),
    body: SafeArea(
      top: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          _gallery(),
          const SizedBox(height: AppSpacing.lg),
          Text(
            _property.title,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            [
              _property.address,
              _property.city,
            ].where((part) => part.trim().isNotEmpty).join(', '),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'LKR ${_property.monthlyRent.toStringAsFixed(0)} / month',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(color: AppPalette.darkOlive),
              ),
              StatusChip(
                label: _property.isAvailable ? 'Available' : 'Unavailable',
                tone: _property.isAvailable
                    ? StatusTone.success
                    : StatusTone.neutral,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          const SectionHeader(title: 'Property facts'),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _fact(Icons.bed_outlined, '${_property.bedrooms} bedrooms'),
              _fact(Icons.bathtub_outlined, '${_property.bathrooms} bathrooms'),
              if (_property.area != null && _property.areaUnit != null)
                _fact(
                  Icons.square_foot_outlined,
                  '${_property.areaType == 'LandArea'
                      ? 'Land area'
                      : _property.areaType == 'FloorArea'
                      ? 'Floor area'
                      : 'Area'}: ${_formatNumber(_property.area!)} ${_property.areaUnit}',
                ),
              if (_property.availableFrom != null)
                _fact(
                  Icons.event_available_outlined,
                  'Available from ${MaterialLocalizations.of(context).formatMediumDate(_property.availableFrom!)}',
                ),
            ],
          ),
          if (_property.description.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            const SectionHeader(title: 'About'),
            const SizedBox(height: AppSpacing.md),
            Text(_property.description),
          ],
          _amenities(),
          _preferences(),
          if (widget.matchReasons.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            const SectionHeader(title: 'Why this matches'),
            const SizedBox(height: AppSpacing.md),
            ...widget.matchReasons.map(
              (reason) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('• $reason'),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          const SectionHeader(title: 'Location'),
          const SizedBox(height: AppSpacing.md),
          Text(
            [
              _property.address,
              _property.city,
            ].where((part) => part.trim().isNotEmpty).join(', '),
          ),
          if (_property.address.trim().isNotEmpty ||
              (_property.latitude != null && _property.longitude != null))
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _openMaps,
                icon: const Icon(Icons.map_outlined),
                label: const Text('Open in Maps'),
              ),
            ),
          const SizedBox(height: AppSpacing.lg),
          const SectionHeader(title: 'Listed by'),
          const SizedBox(height: AppSpacing.md),
          _landlordSummary(),
        ],
      ),
    ),
    bottomNavigationBar: SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: AppPalette.white,
          border: Border(top: BorderSide(color: AppPalette.outline)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: _isVerifying
            ? const Text(
                'Checking current availability…',
                textAlign: TextAlign.center,
              )
            : _verificationFailed
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Current availability could not be verified.',
                    textAlign: TextAlign.center,
                  ),
                  TextButton(
                    onPressed: _refreshProperty,
                    child: const Text('Try again'),
                  ),
                ],
              )
            : _property.isAvailable
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _openViewing,
                      child: const Text('Book a Viewing'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _openApplication,
                      child: const Text('Apply for Rental'),
                    ),
                  ),
                ],
              )
            : const Text(
                'This property is currently unavailable for viewings or applications.',
                textAlign: TextAlign.center,
              ),
      ),
    ),
  );

  Widget _gallery() => FutureBuilder<List<PropertyImage>>(
    future: _images,
    builder: (context, snapshot) {
      final images = snapshot.data ?? const <PropertyImage>[];
      return AspectRatio(
        aspectRatio: 4 / 3,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.card),
          child: Stack(
            children: [
              if (images.isEmpty)
                const Positioned.fill(child: PropertyPhotoFallback())
              else
                PageView.builder(
                  itemCount: images.length,
                  onPageChanged: (index) => setState(() => _imageIndex = index),
                  itemBuilder: (_, index) => PropertyPhoto(
                    propertyId: _property.id,
                    propertyApiService: widget.propertyApiService,
                    image: images[index],
                  ),
                ),
              if (images.isNotEmpty)
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: StatusChip(
                    label: '${_imageIndex + 1} / ${images.length}',
                  ),
                ),
              if (widget.matchScore != null)
                Positioned(
                  left: 12,
                  top: 12,
                  child: StatusChip(
                    label: '${widget.matchScore}% match',
                    tone: StatusTone.success,
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );

  Widget _fact(IconData icon, String label) => ConstrainedBox(
    constraints: BoxConstraints(
      maxWidth: MediaQuery.sizeOf(context).width - 40,
    ),
    child: Chip(
      avatar: Icon(icon, size: 18, color: AppPalette.olive),
      label: Text(label, softWrap: true),
    ),
  );

  Widget _amenities() {
    final details = _property.amenityDetails;
    final items = details != null && details.isNotEmpty
        ? details.where((item) => item.name.trim().isNotEmpty).toList()
        : _property.amenities
              .map((name) => PropertyAmenityDetail(name: name))
              .toList();
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.lg),
        const SectionHeader(title: 'Amenities'),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: items
              .map((item) => _fact(_amenityIcon(item.canonicalKey), item.name))
              .toList(),
        ),
      ],
    );
  }

  Widget _preferences() {
    final property = _property;
    final values = <Widget>[
      if (property.advertisedSecurityDeposit != null)
        _preference(
          'Advertised security deposit',
          'LKR ${property.advertisedSecurityDeposit!.toStringAsFixed(0)}',
        ),
      if (property.preferredLeaseTermMonths != null)
        _preference(
          'Preferred lease term',
          '${property.preferredLeaseTermMonths} months',
        ),
      if (property.petPolicy != null)
        _preference('Pet policy', _petPolicyLabel(property.petPolicy!)),
      if (property.petPolicyNotes != null)
        _preference('Pet policy notes', property.petPolicyNotes!),
      if (property.includedUtilities != null &&
          property.includedUtilities!.isNotEmpty)
        _preference(
          'Included utilities',
          property.includedUtilities!.join(', '),
        ),
    ];
    if (values.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.lg),
        const SectionHeader(title: 'Listing preferences'),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: values,
          ),
        ),
      ],
    );
  }

  Widget _preference(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        Text(value),
      ],
    ),
  );

  Widget _landlordSummary() => FutureBuilder<PublicLandlordSummary?>(
    future: _landlord,
    builder: (context, snapshot) {
      if (!snapshot.hasData || snapshot.data!.displayName.isEmpty) {
        return const AppCard(child: Text('Landlord details unavailable'));
      }
      final summary = snapshot.data!;
      final initials = summary.displayName
          .trim()
          .split(RegExp(r'\s+'))
          .take(2)
          .map((part) => part[0].toUpperCase())
          .join();
      return AppCard(
        child: Row(
          children: [
            ClipOval(
              child: SizedBox.square(
                dimension: 50,
                child: summary.hasProfileImage
                    ? Image.network(
                        widget.propertyApiService.landlordImageUrl(
                          _property.id,
                        ),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => _initials(initials),
                      )
                    : _initials(initials),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    summary.displayName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (summary.memberSinceYear != null)
                    Text('Member since ${summary.memberSinceYear}'),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );

  Widget _initials(String initials) => ColoredBox(
    color: AppPalette.sage,
    child: Center(child: Text(initials)),
  );
}

String _formatNumber(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toString();

String _petPolicyLabel(String value) => switch (value) {
  'Allowed' => 'Pets allowed',
  'NotAllowed' => 'Pets not allowed',
  'Conditional' => 'Pets considered with conditions',
  _ => value,
};

IconData _amenityIcon(String? key) => switch (key) {
  'wifi' => Icons.wifi,
  'parking' => Icons.local_parking_outlined,
  'air-conditioning' => Icons.ac_unit,
  'washer-dryer' => Icons.local_laundry_service_outlined,
  'gym' => Icons.fitness_center,
  'swimming-pool' => Icons.pool_outlined,
  'balcony' => Icons.balcony_outlined,
  'elevator' => Icons.elevator_outlined,
  'furnished' => Icons.chair_outlined,
  'garden' => Icons.yard_outlined,
  'security' => Icons.security_outlined,
  'rooftop' => Icons.roofing_outlined,
  _ => Icons.check_circle_outline,
};
