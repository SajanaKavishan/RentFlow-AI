import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rentflow_mobile/features/properties/models/discovery_filters.dart';
import 'package:rentflow_mobile/features/properties/models/property.dart';
import 'package:rentflow_mobile/features/properties/widgets/discovery_filter_panel.dart';
import 'package:rentflow_mobile/features/properties/widgets/property_card.dart';
import 'package:rentflow_mobile/shared/theme/app_theme.dart';

import 'helpers/discovery_backend.dart';
import 'match_preferences_test.dart' show tapVisible, scrollToVisible;
import 'property_details_test.dart' as fixture;
import 'property_discovery_test.dart' show openDiscovery;

const channel = MethodChannel('rentflow/places');

Future<void> openPanel(
  WidgetTester tester, {
  DiscoveryFilters initial = const DiscoveryFilters(),
  ValueChanged<DiscoveryFilters>? onApply,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.build(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: DiscoveryFilterPanel(
            initial: initial,
            properties: [
              Property.fromJson({
                ...fixture.propertyJson(),
                'city': 'Kurunegala',
                'amenityDetails': [
                  {'canonicalKey': 'wifi', 'name': 'Wireless internet'},
                ],
              }),
            ],
            onApply: onApply ?? (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  testWidgets(
    'filter expands within the list, pushes results down and discards unapplied changes on close',
    (tester) async {
      final backend = DiscoveryBackend();
      addTearDown(backend.close);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 1500);
      addTearDown(tester.view.reset);
      await openDiscovery(tester, backend);
      final before = tester.getTopLeft(find.byType(PropertyCard)).dy;
      await tester.tap(find.byKey(const Key('property-filter')));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(
        tester.getTopLeft(find.byType(PropertyCard)).dy,
        greaterThan(before + 300),
      );
      await tester.enterText(
        find.byKey(const Key('filter-city')),
        'No matching town',
      );
      await tester.pump();
      expect(find.text('Show results'), findsOneWidget);
      expect(find.text('1 property'), findsOneWidget);
      await tester.tap(find.byKey(const Key('property-filter')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('discovery-filter-panel')), findsNothing);
      expect(find.text('1 property'), findsOneWidget);
      await tester.tap(find.byKey(const Key('property-filter')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('filter-city')))
            .controller!
            .text,
        '',
      );
    },
  );

  testWidgets(
    'Show results applies rent and selected amenities without displaying a count',
    (tester) async {
      DiscoveryFilters? applied;
      await openPanel(tester, onApply: (filters) => applied = filters);
      expect(find.text('Show results'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('filter-amenity-wireless internet')),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('filter-amenity-parking')));
      await tester.pump();
      expect(find.text('Show results'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('filter-amenity-parking')));
      await tester.tap(find.byKey(const Key('filter-view-more')));
      await tester.pumpAndSettle();
      await tapVisible(
        tester,
        find.byKey(const ValueKey('filter-amenity-custom terrace')),
      );
      await tapVisible(tester, find.byKey(const Key('filter-show-results')));
      expect(applied!.amenities, {'custom terrace'});
      expect(
        applied!.includes(Property.fromJson(fixture.propertyJson()), ''),
        true,
      );
      await openPanel(tester, onApply: (filters) => applied = filters);
      // Recreate a new draft so the previous selection does not persist between panels.
      tester
          .widget<Slider>(find.byKey(const Key('filter-max-rent')))
          .onChanged!(100000);
      await tester.pump();
      expect(find.text('Show results'), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key('filter-show-results')));
      expect(applied!.maxRent, 100000);
    },
  );

  testWidgets(
    'one letter requests Google towns after debounce and selection uses resolved city',
    (tester) async {
      final requests = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            requests.add(call);
            return switch (call.method) {
              'suggestTowns' => [
                {
                  'placeId': 'google-kurunegala',
                  'town': 'Kurunegala',
                  'description': 'Sri Lanka',
                },
              ],
              'selectTown' => 'Kurunegala',
              _ => null,
            };
          });
      DiscoveryFilters? applied;
      await openPanel(tester, onApply: (filters) => applied = filters);
      await tester.enterText(find.byKey(const Key('filter-city')), 'K');
      await tester.pump(const Duration(milliseconds: 349));
      expect(requests.where((call) => call.method == 'suggestTowns'), isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pumpAndSettle();
      final request = requests.singleWhere(
        (call) => call.method == 'suggestTowns',
      );
      expect(request.arguments['query'], 'K');
      expect(find.text('Google Maps'), findsOneWidget);
      await tapVisible(
        tester,
        find.byKey(const ValueKey('town-google-kurunegala')),
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('filter-city')))
            .controller!
            .text,
        'Kurunegala',
      );
      await tapVisible(tester, find.byKey(const Key('filter-show-results')));
      expect(applied!.city, 'Kurunegala');
      expect(
        requests
            .singleWhere((call) => call.method == 'selectTown')
            .arguments['placeId'],
        'google-kurunegala',
      );
    },
  );

  testWidgets(
    'stale town response and clearing cannot overwrite the current query',
    (tester) async {
      final first = Completer<dynamic>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method != 'suggestTowns') return null;
            if (call.arguments['query'] == 'K') return first.future;
            return [
              {'placeId': 'galle', 'town': 'Galle', 'description': 'Sri Lanka'},
            ];
          });
      await openPanel(tester);
      await tester.enterText(find.byKey(const Key('filter-city')), 'K');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.enterText(find.byKey(const Key('filter-city')), 'G');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      first.complete([
        {'placeId': 'old', 'town': 'Kurunegala', 'description': 'Sri Lanka'},
      ]);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('town-galle')), findsOneWidget);
      expect(find.byKey(const ValueKey('town-old')), findsNothing);
      await tester.tap(find.byTooltip('Clear location'));
      await tester.pumpAndSettle();
      expect(find.text('Google Maps'), findsNothing);
      expect(find.text('Show results'), findsOneWidget);
    },
  );

  testWidgets('Google failure leaves manual town filtering usable', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'suggestTowns') {
            throw PlatformException(code: 'places_unavailable');
          }
          return null;
        });
    DiscoveryFilters? applied;
    await openPanel(tester, onApply: (filters) => applied = filters);
    await tester.enterText(find.byKey(const Key('filter-city')), 'Kurunegala');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.textContaining('Town suggestions unavailable'), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('filter-show-results')));
    expect(applied!.city, 'Kurunegala');
    expect(tester.takeException(), isNull);
  });

  test(
    'amenities require every selected option and match canonical detail keys',
    () {
      final property = Property.fromJson({
        ...fixture.propertyJson(),
        'amenities': ['Custom terrace'],
        'amenityDetails': [
          {'canonicalKey': 'wifi', 'name': 'Wireless internet'},
        ],
      });
      expect(
        const DiscoveryFilters(
          amenities: {'Wi-Fi', 'Custom terrace'},
        ).includes(property, ''),
        true,
      );
      expect(
        const DiscoveryFilters(
          amenities: {'wifi', 'parking'},
        ).includes(property, ''),
        false,
      );
      expect(
        const DiscoveryFilters(
          amenities: {'wifi'},
        ).withQuickFilters(availableOnly: true, bedrooms: 2).amenities,
        {'wifi'},
      );
      expect(const DiscoveryFilters(maxRent: 0).includes(property, ''), false);
    },
  );

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'inline filters including all amenities fit 320px at scale $scale',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 640);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await openPanel(tester);
        await tapVisible(tester, find.byKey(const Key('filter-view-more')));
        await scrollToVisible(
          tester,
          find.byKey(const Key('filter-show-results')),
          150,
        );
      },
    );
  }
}
