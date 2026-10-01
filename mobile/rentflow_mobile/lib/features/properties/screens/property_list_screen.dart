import 'package:flutter/material.dart';

import '../../../shared/theme/app_theme.dart';
import '../../viewings/services/viewing_api_service.dart';
import '../../rental_applications/services/rental_application_api_service.dart';
import '../controllers/property_discovery_controller.dart';
import '../models/discovery_filters.dart';
import '../models/property.dart';
import '../models/property_matching.dart';
import '../services/property_api_service.dart';
import '../widgets/discovery_filter_panel.dart';
import '../widgets/property_card.dart';
import 'match_preferences_screen.dart';
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

class _PropertyListScreenState extends State<PropertyListScreen>
    with WidgetsBindingObserver {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  late final PropertyDiscoveryController _data;
  DiscoveryFilters _filters = const DiscoveryFilters();
  bool _childOpen = false;
  bool _filtersOpen = false;
  AppLifecycleState? _lastLifecycle;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _data = PropertyDiscoveryController(widget.propertyApiService);
    _data.refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    _scrollController.dispose();
    _data.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final previous = _lastLifecycle;
    _lastLifecycle = state;
    if (state != AppLifecycleState.resumed ||
        _childOpen ||
        previous == AppLifecycleState.resumed) {
      return;
    }
    _data.refresh();
  }

  Future<void> _openPreferences() async {
    _childOpen = true;
    final change = await Navigator.of(context).push<PreferenceChange>(
      MaterialPageRoute(
        builder: (_) =>
            MatchPreferencesScreen(service: widget.propertyApiService),
      ),
    );
    _childOpen = false;
    if (!mounted) return;
    // Even Cancel may follow a GET that observed a newer web-side value.
    if (change != null) {
      _data.selectSort('Newest');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            change == PreferenceChange.saved
                ? 'Match preferences saved.'
                : 'Match preferences reset.',
          ),
        ),
      );
    }
    await _data.refreshPreferences(force: true);
    if (change == PreferenceChange.saved && _data.hasScores) {
      _data.selectSort('AI Match');
    }
  }

  void _openFilters() {
    FocusScope.of(context).unfocus();
    setState(() => _filtersOpen = !_filtersOpen);
  }

  void _applyFilters(DiscoveryFilters filters) {
    setState(() {
      _filters = filters;
      _filtersOpen = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _openProperty(Property property, PropertyMatch? match) async {
    _childOpen = true;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PropertyDetailsScreen(
          property: property,
          propertyApiService: widget.propertyApiService,
          viewingApiService: widget.viewingApiService,
          rentalApplicationApiService: widget.rentalApplicationApiService,
          matchScore: match?.matchScore,
          matchReasons: match?.matchReasons ?? const [],
        ),
      ),
    );
    _childOpen = false;
    if (mounted) await _data.refresh();
  }

  List<Property> get _visibleProperties {
    final result = _data.properties
        .where(
          (property) => _filters.includes(property, _searchController.text),
        )
        .toList();
    result.sort((a, b) {
      final order = switch (_data.sort) {
        'AI Match' => (_score(b) ?? -1).compareTo(_score(a) ?? -1),
        'Lowest Rent' => a.monthlyRent.compareTo(b.monthlyRent),
        'Highest Rent' => b.monthlyRent.compareTo(a.monthlyRent),
        _ => b.createdAt.compareTo(a.createdAt),
      };
      return order != 0 ? order : a.id.compareTo(b.id);
    });
    return result;
  }

  int? _score(Property property) {
    final score = _data.matches[property.id]?.matchScore;
    return score != null && score >= 0 && score <= 100 ? score : null;
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ListenableBuilder(
      listenable: _data,
      builder: (context, _) {
        final visible = _visibleProperties;
        return RefreshIndicator(
          onRefresh: _data.refresh,
          child: CustomScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                sliver: SliverList.list(
                  children: [
                    const Text(
                      'EXPLORE HOMES',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.3,
                        color: AppPalette.olive,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Find your place',
                      style: TextStyle(
                        fontSize: 24,
                        height: 1.2,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.6,
                        color: AppPalette.darkOlive,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            key: const Key('property-search'),
                            controller: _searchController,
                            style: const TextStyle(fontSize: 14),
                            textInputAction: TextInputAction.search,
                            onChanged: (_) => setState(() {}),
                            onSubmitted: (_) =>
                                FocusScope.of(context).unfocus(),
                            decoration: InputDecoration(
                              hintText: 'Search properties',
                              fillColor: AppPalette.white,
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                  color: AppPalette.outline,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                  color: AppPalette.olive,
                                  width: 1.5,
                                ),
                              ),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 13,
                              ),
                              prefixIcon: const Icon(
                                Icons.search_rounded,
                                size: 21,
                              ),
                              suffixIcon: _searchController.text.isEmpty
                                  ? null
                                  : IconButton(
                                      tooltip: 'Clear search',
                                      icon: const Icon(
                                        Icons.close_rounded,
                                        size: 18,
                                      ),
                                      onPressed: () =>
                                          setState(_searchController.clear),
                                    ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          key: const Key('property-filter'),
                          tooltip: _filtersOpen
                              ? 'Close filters'
                              : 'Filter properties',
                          onPressed: _openFilters,
                          style: IconButton.styleFrom(
                            minimumSize: const Size(48, 48),
                            backgroundColor: _filters.isEmpty && !_filtersOpen
                                ? AppPalette.darkOlive
                                : AppPalette.olive,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: Icon(
                            _filtersOpen
                                ? Icons.close_rounded
                                : Icons.tune_rounded,
                            color: AppPalette.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _quickFilters(),
                    if (_filtersOpen)
                      DiscoveryFilterPanel(
                        initial: _filters,
                        properties: _data.properties,
                        onApply: _applyFilters,
                      ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 4),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _preferencesAction(),
                      ),
                    ),
                    if (_data.preferencesError != null)
                      _notice(
                        _data.preferencesError!,
                        'Retry preferences',
                        () => _data.refreshPreferences(),
                      ),
                    if (_data.matchesError != null)
                      _notice(
                        _data.matchesError!,
                        'Retry matches',
                        () => _data.refreshPreferences(),
                      ),
                    if (_data.favoritesError != null)
                      _notice(
                        _data.favoritesError!,
                        'Retry saved properties',
                        _data.loadFavorites,
                      ),
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      children: [
                        Text(
                          _data.propertiesLoading
                              ? 'Loading properties…'
                              : _data.propertiesError != null
                              ? 'Properties unavailable'
                              : '${visible.length} ${visible.length == 1 ? 'property' : 'properties'}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        PopupMenuButton<String>(
                          key: const Key('property-sort'),
                          tooltip: 'Sort properties',
                          initialValue: _data.sort,
                          onSelected: _data.selectSort,
                          itemBuilder: (_) => [
                            for (final option in [
                              'AI Match',
                              'Lowest Rent',
                              'Highest Rent',
                              'Newest',
                            ])
                              PopupMenuItem(
                                value: option,
                                enabled:
                                    option != 'AI Match' || _data.hasScores,
                                child: Text(option),
                              ),
                          ],
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    'Sort: ${_data.hasScores || _data.sort != 'AI Match' ? _data.sort : 'Newest'}',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: AppPalette.olive,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const Icon(
                                  Icons.expand_more_rounded,
                                  size: 18,
                                  color: AppPalette.olive,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
              _propertyContent(visible),
            ],
          ),
        );
      },
    ),
  );

  Widget _preferencesAction() => FilledButton(
    key: const Key('match-preferences-action'),
    onPressed: _openPreferences,
    style: FilledButton.styleFrom(
      backgroundColor: AppPalette.darkOlive,
      foregroundColor: AppPalette.white,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      minimumSize: const Size(48, 38),
      tapTargetSize: MaterialTapTargetSize.padded,
      elevation: 0,
      shape: const StadiumBorder(),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          _data.preferences?.isConfigured == true
              ? Icons.edit_outlined
              : Icons.tune_rounded,
          size: 16,
          color: AppPalette.sage,
        ),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            _data.preferences == null
                ? 'Your preferences'
                : _data.preferences!.isConfigured
                ? 'Edit your preferences'
                : 'Enter your preference',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );

  Widget _quickFilters() => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        _chip(
          'All',
          _filters.isEmpty,
          (_) => setState(() {
            _filters = const DiscoveryFilters();
            _filtersOpen = false;
          }),
        ),
        const SizedBox(width: 8),
        _chip(
          'Available',
          _filters.availableOnly,
          (selected) => setState(() {
            _filtersOpen = false;
            _filters = _filters.withQuickFilters(
              availableOnly: selected,
              bedrooms: _filters.bedrooms,
            );
          }),
        ),
        for (final beds in [1, 2, 3]) ...[
          const SizedBox(width: 8),
          _chip(
            '$beds+ Beds',
            _filters.bedrooms == beds,
            (selected) => setState(() {
              _filtersOpen = false;
              _filters = _filters.withQuickFilters(
                availableOnly: _filters.availableOnly,
                bedrooms: selected ? beds : null,
              );
            }),
          ),
        ],
      ],
    ),
  );
  Widget _chip(String label, bool selected, ValueChanged<bool> onSelected) =>
      FilterChip(
        label: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: selected ? AppPalette.white : AppPalette.primaryText,
          ),
        ),
        selected: selected,
        onSelected: onSelected,
        showCheckmark: false,
        selectedColor: AppPalette.olive,
        backgroundColor: AppPalette.white,
        padding: const EdgeInsets.symmetric(horizontal: 5),
        shape: const StadiumBorder(),
        side: BorderSide(
          color: selected ? AppPalette.olive : AppPalette.outline,
        ),
      );
  Widget _notice(String message, String action, VoidCallback retry) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Semantics(
      liveRegion: true,
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            message,
            style: const TextStyle(
              fontSize: 12,
              color: AppPalette.secondaryText,
            ),
          ),
          TextButton(
            onPressed: retry,
            child: Text(action, style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    ),
  );
  Widget _propertyContent(List<Property> visible) {
    if (_data.propertiesLoading) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (_data.propertiesError != null) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Text(_data.propertiesError!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _data.loadProperties,
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }
    if (visible.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No properties match your current search.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      sliver: SliverList.builder(
        itemCount: visible.length,
        itemBuilder: (context, index) {
          final property = visible[index];
          final saved = _data.favorites.contains(property.id);
          return PropertyCard(
            key: ValueKey('discovery-property-${property.id}'),
            property: property,
            propertyApiService: widget.propertyApiService,
            matchScore: _score(property),
            saved: saved,
            favoriteUnavailableReason: !_data.favoritesReady
                ? (_data.favoritesLoading
                      ? 'Loading saved properties'
                      : 'Saved state unavailable')
                : !saved && !property.isAvailable
                ? 'Only available properties can be saved'
                : null,
            favoritePending: _data.favoritePending.contains(property.id),
            onToggleFavorite:
                _data.favoritesReady && (saved || property.isAvailable)
                ? () async {
                    final success = await _data.toggleFavorite(property);
                    if (!mounted || success) return;
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Could not update this saved property. Please try again.',
                        ),
                      ),
                    );
                  }
                : null,
            onTap: () => _openProperty(
              property,
              _score(property) == null ? null : _data.matches[property.id],
            ),
          );
        },
      ),
    );
  }
}
