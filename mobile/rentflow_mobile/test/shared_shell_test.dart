import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rentflow_mobile/features/auth/controllers/auth_controller.dart';
import 'package:rentflow_mobile/features/auth/models/current_user.dart';
import 'package:rentflow_mobile/shared/shell/shared_app_shell.dart';
import 'package:rentflow_mobile/shared/theme/app_theme.dart';
import 'package:rentflow_mobile/shared/widgets/shared_widgets.dart';

import 'widget_test.dart' as fixtures;

CurrentUser userFor(UserRole role) =>
    CurrentUser.fromJson(fixtures.userJson(role));

Future<fixtures.MemoryTokenStorage> pumpShell(
  WidgetTester tester,
  UserRole role, {
  Widget? viewingsContent,
  Widget? applicationsContent,
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
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return storage;
}

void main() {
  testWidgets('tenant home exposes honest journey and owned quick actions', (
    tester,
  ) async {
    await pumpShell(
      tester,
      UserRole.tenant,
      viewingsContent: const Center(child: Text('Viewings content')),
      applicationsContent: const Center(child: Text('Applications content')),
    );

    expect(find.text('Hello, Taylor'), findsOneWidget);
    expect(find.text('Your rental journey'), findsOneWidget);
    expect(find.text('Properties'), findsWidgets);
    expect(find.text('My Viewings'), findsOneWidget);
    expect(find.text('My Applications'), findsOneWidget);
    expect(find.text('Documents'), findsOneWidget);
    expect(
      find.text('AI helps with the work. People stay in control.'),
      findsOneWidget,
    );
    expect(find.text('Recent activity'), findsNothing);

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

  testWidgets(
    'tenant shell reaches Viewings, Applications, Properties, and Profile without feature network calls',
    (tester) async {
      await pumpShell(
        tester,
        UserRole.tenant,
        viewingsContent: const Center(child: Text('Viewings content')),
        applicationsContent: const Center(child: Text('Applications content')),
      );
      expect(find.byType(NavigationBar), findsOneWidget);
      await tester.tap(find.text('Viewings').last);
      await tester.pumpAndSettle();
      expect(find.text('Viewings content'), findsOneWidget);
      await tester.tap(find.text('Applications').last);
      await tester.pumpAndSettle();
      expect(find.text('Applications content'), findsOneWidget);
      await tester.tap(find.text('Properties').last);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Property discovery will appear here'),
        findsOneWidget,
      );
      await tester.tap(find.text('Profile').last);
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
      await tester.tap(find.text('Viewing Requests').last);
      await tester.pumpAndSettle();
      expect(find.text('Viewing queue unavailable'), findsOneWidget);
      await tester.tap(find.text('Profile').last);
      await tester.pumpAndSettle();
      expect(find.text('user@example.com'), findsOneWidget);
    },
  );

  testWidgets('maintenance technician has Home, Assigned Work, and Profile', (
    tester,
  ) async {
    await pumpShell(tester, UserRole.maintenanceTechnician);
    expect(find.byType(NavigationBar), findsOneWidget);
    final navigation = find.byType(NavigationBar);
    expect(
      find.descendant(of: navigation, matching: find.text('Home')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: navigation, matching: find.text('Assigned Work')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: navigation, matching: find.text('Profile')),
      findsOneWidget,
    );
  });

  testWidgets('admin has minimal Home and Profile mobile access', (
    tester,
  ) async {
    await pumpShell(tester, UserRole.admin);
    expect(find.byType(NavigationBar), findsOneWidget);
    final navigation = find.byType(NavigationBar);
    expect(
      find.descendant(of: navigation, matching: find.text('Home')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: navigation, matching: find.text('Profile')),
      findsOneWidget,
    );
    expect(find.text('Users'), findsNothing);
  });

  testWidgets('profile logout clears session', (tester) async {
    final storage = await pumpShell(tester, UserRole.tenant);
    await tester.tap(find.text('Profile').last);
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
        await tester.tap(find.text('Profile').last);
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
