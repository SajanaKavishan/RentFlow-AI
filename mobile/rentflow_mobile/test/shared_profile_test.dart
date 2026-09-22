import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rentflow_mobile/core/network/api_client.dart';
import 'package:rentflow_mobile/features/application_documents/screens/application_documents_screen.dart';
import 'package:rentflow_mobile/features/auth/models/current_user.dart';
import 'package:rentflow_mobile/shared/profile/shared_profile_content.dart';
import 'package:rentflow_mobile/shared/theme/app_theme.dart';

import 'shared_shell_test.dart' as shell;
import 'widget_test.dart' as fixtures;

CurrentUser profileUser(UserRole role, {bool empty = false}) => CurrentUser(
  id: 'profile-user',
  fullName: empty ? '' : 'Amara Silva',
  email: empty ? '' : 'amara.silva@example.com',
  phoneNumber: empty ? '' : '+94 77 123 4567',
  role: role,
);

Future<void> pumpProfile(
  WidgetTester tester, {
  UserRole role = UserRole.tenant,
  CurrentUser? user,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.build(),
      home: MediaQuery(
        data: MediaQueryData(
          textScaler: TextScaler.linear(textScale),
          padding: const EdgeInsets.fromLTRB(12, 28, 12, 24),
        ),
        child: Scaffold(
          appBar: AppBar(title: const Text('Profile')),
          body: SharedProfileContent(user: user ?? profileUser(role)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final role in UserRole.values) {
    testWidgets('profile shows real identity without role badges for $role', (
      tester,
    ) async {
      await pumpProfile(tester, role: role);
      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('Amara Silva'), findsOneWidget);
      expect(find.text('amara.silva@example.com'), findsOneWidget);
      expect(find.text('AS'), findsOneWidget);
      expect(find.byType(CircleAvatar), findsOneWidget);
      for (final label in [
        'Tenant',
        'Landlord',
        'Technician',
        'MaintenanceTechnician',
        'Admin',
        'Role',
        'Verified',
      ]) {
        expect(find.text(label), findsNothing);
      }
      for (final label in ['Account', 'Preferences', 'Support']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(
        find.text('My documents'),
        role == UserRole.tenant ? findsOneWidget : findsNothing,
      );
      expect(find.text('Sign out'), findsOneWidget);
      expect(find.text('RentFlow AI v2.4.1 · © 2026'), findsOneWidget);

      final signOut = tester.widget<OutlinedButton>(
        find.byKey(const Key('profile-sign-out')),
      );
      expect(
        signOut.style?.foregroundColor?.resolve(<WidgetState>{}),
        AppPalette.danger,
      );
    });
  }

  testWidgets('account details use current user data and remain read-only', (
    tester,
  ) async {
    await pumpProfile(tester);
    await tester.tap(find.text('Personal information'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(SelectableText, 'Amara Silva'), findsOneWidget);
    expect(
      find.text('These details are read-only. Editing is unavailable.'),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Email & phone'));
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(SelectableText, 'amara.silva@example.com'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(SelectableText, '+94 77 123 4567'),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Save'), findsNothing);
  });

  testWidgets('missing identity values do not become fictional account data', (
    tester,
  ) async {
    await pumpProfile(tester, user: profileUser(UserRole.tenant, empty: true));
    expect(find.text('?'), findsOneWidget);
    expect(find.text('Not provided'), findsNWidgets(2));
    await tester.tap(find.text('Email & phone'));
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(SelectableText, 'Not provided'),
      findsNWidgets(2),
    );
  });

  testWidgets(
    'unsupported options are visibly unavailable and non-interactive',
    (tester) async {
      await pumpProfile(tester);
      for (final label in [
        'Password & security',
        'My documents',
        'Notifications',
        'Language',
        'Help & support',
        'Feedback',
      ]) {
        final tile = find.ancestor(
          of: find.text(label),
          matching: find.byType(InkWell),
        );
        expect(tester.widget<InkWell>(tile).onTap, isNull);
        expect(
          find.descendant(of: tile, matching: find.byIcon(Icons.chevron_right)),
          findsNothing,
        );
        expect(
          find.descendant(
            of: tile,
            matching: find.text(
              label == 'Feedback'
                  ? 'Message delivery unavailable'
                  : 'Not available yet',
            ),
          ),
          findsOneWidget,
        );
      }
      expect(find.byType(Switch), findsNothing);
    },
  );

  testWidgets(
    'tenant My documents reaches existing application documents flow',
    (tester) async {
      const applicationId = '66666666-6666-4666-8666-666666666666';
      final paths = <String>[];
      final api = ApiClient(
        baseUrl: 'http://test',
        tokenStorage: fixtures.MemoryTokenStorage('token'),
        httpClient: MockClient((request) async {
          paths.add(request.url.path);
          final path = request.url.path;
          if (path == '/api/rental-applications') {
            return http.Response(
              jsonEncode([
                {
                  'id': applicationId,
                  'tenantId': 'profile-user',
                  'propertyId': '22222222-2222-4222-8222-222222222222',
                  'moveInDate': '2030-02-03',
                  'monthlyIncome': 2500,
                  'occupation': 'Engineer',
                  'numberOfOccupants': 2,
                  'status': 0,
                  'createdAt': '2026-09-14T10:00:00Z',
                },
              ]),
              200,
            );
          }
          if (path == '/api/rental-applications/$applicationId') {
            return http.Response(
              jsonEncode({
                'id': applicationId,
                'tenantId': 'profile-user',
                'propertyId': '22222222-2222-4222-8222-222222222222',
                'moveInDate': '2030-02-03',
                'monthlyIncome': 2500,
                'occupation': 'Engineer',
                'numberOfOccupants': 2,
                'status': 0,
                'createdAt': '2026-09-14T10:00:00Z',
              }),
              200,
            );
          }
          return http.Response('[]', 200);
        }),
      );
      addTearDown(api.close);
      await shell.pumpShell(tester, UserRole.tenant, apiClient: api);
      await tester.tap(shell.navigationDestination('Profile'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('My documents'));
      await tester.tap(find.text('My documents'));
      await tester.pumpAndSettle();
      expect(
        find.text('Open an application to view or manage its documents.'),
        findsOneWidget,
      );
      // Let the existing document guidance snackbar dismiss before tapping
      // the application action underneath it on a short viewport.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      final button = find.byKey(
        const ValueKey('application-documents-$applicationId'),
      );
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ApplicationDocumentsScreen>(
              find.byType(ApplicationDocumentsScreen),
            )
            .applicationId,
        applicationId,
      );
      expect(
        paths,
        contains('/api/rental-applications/$applicationId/documents'),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'profile scrolls within safe areas at narrow and wide sizes with large text',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final width in [320.0, 430.0, 900.0]) {
        await tester.binding.setSurfaceSize(Size(width, 640));
        await pumpProfile(tester, textScale: 2);
        expect(tester.takeException(), isNull);
        expect(
          tester.getTopLeft(find.byType(CircleAvatar)).dy,
          greaterThan(28),
        );
        await tester.ensureVisible(find.text('Sign out'));
        await tester.pumpAndSettle();
        final signOut = find.widgetWithText(OutlinedButton, 'Sign out');
        expect(tester.getBottomRight(signOut).dy, lessThanOrEqualTo(616));
        expect(tester.getTopLeft(signOut).dx, greaterThanOrEqualTo(12));
        expect(tester.getSize(signOut).width, lessThanOrEqualTo(580));
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('Email & phone'));
        await tester.tap(find.text('Email & phone'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Close'));
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
    },
  );
}
