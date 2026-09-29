import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rentflow_mobile/core/auth/token_storage.dart';
import 'package:rentflow_mobile/core/network/api_client.dart';
import 'package:rentflow_mobile/features/lease_agreements/screens/lease_details_screen.dart';
import 'package:rentflow_mobile/features/lease_agreements/screens/my_leases_screen.dart';
import 'package:rentflow_mobile/features/lease_agreements/services/lease_agreement_api_service.dart';
import 'package:rentflow_mobile/features/rental_offers/screens/my_rental_offers_screen.dart';
import 'package:rentflow_mobile/features/rental_offers/services/rental_offer_api_service.dart';
import 'package:rentflow_mobile/shared/theme/app_theme.dart';

class _MemoryTokenStorage implements TokenStorage {
  @override
  Future<void> deleteToken() async {}

  @override
  Future<String?> readToken() async => 'lease-ui-token';

  @override
  Future<void> saveToken(String token) async {}
}

const _leaseId = '11111111-1111-4111-8111-111111111111';

Map<String, dynamic> _leaseJson(
  int status, {
  String? id,
  String? updatedAt = '2029-11-21T12:15:00-04:00',
}) => {
  'id': id ?? _leaseId,
  'rentalOfferId': '22222222-2222-4222-8222-222222222222',
  'tenantId': '33333333-3333-4333-8333-333333333333',
  'propertyId': '44444444-4444-4444-8444-444444444444',
  'monthlyRent': 1250.75,
  'securityDeposit': 2500,
  'startDate': '2030-01-31',
  'endDate': '2031-01-30',
  'status': status,
  'createdAt': '2029-11-20T09:00:00Z',
  'updatedAt': updatedAt,
};

Map<String, dynamic> _offerJson() => {
  'id': '55555555-5555-4555-8555-555555555555',
  'rentalApplicationId': '66666666-6666-4666-8666-666666666666',
  'tenantId': '33333333-3333-4333-8333-333333333333',
  'propertyId': '44444444-4444-4444-8444-444444444444',
  'monthlyRent': 1250.75,
  'securityDeposit': 2500,
  'proposedStartDate': '2030-01-31',
  'proposedEndDate': '2031-01-30',
  'expiresAt': '2030-01-01T00:00:00Z',
  'status': 0,
  'landlordNote': null,
  'createdAt': '2029-11-20T09:00:00Z',
  'updatedAt': null,
};

ApiClient _apiClient(Future<http.Response> Function(http.Request) handler) =>
    ApiClient(
      baseUrl: 'http://test',
      httpClient: MockClient(handler),
      tokenStorage: _MemoryTokenStorage(),
    );

Future<void> _pumpList(
  WidgetTester tester,
  Future<http.Response> Function(http.Request) handler,
) async {
  final client = _apiClient(handler);
  addTearDown(client.close);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.build(),
      home: MyLeasesScreen(
        leaseAgreementApiService: LeaseAgreementApiService(client),
        rentalOfferApiService: RentalOfferApiService(client),
      ),
    ),
  );
}

Future<void> _pumpDetails(
  WidgetTester tester,
  Future<http.Response> Function(http.Request) handler,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 1600);
  addTearDown(tester.view.reset);
  final client = _apiClient(handler);
  addTearDown(client.close);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.build(),
      home: LeaseDetailsScreen(
        leaseId: _leaseId,
        leaseAgreementApiService: LeaseAgreementApiService(client),
      ),
    ),
  );
}

