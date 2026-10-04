import 'dart:convert';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rentflow_mobile/features/properties/models/property.dart';
import 'package:rentflow_mobile/features/properties/screens/property_details_screen.dart';
import 'package:rentflow_mobile/features/rental_applications/models/application_eligibility.dart';
import 'package:rentflow_mobile/features/rental_applications/models/rental_application.dart';
import 'package:rentflow_mobile/features/rental_applications/screens/eligible_application_properties_screen.dart';
import 'package:rentflow_mobile/features/rental_applications/screens/my_rental_applications_screen.dart';
import 'package:rentflow_mobile/features/rental_applications/screens/rental_application_form_screen.dart';
import 'package:rentflow_mobile/features/rental_applications/screens/rental_application_details_screen.dart';
import 'package:rentflow_mobile/features/rental_applications/services/rental_application_api_service.dart';
import 'package:rentflow_mobile/features/viewings/screens/tenant_viewing_details_screen.dart';
import 'package:rentflow_mobile/features/viewings/services/viewing_api_service.dart';
import 'package:rentflow_mobile/shared/theme/app_theme.dart';

import 'helpers/discovery_backend.dart';
import 'property_details_test.dart' as property;
import 'rental_application_wizard_test.dart' as wizard;

const eligibilityPath =
    '/api/properties/${property.id}/rental-application-eligibility';
const pickerPath = '/api/rental-applications/eligible-properties';
final apply = find.byKey(const Key('details-apply-now'));
Map<String, dynamic> eligibility({bool completed = true, int? status}) => {
  'canApply': completed && status == null,
  'hasCompletedViewing': completed,
  'reason': completed
      ? null
      : 'Complete a viewing before applying for this property.',
  'existingApplicationId': status == null ? null : wizard.id,
  'existingApplicationStatus': status,
};
Map<String, dynamic> viewing(int status) => {
  'id': 'viewing-1',
  'propertyId': property.id,
  'tenantId': wizard.tenantId,
  'requestedDateTime': '2026-09-01T05:00:00Z',
  'status': status,
  'createdAt': '2026-09-01T00:00:00Z',
  'canCancel': false,
};
Future<void> pump(
  WidgetTester tester,
  DiscoveryBackend backend,
  Widget home,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 2200);
  addTearDown(tester.view.reset);
  addTearDown(backend.client.close);
  await tester.pumpWidget(MaterialApp(theme: AppTheme.build(), home: home));
  addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
  await tester.pumpAndSettle();
}

Widget details(DiscoveryBackend backend) => PropertyDetailsScreen(
  property: Property.fromJson(backend.properties.first),
  propertyApiService: backend.service,
  rentalApplicationApiService: RentalApplicationApiService(backend.client),
);
Widget picker(DiscoveryBackend backend) => EligibleApplicationPropertiesScreen(
  apiService: RentalApplicationApiService(backend.client),
  propertyApiService: backend.service,
);

