import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/theme/app_theme.dart';
import '../models/discovery_filters.dart';
import '../models/property.dart';
import '../models/property_preferences.dart';
import '../services/town_autocomplete_service.dart';

class DiscoveryFilterPanel extends StatefulWidget {
  const DiscoveryFilterPanel({
    super.key,
    required this.initial,
    required this.properties,
    required this.onApply,
    this.townService = const TownAutocompleteService(),
  });
  final DiscoveryFilters initial;
  final List<Property> properties;
  final ValueChanged<DiscoveryFilters> onApply;
  final TownAutocompleteService townService;

  @override
  State<DiscoveryFilterPanel> createState() => _DiscoveryFilterPanelState();
}

class _DiscoveryFilterPanelState extends State<DiscoveryFilterPanel> {
  late final TextEditingController _city;
  late double? _maxRent;
  late Set<String> _amenities;
  bool _more = false;
  bool _loadingTowns = false;
  bool _selectingTown = false;
  String? _townError;
  List<TownPrediction> _towns = [];
  Timer? _debounce;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _city = TextEditingController(text: widget.initial.city);
    _maxRent = widget.initial.maxRent;
    _amenities = widget.initial.amenities.map(amenityIdentity).toSet();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _request++;
    _city.dispose();
    unawaited(widget.townService.endSession());
    super.dispose();
  }

  DiscoveryFilters get _draft => DiscoveryFilters(
    availableOnly: widget.initial.availableOnly,
    bedrooms: widget.initial.bedrooms,
    bathrooms: widget.initial.bathrooms,
    minRent: widget.initial.minRent,
    city: _city.text.trim(),
    maxRent: _maxRent,
    amenities: Set.unmodifiable(_amenities),
  );

  double get _rentLimit {
    final highest = widget.properties.fold<double>(
      250000,
      (value, property) => math.max(value, property.monthlyRent),
    );
    return (math.max(highest, widget.initial.maxRent ?? 0) / 25000).ceil() *
        25000.0;
  }

  Map<String, String> get _amenityOptions {
    final options = {...propertyAmenityCatalog};
    for (final property in widget.properties) {
      final details = property.amenityDetails ?? <PropertyAmenityDetail>[];
      final identities = {
        for (final detail in details)
          detail.name.trim().toLowerCase(): detail.canonicalKey ?? detail.name,
      };
      for (final label in [
        ...property.amenities,
        ...details.map((detail) => detail.name),
      ]) {
        if (label.trim().isEmpty) continue;
        final identity = amenityIdentity(
          identities[label.trim().toLowerCase()] ?? label,
        );
        options[identity] = propertyAmenityCatalog[identity] ?? label.trim();
      }
    }
    for (final selected in _amenities) {
      options.putIfAbsent(
        selected,
        () => propertyAmenityCatalog[selected] ?? selected,
      );
    }
    return options;
  }

  void _queryChanged(String query) {
    _debounce?.cancel();
    final request = ++_request;
    setState(() {
      _towns = [];
      _townError = null;
      _loadingTowns = query.trim().isNotEmpty;
    });
    if (query.trim().isEmpty) {
      unawaited(widget.townService.endSession());
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final towns = await widget.townService.suggest(query);
        if (!mounted || request != _request) return;
        setState(() {
          _towns = towns;
          _loadingTowns = false;
          _townError = towns.isEmpty
              ? 'No town suggestions. You can enter a town manually.'
              : null;
        });
      } catch (_) {
        if (!mounted || request != _request) return;
        setState(() {
          _loadingTowns = false;
          _townError =
              'Town suggestions unavailable. You can enter a town manually.';
        });
      }
    });
  }

  void _useCity(String city) {
    _debounce?.cancel();
    _request++;
    setState(() {
      _city.text = city;
      _towns = [];
      _townError = null;
      _loadingTowns = false;
    });
    FocusScope.of(context).unfocus();
    unawaited(widget.townService.endSession());
  }

  Future<void> _selectTown(TownPrediction town) async {
    final request = ++_request;
    _debounce?.cancel();
    setState(() => _selectingTown = true);
    try {
      final city = await widget.townService.select(town);
      if (!mounted || request != _request) return;
      _useCity(city);
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(
        () => _townError =
            'Could not select this town. Try again or enter it manually.',
      );
    } finally {
      if (mounted) setState(() => _selectingTown = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final options = _amenityOptions.entries.toList();
    final shown = _more
        ? options
        : options
              .where(
                (entry) =>
                    options.indexOf(entry) < 6 ||
                    _amenities.contains(entry.key),
              )
              .toList();
    final cities =
        widget.properties
            .map((property) => property.city.trim())
            .where((city) => city.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return Container(
      key: const Key('discovery-filter-panel'),
      margin: const EdgeInsets.only(top: 12, bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppPalette.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppPalette.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              _heading('Max monthly rent'),
              Text(
                _maxRent == null ? 'Any rent' : 'LKR ${_money(_maxRent!)}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppPalette.olive,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            ),
            child: Slider(
              key: const Key('filter-max-rent'),
              value: (_maxRent ?? _rentLimit).clamp(0, _rentLimit),
              min: 0,
              max: _rentLimit,
              label: _maxRent == null ? 'Any rent' : 'LKR ${_money(_maxRent!)}',
              onChanged: (value) => setState(
                () => _maxRent = value >= _rentLimit
                    ? null
                    : value.roundToDouble(),
              ),
              semanticFormatterCallback: (value) => value >= _rentLimit
                  ? 'Any rent'
                  : '${value.round()} rupees per month',
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text(
                  'LKR 0',
                  style: TextStyle(
                    fontSize: 10,
                    color: AppPalette.secondaryText,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'LKR ${_money(_rentLimit)}+',
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppPalette.secondaryText,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _heading('Location'),
          const SizedBox(height: 8),
          TextField(
            key: const Key('filter-city'),
            controller: _city,
            enabled: !_selectingTown,
            style: const TextStyle(fontSize: 13),
            textCapitalization: TextCapitalization.words,
            inputFormatters: [LengthLimitingTextInputFormatter(100)],
            textInputAction: TextInputAction.done,
            onChanged: _queryChanged,
            onSubmitted: (_) => FocusScope.of(context).unfocus(),
            decoration: InputDecoration(
              hintText: 'Type a town or city',
              fillColor: AppPalette.white,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppPalette.outline),
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
                vertical: 12,
              ),
              prefixIcon: const Icon(Icons.location_on_outlined, size: 19),
              suffixIcon: _loadingTowns || _selectingTown
                  ? const Padding(
                      padding: EdgeInsets.all(15),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : _city.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear location',
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () => _useCity(''),
                    ),
            ),
          ),
          if (_towns.isNotEmpty) ...[
            const SizedBox(height: 4),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: AppPalette.outline),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final town in _towns)
                    TextButton(
                      key: ValueKey('town-${town.placeId}'),
                      onPressed: _selectingTown
                          ? null
                          : () => _selectTown(town),
                      style: TextButton.styleFrom(
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            town.town,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (town.description.isNotEmpty)
                            Text(
                              town.description,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppPalette.secondaryText,
                              ),
                            ),
                        ],
                      ),
                    ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(12, 8, 12, 10),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        'Google Maps',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF5F6368),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_townError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _townError!,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppPalette.secondaryText,
                ),
              ),
            ),
          if (cities.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final city in cities.take(4))
                  _chip(
                    city,
                    _city.text.trim().toLowerCase() == city.toLowerCase(),
                    () => _useCity(
                      _city.text.trim().toLowerCase() == city.toLowerCase()
                          ? ''
                          : city,
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          _heading('Amenities'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final amenity in shown)
                _chip(
                  amenity.value,
                  _amenities.contains(amenity.key),
                  () => setState(() {
                    if (!_amenities.remove(amenity.key)) {
                      _amenities.add(amenity.key);
                    }
                  }),
                  key: ValueKey('filter-amenity-${amenity.key}'),
                ),
            ],
          ),
          if (options.length > 6)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const Key('filter-view-more'),
                onPressed: () => setState(() => _more = !_more),
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                child: Text(
                  _more
                      ? 'View less'
                      : 'View more (${options.length - shown.length})',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('filter-show-results'),
            onPressed: _selectingTown
                ? null
                : () {
                    FocusScope.of(context).unfocus();
                    widget.onApply(_draft);
                  },
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Show results',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
          if (!_draft.isEmpty)
            TextButton(
              key: const Key('filter-clear'),
              onPressed: () {
                FocusScope.of(context).unfocus();
                widget.onApply(const DiscoveryFilters());
              },
              child: const Text(
                'Clear filters',
                style: TextStyle(fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _heading(String text) => Text(
    text,
    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
  );

  Widget _chip(String label, bool selected, VoidCallback toggle, {Key? key}) =>
      FilterChip(
        key: key,
        label: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: math.max(80, MediaQuery.sizeOf(context).width - 128),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: selected ? AppPalette.darkOlive : AppPalette.secondaryText,
            ),
          ),
        ),
        selected: selected,
        onSelected: (_) => toggle(),
        showCheckmark: false,
        visualDensity: VisualDensity.compact,
        selectedColor: AppPalette.sage,
        backgroundColor: AppPalette.white,
        side: BorderSide(
          color: selected ? AppPalette.olive : AppPalette.outline,
        ),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 2),
      );
}

String _money(double value) => value.round().toString().replaceAllMapped(
  RegExp(r'\B(?=(\d{3})+(?!\d))'),
  (_) => ',',
);
