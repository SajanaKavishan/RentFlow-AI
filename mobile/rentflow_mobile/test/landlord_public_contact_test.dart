import 'dart:async';
import 'dart:io';

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
      MethodCall? launched;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            launched = call;
            return true;
          });
      await open(tester);
      await tapVisible(tester, find.text('Call landlord'));
      expect(launched?.method, 'launch');
      expect((launched?.arguments as Map)['url'], 'tel:+94771234567');
      expect(find.text(phone), findsOneWidget);
    });

    testWidgets(
      '$screen shows only protected real contact and sends the bearer token',
      (tester) async {
        await open(tester);
        await scrollToVisible(tester, find.text('Contact landlord'), 250);
        expect(find.text(phone), findsOneWidget);
        expect(find.text('Call landlord'), findsOneWidget);
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
        expect(find.text('Contact landlord'), findsNothing);
        expect(find.text('Call landlord'), findsNothing);
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
      await tester.tap(find.text('Call landlord'));
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
        await tester.tap(find.text('Call landlord'));
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
      expect(find.text('Call landlord'), findsNothing);
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
    expect(find.text('Call landlord'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
