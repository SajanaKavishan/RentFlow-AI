import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rentflow_mobile/features/properties/controllers/property_discovery_controller.dart';
import 'package:rentflow_mobile/features/properties/models/property_matching.dart';

import 'helpers/discovery_backend.dart';
import 'property_details_test.dart' as fixture;

void main() {
  late DiscoveryBackend backend;
  late PropertyDiscoveryController data;
  setUp(() {
    backend = DiscoveryBackend();
    data = PropertyDiscoveryController(backend.service);
  });
  tearDown(() {
    data.dispose();
    backend.close();
  });

  test(
    'web changes are observed through fresh server GET, with no mobile persistence',
    () async {
      await data.refresh();
      expect(data.preferences?.preferredCity, 'Kurunegala');
      expect(data.preferences?.maximumMonthlyRent, 100000);
      expect(data.preferences?.minimumBedrooms, 2);
      expect(data.matches[fixture.id]?.matchScore, 94);
      expect(data.sort, 'AI Match');
      backend.preferences = {
        ...savedPreferences,
        'preferredCity': 'Galle',
        'maximumMonthlyRent': 175000,
      };
      await data.refreshPreferences();
      expect(data.preferences?.preferredCity, 'Galle');
      expect(data.preferences?.maximumMonthlyRent, 175000);
      expect(backend.calls(preferencesPath), 2);
      expect(backend.calls(matchesPath), 2);
    },
  );

  test(
    'mobile PUT writes exact shared contract with bearer auth, then GET refreshes matches',
    () async {
      await data.refresh();
      await backend.service.saveMatchPreferences(
        const PropertyMatchingRequest(
          preferredCity: 'Colombo',
          maximumMonthlyRent: 150000,
          minimumBedrooms: 3,
          minimumBathrooms: 2,
          preferredAmenities: ['parking', 'wifi'],
        ),
      );
      final put = backend.requests.singleWhere(
        (request) => request.method == 'PUT',
      );
      expect(put.url.path, preferencesPath);
      expect(put.headers['Authorization'], 'Bearer tenant-token');
      expect(jsonDecode(put.body), {
        'preferredCity': 'Colombo',
        'maximumMonthlyRent': 150000,
        'minimumBedrooms': 3,
        'minimumBathrooms': 2,
        'preferredAmenities': ['parking', 'wifi'],
      });
      await data.refreshPreferences(force: true);
      expect(backend.preferences['preferredCity'], 'Colombo');
      expect(data.preferences?.preferredCity, 'Colombo');
      expect(backend.calls(matchesPath), 2);
      expect(
        backend.requests.where((request) => request.method == 'POST'),
        isEmpty,
      );
    },
  );

  test(
    'DELETE reset reloads server record, clears scores and uses Newest',
    () async {
      await data.refresh();
      await backend.service.resetMatchPreferences();
      await data.refreshPreferences(force: true);
      expect(backend.calls(preferencesPath, 'DELETE'), 1);
      expect(data.preferences?.isConfigured, false);
      expect(data.matches, isEmpty);
      expect(data.sort, 'Newest');
      expect(backend.calls(matchesPath), 1);
    },
  );

  test(
    'no preferences never runs matcher and cannot select AI Match',
    () async {
      backend.preferences = {'isConfigured': false};
      await data.refresh();
      expect(data.properties, hasLength(1));
      expect(backend.calls(matchesPath), 0);
      data.selectSort('AI Match');
      expect(data.sort, 'Newest');
    },
  );

  for (final failingPath in [preferencesPath, matchesPath, favoritesPath]) {
    test(
      '$failingPath failure preserves normal browsing and supports retry',
      () async {
        backend.intercept = (request) async =>
            request.url.path == failingPath ? http.Response('', 503) : null;
        await data.refresh();
        expect(data.properties, hasLength(1));
        expect(data.propertiesError, isNull);
        if (failingPath == preferencesPath) {
          expect(data.preferencesError, isNotNull);
        }
        if (failingPath == matchesPath) expect(data.matchesError, isNotNull);
        if (failingPath == favoritesPath) expect(data.favoritesReady, false);
        backend.intercept = null;
        await data.refresh();
        expect(data.preferencesError, isNull);
        expect(data.matchesError, isNull);
        expect(data.favoritesReady, true);
      },
    );
  }

  test('no or invalid match scores never imply real matching', () async {
    backend.scores[fixture.id] = null;
    await data.refresh();
    expect(data.hasScores, false);
    expect(data.sort, 'Newest');
    backend.scores[fixture.id] = 101;
    await data.refreshPreferences();
    expect(data.hasScores, false);
  });

  test(
    'favorites use shared GET PUT DELETE and preserve state on failed writes',
    () async {
      await data.refresh();
      final property = data.properties.single;
      expect(await data.toggleFavorite(property), true);
      expect(data.favorites, {fixture.id});
      expect(backend.favorites, {fixture.id});
      backend.intercept = (request) async =>
          request.method == 'DELETE' ? http.Response('', 503) : null;
      expect(await data.toggleFavorite(property), false);
      expect(data.favorites, {fixture.id});
      expect(data.favoritePending, isEmpty);
      backend.intercept = null;
      expect(await data.toggleFavorite(property), true);
      expect(data.favorites, isEmpty);
      backend.intercept = (request) async =>
          request.method == 'PUT' ? http.Response('', 503) : null;
      expect(await data.toggleFavorite(property), false);
      expect(data.favorites, isEmpty);
      for (final request in backend.requests.where(
        (request) => request.url.path.startsWith(favoritesPath),
      )) {
        expect(request.headers['Authorization'], 'Bearer tenant-token');
      }
    },
  );

  test('server-side web favorites refresh into mobile state', () async {
    await data.refresh();
    backend.favorites.add(fixture.id);
    await data.loadFavorites();
    expect(data.favorites, {fixture.id});
  });

  test('duplicate refreshes coalesce while requests are in flight', () async {
    final gate = Completer<void>();
    backend.intercept = (request) async {
      await gate.future;
      return null;
    };
    final first = data.refresh();
    final second = data.refresh();
    await Future<void>.delayed(Duration.zero);
    gate.complete();
    await Future.wait([first, second]);
    expect(backend.calls(preferencesPath), 1);
    expect(backend.calls(favoritesPath), 1);
    expect(backend.calls('/api/properties'), 1);
  });

  test(
    'forced refresh after editing waits for an old GET then reads server again',
    () async {
      final gate = Completer<void>();
      backend.intercept = (request) async {
        if (request.url.path == preferencesPath &&
            backend.calls(preferencesPath) == 1) {
          await gate.future;
          return DiscoveryBackend.json(savedPreferences);
        }
        return null;
      };
      final first = data.refreshPreferences();
      backend.preferences = {...savedPreferences, 'preferredCity': 'Colombo'};
      final afterSave = data.refreshPreferences(force: true);
      gate.complete();
      await Future.wait([first, afterSave]);
      expect(data.preferences?.preferredCity, 'Colombo');
      expect(backend.calls(preferencesPath), 2);
    },
  );
}
