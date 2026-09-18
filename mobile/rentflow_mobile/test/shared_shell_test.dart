import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rentflow_mobile/core/network/api_client.dart';
import 'package:rentflow_mobile/features/auth/controllers/auth_controller.dart';
import 'package:rentflow_mobile/features/auth/models/current_user.dart';
import 'package:rentflow_mobile/features/rental_applications/services/rental_application_api_service.dart';
import 'package:rentflow_mobile/features/viewings/services/viewing_api_service.dart';
import 'package:rentflow_mobile/shared/home/tenant_home.dart';
import 'package:rentflow_mobile/shared/navigation/role_navigation.dart';
import 'package:rentflow_mobile/shared/navigation/tenant_navigation_icon.dart';
import 'package:rentflow_mobile/shared/shell/shared_app_shell.dart';
import 'package:rentflow_mobile/shared/theme/app_theme.dart';
import 'package:rentflow_mobile/shared/widgets/shared_widgets.dart';

import 'widget_test.dart' as fixtures;

CurrentUser userFor(UserRole role) =>
    CurrentUser.fromJson(fixtures.userJson(role));

Finder navigationIcon(IconData icon) => find.descendant(
  of: find.byType(NavigationBar),
  matching: find.byIcon(icon),
);

Finder navigationSemantics(String label) => find.descendant(
  of: find.byType(NavigationBar),
  matching: find.bySemanticsLabel(RegExp('^$label(?:\\n.*)?\$')),
);

Finder navigationDestination(String label) => find.byWidgetPredicate(
  (widget) => widget is NavigationDestination && widget.label == label,
);

