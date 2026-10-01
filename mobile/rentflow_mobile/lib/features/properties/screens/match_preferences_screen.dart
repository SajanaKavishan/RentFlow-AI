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

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final controller in [_city, _rent, _beds, _baths]) {
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
      appBar: AppBar(title: const Text('Match Preferences')),
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
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(
                      _configured
                          ? 'Your saved preferences'
                          : 'Set match preferences',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Use the same preferences on mobile and web. Leave a field empty if you have no preference.',
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      key: const Key('preference-city'),
                      controller: _city,
                      enabled: !_busy,
                      maxLength: 100,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Preferred city',
                        hintText: 'e.g. Kurunegala',
                      ),
                    ),
                    const SizedBox(height: 12),
                    _numberField(
                      _rent,
                      'Maximum monthly rent',
                      'preference-rent',
                      rooms: false,
                    ),
                    const SizedBox(height: 16),
                    _numberField(
                      _beds,
                      'Minimum bedrooms',
                      'preference-beds',
                      rooms: true,
                    ),
                    const SizedBox(height: 16),
                    _numberField(
                      _baths,
                      'Minimum bathrooms',
                      'preference-baths',
                      rooms: true,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Preferred amenities',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    for (final entry in propertyAmenityCatalog.entries)
                      _amenityTile(entry.key, entry.value),
                    // Preserve custom values saved by the web instead of silently dropping them.
                    for (final custom in _customAmenities)
                      _amenityTile(custom, custom),
                    if (_actionError != null) ...[
                      const SizedBox(height: 12),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          _actionError!,
                          style: const TextStyle(color: AppPalette.danger),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _busy ? null : _save,
                      child: Text(
                        _busy ? 'Updating preferences…' : 'Save preferences',
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    if (_configured)
                      TextButton(
                        onPressed: _busy ? null : _reset,
                        child: const Text('Reset saved preferences'),
                      ),
                  ],
                ),
              ),
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
    decoration: InputDecoration(
      labelText: label,
      prefixText: rooms ? null : 'LKR ',
    ),
    validator: (value) => _validateNumber(value, rooms: rooms),
  );

  Widget _amenityTile(String key, String label) => CheckboxListTile(
    key: Key('preference-amenity-$key'),
    value: _amenities.contains(key),
    title: Text(label),
    contentPadding: EdgeInsets.zero,
    controlAffinity: ListTileControlAffinity.leading,
    activeColor: AppPalette.olive,
    onChanged: _busy
        ? null
        : (selected) => setState(() {
            if (selected == true) {
              _amenities.add(key);
            } else {
              _amenities.remove(key);
            }
          }),
  );
}
