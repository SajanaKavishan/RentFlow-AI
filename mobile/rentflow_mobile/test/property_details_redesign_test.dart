import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rentflow_mobile/features/properties/models/property.dart';
import 'package:rentflow_mobile/features/properties/screens/property_details_screen.dart';
import 'package:rentflow_mobile/features/properties/widgets/property_photo.dart';
import 'package:rentflow_mobile/shared/theme/app_theme.dart';

import 'helpers/discovery_backend.dart';
import 'match_preferences_test.dart' show scrollToVisible, tapVisible;
import 'property_details_test.dart' as fixture;

const mapsChannel = MethodChannel('plugins.flutter.io/url_launcher');
const landlord = {
  'displayName': 'Maya Perera',
  'memberSinceYear': 2022,
  'hasProfileImage': false,
};

Map<String, dynamic> detailedListing() => {
  ...fixture.propertyJson(),
  'title': 'Garden Apartment',
  'area': 15,
  'areaType': 'LandArea',
  'areaUnit': 'perch',
  'availableFrom': '2026-10-15',
  'latitude': 6.93,
  'longitude': 79.84,
  'googlePlaceId': 'real-place-id',
  'amenityDetails': [
    {'canonicalKey': 'wifi', 'name': 'Wi-Fi'},
    {'canonicalKey': null, 'name': 'Custom terrace'},
  ],
};

