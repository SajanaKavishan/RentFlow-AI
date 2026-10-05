import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rentflow_mobile/core/network/api_client.dart';
import 'package:rentflow_mobile/features/application_documents/screens/application_documents_screen.dart';
import 'package:rentflow_mobile/features/application_documents/screens/tenant_documents_screen.dart';
import 'package:rentflow_mobile/features/properties/services/property_api_service.dart';
import 'package:rentflow_mobile/features/rental_applications/services/rental_application_api_service.dart';
import 'package:rentflow_mobile/features/tenant_lease_payments/screens/tenant_lease_payments_screen.dart';
import 'package:rentflow_mobile/features/tenant_lease_payments/services/tenant_lease_payments_api_service.dart';
import 'package:rentflow_mobile/shared/theme/app_theme.dart';

import 'tenant_dashboard_test.dart' as dashboard;
import 'widget_test.dart' as fixtures;

final lease = <String, Object?>{
  'id': 'lease',
  'propertyId': 'home',
  'status': 1,
  'monthlyRent': 125000,
  'securityDeposit': 250000,
  'startDate': '2026-09-01',
  'endDate': '2027-09-01',
  'createdAt': '2026-09-01T00:00:00Z',
};
final schedule = <String, Object?>{
  'id': 'schedule',
  'leaseAgreementId': 'lease',
  'dueDate': '2026-10-01',
  'amount': 125000,
  'status': 0,
  'createdAt': '2026-09-01T00:00:00Z',
};
final application = <String, Object?>{
  'id': 'application',
  'tenantId': 'tenant',
  'propertyId': 'home',
  'status': 0,
  'moveInDate': '2026-10-01',
  'monthlyIncome': 250000,
  'occupation': 'Engineer',
  'numberOfOccupants': 1,
  'createdAt': '2026-09-28T10:00:00Z',
};
ApiClient clientFor(Future<http.Response> Function(http.Request) handler) =>
    ApiClient(
      baseUrl: 'http://test',
      httpClient: MockClient(handler),
      tokenStorage: fixtures.MemoryTokenStorage('token'),
    );
http.Response ok(Object value) => http.Response(jsonEncode(value), 200);

void main() {
  testWidgets('lease destination shows real terms and wraps at enlarged text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final client = clientFor(
      (request) async => request.url.path == '/api/lease-agreements/mine'
          ? ok([lease])
          : ok(dashboard.property('home')),
    );
    addTearDown(client.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: TenantLeasePaymentsScreen(
          section: TenantAccountSection.lease,
          apiService: TenantLeasePaymentsApiService(client),
          propertyApiService: PropertyApiService(client),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('My Lease'), findsOneWidget);
    expect(find.text('A spacious home in home'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Rs. 125,000'), findsOneWidget);
    expect(find.text('Rs. 250,000'), findsOneWidget);
    await tester.ensureVisible(find.text('Sep 1, 2027'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'rent submits once as pending and never marks the schedule paid',
    (tester) async {
      final response = Completer<http.Response>();
      var posts = 0;
      Map<String, dynamic>? payload;
      final payments = <Map<String, Object?>>[];
      final client = clientFor((request) async {
        if (request.method == 'POST') {
          posts++;
          payload = jsonDecode(request.body) as Map<String, dynamic>;
          final result = await response.future;
          payments.add(jsonDecode(result.body) as Map<String, dynamic>);
          return result;
        }
        if (request.url.path == '/api/lease-agreements/mine') {
          return ok([lease]);
        }
        if (request.url.path == '/api/payments/mine') return ok(payments);
        return ok([schedule]);
      });
      addTearDown(client.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(),
          home: TenantLeasePaymentsScreen(
            section: TenantAccountSection.rent,
            apiService: TenantLeasePaymentsApiService(client),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Submit payment details'));
      await tester.tap(find.text('Submit payment details'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Submit for confirmation'));
      await tester.tap(find.text('Submit for confirmation'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a payment method.'), findsOneWidget);
      expect(posts, 0);
      await tester.enterText(
        find.byType(TextFormField).first,
        ' Bank transfer ',
      );
      await tester.enterText(find.byType(TextFormField).last, ' REF-123 ');
      await tester.ensureVisible(find.text('Submit for confirmation'));
      await tester.tap(find.text('Submit for confirmation'));
      await tester.pump();
      expect(posts, 1);
      expect(payload, {
        'rentScheduleItemId': 'schedule',
        'paymentMethod': 'Bank transfer',
        'transactionReference': 'REF-123',
      });
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Submitting…'),
            )
            .onPressed,
        isNull,
      );
      response.complete(
        http.Response(
          jsonEncode({
            'id': 'payment',
            'rentScheduleItemId': 'schedule',
            'amount': 125000,
            'status': 0,
            'paymentMethod': 'Bank transfer',
            'transactionReference': 'REF-123',
            'createdAt': '2026-10-01T10:00:00Z',
          }),
          201,
        ),
      );
      await tester.pumpAndSettle();
      expect(posts, 1);
      expect(
        find.text('Payment submitted · Awaiting landlord confirmation'),
        findsOneWidget,
      );
      expect(find.text('Completed'), findsNothing);
      expect(find.text('Paid'), findsNothing);
      expect(find.text('Submit payment details'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed schedules preserve other schedules and payment history', (
    tester,
  ) async {
    final client = clientFor((request) async {
      if (request.url.path == '/api/lease-agreements/mine') {
        return ok([
          lease,
          {...lease, 'id': 'broken'},
        ]);
      }
      if (request.url.path.endsWith('/broken')) return http.Response('', 500);
      if (request.url.path == '/api/payments/mine') {
        return ok([
          {
            'id': 'payment',
            'status': 1,
            'amount': 125000,
            'paymentMethod': 'Bank transfer',
            'paidAt': '2026-09-01T10:00:00Z',
          },
        ]);
      }
      return ok([schedule]);
    });
    addTearDown(client.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: TenantLeasePaymentsScreen(
          section: TenantAccountSection.rent,
          apiService: TenantLeasePaymentsApiService(client),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Some rent schedules could not be loaded'),
      findsOneWidget,
    );
    expect(find.text('Submit payment details'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'documents destination opens the existing document manager for the selected application',
    (tester) async {
      final paths = <String>[];
      final client = clientFor((request) async {
        paths.add(request.url.path);
        if (request.url.path == '/api/rental-applications') {
          return ok([application]);
        }
        if (request.url.path == '/api/rental-applications/application') {
          return ok(application);
        }
        if (request.url.path.endsWith('/documents')) return ok([]);
        return ok(dashboard.property('home'));
      });
      addTearDown(client.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(),
          home: TenantDocumentsScreen(
            rentalApplicationApiService: RentalApplicationApiService(client),
            propertyApiService: PropertyApiService(client),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Your documents'), findsOneWidget);
      await tester.tap(find.text('View documents'));
      await tester.pumpAndSettle();
      expect(find.byType(ApplicationDocumentsScreen), findsOneWidget);
      expect(paths, contains('/api/rental-applications/application/documents'));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('documents load failure retries to the honest empty state', (
    tester,
  ) async {
    var failed = true;
    final client = clientFor(
      (_) async => failed ? http.Response('', 500) : ok([]),
    );
    addTearDown(client.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: TenantDocumentsScreen(
          rentalApplicationApiService: RentalApplicationApiService(client),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Could not load your documents.'), findsOneWidget);
    failed = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('No application documents yet.'),
      findsOneWidget,
    );
  });
}
