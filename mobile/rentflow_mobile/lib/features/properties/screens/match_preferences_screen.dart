import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../shared/theme/app_theme.dart';
import '../models/property_matching.dart';
import '../models/property_preferences.dart';
import '../services/property_api_service.dart';

enum PreferenceChange { saved, reset }

class MatchPreferencesScreen extends StatefulWidget {
  const MatchPreferencesScreen({super.key, required this.service});
  final PropertyApiService service;

  @override
  State<MatchPreferencesScreen> createState() => _MatchPreferencesScreenState();
}

class _MatchPreferencesScreenState extends State<MatchPreferencesScreen> {
  final _form = GlobalKey<FormState>();
  final _city = TextEditingController();
  final _rent = TextEditingController();
  final _beds = TextEditingController();
  final _baths = TextEditingController();
  final Set<String> _amenities = {};
  final Set<String> _customAmenities = {};
  bool _loading = true;
  bool _busy = false;
  bool _configured = false;
  String? _loadError;
  String? _actionError;
  String? _savedDraft;

  bool get _hasChanges => _savedDraft != null && _draft != _savedDraft;

  String get _draft {
    final amenities = _amenities.toList()..sort();
    String number(TextEditingController controller, {bool rooms = false}) {
      final text = controller.text.trim();
      final value = rooms ? int.tryParse(text) : double.tryParse(text);
      return value?.toString() ?? text;
    }

    return jsonEncode([
      _city.text.trim(),
      number(_rent),
      number(_beds, rooms: true),
      number(_baths, rooms: true),
      amenities,
    ]);
  }

  void _draftChanged() {
    if (mounted && !_loading) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    for (final controller in [_city, _rent, _beds, _baths]) {
      controller.addListener(_draftChanged);
    }
    _load();
  }

