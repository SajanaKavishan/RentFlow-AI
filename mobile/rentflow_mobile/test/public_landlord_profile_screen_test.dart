import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rentflow_mobile/features/properties/screens/property_details_screen.dart';
import 'package:rentflow_mobile/features/properties/screens/public_landlord_profile_screen.dart';
import 'package:rentflow_mobile/features/properties/widgets/property_card.dart';
import 'package:rentflow_mobile/features/properties/widgets/property_photo.dart';
import 'package:rentflow_mobile/features/properties/widgets/public_landlord_avatar.dart';
import 'package:rentflow_mobile/shared/theme/app_theme.dart';

import 'helpers/discovery_backend.dart';
import 'match_preferences_test.dart' show scrollToVisible, tapVisible;
import 'property_details_redesign_test.dart' show openDetails;
import 'property_details_test.dart' as fixture;

const summaryPath = '/api/properties/${fixture.id}/landlord-summary';
const listingsPath = '$summaryPath/properties';
const otherPropertyId = '33333333-3333-4333-8333-333333333333';
const summary = {
  'displayName': 'Maya Perera',
  'memberSinceYear': 2022,
  'hasProfileImage': false,
  // Unsupported fields must never be rendered, even if a server sends them.
  'email': 'private@example.com',
  'phoneNumber': '+94770000000',
  'company': 'Private company',
  'rating': 5,
};

