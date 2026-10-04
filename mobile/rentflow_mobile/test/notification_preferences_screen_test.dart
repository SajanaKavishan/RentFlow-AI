import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rentflow_mobile/features/auth/models/current_user.dart';
import 'package:rentflow_mobile/features/auth/screens/login_screen.dart';
import 'package:rentflow_mobile/main.dart';
import 'package:rentflow_mobile/shared/profile/notification_preferences_screen.dart';
import 'package:rentflow_mobile/shared/profile/shared_profile_content.dart';
import 'package:rentflow_mobile/shared/theme/app_theme.dart';

import 'helpers/notification_preferences_backend.dart';

void main() {
  late NotificationPreferencesBackend backend;
  setUp(() => backend = NotificationPreferencesBackend());
  tearDown(() => backend.dispose());

  for (final role in [UserRole.tenant, UserRole.landlord]) {
    testWidgets(
      '$role opens preferences from its real Profile row and returns',
      (tester) async {
        backend.dispose();
        backend = NotificationPreferencesBackend(role: role);
        await backend.pump(tester, fromProfile: true);
        expect(find.text('Preferences'), findsOneWidget);
        expect(find.text('Notifications'), findsOneWidget);
        expect(backend.loads, isEmpty);
        await tester.ensureVisible(find.text('Notifications'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Notifications'));
        await tester.pumpAndSettle();
        expect(find.byType(NotificationPreferencesScreen), findsOneWidget);
        expect(backend.loads, hasLength(1));
        expect(
          backend.loads.single.headers['Authorization'],
          'Bearer preferences-token',
        );
        expect(find.text('Not available yet'), findsNothing);
        await tester.tap(find.byTooltip('Back to Profile'));
        await tester.pumpAndSettle();
        expect(find.byType(SharedProfileContent), findsOneWidget);
        expect(find.text('Personal information'), findsOneWidget);
        expect(find.text('Password & security'), findsOneWidget);
      },
    );
  }

  testWidgets('loading exposes no guessed switches or save action', (
    tester,
  ) async {
    backend.pendingGet = Completer<http.Response>();
    await backend.pump(tester, settle: false);
    expect(find.text('Loading notification preferences…'), findsOneWidget);
    expect(find.byType(Switch), findsNothing);
    expect(find.byKey(const Key('preferences-save')), findsNothing);
    expect(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.liveRegion == true,
      ),
      findsOneWidget,
    );
    backend.pendingGet!.complete(
      http.Response(
        jsonEncode(preferencesJson(viewing: true, applications: false)),
        200,
      ),
    );
    await tester.pumpAndSettle();
    expect(preferenceSwitch(tester, 'preference-viewing').value, isTrue);
    expect(preferenceSwitch(tester, 'preference-applications').value, isFalse);
  });

  testWidgets(
    'loaded settings are authoritative; mandatory security is visibly ON and immutable',
    (tester) async {
      await backend.pump(tester);
      expect(preferenceSwitch(tester, 'preference-viewing').value, isFalse);
      expect(preferenceSwitch(tester, 'preference-applications').value, isTrue);
      final security = preferenceSwitch(tester, 'preference-security');
      expect(security.value, isTrue);
      expect(security.onChanged, isNull);
      expect(find.text('Always on'), findsOneWidget);
      expect(
        find.textContaining('This setting cannot be turned off.'),
        findsOneWidget,
      );
      expect(preferencesSave(tester).onPressed, isNull);
      await togglePreference(tester, 'preference-security');
      expect(preferenceSwitch(tester, 'preference-security').value, isTrue);
      expect(preferencesSave(tester).onPressed, isNull);
      expect(backend.saves, isEmpty);
      expect(find.textContaining('Push'), findsNothing);
      expect(find.textContaining('SMS'), findsNothing);
      expect(find.textContaining('Email notifications'), findsNothing);
    },
  );

  for (final failure in ['network', 'server', 'invalid', 'security-false']) {
    testWidgets('load $failure hides settings and Retry fetches real values', (
      tester,
    ) async {
      backend.failNetwork = failure == 'network';
      backend.getStatus = failure == 'server' ? 500 : 200;
      if (failure == 'invalid') backend.getBody = '{}';
      if (failure == 'security-false') {
        backend.getBody = jsonEncode({
          ...preferencesJson(),
          'accountSecurityUpdatesEnabled': false,
        });
      }
      await backend.pump(tester);
      expect(find.text('Notification preferences unavailable'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.byType(Switch), findsNothing);
      expect(find.byKey(const Key('preferences-save')), findsNothing);
      backend.failNetwork = false;
      backend.getStatus = 200;
      backend.getBody = null;
      backend.preferences = preferencesJson(viewing: true, applications: false);
      await tester.ensureVisible(find.text('Retry'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(backend.loads, hasLength(2));
      expect(preferenceSwitch(tester, 'preference-viewing').value, isTrue);
      expect(
        preferenceSwitch(tester, 'preference-applications').value,
        isFalse,
      );
      expect(preferencesSave(tester).onPressed, isNull);
    });
  }

  for (final key in ['preference-viewing', 'preference-applications']) {
    testWidgets('$key edits only a local draft; reverting disables Save', (
      tester,
    ) async {
      await backend.pump(tester);
      await togglePreference(tester, key);
      expect(preferencesSave(tester).onPressed, isNotNull);
      expect(backend.saves, isEmpty);
      expect(backend.preferences, preferencesJson());
      await togglePreference(tester, key);
      expect(preferencesSave(tester).onPressed, isNull);
      expect(backend.saves, isEmpty);
      await savePreferences(tester);
      expect(backend.saves, isEmpty);
    });
  }

  testWidgets(
    'Save submits both draft values with security true and confirms them',
    (tester) async {
      await backend.pump(tester);
      await togglePreference(tester, 'preference-viewing');
      await togglePreference(tester, 'preference-applications');
      await savePreferences(tester);
      expect(
        jsonDecode(backend.saves.single.body),
        preferencesJson(viewing: true, applications: false),
      );
      expect(preferenceSwitch(tester, 'preference-viewing').value, isTrue);
      expect(
        preferenceSwitch(tester, 'preference-applications').value,
        isFalse,
      );
      expect(preferencesSave(tester).onPressed, isNull);
      expect(find.text('Notification preferences saved.'), findsOneWidget);
      expect(backend.loads, hasLength(1));
      await togglePreference(tester, 'preference-viewing');
      expect(find.text('Notification preferences saved.'), findsNothing);
      expect(preferencesSave(tester).onPressed, isNotNull);
    },
  );

  testWidgets(
    'server-confirmed values replace the requested draft after Save',
    (tester) async {
      await backend.pump(tester);
      backend.putBody = jsonEncode(
        preferencesJson(viewing: false, applications: false),
      );
      await togglePreference(tester, 'preference-viewing');
      await savePreferences(tester);
      expect(
        jsonDecode(backend.saves.single.body),
        preferencesJson(viewing: true, applications: true),
      );
      expect(preferenceSwitch(tester, 'preference-viewing').value, isFalse);
      expect(
        preferenceSwitch(tester, 'preference-applications').value,
        isFalse,
      );
      expect(preferencesSave(tester).onPressed, isNull);
      expect(find.text('Notification preferences saved.'), findsOneWidget);
    },
  );

  testWidgets(
    'pending Save disables switches and action and blocks duplicate submission',
    (tester) async {
      await backend.pump(tester);
      await togglePreference(tester, 'preference-viewing');
      backend.pendingPut = Completer<http.Response>();
      await savePreferences(tester, settle: false);
      expect(preferencesSave(tester).onPressed, isNull);
      expect(find.text('Saving changes…'), findsOneWidget);
      expect(preferenceSwitch(tester, 'preference-viewing').onChanged, isNull);
      expect(
        preferenceSwitch(tester, 'preference-applications').onChanged,
        isNull,
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.liveRegion == true,
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('preferences-save')));
      expect(backend.saves, hasLength(1));
      backend.pendingPut!.complete(
        http.Response(jsonEncode(preferencesJson(viewing: true)), 200),
      );
      await tester.pumpAndSettle();
      expect(preferencesSave(tester).onPressed, isNull);
      expect(find.text('Notification preferences saved.'), findsOneWidget);
    },
  );

  for (final failure in [
    'network',
    'server',
    'rate',
    'invalid',
    'security-false',
  ]) {
    testWidgets(
      'save $failure retains draft and confirmed baseline and allows retry',
      (tester) async {
        await backend.pump(tester);
        backend.failNetwork = failure == 'network';
        backend.putStatus = failure == 'server'
            ? 500
            : failure == 'rate'
            ? 429
            : 200;
        if (failure == 'invalid') backend.putBody = '{}';
        if (failure == 'security-false') {
          backend.putBody = jsonEncode({
            ...preferencesJson(),
            'accountSecurityUpdatesEnabled': false,
          });
        }
        await togglePreference(tester, 'preference-viewing');
        await savePreferences(tester);
        expect(find.byKey(const Key('preferences-feedback')), findsOneWidget);
        expect(find.text('Notification preferences saved.'), findsNothing);
        expect(preferenceSwitch(tester, 'preference-viewing').value, isTrue);
        expect(
          preferenceSwitch(tester, 'preference-applications').value,
          isTrue,
        );
        expect(preferenceSwitch(tester, 'preference-security').value, isTrue);
        expect(preferencesSave(tester).onPressed, isNotNull);
        // Confirmed state remains the previous successful GET, even after errors.
        await togglePreference(tester, 'preference-viewing');
        expect(preferencesSave(tester).onPressed, isNull);
        await togglePreference(tester, 'preference-viewing');
        backend.failNetwork = false;
        backend.putStatus = 200;
        backend.putBody = null;
        await savePreferences(tester);
        expect(backend.saves, hasLength(2));
        expect(preferencesSave(tester).onPressed, isNull);
        expect(find.text('Notification preferences saved.'), findsOneWidget);
      },
    );
  }

  testWidgets(
    'switch semantics include labels and descriptions; security announces required and immutable',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await backend.pump(tester);
      for (final entry in {
        'preference-viewing': 'Viewing updates',
        'preference-applications': 'Rental application updates',
        'preference-security': 'Account security updates',
      }.entries) {
        await tester.ensureVisible(find.byKey(Key(entry.key)));
        await tester.pumpAndSettle();
        final data = tester
            .getSemantics(find.byKey(Key(entry.key)))
            .getSemanticsData();
        expect(data.label, contains(entry.value));
        if (entry.key == 'preference-security') {
          expect(data.label, contains('Always on'));
          expect(data.label, contains('Required'));
          expect(data.label, contains('cannot be turned off'));
        } else {
          expect(data.label, contains('Receive updates when'));
        }
      }
      semantics.dispose();
    },
  );

  testWidgets('401 from preferences uses existing app session navigation', (
    tester,
  ) async {
    await tester.pumpWidget(MyApp(authController: backend.auth));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profile').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Notifications'));
    await tester.pumpAndSettle();
    backend.getStatus = 401;
    await tester.tap(find.text('Notifications'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(NotificationPreferencesScreen), findsNothing);
    expect(backend.auth.isAuthenticated, isFalse);
    expect(backend.storage.token, isNull);
    expect(tester.takeException(), isNull);
  });

  for (final device in [
    (width: 320.0, height: 780.0, ratio: 1.0),
    (width: 720.0, height: 1560.0, ratio: 2.0),
    (width: 1080.0, height: 2340.0, ratio: 3.0),
  ]) {
    testWidgets('preferences wrap and scroll on $device at 200% text', (
      tester,
    ) async {
      tester.view.physicalSize = Size(device.width, device.height);
      tester.view.devicePixelRatio = device.ratio;
      addTearDown(tester.view.reset);
      await backend.pump(tester, scale: 2);
      expect(
        MediaQuery.textScalerOf(
          tester.element(find.byType(NotificationPreferencesScreen)),
        ).scale(14),
        28,
      );
      expect(tester.takeException(), isNull);
      await togglePreference(tester, 'preference-viewing');
      await togglePreference(tester, 'preference-applications');
      await tester.ensureVisible(find.byKey(const Key('preference-security')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('This setting cannot be turned off.'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.byKey(const Key('preferences-save')));
      await tester.pumpAndSettle();
      final action = find.byKey(const Key('preferences-save'));
      expect(
        tester.getBottomRight(action).dy,
        lessThanOrEqualTo(device.height / device.ratio),
      );
      expect(
        tester.getSize(action).width,
        lessThanOrEqualTo(device.width / device.ratio - 40),
      );
      expect(
        preferenceSwitch(tester, 'preference-viewing').activeTrackColor,
        AppPalette.olive,
      );
      expect(tester.takeException(), isNull);
      await savePreferences(tester);
      expect(find.text('Notification preferences saved.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
