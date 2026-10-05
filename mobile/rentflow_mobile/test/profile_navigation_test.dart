import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rentflow_mobile/features/application_documents/screens/tenant_documents_screen.dart';
import 'package:rentflow_mobile/features/auth/controllers/auth_controller.dart';
import 'package:rentflow_mobile/features/auth/models/current_user.dart';
import 'package:rentflow_mobile/features/auth/services/auth_service.dart';
import 'package:rentflow_mobile/features/properties/screens/match_preferences_screen.dart';
import 'package:rentflow_mobile/features/rental_applications/screens/my_rental_applications_screen.dart';
import 'package:rentflow_mobile/features/rental_applications/services/rental_application_api_service.dart';
import 'package:rentflow_mobile/shared/profile/shared_profile_content.dart';
import 'package:rentflow_mobile/shared/shell/shared_app_shell.dart';
import 'package:rentflow_mobile/shared/theme/app_theme.dart';

import 'helpers/discovery_backend.dart';
import 'shared_shell_test.dart' show navigationDestination;
import 'widget_test.dart' show userJson;

void main() {
  late DiscoveryBackend backend;
  late AuthController auth;
  late RentalApplicationApiService applications;
  Future<http.Response?> Function(http.Request)? intercept;

  setUp(() {
    intercept = null;
    backend = DiscoveryBackend();
    backend.intercept = (request) async {
      final intercepted = await intercept?.call(request);
      if (intercepted != null) return intercepted;
      if (request.url.path == '/api/auth/me') {
        return DiscoveryBackend.json(userJson(UserRole.tenant));
      }
      if (request.url.path == '/api/rental-applications') {
        return DiscoveryBackend.json([]);
      }
      return null;
    };
    applications = RentalApplicationApiService(backend.client);
    auth = AuthController(
      authService: AuthService(backend.client),
      tokenStorage: backend.client.tokenStorage,
    );
    backend.client.setUnauthorizedHandler(auth.handleUnauthorized);
  });
  tearDown(() {
    auth.dispose();
    backend.close();
  });

  Future<void> pump(WidgetTester tester, {bool standalone = false}) async {
    await auth.restoreSession();
    await tester.pumpWidget(
      AuthScope(
        controller: auth,
        child: MaterialApp(
          theme: AppTheme.build(),
          home: standalone
              ? Scaffold(body: SharedProfileContent(user: auth.currentUser!))
              : SharedAppShell(
                  user: auth.currentUser!,
                  propertyApiService: backend.service,
                  rentalApplicationApiService: applications,
                  applicationsContent: const Text(
                    'Generic Applications should not open',
                  ),
                ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (!standalone) {
      await tester.tap(navigationDestination('Profile'));
      await tester.pumpAndSettle();
    }
    backend.requests.clear();
  }

  Future<void> tap(
    WidgetTester tester,
    Finder finder, {
    bool settle = true,
  }) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  for (final standalone in [false, true]) {
    testWidgets(
      'Profile documents directly reuses grouped workspace (${standalone ? 'standalone' : 'shell'})',
      (tester) async {
        await pump(tester, standalone: standalone);
        final originalUser = auth.currentUser;
        final originalToken = await backend.client.tokenStorage.readToken();
        final originalShell = standalone
            ? null
            : tester.state(find.byType(SharedAppShell));
        await tap(tester, find.text('Application documents'));
        final screen = tester.widget<TenantDocumentsScreen>(
          find.byType(TenantDocumentsScreen),
        );
        expect(
          screen.rentalApplicationApiService!.apiClient,
          same(backend.client),
        );
        if (!standalone) {
          expect(screen.rentalApplicationApiService, same(applications));
          expect(screen.propertyApiService, same(backend.service));
        }
        expect(find.byType(MyRentalApplicationsScreen), findsNothing);
        expect(find.text('Generic Applications should not open'), findsNothing);
        expect(
          find.text('Open an application to view or manage its documents.'),
          findsNothing,
        );
        expect(
          find.textContaining('No application documents yet.'),
          findsOneWidget,
        );
        expect(backend.requests.map((request) => request.url.path), [
          '/api/rental-applications',
        ]);
        expect(
          backend.requests.single.headers['Authorization'],
          'Bearer $originalToken',
        );
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(SharedProfileContent), findsOneWidget);
        expect(auth.currentUser, same(originalUser));
        expect(await backend.client.tokenStorage.readToken(), originalToken);
        if (!standalone) {
          expect(
            tester.state(find.byType(SharedAppShell)),
            same(originalShell),
          );
        }
      },
    );
  }

  testWidgets(
    'document loading and failure remain truthful and Retry uses existing API',
    (tester) async {
      await pump(tester);
      final gate = Completer<http.Response>();
      intercept = (request) async =>
          request.url.path == '/api/rental-applications' ? gate.future : null;
      await tap(tester, find.text('Application documents'), settle: false);
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('Loading your documents'), findsOneWidget);
      expect(
        find.textContaining('No application documents yet.'),
        findsNothing,
      );
      gate.complete(http.Response('', 500));
      await tester.pumpAndSettle();
      expect(find.text('Could not load your documents.'), findsOneWidget);
      expect(
        find.textContaining('No application documents yet.'),
        findsNothing,
      );
      intercept = null;
      await tap(tester, find.text('Try again'));
      expect(
        find.textContaining('No application documents yet.'),
        findsOneWidget,
      );
      expect(backend.calls('/api/rental-applications'), 2);
      expect(
        backend.requests.every((request) => request.method == 'GET'),
        isTrue,
      );
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.byType(SharedProfileContent), findsOneWidget);
    },
  );

  for (final configured in [false, true]) {
    testWidgets(
      'Profile reuses ${configured ? 'configured' : 'unconfigured'} Match Preferences and returns safely',
      (tester) async {
        if (!configured) backend.preferences = {'isConfigured': false};
        await pump(tester);
        final originalShell = tester.state(find.byType(SharedAppShell));
        final originalUser = auth.currentUser;
        await tap(tester, find.text('Match preferences'));
        expect(
          tester
              .widget<MatchPreferencesScreen>(
                find.byType(MatchPreferencesScreen),
              )
              .service,
          same(backend.service),
        );
        expect(
          find.text(
            configured ? 'Your saved preferences' : 'Set match preferences',
          ),
          findsOneWidget,
        );
        expect(
          find.text('Reset saved preferences'),
          configured ? findsOneWidget : findsNothing,
        );
        expect(
          tester
              .widget<TextFormField>(find.byKey(const Key('preference-city')))
              .controller!
              .text,
          configured ? 'Kurunegala' : '',
        );
        expect(backend.calls(preferencesPath), 1);
        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();
        expect(find.byType(SharedProfileContent), findsOneWidget);
        expect(tester.state(find.byType(SharedAppShell)), same(originalShell));
        expect(auth.currentUser, same(originalUser));
        await tap(tester, find.text('Match preferences'));
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(SharedProfileContent), findsOneWidget);
        expect(backend.calls(preferencesPath, 'PUT'), 0);
        expect(backend.calls(preferencesPath, 'DELETE'), 0);
      },
    );
  }

  testWidgets(
    'saving Match Preferences through Profile uses canonical PUT and persists on reopen',
    (tester) async {
      await pump(tester);
      await tap(tester, find.text('Match preferences'));
      await tester.enterText(
        find.byKey(const Key('preference-city')),
        'Colombo',
      );
      await tester.pump();
      await tap(tester, find.text('Save preferences'));
      expect(find.byType(SharedProfileContent), findsOneWidget);
      expect(backend.calls(preferencesPath, 'PUT'), 1);
      final request = backend.requests.singleWhere((r) => r.method == 'PUT');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(
        body.keys,
        unorderedEquals([
          'preferredCity',
          'maximumMonthlyRent',
          'minimumBedrooms',
          'minimumBathrooms',
          'preferredAmenities',
        ]),
      );
      expect(body['preferredCity'], 'Colombo');
      expect(backend.calls(matchesPath), 0);
      await tap(tester, find.text('Match preferences'));
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('preference-city')))
            .controller!
            .text,
        'Colombo',
      );
      await tap(tester, find.text('Cancel'));
      expect(find.byType(SharedProfileContent), findsOneWidget);
      expect(auth.isAuthenticated, isTrue);
    },
  );
}
