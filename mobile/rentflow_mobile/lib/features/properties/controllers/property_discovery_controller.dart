import 'package:flutter/foundation.dart';

import '../models/property.dart';
import '../models/property_matching.dart';
import '../models/property_preferences.dart';
import '../services/property_api_service.dart';

/// In-memory view state only. Preferences and favorites always come from the
/// authenticated backend; scores always come from the saved-preference matcher.
class PropertyDiscoveryController extends ChangeNotifier {
  PropertyDiscoveryController(this.service);
  final PropertyApiService service;

  List<Property> properties = [];
  PropertyPreferences? preferences;
  Map<String, PropertyMatch> matches = {};
  Set<String> favorites = {};
  final Set<String> favoritePending = {};
  bool propertiesLoading = true;
  bool preferencesLoading = true;
  bool favoritesLoading = true;
  bool favoritesReady = false;
  String? propertiesError;
  String? preferencesError;
  String? matchesError;
  String? favoritesError;
  Future<void>? _propertyLoad;
  Future<void>? _preferenceLoad;
  Future<void>? _favoriteLoad;
  bool _disposed = false;
  bool _defaultSortChosen = false;
  String sort = 'Newest';

  bool get hasScores => matches.values.any(
    (match) =>
        match.matchScore != null &&
        match.matchScore! >= 0 &&
        match.matchScore! <= 100,
  );

  void _update() {
    if (!_disposed) notifyListeners();
  }

  Future<void> refresh() async {
    await Future.wait([
      loadProperties(),
      refreshPreferences(),
      loadFavorites(),
    ]);
  }

  Future<void> loadProperties() => _propertyLoad ??= _fetchProperties()
      .whenComplete(() => _propertyLoad = null);

  Future<void> _fetchProperties() async {
    propertiesLoading = true;
    propertiesError = null;
    _update();
    try {
      properties = await service.getProperties();
    } catch (_) {
      propertiesError = 'Could not load properties. Please try again.';
    } finally {
      propertiesLoading = false;
      _update();
    }
  }

  Future<void> refreshPreferences({bool force = false}) async {
    final pending = _preferenceLoad;
    if (pending != null) {
      await pending;
      if (!force || _disposed) return;
    }
    await (_preferenceLoad ??= _fetchPreferences().whenComplete(
      () => _preferenceLoad = null,
    ));
  }

  Future<void> _fetchPreferences() async {
    preferencesLoading = true;
    preferencesError = null;
    matchesError = null;
    matches = {};
    _update();
    try {
      preferences = await service.getMatchPreferences();
      if (preferences!.isConfigured) {
        try {
          final result = await service.getSavedPropertyMatches();
          matches = {
            for (final match in result.matches) match.propertyId: match,
          };
        } catch (_) {
          matchesError = 'Matches unavailable. You can still browse homes.';
        }
      }
    } catch (_) {
      preferences = null;
      preferencesError = 'Match preferences unavailable.';
    } finally {
      preferencesLoading = false;
      if (!_defaultSortChosen && hasScores) {
        sort = 'AI Match';
        _defaultSortChosen = true;
      }
      if (!hasScores && sort == 'AI Match') sort = 'Newest';
      _update();
    }
  }

  Future<void> loadFavorites() => _favoriteLoad ??= _fetchFavorites()
      .whenComplete(() => _favoriteLoad = null);

  Future<void> _fetchFavorites() async {
    // A GET that started before a write must never overwrite that write.
    if (favoritePending.isNotEmpty) return;
    favoritesLoading = true;
    favoritesReady = false;
    favoritesError = null;
    _update();
    try {
      favorites = await service.getPropertyFavorites();
      favoritesReady = true;
    } catch (_) {
      favoritesError = 'Saved properties unavailable.';
    } finally {
      favoritesLoading = false;
      _update();
    }
  }

  Future<bool> toggleFavorite(Property property) async {
    if (!favoritesReady ||
        favoritesLoading ||
        favoritePending.contains(property.id)) {
      return false;
    }
    final wasSaved = favorites.contains(property.id);
    if (!wasSaved && !property.isAvailable) return false;
    favoritePending.add(property.id);
    _update();
    try {
      await service.setPropertyFavorite(property.id, saved: !wasSaved);
      if (wasSaved) {
        favorites.remove(property.id);
      } else {
        favorites.add(property.id);
      }
      return true;
    } catch (_) {
      return false;
    } finally {
      favoritePending.remove(property.id);
      _update();
    }
  }

  void selectSort(String value) {
    if (value == 'AI Match' && !hasScores) return;
    if (value == 'Liked' && !favoritesReady) return;
    sort = value;
    _defaultSortChosen = true;
    _update();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