void main() {
  group('MyLeasesScreen', () {
    testWidgets('shows loading, all statuses, multiple leases, and terms', (
      tester,
    ) async {
      final response = Completer<http.Response>();
      await _pumpList(tester, (_) => response.future);
      expect(find.text('Loading leases'), findsOneWidget);

      response.complete(
        http.Response(
          jsonEncode([
            for (var status = 0; status <= 3; status++)
              _leaseJson(
                status,
                id: '11111111-1111-4111-8111-11111111111$status',
              ),
          ]),
          200,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Card), findsNWidgets(5));
      for (final status in ['Pending', 'Active', 'Terminated', 'Completed']) {
        expect(find.text(status), findsOneWidget);
      }
      expect(find.text('1250.75'), findsNWidgets(4));
      expect(find.text('2500.00'), findsNWidgets(4));
      expect(find.text('2030-01-31'), findsNWidgets(4));
      expect(find.text('2031-01-30'), findsNWidgets(4));
      expect(
        find.text('44444444-4444-4444-8444-444444444444'),
        findsNWidgets(4),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('empty state keeps Rental Offers entry available', (
      tester,
    ) async {
      final requests = <String>[];
      await _pumpList(tester, (request) async {
        requests.add(request.url.path);
        if (request.url.path == '/api/lease-agreements/mine') {
          return http.Response('[]', 200);
        }
        return http.Response(jsonEncode([_offerJson()]), 200);
      });
      await tester.pumpAndSettle();

      expect(find.text('No leases yet'), findsOneWidget);
      expect(find.byKey(const ValueKey('rental-offers-entry')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('rental-offers-entry')));
      await tester.pumpAndSettle();
      expect(find.byType(MyRentalOffersScreen), findsOneWidget);
      expect(requests, [
        '/api/lease-agreements/mine',
        '/api/rental-offers/mine',
      ]);
    });

    testWidgets('error has a retry action and retries the request', (
      tester,
    ) async {
      var calls = 0;
      await _pumpList(tester, (_) async {
        calls++;
        return calls == 1
            ? http.Response('{}', 503)
            : http.Response(jsonEncode([_leaseJson(1)]), 200);
      });
      await tester.pumpAndSettle();
      expect(
        find.text('The lease agreement request failed. Please try again.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.text('Active'), findsOneWidget);
    });

    testWidgets('refresh button reloads the lease list', (tester) async {
      var calls = 0;
      await _pumpList(tester, (_) async {
        calls++;
        return http.Response(jsonEncode([_leaseJson(calls == 1 ? 0 : 1)]), 200);
      });
      await tester.pumpAndSettle();
      expect(find.text('Pending'), findsOneWidget);
      await tester.tap(find.byTooltip('Refresh leases'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.text('Active'), findsOneWidget);
    });

    testWidgets(
      'lease card opens authoritative details and refreshes on return',
      (tester) async {
        final requests = <String>[];
        await _pumpList(tester, (request) async {
          requests.add(request.url.path);
          if (request.url.path == '/api/lease-agreements/mine') {
            return http.Response(jsonEncode([_leaseJson(1)]), 200);
          }
          return http.Response(jsonEncode(_leaseJson(1)), 200);
        });
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('lease-card-$_leaseId')));
        await tester.pumpAndSettle();
        expect(find.byType(LeaseDetailsScreen), findsOneWidget);
        expect(requests, [
          '/api/lease-agreements/mine',
          '/api/lease-agreements/$_leaseId',
        ]);

        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byType(MyLeasesScreen), findsOneWidget);
        expect(requests.last, '/api/lease-agreements/mine');
      },
    );
  });

  group('LeaseDetailsScreen', () {
    testWidgets('shows loading then authoritative read-only lease fields', (
      tester,
    ) async {
      final response = Completer<http.Response>();
      await _pumpDetails(tester, (_) => response.future);
      expect(find.text('Loading lease details'), findsOneWidget);
      response.complete(http.Response(jsonEncode(_leaseJson(1)), 200));
      await tester.pumpAndSettle();

      expect(find.text('Active'), findsOneWidget);
      expect(find.text('1250.75'), findsOneWidget);
      expect(find.text('2500.00'), findsOneWidget);
      expect(find.text('2030-01-31'), findsOneWidget);
      expect(find.text('2031-01-30'), findsOneWidget);
      expect(find.text('44444444-4444-4444-8444-444444444444'), findsOneWidget);
      expect(find.text('22222222-2222-4222-8222-222222222222'), findsOneWidget);
      expect(find.text('Created'), findsOneWidget);
      expect(find.text('Updated'), findsOneWidget);
      expect(find.text('Accept'), findsNothing);
      expect(find.text('Reject'), findsNothing);
      expect(find.text('Sign'), findsNothing);
      expect(find.text('Terminate'), findsNothing);
    });

    testWidgets('nullable updatedAt is omitted and Rent Schedule is pending', (
      tester,
    ) async {
      var calls = 0;
      await _pumpDetails(tester, (_) async {
        calls++;
        return http.Response(jsonEncode(_leaseJson(2, updatedAt: null)), 200);
      });
      await tester.pumpAndSettle();
      expect(find.text('Terminated'), findsOneWidget);
      expect(find.text('Updated'), findsNothing);
      expect(find.byKey(const ValueKey('rent-schedule-entry')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('rent-schedule-entry')));
      await tester.pumpAndSettle();
      expect(find.text('Integration pending'), findsOneWidget);
      expect(find.text('Rent Schedule'), findsWidgets);
      expect(calls, 1);
    });

    testWidgets('403 shows a safe permission message', (tester) async {
      await _pumpDetails(tester, (_) async => http.Response('{}', 403));
      await tester.pumpAndSettle();
      expect(
        find.text('You do not have permission to access this resource.'),
        findsOneWidget,
      );
      expect(find.text('{}'), findsNothing);
    });

    testWidgets('404 shows a safe unavailable state', (tester) async {
      await _pumpDetails(tester, (_) async => http.Response('{}', 404));
      await tester.pumpAndSettle();
      expect(
        find.text('The requested lease agreement is unavailable.'),
        findsOneWidget,
      );
    });

    testWidgets('server and connection failures can be retried safely', (
      tester,
    ) async {
      var calls = 0;
      await _pumpDetails(tester, (_) async {
        calls++;
        if (calls == 1) return http.Response('secret backend text', 500);
        if (calls == 2) throw http.ClientException('connection internals');
        return http.Response(jsonEncode(_leaseJson(3)), 200);
      });
      await tester.pumpAndSettle();
      expect(
        find.text('The lease agreement request failed. Please try again.'),
        findsOneWidget,
      );
      expect(find.text('secret backend text'), findsNothing);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(
        find.text('Unable to connect to the lease agreement service.'),
        findsOneWidget,
      );
      expect(find.text('connection internals'), findsNothing);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(calls, 3);
      expect(find.text('Completed'), findsOneWidget);
    });
  });
}
