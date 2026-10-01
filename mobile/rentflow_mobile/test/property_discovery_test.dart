import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rentflow_mobile/features/properties/screens/property_details_screen.dart';
import 'package:rentflow_mobile/features/properties/screens/property_list_screen.dart';
import 'package:rentflow_mobile/features/properties/widgets/property_card.dart';
import 'package:rentflow_mobile/shared/theme/app_theme.dart';

import 'helpers/discovery_backend.dart';
import 'match_preferences_test.dart' show tapVisible, scrollToVisible;
import 'property_details_test.dart' as fixture;

const secondId = '33333333-3333-4333-8333-333333333333';

Future<void> openDiscovery(
  WidgetTester tester,
  DiscoveryBackend backend,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.build(),
      home: Scaffold(
        body: PropertyListScreen(propertyApiService: backend.service),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late DiscoveryBackend backend;
  setUp(() => backend = DiscoveryBackend());
  tearDown(() => backend.close());

  testWidgets(
    'compact discovery shows exact count and real score without avatar summary or Verified',
    (tester) async {
      await openDiscovery(tester, backend);
      expect(find.text('EXPLORE HOMES'), findsOneWidget);
      expect(find.text('Find your place'), findsOneWidget);
      expect(find.text('Edit your preferences'), findsOneWidget);
      expect(find.text('1 property'), findsOneWidget);
      expect(find.text('Sort: AI Match'), findsOneWidget);
      expect(find.text('94% Match'), findsOneWidget);
      expect(find.text('AM'), findsNothing);
      expect(find.text('Verified'), findsNothing);
      expect(find.textContaining('AI summary'), findsNothing);
      expect(find.text('AI Property Match'), findsNothing);
      expect(find.byKey(const Key('property-filter')), findsOneWidget);
      expect(find.byType(CircleAvatar), findsNothing);
      expect(tester.getTopLeft(find.byType(PropertyCard)).dy, lessThan(360));
    },
  );

  testWidgets(
    'no saved preferences produces unscored browsing and truthful disabled AI sort',
    (tester) async {
      backend.preferences = {'isConfigured': false};
      await openDiscovery(tester, backend);
      expect(find.text('Enter your preference'), findsOneWidget);
      expect(find.text('Sort: Newest'), findsOneWidget);
      expect(find.textContaining('% Match'), findsNothing);
      await tester.tap(find.byKey(const Key('property-sort')));
      await tester.pumpAndSettle();
      final option = tester.widget<PopupMenuItem<String>>(
        find.widgetWithText(PopupMenuItem<String>, 'AI Match'),
      );
      expect(option.enabled, false);
      expect(backend.calls(matchesPath), 0);
    },
  );

  testWidgets(
    'search uses title address and city, and chips use minimum bedrooms with truthful counts',
    (tester) async {
      backend.properties.add({
        ...fixture.propertyJson(available: false),
        'id': secondId,
        'title': 'Garden flat',
        'city': 'Galle',
        'address': 'Seaside Road',
        'bedrooms': 1,
      });
      await openDiscovery(tester, backend);
      expect(find.text('2 properties'), findsOneWidget);
      for (final query in ['spacious', '42 Garden', 'Colombo']) {
        await tester.enterText(find.byKey(const Key('property-search')), query);
        await tester.pumpAndSettle();
        expect(find.text('1 property'), findsOneWidget);
      }
      await tester.enterText(find.byKey(const Key('property-search')), '');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, '1+ Beds'));
      await tester.pumpAndSettle();
      expect(find.text('2 properties'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilterChip, '2+ Beds'));
      await tester.pumpAndSettle();
      expect(find.text('1 property'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilterChip, 'All'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, 'Available'));
      await tester.pumpAndSettle();
      expect(find.text('1 property'), findsOneWidget);
      expect(backend.calls('/api/properties'), 1);
      expect(find.textContaining('homes available'), findsNothing);
    },
  );

  testWidgets(
    'inline panel applies real city and rent without changing saved preferences',
    (tester) async {
      backend.properties.add({
        ...fixture.propertyJson(),
        'id': secondId,
        'city': 'Galle',
        'monthlyRent': 80000,
      });
      await openDiscovery(tester, backend);
      await tester.tap(find.byKey(const Key('property-filter')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('filter-city')), 'Galle');
      tester
          .widget<Slider>(find.byKey(const Key('filter-max-rent')))
          .onChanged!(100000);
      await tester.pump();
      await tapVisible(tester, find.byKey(const Key('filter-show-results')));
      expect(find.text('1 property'), findsOneWidget);
      expect(
        tester.widget<PropertyCard>(find.byType(PropertyCard)).property.id,
        secondId,
      );
      expect(backend.calls(preferencesPath, 'PUT'), 0);
    },
  );

  testWidgets('real matches sort descending and rent/newest remain available', (
    tester,
  ) async {
    backend.properties.add({
      ...fixture.propertyJson(),
      'id': secondId,
      'monthlyRent': 80000,
      'createdAt': '2026-10-01T00:00:00Z',
    });
    backend.scores[secondId] = 75;
    await openDiscovery(tester, backend);
    expect(
      tester.widget<PropertyCard>(find.byType(PropertyCard).first).property.id,
      fixture.id,
    );
    for (final sort in ['Lowest Rent', 'Highest Rent', 'Newest']) {
      await tester.tap(find.byKey(const Key('property-sort')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(sort));
      await tester.pumpAndSettle();
      expect(find.text('Sort: $sort'), findsOneWidget);
      expect(
        tester
            .widget<PropertyCard>(find.byType(PropertyCard).first)
            .property
            .id,
        sort == 'Highest Rent' ? fixture.id : secondId,
      );
    }
  });

  testWidgets('saving preferences refreshes server GET and backend matches', (
    tester,
  ) async {
    await openDiscovery(tester, backend);
    expect(backend.calls(matchesPath), 1);
    await tester.tap(find.byKey(const Key('match-preferences-action')));
    await tester.pumpAndSettle();
    expect(backend.calls(preferencesPath), 2);
    await tester.enterText(find.byKey(const Key('preference-city')), 'Colombo');
    backend.scores[fixture.id] = 83;
    await tapVisible(tester, find.text('Save preferences'));
    expect(backend.calls(preferencesPath, 'PUT'), 1);
    expect(backend.calls(preferencesPath), 3);
    expect(backend.calls(matchesPath), 2);
    expect(find.text('83% Match'), findsOneWidget);
    expect(find.text('Sort: AI Match'), findsOneWidget);
  });

  testWidgets('reset reloads server and removes all score badges', (
    tester,
  ) async {
    await openDiscovery(tester, backend);
    await tester.tap(find.byKey(const Key('match-preferences-action')));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('Reset saved preferences'));
    await tester.tap(find.text('Reset preferences'));
    await tester.pumpAndSettle();
    expect(find.text('Sort: Newest'), findsOneWidget);
    expect(find.text('Enter your preference'), findsOneWidget);
    expect(find.textContaining('% Match'), findsNothing);
    expect(backend.calls(preferencesPath, 'DELETE'), 1);
  });

  testWidgets(
    'each real resume reloads web values and favorites; duplicate resume events are deduplicated',
    (tester) async {
      await openDiscovery(tester, backend);
      backend.preferences = {'isConfigured': false};
      backend.favorites.add(fixture.id);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(backend.calls(preferencesPath), 2);
      expect(find.text('Enter your preference'), findsOneWidget);
      expect(find.textContaining('% Match'), findsNothing);
      expect(
        tester.widget<PropertyCard>(find.byType(PropertyCard)).saved,
        true,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(backend.calls(preferencesPath), 2);
      backend.preferences = {...savedPreferences, 'preferredCity': 'Colombo'};
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(backend.calls(preferencesPath), 3);
      expect(find.text('94% Match'), findsOneWidget);
    },
  );

  testWidgets(
    'heart writes server state and failed removal retains saved state with an error',
    (tester) async {
      await openDiscovery(tester, backend);
      await tester.ensureVisible(
        find.byKey(const ValueKey('property-favorite-${fixture.id}')),
      );
      await tester.tap(
        find.byKey(const ValueKey('property-favorite-${fixture.id}')),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<PropertyCard>(find.byType(PropertyCard)).saved,
        true,
      );
      backend.intercept = (request) async =>
          request.method == 'DELETE' ? http.Response('', 503) : null;
      await tester.tap(
        find.byKey(const ValueKey('property-favorite-${fixture.id}')),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<PropertyCard>(find.byType(PropertyCard)).saved,
        true,
      );
      expect(
        find.textContaining('Could not update this saved property'),
        findsOneWidget,
      );
      expect(backend.favorites, {fixture.id});
    },
  );

  testWidgets(
    'optional source failures leave card usable and retry controls visible',
    (tester) async {
      backend.intercept = (request) async =>
          [preferencesPath, favoritesPath].contains(request.url.path)
          ? http.Response('', 503)
          : null;
      await openDiscovery(tester, backend);
      expect(find.text('1 property'), findsOneWidget);
      expect(find.text('Retry preferences'), findsOneWidget);
      expect(find.text('Retry saved properties'), findsOneWidget);
      await scrollToVisible(tester, find.byType(PropertyCard), 180);
      expect(find.byType(PropertyCard), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('property-favorite-${fixture.id}')),
            )
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('card opens existing details with backend score and reasons', (
    tester,
  ) async {
    await openDiscovery(tester, backend);
    await scrollToVisible(tester, find.textContaining('A comfortable'), 200);
    await tester.tap(find.textContaining('A comfortable'));
    await tester.pumpAndSettle();
    final details = tester.widget<PropertyDetailsScreen>(
      find.byType(PropertyDetailsScreen),
    );
    expect(details.property.id, fixture.id);
    expect(details.matchScore, 94);
    expect(details.matchReasons, ['Matches your preferred city.']);
  });

  for (final scenario in [
    (size: const Size(320, 640), scale: 1.0),
    (size: const Size(360, 640), scale: 1.0),
    (size: const Size(360, 780), scale: 1.0),
    (size: const Size(393, 851), scale: 1.0),
    (size: const Size(320, 640), scale: 2.0),
  ]) {
    testWidgets(
      'discovery and cards fit ${scenario.size} at text scale ${scenario.scale}',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = scenario.size;
        tester.platformDispatcher.textScaleFactorTestValue = scenario.scale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        backend.properties = [
          {...fixture.propertyJson(), 'area': 1500.5, 'areaUnit': 'sqft'},
        ];
        await openDiscovery(tester, backend);
        await scrollToVisible(
          tester,
          find.byKey(const ValueKey('property-favorite-${fixture.id}')),
          100,
        );
        final heart = tester.getRect(
          find.byKey(const ValueKey('property-favorite-${fixture.id}')),
        );
        expect(heart.right, lessThanOrEqualTo(scenario.size.width));
        await scrollToVisible(
          tester,
          find.descendant(
            of: find.byType(PropertyCard),
            matching: find.text('Available'),
          ),
          180,
        );
        expect(find.text('Unavailable'), findsNothing);
        expect(tester.takeException(), isNull);
        final title = tester.widget<Text>(find.textContaining('A comfortable'));
        expect(title.maxLines, isNull);
      },
    );
  }

  testWidgets(
    'reference card keeps rent beside the title and shows real amenity pills',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 780);
      addTearDown(tester.view.reset);
      backend.properties = [
        {
          ...fixture.propertyJson(),
          'amenities': ['Wi-Fi', 'Parking', 'Garden', 'Gym', 'Balcony'],
        },
      ];
      await openDiscovery(tester, backend);
      await scrollToVisible(
        tester,
        find.byKey(const ValueKey('property-title-${fixture.id}')),
        150,
      );
      final title = tester.getRect(
        find.byKey(const ValueKey('property-title-${fixture.id}')),
      );
      final rent = tester.getRect(
        find.byKey(const ValueKey('property-rent-${fixture.id}')),
      );
      expect(rent.left, greaterThan(title.right));
      expect(rent.top, title.top);
      expect(find.text('LKR 125,000'), findsOneWidget);
      await scrollToVisible(tester, find.text('+2 more'), 150);
      expect(find.text('Wi-Fi'), findsOneWidget);
      expect(find.text('Parking'), findsOneWidget);
      expect(find.text('Garden'), findsOneWidget);
      expect(find.text('Gym'), findsNothing);
      expect(find.text('Verified'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'reference card stacks rent below a long title at enlarged text',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 640);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await openDiscovery(tester, backend);
      await scrollToVisible(
        tester,
        find.byKey(const ValueKey('property-rent-${fixture.id}')),
        150,
      );
      final title = tester.getRect(
        find.byKey(const ValueKey('property-title-${fixture.id}')),
      );
      final rent = tester.getRect(
        find.byKey(const ValueKey('property-rent-${fixture.id}')),
      );
      expect(rent.top, greaterThan(title.bottom));
      expect(rent.left, title.left);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'image API failure keeps the property and real match usable with a photo fallback',
    (tester) async {
      backend.intercept = (request) async =>
          request.url.path.endsWith('/images') ? http.Response('', 503) : null;
      await openDiscovery(tester, backend);
      expect(
        find.byKey(const ValueKey('property-photo-fallback')),
        findsOneWidget,
      );
      expect(find.text('94% Match'), findsOneWidget);
      expect(find.text('1 property'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
