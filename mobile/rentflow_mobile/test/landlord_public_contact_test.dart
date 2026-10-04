import 'dart:async';
import 'dart:io';
import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rentflow_mobile/features/properties/widgets/landlord_contact_card.dart';
import 'package:rentflow_mobile/shared/theme/app_theme.dart';

import 'helpers/discovery_backend.dart';
import 'match_preferences_test.dart' show tapVisible, scrollToVisible;
import 'property_details_redesign_test.dart' as details;
import 'public_landlord_profile_screen_test.dart' as profile;
import 'property_details_test.dart' as fixture;

const contactPath = '/api/properties/${fixture.id}/landlord-contact';
const phone = '+94 77 123 4567';
const channel = MethodChannel('plugins.flutter.io/url_launcher');

void main() {
  late DiscoveryBackend backend;
  http.Response contact = DiscoveryBackend.json({
    'displayName': 'Maya Perera',
    'phoneNumber': phone,
  });
  setUp(() {
    backend = DiscoveryBackend();
    contact = DiscoveryBackend.json({
      'displayName': 'Maya Perera',
      'phoneNumber': phone,
    });
    backend.intercept = (request) async {
      if (request.url.path == contactPath) return contact;
      if (request.url.path.endsWith('/landlord-summary')) {
        return DiscoveryBackend.json(profile.summary);
      }
      if (request.url.path.endsWith('/landlord-summary/properties')) {
        return DiscoveryBackend.json([]);
      }
      return null;
    };
  });
  tearDown(() {
    backend.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'dialer URI accepts supported formatting and rejects unsafe numbers',
    () {
      expect(landlordDialerUri(phone).toString(), 'tel:+94771234567');
      expect(
        landlordDialerUri('+44 (20) 7123-4567').toString(),
        'tel:+442071234567',
      );
      for (final value in [
        '',
        'abc',
        '12-----',
        '+94771234567?call=true',
        '+94771234567;ext=123',
        '1234567890123456',
      ]) {
        expect(landlordDialerUri(value), isNull);
      }
      for (final manifest
          in Directory('android')
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('AndroidManifest.xml'))) {
        expect(
          manifest.readAsStringSync(),
          isNot(contains('android.permission.CALL_PHONE')),
        );
      }
    },
  );

  for (final screen in ['details', 'profile']) {
    Future<void> open(WidgetTester tester) => screen == 'details'
        ? details.openDetails(tester, backend)
        : profile.openProfile(tester, backend);

    testWidgets('$screen Call landlord still opens the native dialer', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      MethodCall? launched;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            launched = call;
            return true;
          });
      await open(tester);
      final callIcon = find.byKey(const Key('landlord-call'));
      await scrollToVisible(tester, callIcon, 250);
      expect(find.text('Call'), findsOneWidget);
      final node = tester.getSemantics(find.bySemanticsLabel('Call landlord'));
      expect(node.label, 'Call landlord');
      expect(node.flagsCollection.isButton, isTrue);
      expect(node.flagsCollection.isEnabled, Tristate.isTrue);
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      semantics.dispose();
      await tapVisible(tester, find.text('Call'));
      expect(launched?.method, 'launch');
      expect((launched?.arguments as Map)['url'], 'tel:+94771234567');
      expect((launched?.arguments as Map)['useWebView'], isFalse);
      expect(find.text(phone), findsOneWidget);
    });

    testWidgets(
      '$screen shows only protected real contact and sends the bearer token',
      (tester) async {
        await open(tester);
        await scrollToVisible(tester, find.text('Contact landlord'), 250);
        expect(find.text(phone), findsOneWidget);
        expect(find.byTooltip('Call landlord'), findsOneWidget);
        expect(find.byIcon(Icons.phone_outlined), findsOneWidget);
        expect(find.text('Call'), findsOneWidget);
        expect(find.text('Call landlord'), findsNothing);
        expect(
          find
              .byType(FilledButton)
              .evaluate()
              .where(
                (e) =>
                    e.findAncestorWidgetOfExactType<LandlordContactCard>() !=
                    null,
              ),
          isEmpty,
        );
        expect(find.text('private@example.com'), findsNothing);
        expect(find.text('+94770000000'), findsNothing);
        expect(
          backend.requests
              .firstWhere((r) => r.url.path == contactPath)
              .headers['Authorization'],
          'Bearer tenant-token',
        );
      },
    );

    for (final result in ['disabled', 'invalid', 'forbidden']) {
      testWidgets('$screen omits contact and call button when $result', (
        tester,
      ) async {
        contact = switch (result) {
          'disabled' => http.Response('', 204),
          'forbidden' => http.Response('', 403),
          _ => DiscoveryBackend.json({
            'displayName': 'Maya Perera',
            'phoneNumber': '12-----',
          }),
        };
        await open(tester);
        if (screen == 'details') {
          await scrollToVisible(
            tester,
            find.byKey(const Key('details-landlord')),
            250,
          );
        }
        expect(find.text('Contact landlord'), findsNothing);
        expect(find.byTooltip('Call landlord'), findsNothing);
        expect(find.text('Call'), findsNothing);
        expect(find.text(phone), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }

  Future<void> openCard(WidgetTester tester, {double scale = 1}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: LandlordContactCard(
                propertyId: fixture.id,
                service: backend.service,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'call opens a safe native dialer URL without initiating the call',
    (tester) async {
      MethodCall? launched;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            launched = call;
            return true;
          });
      await openCard(tester);
      await tester.tap(find.byTooltip('Call landlord'));
      await tester.pumpAndSettle();
      expect(launched?.method, 'launch');
      expect((launched?.arguments as Map)['url'], 'tel:+94771234567');
      expect(
        find.text('Calling is not available on this device.'),
        findsNothing,
      );
    },
  );

  for (final throws in [false, true]) {
    testWidgets(
      'dialer ${throws ? 'exception' : 'failure'} keeps the visible number and shows safe feedback',
      (tester) async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (_) async {
              if (throws) throw PlatformException(code: 'unavailable');
              return false;
            });
        await openCard(tester);
        await tester.tap(find.byTooltip('Call landlord'));
        await tester.pumpAndSettle();
        expect(
          find.text('Calling is not available on this device.'),
          findsOneWidget,
        );
        expect(find.text(phone), findsOneWidget);
      },
    );
  }

  testWidgets(
    'resume refresh updates changed contact and removes disabled contact',
    (tester) async {
      await openCard(tester);
      contact = DiscoveryBackend.json({
        'displayName': 'Maya Perera',
        'phoneNumber': '+442071234567',
      });
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text(phone), findsNothing);
      expect(find.text('+442071234567'), findsOneWidget);
      contact = http.Response('', 204);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Contact landlord'), findsNothing);
      expect(find.byTooltip('Call landlord'), findsNothing);
    },
  );

  testWidgets('profile pull refresh removes disabled contact', (tester) async {
    await profile.openProfile(tester, backend);
    contact = http.Response('', 204);
    await tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    await tester.pumpAndSettle();
    expect(find.text(phone), findsNothing);
    expect(find.text('Contact landlord'), findsNothing);
  });

  testWidgets('stale request cannot restore a disabled phone', (tester) async {
    final pending = Completer<http.Response>();
    backend.intercept = (request) async =>
        request.url.path == contactPath ? pending.future : null;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LandlordContactCard(
            propertyId: fixture.id,
            service: backend.service,
          ),
        ),
      ),
    );
    await tester.pump();
    backend.intercept = (request) async =>
        request.url.path == contactPath ? http.Response('', 204) : null;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    pending.complete(
      DiscoveryBackend.json({
        'displayName': 'Maya Perera',
        'phoneNumber': phone,
      }),
    );
    await tester.pumpAndSettle();
    expect(find.text(phone), findsNothing);
  });

  testWidgets('contact and call label fit narrow layout with large text', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 720);
    addTearDown(tester.view.reset);
    await openCard(tester, scale: 2);
    await tapVisible(tester, find.text(phone));
    expect(find.byTooltip('Call landlord'), findsOneWidget);
    expect(find.byIcon(Icons.phone_outlined), findsOneWidget);
    expect(find.text('Call'), findsOneWidget);
    expect(find.text('Call landlord'), findsNothing);
    expect(
      find
          .byType(FilledButton)
          .evaluate()
          .where(
            (e) =>
                e.findAncestorWidgetOfExactType<LandlordContactCard>() != null,
          ),
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  for (final screen in ['details', 'profile']) {
    for (final scenario in [
      (pixels: const Size(320, 780), dpr: 1.0),
      (pixels: const Size(720, 1560), dpr: 2.0),
      (pixels: const Size(1080, 2340), dpr: 3.0),
    ]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          '$screen long public identity/contact fit ${scenario.pixels} at ${scale}x',
          (tester) async {
            const longName =
                'Pansilu Ruwantha Wijesinghe Arachchilage Gunawardena';
            const longPhone = '+123 (456) 789-012-345';
            tester.view.devicePixelRatio = scenario.dpr;
            tester.view.physicalSize = scenario.pixels;
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            addTearDown(tester.view.reset);
            addTearDown(
              tester.platformDispatcher.clearTextScaleFactorTestValue,
            );
            contact = DiscoveryBackend.json({
              'displayName': longName,
              'phoneNumber': longPhone,
            });
            final previous = backend.intercept;
            backend.intercept = (request) async {
              if (request.url.path.endsWith('/landlord-summary')) {
                return DiscoveryBackend.json({
                  ...profile.summary,
                  'displayName': longName,
                });
              }
              return previous?.call(request);
            };
            if (screen == 'details') {
              await details.openDetails(tester, backend);
            } else {
              await profile.openProfile(tester, backend, textScale: scale);
            }
            await scrollToVisible(tester, find.text(longName), 180);
            expect(find.text(longName), findsOneWidget);
            await scrollToVisible(
              tester,
              find.byKey(const Key('landlord-call')),
              180,
            );
            expect(find.text(longPhone), findsOneWidget);
            expect(find.text('Call'), findsOneWidget);
            expect(find.text('Call landlord'), findsNothing);
            final numberRect = tester.getRect(find.text(longPhone));
            final iconRect = tester.getRect(
              find.byKey(const Key('landlord-call')),
            );
            expect(numberRect.right, lessThan(iconRect.left));
            expect(iconRect.width, greaterThanOrEqualTo(44));
            expect(iconRect.height, greaterThanOrEqualTo(44));
            expect(
              iconRect.right,
              lessThanOrEqualTo(scenario.pixels.width / scenario.dpr),
            );
            if (scale == 2) {
              expect(numberRect.height, greaterThan(40));
            }
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}
