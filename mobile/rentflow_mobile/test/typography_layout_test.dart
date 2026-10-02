import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rentflow_mobile/features/auth/controllers/auth_controller.dart';
import 'package:rentflow_mobile/features/auth/models/current_user.dart';
import 'package:rentflow_mobile/features/auth/screens/login_screen.dart';
import 'package:rentflow_mobile/features/maintenance/screens/create_maintenance_request_screen.dart';
import 'package:rentflow_mobile/features/maintenance/services/maintenance_api_service.dart';
import 'package:rentflow_mobile/features/properties/models/property.dart';
import 'package:rentflow_mobile/features/properties/screens/property_details_screen.dart';
import 'package:rentflow_mobile/features/properties/screens/property_list_screen.dart';
import 'package:rentflow_mobile/features/rental_applications/screens/rental_application_form_screen.dart';
import 'package:rentflow_mobile/features/rental_applications/services/rental_application_api_service.dart';
import 'package:rentflow_mobile/features/viewings/screens/book_viewing_screen.dart';
import 'package:rentflow_mobile/features/viewings/services/viewing_api_service.dart';
import 'package:rentflow_mobile/shared/home/tenant_home.dart';
import 'package:rentflow_mobile/shared/profile/shared_profile_content.dart';
import 'package:rentflow_mobile/shared/shell/shared_app_shell.dart';
import 'package:rentflow_mobile/shared/theme/app_theme.dart';

import 'helpers/discovery_backend.dart';
import 'widget_test.dart' as fixtures;

void main() {
  for (final scale in [1.0, 1.3, 2.0]) {
    testWidgets('key workflows wrap at 320px with ${scale}x text', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 780);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final backend = DiscoveryBackend();
      addTearDown(backend.close);
      final storage = fixtures.MemoryTokenStorage('token');
      final controller = fixtures.buildController(storage);
      await controller.restoreSession();
      addTearDown(controller.dispose);
      final user = CurrentUser.fromJson(fixtures.userJson(UserRole.tenant));
      final property = Property.fromJson(backend.properties.single);
      final screens = <String, Widget>{
        'discovery': Scaffold(
          body: PropertyListScreen(propertyApiService: backend.service),
        ),
        'details': PropertyDetailsScreen(
          property: property,
          propertyApiService: backend.service,
        ),
        'application form': RentalApplicationFormScreen(
          propertyId: property.id,
          propertyTitle: property.title,
          rentalApplicationApiService: RentalApplicationApiService(
            backend.client,
          ),
        ),
        'maintenance form': CreateMaintenanceRequestScreen(
          propertyId: property.id,
          maintenanceApiService: MaintenanceApiService(backend.client),
        ),
        'dashboard': Scaffold(
          body: TenantHome(
            user: user,
            propertyApiService: backend.service,
            onDestinationSelected: (_) {},
            onOpenViewings: () {},
            onOpenDocuments: () {},
            onOpenNotifications: () {},
          ),
        ),
        'profile': Scaffold(body: SharedProfileContent(user: user)),
        'login': const LoginScreen(),
        for (final role in [
          UserRole.landlord,
          UserRole.maintenanceTechnician,
          UserRole.admin,
        ])
          '$role navigation': SharedAppShell(
            user: CurrentUser.fromJson(fixtures.userJson(role)),
          ),
      };
      for (final entry in screens.entries) {
        // Unmount each previous workflow so its state cannot mask another screen's initial layout.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(
          AuthScope(
            controller: controller,
            child: MaterialApp(theme: AppTheme.build(), home: entry.value),
          ),
        );
        await tester.pumpAndSettle();
        final layoutError = tester.takeException();
        expect(layoutError, isNull, reason: '${entry.key} at ${scale}x');
        // Exercise the scrolled content too, including lower form controls.
        final scrolls = find.byType(SingleChildScrollView);
        if (scrolls.evaluate().isNotEmpty) {
          await tester.drag(scrolls.first, const Offset(0, -1500));
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: '${entry.key} lower content at ${scale}x',
          );
        }
      }
    });
  }

  testWidgets(
    'pushed booking owns its chrome and leaves shell navigation on return',
    (tester) async {
      final backend = DiscoveryBackend();
      addTearDown(backend.close);
      final user = CurrentUser.fromJson(fixtures.userJson(UserRole.tenant));
      final property = Property.fromJson(backend.properties.single);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(),
          home: SharedAppShell(
            user: user,
            propertyApiService: backend.service,
            viewingApiService: ViewingApiService(backend.client),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final destination = find.byWidgetPredicate(
        (widget) =>
            widget is NavigationDestination && widget.label == 'Properties',
      );
      await tester.tap(destination);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(property.title));
      await tester.pumpAndSettle();
      await tester.tap(find.text(property.title));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('details-book-viewing')));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.byIcon(Icons.menu), findsNothing);
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.byType(BackButton), findsOneWidget);
      expect(find.byType(BookViewingScreen), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(PropertyDetailsScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(PropertyListScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