Future<void> openProfile(
  WidgetTester tester,
  DiscoveryBackend backend, {
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.build(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: PublicLandlordProfileScreen(
        propertyId: fixture.id,
        propertyApiService: backend.service,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late DiscoveryBackend backend;
  setUp(() {
    backend = DiscoveryBackend();
    backend.properties = [
      {
        ...fixture.propertyJson(),
        'id': otherPropertyId,
        'title': 'Garden Apartment',
      },
    ];
    backend.intercept = (request) async {
      if (request.url.path == summaryPath) {
        return DiscoveryBackend.json(summary);
      }
      if (request.url.path == listingsPath) {
        return DiscoveryBackend.json(backend.properties);
      }
      return null;
    };
  });
  tearDown(() => backend.close());

  testWidgets(
    'safe identity, real property cards and no public contact actions',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await openProfile(tester, backend);
      expect(find.text('Maya Perera'), findsNWidgets(2));
      expect(find.text('Member since 2022'), findsOneWidget);
      expect(find.text('Other properties'), findsOneWidget);
      expect(find.text('1 available property'), findsOneWidget);
      final avatar = tester.widget<PublicLandlordAvatar>(
        find.byType(PublicLandlordAvatar),
      );
      expect(avatar.size, inInclusiveRange(64, 72));
      expect(
        tester
            .getSize(find.byKey(const Key('landlord-listings-identity')))
            .height,
        lessThan(120),
      );
      expect(
        find.bySemanticsLabel(RegExp('Maya Perera profile image')),
        findsOneWidget,
      );
      semantics.dispose();
      expect(find.text('MP'), findsOneWidget);
      expect(find.byType(PropertyCard), findsOneWidget);
      await scrollToVisible(tester, find.text('Garden Apartment'), 200);
      expect(find.textContaining('Colombo'), findsOneWidget);
      expect(find.textContaining('125,000'), findsOneWidget);
      expect(find.textContaining('private@example.com'), findsNothing);
      expect(find.textContaining('+94770000000'), findsNothing);
      expect(find.textContaining('Private company'), findsNothing);
      expect(find.textContaining('Contact'), findsNothing);
      expect(backend.calls(summaryPath), 1);
      expect(backend.calls(listingsPath), 1);
      expect(
        backend.requests.any((request) => request.url.path.contains('/users')),
        isFalse,
      );
      expect(
        backend.requests
            .firstWhere((request) => request.url.path == listingsPath)
            .headers['Authorization'],
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'profile image uses the safe endpoint and falls back to initials',
    (tester) async {
      backend.intercept = (request) async {
        if (request.url.path == summaryPath) {
          return DiscoveryBackend.json({...summary, 'hasProfileImage': true});
        }
        if (request.url.path == listingsPath) return DiscoveryBackend.json([]);
        return null;
      };
      await openProfile(tester, backend);
      final image = tester.widget<Image>(find.byType(Image));
      expect(
        (image.image as NetworkImage).url,
        'https://test.example$summaryPath/image',
      );
      expect(find.text('MP'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'details card opens profile, another listing opens normal details, back restores each screen',
    (tester) async {
      final other = {
        ...fixture.propertyJson(),
        'id': '33333333-3333-4333-8333-333333333333',
        'title': 'Orchard House',
      };
      backend.intercept = (request) async {
        if (request.url.path.endsWith('/landlord-summary')) {
          return DiscoveryBackend.json(summary);
        }
        if (request.url.path == listingsPath) {
          return DiscoveryBackend.json([other]);
        }
        if (request.url.path == '/api/properties/${other['id']}') {
          return DiscoveryBackend.json(other);
        }
        return null;
      };
      await openDetails(tester, backend);
      expect(find.text('View landlord profile'), findsNothing);
      final semantics = tester.ensureSemantics();
      await scrollToVisible(tester, find.text('View other properties'), 200);
      expect(
        find.bySemanticsLabel(RegExp('View other properties by Maya Perera')),
        findsOneWidget,
      );
      await tapVisible(tester, find.text('View other properties'));
      semantics.dispose();
      expect(find.byType(PublicLandlordProfileScreen), findsOneWidget);
      expect(
        tester
            .widget<PublicLandlordProfileScreen>(
              find.byType(PublicLandlordProfileScreen),
            )
            .propertyId,
        fixture.id,
      );
      expect(backend.calls(listingsPath), 1);
      await tapVisible(tester, find.text('Orchard House'));
      expect(find.byType(PropertyDetailsScreen), findsOneWidget);
      expect(find.text('Orchard House'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(PublicLandlordProfileScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(PropertyDetailsScreen), findsOneWidget);
      expect(find.text('Garden Apartment'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('empty listings retain the public identity', (tester) async {
    backend.properties = [];
    await openProfile(tester, backend);
    expect(find.text('Maya Perera'), findsNWidgets(2));
    expect(
      find.text('No other properties are currently available.'),
      findsOneWidget,
    );
    expect(find.byType(PropertyCard), findsNothing);
    expect(find.text('0 available properties'), findsOneWidget);
  });

  testWidgets(
    'the originating property alone produces the honest other-properties empty state',
    (tester) async {
      backend.properties = [fixture.propertyJson()];
      await openProfile(tester, backend);
      expect(find.text('Other properties'), findsOneWidget);
      expect(find.text('0 available properties'), findsOneWidget);
      expect(
        find.text('No other properties are currently available.'),
        findsOneWidget,
      );
      expect(find.byType(PropertyCard), findsNothing);
      expect(find.text('Member since 2022'), findsOneWidget);
    },
  );

  testWidgets(
    'real count excludes the current property and keeps multiple available listings',
    (tester) async {
      backend.properties = [
        {...fixture.propertyJson(), 'id': fixture.id.toUpperCase()},
        {
          ...fixture.propertyJson(),
          'id': otherPropertyId,
          'title': 'Garden Apartment',
        },
        {
          ...fixture.propertyJson(),
          'id': '44444444-4444-4444-8444-444444444444',
          'title': 'Orchard House',
        },
      ];
      await openProfile(tester, backend);
      expect(find.text('2 available properties'), findsOneWidget);
      expect(
        find.byKey(ValueKey('property-title-${fixture.id.toUpperCase()}')),
        findsNothing,
      );
      await scrollToVisible(tester, find.text('Garden Apartment'), 200);
      expect(find.text('Garden Apartment'), findsOneWidget);
      await scrollToVisible(tester, find.text('Orchard House'), 200);
      expect(find.text('Orchard House'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final contactEnabled in [false, true]) {
    testWidgets(
      'long names, ${contactEnabled ? 'enabled' : 'disabled'} contact, and 2x text fit a narrow phone',
      (tester) async {
        const longName = 'Pansilu Ruwantha Wijesinghe Arachchilage Gunawardena';
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 780);
        addTearDown(tester.view.reset);
        backend.intercept = (request) async {
          if (request.url.path == summaryPath) {
            return DiscoveryBackend.json({...summary, 'displayName': longName});
          }
          if (request.url.path == listingsPath) {
            return DiscoveryBackend.json(backend.properties);
          }
          if (request.url.path.endsWith('/landlord-contact')) {
            return contactEnabled
                ? DiscoveryBackend.json({
                    'displayName': longName,
                    'phoneNumber': '+94771234567',
                  })
                : http.Response('', 204);
          }
          return null;
        };
        await openProfile(tester, backend, textScale: 2);
        final appBar = tester.widget<AppBar>(find.byType(AppBar));
        final title = appBar.title! as Text;
        expect(title.data, longName);
        expect(title.maxLines, 1);
        expect(title.overflow, TextOverflow.ellipsis);
        expect(
          MediaQuery.textScalerOf(
            tester.element(find.byType(PublicLandlordProfileScreen)),
          ).scale(14),
          28,
        );
        expect(find.text(longName), findsNWidgets(2));
        expect(find.text('Member since 2022'), findsOneWidget);
        expect(find.text('PR'), findsOneWidget);
        if (contactEnabled) {
          await scrollToVisible(tester, find.text('Call landlord'), 200);
          expect(find.text('+94771234567'), findsOneWidget);
          expect(
            tester
                .getSize(find.widgetWithText(FilledButton, 'Call landlord'))
                .height,
            greaterThanOrEqualTo(48),
          );
        } else {
          expect(find.text('Contact landlord'), findsNothing);
          expect(find.text('Call landlord'), findsNothing);
        }
        await scrollToVisible(tester, find.text('Garden Apartment'), 200);
        expect(find.text('Garden Apartment'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('unavailable profile hides server errors and retries safely', (
    tester,
  ) async {
    var failed = true;
    backend.intercept = (request) async {
      if (request.url.path == summaryPath) {
        return failed
            ? http.Response('private@example.com +94770000000', 404)
            : DiscoveryBackend.json(summary);
      }
      if (request.url.path == listingsPath) return DiscoveryBackend.json([]);
      return null;
    };
    await openProfile(tester, backend);
    expect(find.text('Landlord properties unavailable'), findsOneWidget);
    expect(find.textContaining('private@example.com'), findsNothing);
    expect(backend.calls(listingsPath), 0);
    failed = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Maya Perera'), findsNWidgets(2));
    expect(backend.calls(summaryPath), 2);
  });

  testWidgets(
    'listings failure preserves identity and rejects unavailable listings',
    (tester) async {
      backend.properties = [fixture.propertyJson(available: false)];
      await openProfile(tester, backend);
      expect(find.text('Maya Perera'), findsNWidgets(2));
      expect(find.text('Properties unavailable'), findsOneWidget);
      expect(find.byType(PropertyCard), findsNothing);
      backend.properties = [];
      await tapVisible(tester, find.text('Try again'));
      expect(
        find.text('No other properties are currently available.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('profile and listings have separate loading states', (
    tester,
  ) async {
    final profile = Completer<http.Response>();
    final listings = Completer<http.Response>();
    backend.intercept = (request) async {
      if (request.url.path == summaryPath) return profile.future;
      if (request.url.path == listingsPath) return listings.future;
      return null;
    };
    await tester.pumpWidget(
      MaterialApp(
        home: PublicLandlordProfileScreen(
          propertyId: fixture.id,
          propertyApiService: backend.service,
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Loading landlord properties'), findsOneWidget);
    expect(find.text('Landlord properties'), findsOneWidget);
    expect(find.textContaining('available propert'), findsNothing);
    expect(backend.calls(listingsPath), 0);
    profile.complete(DiscoveryBackend.json(summary));
    await tester.pump();
    await tester.pump();
    expect(find.text('Maya Perera'), findsNWidgets(2));
    expect(find.text('Loading properties'), findsOneWidget);
    expect(find.textContaining('available propert'), findsNothing);
    listings.complete(DiscoveryBackend.json([]));
    await tester.pumpAndSettle();
    expect(
      find.text('No other properties are currently available.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'property image failure does not fail the profile and favorite uses existing API',
    (tester) async {
      backend.intercept = (request) async {
        if (request.url.path == summaryPath) {
          return DiscoveryBackend.json(summary);
        }
        if (request.url.path == listingsPath) {
          return DiscoveryBackend.json(backend.properties);
        }
        if (request.url.path.endsWith('/images')) return http.Response('', 503);
        return null;
      };
      await openProfile(tester, backend);
      expect(find.text('Maya Perera'), findsNWidgets(2));
      expect(find.byType(PropertyPhotoFallback), findsOneWidget);
      await tapVisible(
        tester,
        find.byKey(const ValueKey('property-favorite-$otherPropertyId')),
      );
      expect(backend.favorites, {otherPropertyId});
      expect(backend.calls('$favoritesPath/$otherPropertyId', 'PUT'), 1);
      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
    },
  );

  for (final width in [320.0, 360.0, 430.0]) {
    testWidgets('profile fits $width width with large text', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 780);
      addTearDown(tester.view.reset);
      await openProfile(tester, backend, textScale: 2);
      expect(find.text('Maya Perera'), findsNWidgets(2));
      await scrollToVisible(tester, find.text('Garden Apartment'), 200);
      expect(tester.takeException(), isNull);
    });
  }
}