  @override
  void dispose() {
    for (final controller in [_city, _rent, _beds, _baths]) {
      controller.removeListener(_draftChanged);
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final saved = await widget.service.getMatchPreferences();
      if (!mounted) return;
      _city.text = saved.preferredCity ?? '';
      _rent.text = saved.maximumMonthlyRent == null
          ? ''
          : _number(saved.maximumMonthlyRent!);
      _beds.text = saved.minimumBedrooms?.toString() ?? '';
      _baths.text = saved.minimumBathrooms?.toString() ?? '';
      _amenities
        ..clear()
        ..addAll(
          saved.preferredAmenities.map(
            (value) => preferenceAmenityKey(value) ?? value,
          ),
        );
      _customAmenities
        ..clear()
        ..addAll(
          _amenities.where(
            (value) => !propertyAmenityCatalog.containsKey(value),
          ),
        );
      setState(() {
        _savedDraft = _draft;
        _configured = saved.isConfigured;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError =
              'Could not load your saved preferences. Please try again.';
        });
      }
    }
  }

  String _number(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toString();

  String? _validateNumber(String? text, {required bool rooms}) {
    final raw = text?.trim() ?? '';
    if (raw.isEmpty) return null;
    final value = rooms ? int.tryParse(raw)?.toDouble() : double.tryParse(raw);
    if (value == null ||
        !value.isFinite ||
        value < 0 ||
        value > (rooms ? 20 : 9999999999999999)) {
      return rooms
          ? 'Enter a whole number from 0 to 20.'
          : 'Enter a valid non-negative monthly rent.';
    }
    return null;
  }

  Future<void> _save() async {
    if (_busy || !_hasChanges) return;
    FocusScope.of(context).unfocus();
    if (!_form.currentState!.validate()) return;
    if (_amenities.length > 20) {
      setState(() => _actionError = 'Choose up to 20 amenities.');
      return;
    }
    final request = PropertyMatchingRequest(
      preferredCity: _city.text.trim().isEmpty ? null : _city.text.trim(),
      maximumMonthlyRent: double.tryParse(_rent.text.trim()),
      minimumBedrooms: int.tryParse(_beds.text.trim()),
      minimumBathrooms: int.tryParse(_baths.text.trim()),
      preferredAmenities: _amenities.toList(),
    );
    if (request.preferredCity == null &&
        request.maximumMonthlyRent == null &&
        request.minimumBedrooms == null &&
        request.minimumBathrooms == null &&
        _amenities.isEmpty) {
      setState(() => _actionError = 'Set at least one match preference.');
      return;
    }
    setState(() {
      _busy = true;
      _actionError = null;
    });
    try {
      await widget.service.saveMatchPreferences(request);
      if (!mounted) return;
      setState(() => _busy = false);
      Navigator.pop(context, PreferenceChange.saved);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _actionError =
              'Could not save preferences. Your changes are still here; please try again.';
        });
      }
    }
  }

  Future<void> _reset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset match preferences?'),
        content: const Text(
          'This clears your saved preferences on both mobile and web.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep preferences'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset preferences'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _actionError = null;
    });
    try {
      await widget.service.resetMatchPreferences();
      if (!mounted) return;
      setState(() => _busy = false);
      Navigator.pop(context, PreferenceChange.reset);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _actionError = 'Could not reset preferences. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Match Preferences'),
        backgroundColor: AppPalette.warmCream,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: const TextStyle(
          color: AppPalette.darkOlive,
          fontSize: 19,
          fontWeight: FontWeight.w700,
        ),
      ),
      bottomNavigationBar: _loading || _loadError != null ? null : _actions(),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_loadError!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _load,
                      child: const Text('Retry preferences'),
                    ),
                  ],
                ),
              ),
            )
          : SafeArea(
              child: Form(
                key: _form,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _intro(),
                      const SizedBox(height: 18),
                      _section(
                        Icons.location_on_outlined,
                        'Location & budget',
                        'Start with where you want to live.',
                        [
                          TextFormField(
                            key: const Key('preference-city'),
                            controller: _city,
                            enabled: !_busy,
                            maxLength: 100,
                            textCapitalization: TextCapitalization.words,
                            textInputAction: TextInputAction.next,
                            style: const TextStyle(fontSize: 14),
                            decoration: _inputDecoration('Preferred city')
                                .copyWith(
                                  hintText: 'e.g. Kurunegala',
                                  counterText: '',
                                  prefixIcon: const Icon(
                                    Icons.location_on_outlined,
                                    size: 19,
                                  ),
                                ),
                          ),
                          const SizedBox(height: 16),
                          _numberField(
                            _rent,
                            'Maximum monthly rent',
                            'preference-rent',
                            rooms: false,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _section(
                        Icons.bed_outlined,
                        'Room to feel at home',
                        'Choose a minimum, or keep your options open.',
                        [
                          _roomSelector(
                            _beds,
                            'Minimum bedrooms',
                            'preference-beds',
                          ),
                          const SizedBox(height: 20),
                          _roomSelector(
                            _baths,
                            'Minimum bathrooms',
                            'preference-baths',
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _section(
                        Icons.auto_awesome_outlined,
                        'Preferred amenities',
                        'Pick the little things that matter to you.',
                        [
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              for (final entry
                                  in propertyAmenityCatalog.entries)
                                _amenityTile(entry.key, entry.value),
                              // Keep custom amenities from the shared saved record selectable.
                              for (final custom in _customAmenities)
                                _amenityTile(custom, custom),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
    ),
  );

  Widget _intro() => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [AppPalette.darkOlive, AppPalette.olive],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.auto_awesome_rounded, size: 16, color: AppPalette.sage),
            SizedBox(width: 8),
            Flexible(
              child: Text(
                'MAKE IT YOURS',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                  color: AppPalette.sage,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          _configured ? 'Your saved preferences' : 'Set match preferences',
          style: const TextStyle(
            fontSize: 22,
            height: 1.2,
            fontWeight: FontWeight.w600,
            color: AppPalette.white,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'A home that fits your life. Leave any field empty if you have no preference.',
          style: TextStyle(fontSize: 12, height: 1.5, color: AppPalette.sage),
        ),
      ],
    ),
  );

  Widget _section(
    IconData icon,
    String title,
    String subtitle,
    List<Widget> children,
  ) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppPalette.white,
      border: Border.all(color: AppPalette.outline.withValues(alpha: 0.7)),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppPalette.softCream,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: AppPalette.olive),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppPalette.darkOlive,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11,
                      height: 1.4,
                      color: AppPalette.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        ...children,
      ],
    ),
  );

  InputDecoration _inputDecoration(String label) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(fontSize: 12, color: AppPalette.secondaryText),
    filled: true,
    fillColor: AppPalette.warmCream,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppPalette.outline),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppPalette.olive, width: 1.5),
    ),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
  );

  Widget _roomSelector(
    TextEditingController controller,
    String label,
    String key,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _numberField(controller, label, key, rooms: true),
      const SizedBox(height: 8),
      Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (final value in <int?>[null, 1, 2, 3, 4])
            ChoiceChip(
              key: Key('$key-choice-${value ?? 'any'}'),
              label: Text(
                value == null ? 'Any' : '$value+',
                style: const TextStyle(fontSize: 11),
              ),
              selected: value == null
                  ? controller.text.trim().isEmpty
                  : int.tryParse(controller.text.trim()) == value,
              onSelected: _busy
                  ? null
                  : (_) => controller.text = value?.toString() ?? '',
              showCheckmark: false,
              selectedColor: AppPalette.sage,
              backgroundColor: AppPalette.white,
              side: BorderSide(
                color:
                    (value == null
                        ? controller.text.trim().isEmpty
                        : int.tryParse(controller.text.trim()) == value)
                    ? AppPalette.olive
                    : AppPalette.outline,
              ),
              shape: const StadiumBorder(),
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    ],
  );

  Widget _actions() => Container(
    decoration: const BoxDecoration(
      color: AppPalette.white,
      border: Border(top: BorderSide(color: AppPalette.outline)),
    ),
    child: SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_actionError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  _actionError!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppPalette.danger,
                  ),
                ),
              ),
            ),
          if (_configured)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _busy ? null : _reset,
                child: const Text(
                  'Reset saved preferences',
                  textAlign: TextAlign.left,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppPalette.secondaryText,
                  ),
                ),
              ),
            ),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Cancel', textAlign: TextAlign.center),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: _busy || !_hasChanges ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppPalette.darkOlive,
                      disabledBackgroundColor: AppPalette.softCream,
                      disabledForegroundColor: AppPalette.secondaryText,
                      minimumSize: const Size(48, 48),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      _busy ? 'Updating preferences…' : 'Save preferences',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _numberField(
    TextEditingController controller,
    String label,
    String key, {
    required bool rooms,
  }) => TextFormField(
    key: Key(key),
    controller: controller,
    enabled: !_busy,
    keyboardType: TextInputType.numberWithOptions(decimal: !rooms),
    textInputAction: TextInputAction.next,
    style: const TextStyle(fontSize: 14),
    decoration: _inputDecoration(label).copyWith(
      prefixText: rooms ? null : 'LKR ',
      hintText: rooms ? 'Any' : 'No maximum',
    ),
    validator: (value) => _validateNumber(value, rooms: rooms),
  );

  Widget _amenityTile(String key, String label) => FilterChip(
    key: Key('preference-amenity-$key'),
    selected: _amenities.contains(key),
    label: Text(
      label,
      style: const TextStyle(fontSize: 12, color: AppPalette.darkOlive),
    ),
    avatar: Icon(_amenityIcon(key), size: 17, color: AppPalette.olive),
    selectedColor: AppPalette.sage,
    backgroundColor: AppPalette.white,
    checkmarkColor: AppPalette.darkOlive,
    side: BorderSide(
      color: _amenities.contains(key) ? AppPalette.olive : AppPalette.outline,
    ),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    onSelected: _busy
        ? null
        : (selected) => setState(() {
            if (selected) {
              _amenities.add(key);
            } else {
              _amenities.remove(key);
            }
          }),
  );

  IconData _amenityIcon(String key) => switch (key) {
    'wifi' => Icons.wifi_rounded,
    'parking' => Icons.local_parking_rounded,
    'air-conditioning' => Icons.ac_unit_rounded,
    'washer-dryer' => Icons.local_laundry_service_outlined,
    'gym' => Icons.fitness_center_rounded,
    'swimming-pool' => Icons.pool_rounded,
    'balcony' => Icons.balcony_outlined,
    'elevator' => Icons.elevator_outlined,
    'furnished' => Icons.chair_outlined,
    'garden' => Icons.yard_outlined,
    'security' => Icons.shield_outlined,
    'rooftop' => Icons.roofing_rounded,
    _ => Icons.check_circle_outline_rounded,
  };
}
