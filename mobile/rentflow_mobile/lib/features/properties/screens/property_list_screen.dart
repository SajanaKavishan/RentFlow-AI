import 'package:flutter/material.dart';

import '../../../shared/theme/app_theme.dart';
import '../../viewings/services/viewing_api_service.dart';
import '../../rental_applications/services/rental_application_api_service.dart';
import '../models/property.dart';
import '../services/property_api_service.dart';
import '../widgets/property_card.dart';
import 'property_matching_screen.dart';
import 'property_details_screen.dart';

class PropertyListScreen extends StatefulWidget {
  const PropertyListScreen({
    super.key,
    required this.propertyApiService,
    this.viewingApiService,
    this.rentalApplicationApiService,
  });

  final PropertyApiService propertyApiService;
  final ViewingApiService? viewingApiService;
  final RentalApplicationApiService? rentalApplicationApiService;

  @override
  State<PropertyListScreen> createState() => _PropertyListScreenState();
}

class _PropertyListScreenState extends State<PropertyListScreen> {
  final _searchController = TextEditingController();

  List<Property> _properties = const [];
  bool _isLoading = true;
  String? _errorMessage;
  bool _availableOnly = false;
  int? _bedrooms;

  @override
  void initState() {
    super.initState();
    _loadProperties();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadProperties() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final properties = await widget.propertyApiService.getProperties(
        city: _searchController.text.trim(),
        bedrooms: _bedrooms,
        isAvailable: _availableOnly ? true : null,
      );

      if (!mounted) return;

      setState(() {
        _properties = properties;
        _isLoading = false;
      });
    } on PropertyApiException catch (error) {
      if (!mounted) return;

      setState(() {
        _errorMessage = error.message;
        _isLoading = false;
      });
    }
  }

  void _openPropertyMatching() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('AI Property Match')),
          body: PropertyMatchingScreen(
            propertyApiService: widget.propertyApiService,
            viewingApiService: widget.viewingApiService,
            rentalApplicationApiService: widget.rentalApplicationApiService,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _loadProperties,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  Text(
                    'EXPLORE HOMES',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: AppPalette.olive,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Find your place',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: AppPalette.darkOlive,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Explore available homes that fit the way you want to live.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 18),

                  // AI Property Matching
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _openPropertyMatching,
                      icon: const Icon(Icons.auto_awesome),
                      label: const Text('AI Property Match'),
                    ),
                  ),

                  const SizedBox(height: 18),
                  _buildSearch(),
                  const SizedBox(height: 14),
                  _buildFilters(),
                  const SizedBox(height: 26),
                  Text(
                    'Properties',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${_properties.length} homes to explore',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                ]),
              ),
            ),
            _buildPropertyContent(),
          ],
        ),
      ),
    );
  }

  Widget _buildSearch() {
    return TextField(
      controller: _searchController,
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => _loadProperties(),
      decoration: InputDecoration(
        hintText: 'Search by city',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: IconButton(
          tooltip: 'Search',
          onPressed: _loadProperties,
          icon: const Icon(Icons.arrow_forward_rounded),
        ),
      ),
    );
  }

  Widget _buildFilters() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          FilterChip(
            label: const Text('Available'),
            selected: _availableOnly,
            onSelected: (selected) {
              setState(() => _availableOnly = selected);
              _loadProperties();
            },
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: const Text('1+ Beds'),
            selected: _bedrooms == 1,
            onSelected: (selected) {
              setState(() => _bedrooms = selected ? 1 : null);
              _loadProperties();
            },
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: const Text('2+ Beds'),
            selected: _bedrooms == 2,
            onSelected: (selected) {
              setState(() => _bedrooms = selected ? 2 : null);
              _loadProperties();
            },
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: const Text('3+ Beds'),
            selected: _bedrooms == 3,
            onSelected: (selected) {
              setState(() => _bedrooms = selected ? 3 : null);
              _loadProperties();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPropertyContent() {
    if (_isLoading) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.cloud_off_outlined,
                  size: 42,
                  color: AppPalette.olive,
                ),
                const SizedBox(height: 12),
                Text(_errorMessage!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _loadProperties,
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_properties.isEmpty) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'No properties match your current search.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      sliver: SliverList.builder(
        itemCount: _properties.length,
        itemBuilder: (context, index) {
          final property = _properties[index];

          return PropertyCard(
            property: property,
            propertyApiService: widget.propertyApiService,
            onTap: () {
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => PropertyDetailsScreen(
                    property: property,
                    propertyApiService: widget.propertyApiService,
                    viewingApiService: widget.viewingApiService,
                    rentalApplicationApiService:
                        widget.rentalApplicationApiService,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