void main() {
  for (final status in [0, 2]) {
    testWidgets(
      'Completed viewing status $status continues or views the existing application',
      (tester) async {
        final backend = wizard.Backend(status: status, step: 0).discovery;
        final previous = backend.intercept;
        backend.intercept = (request) async {
          if (request.url.path == '/api/viewings/viewing-1') {
            return DiscoveryBackend.json(viewing(4));
          }
          if (request.url.path == eligibilityPath) {
            return DiscoveryBackend.json(eligibility(status: status));
          }
          return await previous?.call(request);
        };
        await pump(
          tester,
          backend,
          TenantViewingDetailsScreen(
            viewingId: 'viewing-1',
            viewingApiService: ViewingApiService(backend.client),
          ),
        );
        expect(find.text('Your application'), findsOneWidget);
        expect(find.text('Apply for this property'), findsNothing);
        await tester.ensureVisible(apply);
        await tester.tap(apply);
        await tester.pumpAndSettle();
        if (status == 0) {
          expect(
            tester
                .widget<RentalApplicationFormScreen>(
                  find.byType(RentalApplicationFormScreen),
                )
                .application
                ?.id,
            wizard.id,
          );
        } else {
          expect(
            tester
                .widget<RentalApplicationDetailsScreen>(
                  find.byType(RentalApplicationDetailsScreen),
                )
                .application
                .id,
            wizard.id,
          );
        }
        expect(backend.calls('/api/rental-applications', 'POST'), 0);
      },
    );
  }
  testWidgets('tap rechecks another-device draft before opening the wizard', (
    tester,
  ) async {
    final backend = wizard.Backend(step: 0).discovery;
    final previous = backend.intercept;
    bool existing = false;
    backend.intercept = (request) async => request.url.path == eligibilityPath
        ? DiscoveryBackend.json(eligibility(status: existing ? 0 : null))
        : await previous?.call(request);
    await pump(tester, backend, details(backend));
    expect(find.text('Apply Now'), findsOneWidget);
    existing = true;
    await tester.tap(apply);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<RentalApplicationFormScreen>(
            find.byType(RentalApplicationFormScreen),
          )
          .application
          ?.id,
      wizard.id,
    );
    expect(backend.calls('/api/rental-applications', 'POST'), 0);
  });
  testWidgets(
    'locked eligibility buttons align without helper text on a small phone at 2x text',
    (tester) async {
      final backend = DiscoveryBackend()..completedPropertyIds.clear();
      final semantics = tester.ensureSemantics();
      await pump(tester, backend, details(backend));
      tester.view.physicalSize = const Size(320, 720);
      tester.view.padding = const FakeViewPadding(bottom: 24);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(apply).onPressed, isNull);
      expect(find.text('Apply after viewing'), findsOneWidget);
      expect(
        find.text('Complete a viewing before applying for this property.'),
        findsNothing,
      );
      final node = tester.getSemantics(apply);
      expect(node.flagsCollection.isEnabled, Tristate.isFalse);
      final bookRect = tester.getRect(
        find.byKey(const Key('details-book-viewing')),
      );
      final applyRect = tester.getRect(apply);
      expect(applyRect.top, bookRect.top);
      expect(applyRect.bottom, bookRect.bottom);
      expect(applyRect.left, greaterThan(bookRect.right));
      expect(
        tester.getSize(find.byKey(const Key('details-cta-bar'))).height,
        applyRect.height + 35, // 10px top, 24px safe area, 1px border.
      );
      expect(applyRect.bottom, lessThanOrEqualTo(720 - 24));
      semantics.dispose();
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'eligibility contract fails closed for malformed and contradictory data',
    () {
      for (final value in <Map<String, dynamic>>[
        {},
        {'canApply': true, 'hasCompletedViewing': false},
        {...eligibility(), 'existingApplicationId': wizard.id},
        {...eligibility(status: 0), 'canApply': true},
        {...eligibility(status: 0), 'existingApplicationStatus': 99},
      ]) {
        expect(
          () => ApplicationEligibility.fromJson(value),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'services use JWT without client tenant parameters and preserve safe 409 detail',
    () async {
      final backend = DiscoveryBackend();
      addTearDown(backend.client.close);
      final service = RentalApplicationApiService(backend.client);
      expect((await service.getEligibility(property.id)).canApply, isTrue);
      expect((await service.getEligibleProperties()).single.id, property.id);
      for (final request in backend.requests) {
        expect(request.headers['Authorization'], 'Bearer tenant-token');
        expect(request.url.queryParameters, isEmpty);
      }
      backend.intercept = (_) async => http.Response(
        jsonEncode({
          'detail':
              'Complete a viewing for this property before starting a rental application.',
        }),
        409,
      );
      await expectLater(
        service.getEligibility(property.id),
        throwsA(
          isA<RentalApplicationApiException>().having(
            (e) => e.message,
            'message',
            contains('Complete a viewing'),
          ),
        ),
      );
    },
  );
  for (final state in [
    'no viewing',
    'Approved',
    'another property Completed',
  ]) {
    testWidgets('property Apply stays locked with $state', (tester) async {
      final backend = DiscoveryBackend()..completedPropertyIds.clear();
      backend.completedPropertyIds.add('another-property');
      await pump(tester, backend, details(backend));
      expect(tester.widget<FilledButton>(apply).onPressed, isNull);
      expect(find.text('Apply after viewing'), findsOneWidget);
      expect(
        find.text('Complete a viewing before applying for this property.'),
        findsNothing,
      );
      expect(backend.calls(eligibilityPath), 1);
    });
  }
  testWidgets(
    'Completed unlocks correct wizard and return refresh sees an existing app',
    (tester) async {
      final backend = wizard.Backend(step: 0).discovery;
      final previous = backend.intercept;
      int? status;
      backend.intercept = (request) async => request.url.path == eligibilityPath
          ? DiscoveryBackend.json(eligibility(status: status))
          : await previous?.call(request);
      await pump(tester, backend, details(backend));
      expect(tester.widget<FilledButton>(apply).onPressed, isNotNull);
      await tester.tap(apply);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<RentalApplicationFormScreen>(
              find.byType(RentalApplicationFormScreen),
            )
            .propertyId,
        property.id,
      );
      expect(backend.calls('/api/rental-applications', 'POST'), 0);
      status = 0;
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      expect(find.text('Continue application'), findsOneWidget);
    },
  );
  for (final status in [0, 3, 1, 2]) {
    testWidgets('existing status $status routes to the same application', (
      tester,
    ) async {
      final fixture = wizard.Backend(status: status, step: 0);
      final backend = fixture.discovery;
      final previous = backend.intercept;
      backend.intercept = (request) async => request.url.path == eligibilityPath
          ? DiscoveryBackend.json(eligibility(completed: false, status: status))
          : await previous?.call(request);
      await pump(tester, backend, details(backend));
      expect(
        find.text(
          status == 0 || status == 3
              ? 'Continue application'
              : 'View application',
        ),
        findsOneWidget,
      );
      await tester.tap(apply);
      await tester.pumpAndSettle();
      if (status == 0 || status == 3) {
        expect(
          tester
              .widget<RentalApplicationFormScreen>(
                find.byType(RentalApplicationFormScreen),
              )
              .application
              ?.id,
          wizard.id,
        );
      } else {
        expect(
          tester
              .widget<RentalApplicationDetailsScreen>(
                find.byType(RentalApplicationDetailsScreen),
              )
              .application
              .id,
          wizard.id,
        );
      }
      expect(backend.calls('/api/rental-applications', 'POST'), 0);
    });
  }
  testWidgets('resume reloads authoritative eligibility', (tester) async {
    final backend = DiscoveryBackend()..completedPropertyIds.clear();
    await pump(tester, backend, details(backend));
    expect(tester.widget<FilledButton>(apply).onPressed, isNull);
    backend.completedPropertyIds.add(property.id);
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(apply).onPressed, isNotNull);
    expect(backend.calls(eligibilityPath), greaterThan(1));
  });
  testWidgets('eligibility error locks Apply and retry recovers', (
    tester,
  ) async {
    final backend = DiscoveryBackend();
    bool fail = true;
    backend.intercept = (request) async =>
        request.url.path == eligibilityPath && fail
        ? http.Response('{}', 503)
        : null;
    await pump(tester, backend, details(backend));
    expect(tester.widget<FilledButton>(apply).onPressed, isNull);
    expect(
      find.text('Unable to check application eligibility. Please try again.'),
      findsOneWidget,
    );
    fail = false;
    await tester.tap(find.text('Retry eligibility check'));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(apply).onPressed, isNotNull);
  });
  for (final status in [4, 1]) {
    testWidgets('viewing status $status only offers Completed next step', (
      tester,
    ) async {
      final backend = DiscoveryBackend();
      backend.intercept = (request) async =>
          request.url.path == '/api/viewings/viewing-1'
          ? DiscoveryBackend.json(viewing(status))
          : null;
      await pump(
        tester,
        backend,
        TenantViewingDetailsScreen(
          viewingId: 'viewing-1',
          viewingApiService: ViewingApiService(backend.client),
        ),
      );
      if (status == 4) {
        expect(find.text('Ready to apply?'), findsOneWidget);
        await tester.ensureVisible(apply);
        await tester.tap(apply);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<RentalApplicationFormScreen>(
                find.byType(RentalApplicationFormScreen),
              )
              .propertyId,
          property.id,
        );
      } else {
        expect(find.text('Ready to apply?'), findsNothing);
        expect(backend.calls(eligibilityPath), 0);
      }
      expect(backend.calls('/api/rental-applications', 'POST'), 0);
    });
  }
  testWidgets(
    'Completed card hides when another business rule blocks application',
    (tester) async {
      final backend = DiscoveryBackend();
      backend.intercept = (request) async {
        if (request.url.path == '/api/viewings/viewing-1') {
          return DiscoveryBackend.json(viewing(4));
        }
        if (request.url.path == eligibilityPath) {
          return DiscoveryBackend.json({
            'canApply': false,
            'hasCompletedViewing': true,
            'reason': 'This property is currently unavailable.',
          });
        }
        return null;
      };
      await pump(
        tester,
        backend,
        TenantViewingDetailsScreen(
          viewingId: 'viewing-1',
          viewingApiService: ViewingApiService(backend.client),
        ),
      );
      expect(find.text('Ready to apply?'), findsNothing);
      expect(apply, findsNothing);
    },
  );
  testWidgets('+ New uses only eligible picker and correct wizard', (
    tester,
  ) async {
    final backend = DiscoveryBackend();
    backend.properties.add({
      ...property.propertyJson(),
      'id': 'other',
      'title': 'Unviewed home',
    });
    backend.intercept = (request) async =>
        request.url.path == '/api/rental-applications'
        ? DiscoveryBackend.json([])
        : null;
    await pump(
      tester,
      backend,
      MyRentalApplicationsScreen(
        rentalApplicationApiService: RentalApplicationApiService(
          backend.client,
        ),
        propertyApiService: backend.service,
      ),
    );
    await tester.tap(find.text('+ New'));
    await tester.pumpAndSettle();
    expect(find.byType(EligibleApplicationPropertiesScreen), findsOneWidget);
    expect(find.text('Choose a property'), findsOneWidget);
    expect(find.text('Unviewed home'), findsNothing);
    expect(
      find.text(property.propertyJson()['title'] as String),
      findsOneWidget,
    );
    expect(find.text('Completed viewing'), findsOneWidget);
    await tester.tap(find.text('Start application'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<RentalApplicationFormScreen>(
            find.byType(RentalApplicationFormScreen),
          )
          .propertyId,
      property.id,
    );
    expect(backend.calls('/api/rental-applications', 'POST'), 0);
  });
  testWidgets('empty picker has truthful destinations and manual refresh', (
    tester,
  ) async {
    final backend = DiscoveryBackend()..completedPropertyIds.clear();
    await pump(tester, backend, picker(backend));
    expect(find.text('No properties ready to apply'), findsOneWidget);
    expect(
      find.text(
        'Complete a property viewing before starting a rental application.',
      ),
      findsOneWidget,
    );
    expect(find.text('Browse properties'), findsOneWidget);
    expect(find.text('My viewings'), findsOneWidget);
    backend.completedPropertyIds.add(property.id);
    await tester.tap(find.byTooltip('Refresh eligible properties'));
    await tester.pumpAndSettle();
    expect(find.text('Start application'), findsOneWidget);
    expect(find.text('No properties ready to apply'), findsNothing);
  });
  testWidgets(
    'picker handles network error safely and retry returns a distinct card',
    (tester) async {
      final backend = DiscoveryBackend();
      bool fail = true;
      backend.intercept = (request) async =>
          request.url.path == pickerPath && fail
          ? http.Response('{}', 503)
          : null;
      await pump(tester, backend, picker(backend));
      expect(
        find.text('Unable to load eligible properties. Please try again.'),
        findsOneWidget,
      );
      fail = false;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Completed viewing'), findsOneWidget);
    },
  );
  testWidgets('direct new wizard blocks an ineligible property before writes', (
    tester,
  ) async {
    final backend = DiscoveryBackend()..completedPropertyIds.clear();
    await pump(
      tester,
      backend,
      RentalApplicationFormScreen(
        propertyId: property.id,
        rentalApplicationApiService: RentalApplicationApiService(
          backend.client,
        ),
      ),
    );
    expect(
      find.text('Complete a viewing before applying for this property.'),
      findsOneWidget,
    );
    expect(backend.requests.where((r) => r.method != 'GET'), isEmpty);
  });
  testWidgets('legacy draft can still be edited with no Completed viewing', (
    tester,
  ) async {
    final backend = wizard.Backend(step: 0).discovery
      ..completedPropertyIds.clear();
    await pump(
      tester,
      backend,
      RentalApplicationFormScreen(
        propertyId: property.id,
        application: RentalApplication.fromJson(wizard.applicationJson()),
        rentalApplicationApiService: RentalApplicationApiService(
          backend.client,
        ),
      ),
    );
    expect(
      find.text('Complete a viewing before applying for this property.'),
      findsNothing,
    );
    expect(find.byType(TextFormField), findsWidgets);
    expect(backend.calls(eligibilityPath), 0);
    expect(backend.calls('/api/rental-applications', 'POST'), 0);
  });
}