Future<fixtures.MemoryTokenStorage> pumpShell(
  WidgetTester tester,
  UserRole role, {
  Widget? viewingsContent,
  Widget? applicationsContent,
  ApiClient? apiClient,
}) async {
  final storage = fixtures.MemoryTokenStorage('token');
  final controller = fixtures.buildController(storage, role: role);
  await controller.restoreSession();
  await tester.pumpWidget(
    AuthScope(
      controller: controller,
      child: MaterialApp(
        theme: AppTheme.build(),
        home: SharedAppShell(
          user: userFor(role),
          viewingsContent: viewingsContent,
          applicationsContent: applicationsContent,
          viewingApiService: apiClient == null
              ? null
              : ViewingApiService(apiClient),
          rentalApplicationApiService: apiClient == null
              ? null
              : RentalApplicationApiService(apiClient),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return storage;
}

void main() {
  testWidgets(
    'populated tenant home stays compact and accessible at mobile widths',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final apiClient = ApiClient(
        baseUrl: 'http://test',
        tokenStorage: fixtures.MemoryTokenStorage('token'),
        httpClient: MockClient(
          (request) async => http.Response(
            jsonEncode(
              request.url.path.endsWith('/viewings')
                  ? []
                  : [
                      {
                        'id': 'application-test',
                        'tenantId': 'tenant-test',
                        'propertyId': '22222222-2222-4222-8222-222222222222',
                        'moveInDate': '2026-10-01',
                        'monthlyIncome': 2500,
                        'occupation': 'Engineer',
                        'numberOfOccupants': 2,
                        'status': 2,
                        'createdAt': '2026-09-14T10:00:00Z',
                        'updatedAt': '2026-09-15T11:30:00Z',
                      },
                    ],
            ),
            200,
          ),
        ),
      );
      addTearDown(apiClient.close);
      final semantics = tester.ensureSemantics();

      for (final width in [360.0, 390.0, 412.0, 430.0]) {
        await tester.binding.setSurfaceSize(Size(width, 800));
        await pumpShell(tester, UserRole.tenant, apiClient: apiClient);
        expect(find.text('Your application is being reviewed'), findsOneWidget);
        expect(find.text('UNDER REVIEW'), findsOneWidget);
        expect(find.text('Move-in requested for Oct 1, 2026'), findsOneWidget);
        expect(find.text('Recent activity'), findsOneWidget);
        expect(find.text('Application updated'), findsOneWidget);
        expect(find.text('Sep 15, 2026'), findsOneWidget);
        expect(find.text('See all'), findsNothing);

        final journey = find.byKey(const Key('tenant-journey-card'));
        expect(tester.getSize(journey).height, lessThan(200));
        final decoration =
            tester.widget<Container>(journey).decoration! as BoxDecoration;
        expect(decoration.color, AppPalette.darkOlive);

        final cards = ['My Viewings', 'My Lease', 'Pay Rent', 'Documents']
            .map(
              (label) => find.ancestor(
                of: find.text(label),
                matching: find.byType(AppCard),
              ),
            )
            .toList();
        expect(tester.getTopLeft(cards[0]).dy, tester.getTopLeft(cards[1]).dy);
        expect(tester.getTopLeft(cards[2]).dy, tester.getTopLeft(cards[3]).dy);
        expect(tester.getTopLeft(cards[0]).dx, tester.getTopLeft(cards[2]).dx);
        expect(tester.getSize(cards[0]).height, lessThan(110));
        for (final card in cards) {
          expect(tester.getSize(card), tester.getSize(cards[0]));
        }
        expect(
          tester.getSemantics(find.bySemanticsLabel('Documents')),
          matchesSemantics(
            label: 'Documents',
            isButton: true,
            hasTapAction: true,
          ),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
      semantics.dispose();
    },
  );

  testWidgets('recent activity shows three separate cards and opens all', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final apiClient = ApiClient(
      baseUrl: 'http://test',
      tokenStorage: fixtures.MemoryTokenStorage('token'),
      httpClient: MockClient(
        (request) async => http.Response(
          jsonEncode(
            request.url.path.endsWith('/viewings')
                ? []
                : [
                    for (var index = 0; index < 5; index++)
                      {
                        'id': 'application-$index',
                        'tenantId': 'tenant-test',
                        'propertyId': 'property-$index',
                        'moveInDate': '2026-10-01',
                        'monthlyIncome': 2500,
                        'occupation': 'Engineer',
                        'numberOfOccupants': 2,
                        'status': 1,
                        'createdAt': '2026-09-14T10:00:00Z',
                        'updatedAt': '2026-09-${15 - index}T11:30:00Z',
                      },
                  ],
          ),
          200,
        ),
      ),
    );
    addTearDown(apiClient.close);

    await pumpShell(tester, UserRole.tenant, apiClient: apiClient);
    final homeList = find.byKey(const Key('tenant-home-activity-list'));
    expect(
      find.descendant(of: homeList, matching: find.text('Application updated')),
      findsNWidgets(3),
    );
    expect(
      find.descendant(of: homeList, matching: find.byType(AppCard)),
      findsNWidgets(3),
    );
    expect(find.text('See all'), findsOneWidget);

    await tester.ensureVisible(find.text('See all'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('See all'));
    await tester.pumpAndSettle();
    final allActivity = find.byKey(const Key('tenant-all-activity-sheet'));
    expect(find.text('All recent activity'), findsOneWidget);
    expect(
      find.descendant(of: allActivity, matching: find.byType(AppCard)),
      findsNWidgets(5),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'tenant home supports enlarged text and real empty/error states',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      var unavailable = true;
      final apiClient = ApiClient(
        baseUrl: 'http://test',
        tokenStorage: fixtures.MemoryTokenStorage('token'),
        httpClient: MockClient(
          (_) async => http.Response('[]', unavailable ? 500 : 200),
        ),
      );
      addTearDown(apiClient.close);
      await pumpShell(tester, UserRole.tenant, apiClient: apiClient);
      expect(find.text('Journey unavailable'), findsOneWidget);
      expect(find.text('Recent activity'), findsNothing);
      expect(tester.takeException(), isNull);
      unavailable = false;
      await tester.ensureVisible(find.text('Try again'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('No rental journey yet'), findsOneWidget);
      expect(find.text('Recent activity'), findsNothing);
      await tester.ensureVisible(find.text('Documents'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('tenant home exposes the four requested quick actions', (
    tester,
  ) async {
    await pumpShell(
      tester,
      UserRole.tenant,
      viewingsContent: const Center(child: Text('Viewings content')),
      applicationsContent: const Center(child: Text('Applications content')),
    );

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            RegExp(
              r'^Good (morning|afternoon|evening|night), Taylor$',
            ).hasMatch(widget.data ?? ''),
      ),
      findsOneWidget,
    );
    expect(find.text('What would you like to do?'), findsOneWidget);
    expect(find.text('My Viewings'), findsOneWidget);
    expect(find.text('My Lease'), findsOneWidget);
    expect(find.text('Pay Rent'), findsOneWidget);
    expect(find.text('Documents'), findsOneWidget);
    expect(find.text('Find properties'), findsNothing);
    expect(find.text('My applications'), findsNothing);
    expect(find.byIcon(Icons.calendar_month_outlined), findsOneWidget);
    expect(find.byIcon(Icons.article_outlined), findsOneWidget);
    expect(find.byIcon(Icons.credit_card_outlined), findsOneWidget);
    expect(find.byIcon(Icons.folder_outlined), findsOneWidget);
    expect(find.byTooltip('Notifications'), findsOneWidget);
    expect(find.byTooltip('Open profile'), findsNothing);
    expect(find.text('RentFlow AI'), findsNothing);
    expect(
      find.text('AI helps with the work. People stay in control.'),
      findsNothing,
    );
    expect(find.text('Recent activity'), findsNothing);

    final semantics = tester.ensureSemantics();
    for (final label in ['My Viewings', 'My Lease', 'Pay Rent', 'Documents']) {
      expect(find.bySemanticsLabel(label), findsOneWidget);
    }
    semantics.dispose();

    await tester.ensureVisible(find.text('My Viewings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('My Viewings'));
    await tester.pumpAndSettle();
    expect(find.text('Viewings content'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('My Lease'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('My Lease'));
    await tester.pumpAndSettle();
    expect(find.text('Integration pending'), findsOneWidget);
    expect(find.textContaining('lease module is integrated'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Pay Rent'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pay Rent'));
    await tester.pumpAndSettle();
    expect(find.text('Integration pending'), findsOneWidget);
    expect(find.textContaining('payment module is integrated'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Documents'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Documents'));
    await tester.pumpAndSettle();
    expect(find.text('Applications content'), findsOneWidget);
    expect(
      find.text('Open an application to view or manage its documents.'),
      findsOneWidget,
    );
  });

  testWidgets('tenant greeting follows Sri Lanka time boundaries', (
    tester,
  ) async {
    Future<void> pumpAt(DateTime instant, String expected) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(),
          home: Scaffold(
            body: TenantHome(
              user: userFor(UserRole.tenant),
              onDestinationSelected: (RoleDestinationId _) {},
              onOpenViewings: () {},
              onOpenLease: () {},
              onPayRent: () {},
              onOpenDocuments: () {},
              onOpenNotifications: () {},
              now: () => instant,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('$expected, Taylor'), findsOneWidget);
      expect(find.text('FRIDAY, 18 SEPTEMBER'), findsOneWidget);
    }

    await pumpAt(DateTime.utc(2026, 9, 17, 23, 29), 'Good night');
    await pumpAt(DateTime.utc(2026, 9, 17, 23, 30), 'Good morning');
    await pumpAt(DateTime.utc(2026, 9, 18, 6, 29), 'Good morning');
    await pumpAt(DateTime.utc(2026, 9, 18, 6, 30), 'Good afternoon');
    await pumpAt(DateTime.utc(2026, 9, 18, 11, 29), 'Good afternoon');
    await pumpAt(DateTime.utc(2026, 9, 18, 11, 30), 'Good evening');
    await pumpAt(DateTime.utc(2026, 9, 18, 15, 29), 'Good evening');
    await pumpAt(DateTime.utc(2026, 9, 18, 15, 30), 'Good night');
  });

  testWidgets('authenticated navigation is icon-only and remains accessible', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 720));
    await pumpShell(tester, UserRole.tenant);

    final navigation = find.byType(NavigationBar);
    final bar = tester.widget<NavigationBar>(navigation);
    expect(bar.labelBehavior, NavigationDestinationLabelBehavior.alwaysHide);
    expect(tester.getSize(navigation).height, 64);
    expect(
      bar.destinations.whereType<NavigationDestination>().map(
        (destination) => destination.label,
      ),
      ['Home', 'Properties', 'Applications', 'Maintenance', 'Profile'],
    );

    final semantics = tester.ensureSemantics();
    expect(navigationSemantics('Viewings'), findsNothing);
    for (final label in [
      'Home',
      'Properties',
      'Applications',
      'Maintenance',
      'Profile',
    ]) {
      final destination = navigationSemantics(label);
      expect(destination, findsOneWidget);
      final target = tester.getSemantics(destination).rect.size;
      expect(target.width, greaterThanOrEqualTo(44));
      expect(target.height, greaterThanOrEqualTo(44));
    }

    expect(bar.indicatorColor, Colors.transparent);
    expect(bar.backgroundColor, AppPalette.white);
    final home = bar.destinations.first as NavigationDestination;
    expect((home.selectedIcon! as TenantNavigationIcon).selected, isTrue);
    expect((home.icon as TenantNavigationIcon).selected, isFalse);

    semantics.dispose();
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets(
    'tenant shell reaches Applications, Maintenance, Properties, and Profile without feature network calls',
    (tester) async {
      await pumpShell(
        tester,
        UserRole.tenant,
        viewingsContent: const Center(child: Text('Viewings content')),
        applicationsContent: const Center(child: Text('Applications content')),
      );
      expect(find.byType(NavigationBar), findsOneWidget);
      await tester.tap(navigationDestination('Applications'));
      await tester.pumpAndSettle();
      expect(find.text('Applications content'), findsOneWidget);
      await tester.tap(navigationDestination('Maintenance'));
      await tester.pumpAndSettle();
      expect(find.text('Integration pending'), findsOneWidget);
      expect(
        find.textContaining('maintenance requests will appear here'),
        findsOneWidget,
      );
      await tester.tap(navigationDestination('Properties'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Property discovery will appear here'),
        findsOneWidget,
      );
      await tester.tap(navigationDestination('Profile'));
      await tester.pumpAndSettle();
      expect(find.text('user@example.com'), findsOneWidget);
      expect(find.text('+94 77 123 4567'), findsOneWidget);
      for (final section in [
        'Account',
        'Security',
        'Preferences',
        'Documents',
        'Support',
      ]) {
        expect(find.text(section), findsOneWidget);
      }
    },
  );

  testWidgets(
    'landlord home exposes honest mobile actions and workspace handoff',
    (tester) async {
      await pumpShell(tester, UserRole.landlord);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('Hello, Larry'), findsOneWidget);
      expect(find.text('Viewing Requests'), findsWidgets);
      expect(find.text('Rental Applications'), findsOneWidget);
      expect(find.byTooltip('Notifications'), findsOneWidget);
      expect(find.byTooltip('Open profile'), findsOneWidget);
      expect(find.text('Recent activity'), findsNothing);
      expect(
        find.text(
          'Full management tools are available on the RentFlow web workspace.',
        ),
        findsOneWidget,
      );
      await tester.tap(navigationIcon(Icons.calendar_month_outlined));
      await tester.pumpAndSettle();
      expect(find.text('Viewing queue unavailable'), findsOneWidget);
      await tester.tap(navigationDestination('Profile'));
      await tester.pumpAndSettle();
      expect(find.text('user@example.com'), findsOneWidget);
    },
  );

  testWidgets('maintenance technician has Home, Assigned Work, and Profile', (
    tester,
  ) async {
    await pumpShell(tester, UserRole.maintenanceTechnician);
    expect(find.byType(NavigationBar), findsOneWidget);
    final semantics = tester.ensureSemantics();
    expect(navigationSemantics('Home'), findsOneWidget);
    expect(navigationSemantics('Assigned Work'), findsOneWidget);
    expect(navigationSemantics('Profile'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('admin has minimal Home and Profile mobile access', (
    tester,
  ) async {
    await pumpShell(tester, UserRole.admin);
    expect(find.byType(NavigationBar), findsOneWidget);
    final semantics = tester.ensureSemantics();
    expect(navigationSemantics('Home'), findsOneWidget);
    expect(navigationSemantics('Profile'), findsOneWidget);
    semantics.dispose();
    expect(find.text('Users'), findsNothing);
  });

  testWidgets('profile logout clears session', (tester) async {
    final storage = await pumpShell(tester, UserRole.tenant);
    await tester.tap(navigationDestination('Profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Logout'));
    await tester.pumpAndSettle();
    expect(storage.token, isNull);
  });

  testWidgets(
    'shared shell and profile fit 360, 390, 412, and 430 logical pixels',
    (tester) async {
      for (final width in [360.0, 390.0, 412.0, 430.0]) {
        await tester.binding.setSurfaceSize(Size(width, 720));
        await pumpShell(
          tester,
          UserRole.tenant,
          viewingsContent: const Text('Viewings content'),
          applicationsContent: const Text('Applications content'),
        );
        await tester.tap(navigationDestination('Profile'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
      await tester.binding.setSurfaceSize(null);
    },
  );

  testWidgets('shared presentation states are explicit', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: UnavailableState(module: 'Properties')),
      ),
    );
    expect(find.text('Integration pending'), findsOneWidget);
    expect(find.text('Properties'), findsOneWidget);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: UnauthorizedState())),
    );
    expect(find.text('Not accessible'), findsOneWidget);
  });
}
