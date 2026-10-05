import 'package:flutter/material.dart';

import '../../../shared/theme/app_theme.dart';
import '../models/property_matching.dart';
import '../services/property_api_service.dart';
import '../../viewings/services/viewing_api_service.dart';
import '../../rental_applications/services/rental_application_api_service.dart';
import 'property_details_screen.dart';
import '../widgets/property_photo.dart';

class PropertyMatchingScreen extends StatefulWidget {
  const PropertyMatchingScreen({
    super.key,
    required this.propertyApiService,
    this.viewingApiService,
    this.rentalApplicationApiService,
    this.initialResult,
  });

  final PropertyApiService propertyApiService;
  final ViewingApiService? viewingApiService;
  final RentalApplicationApiService? rentalApplicationApiService;
  final PropertyMatchingResponse? initialResult;

  @override
  State<PropertyMatchingScreen> createState() => _PropertyMatchingScreenState();
}

class _PropertyMatchingScreenState extends State<PropertyMatchingScreen> {
  final _cityController = TextEditingController();
  final _maximumRentController = TextEditingController();
  final _bedroomsController = TextEditingController();
  final _bathroomsController = TextEditingController();
  final _amenitiesController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;
  PropertyMatchingResponse? _result;

  @override
  void initState() {
    super.initState();
    _result = widget.initialResult;
  }

  @override
  void dispose() {
    _cityController.dispose();
    _maximumRentController.dispose();
    _bedroomsController.dispose();
    _bathroomsController.dispose();
    _amenitiesController.dispose();
    super.dispose();
  }

  Future<void> _findMatches() async {
    FocusScope.of(context).unfocus();

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _result = null;
    });

    final city = _cityController.text.trim();
    final maximumRent = double.tryParse(_maximumRentController.text.trim());
    final bedrooms = int.tryParse(_bedroomsController.text.trim());
    final bathrooms = int.tryParse(_bathroomsController.text.trim());

    final amenities = _amenitiesController.text
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);

    final request = PropertyMatchingRequest(
      preferredCity: city.isEmpty ? null : city,
      maximumMonthlyRent: maximumRent,
      minimumBedrooms: bedrooms,
      minimumBathrooms: bathrooms,
      preferredAmenities: amenities,
    );

    try {
      final result = await widget.propertyApiService.matchProperties(request);

      if (!mounted) return;

      setState(() {
        _result = result;
        _isLoading = false;
      });
    } on PropertyApiException catch (error) {
      if (!mounted) return;

      setState(() {
        _errorMessage = error.message;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _errorMessage = 'Unable to generate property recommendations.';
        _isLoading = false;
      });
    }
  }

  void _clear() {
    _cityController.clear();
    _maximumRentController.clear();
    _bedroomsController.clear();
    _bathroomsController.clear();
    _amenitiesController.clear();

    setState(() {
      _result = null;
      _errorMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'AI PROPERTY MATCHING',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: AppPalette.olive,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Find your best match',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: AppPalette.darkOlive,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tell RentFlow what you are looking for and '
              'the Property Matching Agent will rank suitable homes.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            _buildForm(),
            const SizedBox(height: 24),
            if (_isLoading) _buildLoading(),
            if (_errorMessage != null) _buildError(),
            if (_result != null) _buildResults(_result!),
          ],
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Your preferences',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _cityController,
              decoration: const InputDecoration(
                labelText: 'Preferred city',
                hintText: 'e.g. Colombo',
                prefixIcon: Icon(Icons.location_on_outlined),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _maximumRentController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Maximum monthly rent',
                hintText: 'e.g. 150000',
                prefixIcon: Icon(Icons.payments_outlined),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _bedroomsController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Minimum bedrooms',
                hintText: 'e.g. 2',
                prefixIcon: Icon(Icons.bed_outlined),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _bathroomsController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Minimum bathrooms',
                hintText: 'e.g. 2',
                prefixIcon: Icon(Icons.bathtub_outlined),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _amenitiesController,
              decoration: const InputDecoration(
                labelText: 'Preferred amenities',
                hintText: 'balcony, parking',
                prefixIcon: Icon(Icons.checklist_rounded),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _isLoading ? null : _findMatches,
              icon: const Icon(Icons.auto_awesome),
              label: Text(
                _isLoading ? 'Finding matches...' : 'Find AI Matches',
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _isLoading ? null : _clear,
              child: const Text('Clear preferences'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: Column(
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'The Property Matching Agent is '
              'evaluating available homes...',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline, color: AppPalette.olive),
            const SizedBox(width: 12),
            Expanded(child: Text(_errorMessage!)),
          ],
        ),
      ),
    );
  }

  Widget _buildResults(PropertyMatchingResponse result) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (result.summary.trim().isNotEmpty) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.auto_awesome, color: AppPalette.olive),
                      const SizedBox(width: 8),
                      Text(
                        'AI summary',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(result.summary),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
        Text(
          'Recommended properties',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          '${result.matches.length} matches found',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 14),
        if (result.matches.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'No properties matched these preferences. '
                'Try widening your search.',
              ),
            ),
          )
        else
          ...result.matches.map(_buildMatchCard),
      ],
    );
  }

  Widget _buildMatchCard(PropertyMatch match) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          try {
            final property = await widget.propertyApiService.getPropertyById(
              match.propertyId,
            );
            if (!mounted) return;
            Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => PropertyDetailsScreen(
                  property: property,
                  propertyApiService: widget.propertyApiService,
                  viewingApiService: widget.viewingApiService,
                  rentalApplicationApiService:
                      widget.rentalApplicationApiService,
                  matchScore: match.matchScore,
                  matchReasons: match.matchReasons,
                ),
              ),
            );
          } on PropertyApiException catch (error) {
            if (mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(error.message)));
            }
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.medium),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: PropertyPhoto(
                    propertyId: match.propertyId,
                    propertyApiService: widget.propertyApiService,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      match.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (match.matchScore != null) ...[
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppPalette.olive.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${match.matchScore}%',
                        style: const TextStyle(
                          color: AppPalette.darkOlive,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.location_on_outlined, size: 18),
                  const SizedBox(width: 5),
                  Expanded(child: Text(match.city)),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'LKR ${match.monthlyRent.toStringAsFixed(0)} / month',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                '${match.bedrooms} bed  •  '
                '${match.bathrooms} bath',
              ),
              if (match.amenities.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: match.amenities
                      .map((amenity) => Chip(label: Text(amenity)))
                      .toList(growable: false),
                ),
              ],
              if (match.matchReasons.isNotEmpty) ...[
                const Divider(height: 28),
                Text(
                  'Why this matches',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                ...match.matchReasons.map(
                  (reason) => Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 3),
                          child: Icon(
                            Icons.check_circle_outline,
                            size: 17,
                            color: AppPalette.olive,
                          ),
                        ),
                        const SizedBox(width: 7),
                        Expanded(child: Text(reason)),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