Future<void> openDetails(
  WidgetTester tester,
  DiscoveryBackend backend, {
  Map<String, dynamic>? listing,
  int? score,
  List<String> reasons = const [],
}) async {
  backend.properties = [listing ?? detailedListing()];
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.build(),
      home: PropertyDetailsScreen(
        property: Property.fromJson(backend.properties.single),
        propertyApiService: backend.service,
        matchScore: score,
        matchReasons: reasons,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late DiscoveryBackend backend;
  setUp(() {
    backend = DiscoveryBackend();
    backend.intercept = (request) async =>
        request.url.path.endsWith('/landlord-summary')
        ? DiscoveryBackend.json(landlord)
        : null;
  });
  tearDown(() {
    backend.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(mapsChannel, null);
  });

  testWidgets(
    'edge-to-edge gallery orders primary first, pages real images and updates dots',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 780);
      addTearDown(tester.view.reset);
      backend.intercept = (request) async {
        if (request.url.path.endsWith('/images')) {
          return DiscoveryBackend.json([
            {'id': 'second', 'sortOrder': 0, 'isPrimary': false},
            {'id': 'primary', 'sortOrder': 9, 'isPrimary': true},
          ]);
        }
        if (request.url.path.endsWith('/url')) {
          return DiscoveryBackend.json({
            'url': 'https://cdn.example/property.jpg',
          });
        }
        if (request.url.path.endsWith('/landlord-summary')) {
          return DiscoveryBackend.json(landlord);
        }
        return null;
      };
      await openDetails(tester, backend);
      final hero = tester.getRect(find.byKey(const Key('details-gallery')));
      expect(hero.left, 0);
      expect(hero.width, 360);
      expect(hero.height, inInclusiveRange(210, 240));
      expect(
        tester
            .widget<PropertyPhoto>(find.byType(PropertyPhoto).first)
            .image!
            .id,
        'primary',
      );
      expect(
        tester
            .widget<AnimatedContainer>(
              find.byKey(const ValueKey('details-photo-dot-0')),
            )
            .constraints!
            .maxWidth,
        16,
      );
      await tester.drag(
        find.byKey(const Key('details-gallery-pages')),
        const Offset(-330, 0),
      );
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Photo 2 of 2'), findsOneWidget);
      expect(
        tester
            .widget<AnimatedContainer>(
              find.byKey(const ValueKey('details-photo-dot-1')),
            )
            .constraints!
            .maxWidth,
        16,
      );
      expect(backend.calls('/api/properties/${fixture.id}/images'), 1);
    },
  );

  testWidgets(
    'favorite starts from server state and failed removal keeps the filled heart',
    (tester) async {
      backend.favorites.add(fixture.id);
      await openDetails(tester, backend);
      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
      backend.intercept = (request) async => request.method == 'DELETE'
          ? http.Response('', 503)
          : request.url.path.endsWith('/landlord-summary')
          ? DiscoveryBackend.json(landlord)
          : null;
      await tester.tap(find.byKey(const Key('details-favorite')));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
      expect(
        find.textContaining('Could not update this saved property'),
        findsOneWidget,
      );
      expect(backend.favorites, {fixture.id});
      expect(backend.calls('$favoritesPath/${fixture.id}', 'DELETE'), 1);
      expect(
        backend.requests
            .firstWhere((request) => request.method == 'DELETE')
            .headers['Authorization'],
        'Bearer tenant-token',
      );
    },
  );

  testWidgets(
    'favorite add only changes after success and blocks concurrent taps',
    (tester) async {
      final response = Completer<http.Response>();
      backend.intercept = (request) async {
        if (request.method == 'PUT') return response.future;
        if (request.url.path.endsWith('/landlord-summary')) {
          return DiscoveryBackend.json(landlord);
        }
        return null;
      };
      await openDetails(tester, backend);
      await tester.tap(find.byKey(const Key('details-favorite')));
      await tester.pump();
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('details-favorite')))
            .onPressed,
        isNull,
      );
      expect(backend.calls('$favoritesPath/${fixture.id}', 'PUT'), 1);
      response.complete(http.Response('', 204));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
    },
  );

  testWidgets('favorite read failure can retry without breaking details', (
    tester,
  ) async {
    backend.intercept = (request) async =>
        request.url.path == favoritesPath ? http.Response('', 503) : null;
    await openDetails(tester, backend);
    expect(find.byTooltip('Retry saved properties'), findsOneWidget);
    expect(find.text('Book Viewing'), findsOneWidget);
    backend.intercept = null;
    await tester.tap(find.byKey(const Key('details-favorite')));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Save property'), findsOneWidget);
    expect(backend.calls(favoritesPath), 2);
  });

  testWidgets(
    'real title rent match facts availability and custom amenities are truthful',
    (tester) async {
      await openDetails(
        tester,
        backend,
        score: 94,
        reasons: ['Matches your preferred city.'],
      );
      expect(find.text('Garden Apartment'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('details-address'))).data,
        '42 Garden Road, Colombo',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('details-rent')))
            .textSpan!
            .toPlainText(),
        'Rs. 125,000 /mo',
      );
      expect(find.text('AI Match'), findsOneWidget);
      expect(find.text('94%'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byKey(const Key('details-match-progress')),
            )
            .value,
        0.94,
      );
      expect(find.text('3 Beds'), findsOneWidget);
      expect(find.text('2 Baths'), findsOneWidget);
      expect(find.text('15 perches'), findsOneWidget);
      expect(find.text('Land area'), findsOneWidget);
      expect(find.text('Available from'), findsOneWidget);
      expect(find.text('Oct 15, 2026'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('details-amenity-Custom terrace')),
        findsOneWidget,
      );
      await scrollToVisible(tester, find.text('Why this matches'), 200);
      expect(find.text('Matches your preferred city.'), findsOneWidget);
      expect(find.textContaining('reviews'), findsNothing);
      expect(find.text('Message'), findsNothing);
      expect(find.textContaining('Verified'), findsNothing);
      expect(find.byIcon(Icons.share), findsNothing);
    },
  );

  for (final score in <int?>[null, -1, 101]) {
    testWidgets('rent-only card omits absent or invalid match score $score', (
      tester,
    ) async {
      await openDetails(tester, backend, score: score);
      expect(find.text('AI Match'), findsNothing);
      expect(find.byKey(const Key('details-match-progress')), findsNothing);
      expect(find.text('Why this matches'), findsNothing);
    });
  }

  testWidgets(
    'real zero score is visible and missing area is not replaced with square feet',
    (tester) async {
      await openDetails(
        tester,
        backend,
        listing: fixture.propertyJson(),
        score: 0,
      );
      expect(find.text('0%'), findsOneWidget);
      expect(find.text('Area not listed'), findsOneWidget);
      expect(find.text('Available now'), findsNWidgets(2));
      expect(find.text('Available from'), findsNothing);
      expect(find.textContaining('sq ft'), findsNothing);
    },
  );

  testWidgets(
    'current unavailable response hides future date, creation actions and unsaved favorite',
    (tester) async {
      final listing = detailedListing();
      backend.intercept = (request) async =>
          request.url.path == '/api/properties/${fixture.id}'
          ? DiscoveryBackend.json({...listing, 'isAvailable': false})
          : null;
      await openDetails(tester, backend, listing: listing);
      expect(find.text('Currently unavailable'), findsOneWidget);
      expect(find.text('Oct 15, 2026'), findsNothing);
      expect(find.text('Book Viewing'), findsNothing);
      expect(find.text('Apply Now'), findsNothing);
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('details-favorite')))
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets(
    'long real description expands and collapses without changing its content',
    (tester) async {
      final description = List.filled(
        25,
        'Bright rooms with a quiet garden view and space for family living.',
      ).join(' ');
      await openDetails(
        tester,
        backend,
        listing: {...detailedListing(), 'description': description},
      );
      await tapVisible(tester, find.byKey(const Key('details-read-more')));
      final expanded = tester.widget<Text>(
        find.byKey(const Key('details-description')),
      );
      expect(expanded.data, description);
      expect(expanded.maxLines, isNull);
      await tapVisible(tester, find.text('Read less'));
      expect(
        tester
            .widget<Text>(find.byKey(const Key('details-description')))
            .maxLines,
        4,
      );
    },
  );

  for (final withCoordinates in [true, false]) {
    testWidgets(
      'external Maps uses real ${withCoordinates ? 'coordinates and place ID' : 'address'}',
      (tester) async {
        MethodCall? launched;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(mapsChannel, (call) async {
              launched = call;
              return true;
            });
        final listing = withCoordinates
            ? detailedListing()
            : fixture.propertyJson();
        await openDetails(tester, backend, listing: listing);
        await tapVisible(tester, find.byKey(const Key('details-open-maps')));
        final uri = Uri.parse(launched!.arguments['url'] as String);
        expect(uri.host, 'www.google.com');
        expect(
          uri.queryParameters['query'],
          withCoordinates ? '6.93,79.84' : '42 Garden Road, Colombo',
        );
        expect(
          uri.queryParameters['query_place_id'],
          withCoordinates ? 'real-place-id' : null,
        );
        expect(launched!.arguments['useWebView'], false);
      },
    );
  }

  testWidgets(
    'Maps launch failure shows a usable error without losing sticky actions',
    (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(mapsChannel, (_) async => false);
      await openDetails(tester, backend);
      await tapVisible(tester, find.byKey(const Key('details-open-maps')));
      expect(find.text('Unable to open Maps.'), findsOneWidget);
      expect(find.text('Apply Now'), findsOneWidget);
    },
  );

  for (final hasImage in [false, true]) {
    testWidgets(
      'public landlord ${hasImage ? 'failed photo' : 'absent photo'} falls back to initials',
      (tester) async {
        backend.intercept = (request) async =>
            request.url.path.endsWith('/landlord-summary')
            ? DiscoveryBackend.json({...landlord, 'hasProfileImage': hasImage})
            : null;
        await openDetails(tester, backend);
        await scrollToVisible(
          tester,
          find.byKey(const Key('details-landlord')),
          250,
        );
        expect(find.text('MP'), findsOneWidget);
        expect(find.text('Maya Perera'), findsOneWidget);
        expect(find.text('Member since 2022'), findsOneWidget);
        expect(find.textContaining('Verified'), findsNothing);
        expect(find.text('Message'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('gallery Back returns to the property list route', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => PropertyDetailsScreen(
                    property: Property.fromJson(detailedListing()),
                    propertyApiService: backend.service,
                  ),
                ),
              ),
              child: const Text('Open property'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open property'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('details-back')));
    await tester.pumpAndSettle();
    expect(find.text('Open property'), findsOneWidget);
    expect(find.byType(PropertyDetailsScreen), findsNothing);
  });

  for (final scenario in [
    (pixels: const Size(720, 1280), dpr: 2.0, scale: 1.0),
    (pixels: const Size(720, 1560), dpr: 2.0, scale: 1.0),
    (pixels: const Size(1080, 2340), dpr: 3.0, scale: 1.0),
    (pixels: const Size(640, 1280), dpr: 2.0, scale: 2.0),
  ]) {
    testWidgets(
      'details stay readable and CTAs stay safe at ${scenario.pixels} / ${scenario.dpr} and ${scenario.scale}x text',
      (tester) async {
        tester.view.devicePixelRatio = scenario.dpr;
        tester.view.physicalSize = scenario.pixels;
        tester.view.padding = FakeViewPadding(
          top: 24 * scenario.dpr,
          bottom: 24 * scenario.dpr,
        );
        tester.platformDispatcher.textScaleFactorTestValue = scenario.scale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final longAmenity = List.filled(
          8,
          'Private terrace overlooking the garden',
        ).join(' ');
        await openDetails(
          tester,
          backend,
          score: 94,
          listing: {
            ...detailedListing(),
            'title': fixture.propertyJson()['title'],
            'address': List.filled(
              5,
              '42 Garden Road near the gardens',
            ).join(' '),
            'amenityDetails': [
              {'canonicalKey': null, 'name': longAmenity},
            ],
          },
        );
        final before = tester.getRect(find.byKey(const Key('details-cta-bar')));
        final viewing = tester.getRect(
          find.byKey(const Key('details-book-viewing')),
        );
        final apply = tester.getRect(
          find.byKey(const Key('details-apply-now')),
        );
        expect(viewing.height, apply.height);
        expect(viewing.right, lessThan(apply.left));
        expect(
          apply.bottom,
          lessThanOrEqualTo(scenario.pixels.height / scenario.dpr - 24),
        );
        await scrollToVisible(
          tester,
          find.byKey(const Key('details-landlord')),
          180,
        );
        await tester.ensureVisible(find.text('View other properties'));
        await tester.pumpAndSettle();
        expect(find.text('View landlord profile'), findsNothing);
        expect(
          tester.getTopLeft(find.text('View other properties')).dy,
          greaterThanOrEqualTo(24),
        );
        expect(
          tester.getRect(find.byKey(const Key('details-cta-bar'))),
          before,
        );
        expect(
          tester.getBottomLeft(find.byKey(const Key('details-landlord'))).dy,
          lessThanOrEqualTo(before.top),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
