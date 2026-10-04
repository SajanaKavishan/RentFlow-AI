import 'dart:convert';
import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rentflow_mobile/core/network/api_client.dart';
import 'package:rentflow_mobile/features/application_documents/screens/application_documents_screen.dart';
import 'package:rentflow_mobile/features/application_documents/screens/tenant_documents_screen.dart';
import 'package:rentflow_mobile/features/rental_applications/screens/my_rental_applications_screen.dart';
import 'package:rentflow_mobile/features/auth/models/current_user.dart';
import 'package:rentflow_mobile/shared/profile/shared_profile_content.dart';
import 'package:rentflow_mobile/shared/theme/app_theme.dart';
import 'package:rentflow_mobile/shared/profile/personal_information_screen.dart';
import 'package:rentflow_mobile/shared/profile/password_security_screen.dart';

import 'helpers/profile_backend.dart';

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
          body: SharedProfileContent(
            user: user ?? profileUser(role),
            onOpenReviews: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  List<String> rowsFor(UserRole role) => [
    'Personal information',
    'Password & security',
    if (role == UserRole.tenant) 'Application documents',
    if (role == UserRole.landlord) ...['Public contact', 'Reviews'],
    if (role == UserRole.tenant || role == UserRole.landlord) 'Notifications',
    if (role == UserRole.tenant) 'Match preferences',
    if (role != UserRole.admin) 'Help & support',
  ];

  for (final role in UserRole.values) {
    testWidgets(
      'Profile rows retain accessible titles and tap targets for ${role.name}',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          await pumpProfile(tester, role: role);
          for (final title in rowsFor(role)) {
            await tester.ensureVisible(find.text(title));
            await tester.pumpAndSettle();
            final finder = find.bySemanticsLabel(
              RegExp('^${RegExp.escape(title)}\n'),
            );
            expect(finder, findsOneWidget);
            final data = tester.getSemantics(finder).getSemanticsData();
            expect(data.label.startsWith('$title\n'), isTrue);
            expect(data.hasAction(SemanticsAction.tap), isTrue);
            final row = find
                .ancestor(of: find.text(title), matching: find.byType(InkWell))
                .first;
            expect(tester.getSize(row).height, greaterThanOrEqualTo(48));
            final icons = tester
                .widgetList<Icon>(
                  find.descendant(of: row, matching: find.byType(Icon)),
                )
                .toList();
            expect(icons.first.size, 22);
            expect(icons.last.icon, Icons.chevron_right);
            expect(tester.widget<Text>(find.text(title)).style!.fontSize, 16);
          }
          for (final heading in [
            'Account',
            if (role == UserRole.tenant || role == UserRole.landlord)
              'Preferences',
            if (role != UserRole.admin) 'Support',
          ]) {
            expect(tester.widget<Text>(find.text(heading)).style!.fontSize, 12);
            expect(
              tester
                  .widgetList<Semantics>(
                    find.ancestor(
                      of: find.text(heading),
                      matching: find.byType(Semantics),
                    ),
                  )
                  .any((widget) => widget.properties.header == true),
              isTrue,
            );
          }
        } finally {
          semantics.dispose();
        }
      },
    );

    for (final device in [
      (320.0, 780.0, 1.0),
      (720.0, 1560.0, 2.0),
      (1080.0, 2340.0, 3.0),
    ]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          'Profile ${role.name} long identity fits ${device.$1}×${device.$2} at ${scale}x',
          (tester) async {
            tester.view.physicalSize = Size(device.$1, device.$2);
            tester.view.devicePixelRatio = device.$3;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final user = CurrentUser(
              id: 'long-identity',
              role: role,
              phoneNumber: '+94 77 123 4567',
              fullName:
                  'Amara Wijesinghe Bandaranayake ${'LongFamilyName ' * 5}',
              email:
                  '${'verylongemailaddress' * 4}@very-long-company-domain.example.com',
            );
            await pumpProfile(tester, user: user, textScale: scale);
            expect(find.text(user.fullName.trim()), findsOneWidget);
            expect(find.text(user.email), findsOneWidget);
            expect(tester.takeException(), isNull);
            for (final title in [...rowsFor(role), 'Sign out']) {
              await tester.ensureVisible(find.text(title));
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
            }
            expect(
              MediaQuery.textScalerOf(
                tester.element(find.byType(SharedProfileContent)),
              ).scale(14),
              14 * scale,
            );
            final signOut = find.widgetWithText(OutlinedButton, 'Sign out');
            expect(
              tester.getBottomRight(signOut).dy,
              lessThanOrEqualTo(device.$2 / device.$3 - 24),
            );
          },
        );
      }
    }
  }

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
      expect(find.text('Account'), findsOneWidget);
      expect(find.text('Password & security'), findsOneWidget);
      final hasPreferences =
          role == UserRole.tenant || role == UserRole.landlord;
      expect(
        find.text('Preferences'),
        hasPreferences ? findsOneWidget : findsNothing,
      );
      expect(
        find.text('Notifications'),
        hasPreferences ? findsOneWidget : findsNothing,
      );
      expect(
        find.text('Support'),
        role == UserRole.admin ? findsNothing : findsOneWidget,
      );
      expect(
        find.text('Help & support'),
        role == UserRole.admin ? findsNothing : findsOneWidget,
      );
      expect(find.text('Feedback'), findsNothing);
      expect(
        find.text('Application documents'),
        role == UserRole.tenant ? findsOneWidget : findsNothing,
      );
      expect(
        find.text('Match preferences'),
        role == UserRole.tenant ? findsOneWidget : findsNothing,
      );
      expect(find.text('Personal information'), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
      expect(
        find.text('Reviews'),
        role == UserRole.landlord ? findsOneWidget : findsNothing,
      );
      expect(
        find.text('Public contact'),
        role == UserRole.landlord ? findsOneWidget : findsNothing,
      );
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

  testWidgets('landlord profile Reviews opens its read-only destination', (
    tester,
  ) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: Scaffold(
          body: SharedProfileContent(
            user: profileUser(UserRole.landlord),
            onOpenReviews: () => opened = true,
          ),
        ),
      ),
    );
    await tester.ensureVisible(find.text('Reviews'));
    await tester.tap(find.text('Reviews'));
    expect(opened, isTrue);
  });

  testWidgets('personal information opens a dedicated account screen', (
    tester,
  ) async {
    final backend = ProfileBackend();
    addTearDown(backend.dispose);
    await backend.pump(
      tester,
      (user) => Scaffold(body: SharedProfileContent(user: user)),
    );
    await tester.tap(find.text('Personal information'));
    await tester.pumpAndSettle();
    expect(find.byType(PersonalInformationScreen), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('profile-full-name')))
          .controller!
          .text,
      'Amara Silva',
    );
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.byKey(const Key('profile-email')),
              matching: find.byType(TextField),
            ),
          )
          .readOnly,
      isTrue,
    );
  });

  testWidgets('missing identity values do not become fictional account data', (
    tester,
  ) async {
    await pumpProfile(tester, user: profileUser(UserRole.tenant, empty: true));
    expect(find.text('?'), findsOneWidget);
    expect(find.text('Not provided'), findsNWidgets(2));
  });

  testWidgets(
    'duplicate and deferred options are omitted without dead actions',
    (tester) async {
      await pumpProfile(tester);
      for (final label in [
        'Email & phone',
        'Language',
        'Feedback',
        'Coming soon',
      ]) {
        expect(find.text(label), findsNothing);
      }
      expect(find.text('Not available yet'), findsNothing);
      expect(find.byType(Switch), findsNothing);
    },
  );

  for (final role in UserRole.values) {
    testWidgets('Password & security opens a working screen for $role', (
      tester,
    ) async {
      final backend = ProfileBackend(role: role);
      addTearDown(backend.dispose);
      await backend.pump(
        tester,
        (user) => Scaffold(body: SharedProfileContent(user: user)),
      );
      await tester.ensureVisible(find.text('Password & security'));
      await tester.tap(find.text('Password & security'));
      await tester.pumpAndSettle();
      expect(find.byType(PasswordSecurityScreen), findsOneWidget);
      expect(find.byKey(const Key('password-current')), findsOneWidget);
      expect(find.byKey(const Key('password-submit')), findsOneWidget);
      expect(find.text('Not available yet'), findsNothing);
      expect(find.textContaining('Forgot'), findsNothing);
      expect(find.textContaining('Reset password'), findsNothing);
      await tester.tap(find.byTooltip('Back to Profile'));
      await tester.pumpAndSettle();
      expect(find.byType(SharedProfileContent), findsOneWidget);
    });
  }

  testWidgets(
    'tenant Profile opens grouped documents directly and preserves application scope',
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
      await tester.ensureVisible(find.text('Application documents'));
      await tester.tap(find.text('Application documents'));
      await tester.pumpAndSettle();
      expect(
        find.text('Open an application to view or manage its documents.'),
        findsNothing,
      );
      expect(find.byType(TenantDocumentsScreen), findsOneWidget);
      expect(find.byType(MyRentalApplicationsScreen), findsNothing);
      expect(find.byType(ApplicationDocumentsScreen), findsNothing);
      final button = find.text('View documents');
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
        await tester.pumpWidget(const SizedBox());
      }
    },
  );
}
