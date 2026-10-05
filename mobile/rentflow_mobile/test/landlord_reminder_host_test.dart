import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rentflow_mobile/features/properties/services/property_api_service.dart';
import 'package:rentflow_mobile/features/viewing_follow_ups/widgets/tenant_follow_up_host.dart';
import 'package:rentflow_mobile/features/viewings/services/viewing_api_service.dart';
import 'package:rentflow_mobile/features/viewings/services/viewing_reminders.dart';
import 'package:rentflow_mobile/features/viewings/widgets/landlord_reminder_host.dart';
import 'package:rentflow_mobile/features/viewings/screens/landlord_viewing_request_details_screen.dart';
import 'package:rentflow_mobile/shared/theme/app_theme.dart';
import 'helpers/landlord_workspace_fixture.dart';

void main() {
  for (final action in ['Not now', 'Yes, mark completed', 'conflict']) {
    testWidgets('server-driven reminder handles $action with real endpoint', (
      tester,
    ) async {
      var status = 1;
      var eligible = true;
      var patches = 0;
      var details = 0;
      final device = MemoryReminderDevice()..denyPermission = true;
      final reminders = ViewingReminders(device, now: () => reminderNow);
      final client = workspaceClient((request) async {
        if (request.method == 'PATCH') {
          expect(request.url.path, '/api/viewings/viewing/complete');
          patches++;
          if (action == 'conflict') {
            eligible = false;
            return jsonResponse({
              'detail': 'The viewing is no longer eligible.',
            }, 409);
          }
          status = 4;
          eligible = false;
          return jsonResponse(viewingJson(status: status, eligible: eligible));
        }
        if (request.url.path == '/api/properties/mine') {
          return jsonResponse([propertyJson()]);
        }
        if (request.url.path == '/api/viewings/property/property') {
          return jsonResponse([
            viewingJson(status: status, eligible: eligible),
            viewingJson(id: 'second'),
          ]);
        }
        if (request.url.path == '/api/viewings/viewing') {
          details++;
          return jsonResponse(viewingJson(status: status, eligible: eligible));
        }
        return jsonResponse({}, 404);
      });
      addTearDown(client.close);
      final key = GlobalKey<NavigatorState>();
      final observer = FollowUpNavigationObserver();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(),
          navigatorKey: key,
          navigatorObservers: [observer],
          builder: (_, child) => LandlordReminderHost(
            ownerId: ownerId,
            navigatorKey: key,
            navigation: observer,
            service: ViewingApiService(client),
            properties: PropertyApiService(client),
            reminders: reminders,
            now: () => reminderNow,
            child: child!,
          ),
          home: const Scaffold(body: Text('Workspace')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('How did the viewing go?'), findsOneWidget);
      expect(find.text('Garden House'), findsOneWidget);
      expect(find.text('Nimal Perera'), findsOneWidget);
      expect(details, 1);
      await tester.tap(
        find.text(action == 'conflict' ? 'Yes, mark completed' : action),
      );
      await tester.pumpAndSettle();
      if (action == 'conflict') {
        expect(find.text('The viewing is no longer eligible.'), findsOneWidget);
        expect(details, 2);
        expect(status, 1);
        final button = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Yes, mark completed'),
        );
        expect(button.onPressed, isNull);
        await tester.tap(find.text('Not now'));
        await tester.pumpAndSettle();
      }
      expect(patches, action == 'Not now' ? 0 : 1);
      expect(status, action == 'Yes, mark completed' ? 4 : 1);
      expect(find.text('How did the viewing go?'), findsNothing);
      expect(find.text('Workspace'), findsOneWidget);
      // Dismissing/handling does not chain another eligible viewing.
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('How did the viewing go?'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets(
    'future schedule denied permission keeps in-app fallback on resume',
    (tester) async {
      var now = reminderNow;
      var eligible = false;
      final at = reminderNow.add(const Duration(minutes: 30));
      final device = MemoryReminderDevice()..denyPermission = true;
      final reminders = ViewingReminders(device, now: () => now);
      final client = workspaceClient(
        (request) async => request.url.path == '/api/properties/mine'
            ? jsonResponse([propertyJson()])
            : request.url.path.contains('/property/')
            ? jsonResponse([viewingJson(eligible: eligible, at: at)])
            : jsonResponse(viewingJson(eligible: eligible, at: at)),
      );
      addTearDown(client.close);
      final key = GlobalKey<NavigatorState>();
      final observer = FollowUpNavigationObserver();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: key,
          navigatorObservers: [observer],
          builder: (_, child) => LandlordReminderHost(
            ownerId: ownerId,
            navigatorKey: key,
            navigation: observer,
            service: ViewingApiService(client),
            properties: PropertyApiService(client),
            reminders: reminders,
            now: () => now,
            child: child!,
          ),
          home: const Scaffold(body: Text('Workspace')),
        ),
      );
      await tester.pumpAndSettle();
      expect(device.permissionRequests, 1);
      expect(find.text('How did the viewing go?'), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      now = at;
      eligible = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('How did the viewing go?'), findsOneWidget);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('How did the viewing go?'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'multiple past timestamps with false server permission never offer completion or poll repeatedly',
    (tester) async {
      var reads = 0;
      final client = workspaceClient((request) async {
        reads++;
        if (request.url.path == '/api/properties/mine') {
          return jsonResponse([propertyJson()]);
        }
        return jsonResponse([
          viewingJson(
            eligible: false,
            at: reminderNow.subtract(const Duration(hours: 2)),
          ),
          viewingJson(
            id: 'second',
            eligible: false,
            at: reminderNow.subtract(const Duration(hours: 1)),
          ),
        ]);
      });
      addTearDown(client.close);
      final key = GlobalKey<NavigatorState>();
      final observer = FollowUpNavigationObserver();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: key,
          navigatorObservers: [observer],
          builder: (_, child) => LandlordReminderHost(
            ownerId: ownerId,
            navigatorKey: key,
            navigation: observer,
            service: ViewingApiService(client),
            properties: PropertyApiService(client),
            reminders: ViewingReminders(
              MemoryReminderDevice(),
              now: () => reminderNow,
            ),
            now: () => reminderNow,
            child: child!,
          ),
          home: const Scaffold(body: Text('Workspace')),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('How did the viewing go?'), findsNothing);
      final afterRefresh = reads;
      await tester.pump(const Duration(seconds: 10));
      expect(reads, afterRefresh);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'valid notification tap fetches and opens the correct Viewing Details',
    (tester) async {
      final reminders = ViewingReminders(
        MemoryReminderDevice(),
        now: () => reminderNow,
      );
      reminders.tappedPayload.value = jsonEncode({
        'owner': ownerId,
        'viewing': 'viewing',
      });
      final client = workspaceClient((request) async {
        if (request.url.path == '/api/properties/mine') {
          return jsonResponse([propertyJson()]);
        }
        if (request.url.path.contains('/property/')) {
          return jsonResponse([viewingJson()]);
        }
        expect(request.url.path, '/api/viewings/viewing');
        return jsonResponse(viewingJson());
      });
      addTearDown(client.close);
      final key = GlobalKey<NavigatorState>();
      final observer = FollowUpNavigationObserver();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: key,
          navigatorObservers: [observer],
          builder: (_, child) => LandlordReminderHost(
            ownerId: ownerId,
            navigatorKey: key,
            navigation: observer,
            service: ViewingApiService(client),
            properties: PropertyApiService(client),
            reminders: reminders,
            now: () => reminderNow,
            child: child!,
          ),
          home: const Scaffold(body: Text('Workspace')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(LandlordViewingRequestDetailsScreen), findsOneWidget);
      expect(find.text('How did the viewing go?'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
