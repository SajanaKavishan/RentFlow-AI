import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rentflow_mobile/core/auth/token_storage.dart';
import 'package:rentflow_mobile/core/network/api_client.dart';
import 'package:rentflow_mobile/features/auth/models/current_user.dart';
import 'package:rentflow_mobile/features/lease_agreements/screens/lease_details_screen.dart';
import 'package:rentflow_mobile/features/lease_agreements/screens/my_leases_screen.dart';
import 'package:rentflow_mobile/features/lease_agreements/services/lease_agreement_api_service.dart';
import 'package:rentflow_mobile/features/payments/screens/payment_details_screen.dart';
import 'package:rentflow_mobile/features/payments/screens/pay_rent_screen.dart';
import 'package:rentflow_mobile/features/payments/services/payment_api_service.dart';
import 'package:rentflow_mobile/features/rental_offers/screens/my_rental_offers_screen.dart';
import 'package:rentflow_mobile/features/rental_offers/screens/rental_offer_details_screen.dart';
import 'package:rentflow_mobile/features/rental_offers/services/rental_offer_api_service.dart';
import 'package:rentflow_mobile/features/rent_schedules/screens/lease_rent_schedule_screen.dart';
import 'package:rentflow_mobile/features/rent_schedules/services/rent_schedule_api_service.dart';
import 'package:rentflow_mobile/shared/shell/shared_app_shell.dart';
import 'package:rentflow_mobile/shared/theme/app_theme.dart';

class _MemoryTokenStorage implements TokenStorage {
  @override
  Future<void> deleteToken() async {}

  @override
  Future<String?> readToken() async => 'tenant-offer-token';

  @override
  Future<void> saveToken(String token) async {}
}

CurrentUser _user(UserRole role) => CurrentUser(
  id: '33333333-3333-4333-8333-333333333333',
  fullName: 'Test User',
  email: 'test@example.com',
  phoneNumber: '0770000000',
  role: role,
);

Map<String, dynamic> _offerJson() => {
  'id': '11111111-1111-4111-8111-111111111111',
  'rentalApplicationId': '22222222-2222-4222-8222-222222222222',
  'tenantId': '33333333-3333-4333-8333-333333333333',
  'propertyId': '44444444-4444-4444-8444-444444444444',
  'monthlyRent': 1250.75,
  'securityDeposit': 2500,
  'proposedStartDate': '2030-01-31',
  'proposedEndDate': '2031-01-30',
  'expiresAt': '2029-12-01T18:30:00+05:30',
  'status': 0,
  'landlordNote': null,
  'createdAt': '2029-11-20T09:00:00Z',
  'updatedAt': null,
};

Map<String, dynamic> _leaseJson() => {
  'id': '11111111-1111-4111-8111-111111111111',
  'rentalOfferId': '22222222-2222-4222-8222-222222222222',
  'tenantId': '33333333-3333-4333-8333-333333333333',
  'propertyId': '44444444-4444-4444-8444-444444444444',
  'monthlyRent': 1250.75,
  'securityDeposit': 2500,
  'startDate': '2030-01-31',
  'endDate': '2031-01-30',
  'status': 1,
  'createdAt': '2029-11-20T09:00:00Z',
  'updatedAt': null,
};

void main() {
  testWidgets('tenant My Lease opens lease area with nested navigation', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final apiClient = ApiClient(
      baseUrl: 'http://test',
      tokenStorage: _MemoryTokenStorage(),
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/api/lease-agreements/mine') {
          return http.Response(jsonEncode([_leaseJson()]), 200);
        }
        if (request.url.path ==
            '/api/lease-agreements/11111111-1111-4111-8111-111111111111') {
          return http.Response(jsonEncode(_leaseJson()), 200);
        }
        if (request.url.path ==
            '/api/rent-schedules/lease/11111111-1111-4111-8111-111111111111') {
          return http.Response(
            jsonEncode([
              _scheduleItem('55555555-5555-4555-8555-555555555555', 0),
              _scheduleItem('66666666-6666-4666-8666-666666666666', 2),
              _scheduleItem('77777777-7777-4777-8777-777777777777', 1),
            ]),
            200,
          );
        }
        if (request.url.path ==
            '/api/rent-schedules/lease/11111111-1111-4111-8111-111111111111/outstanding') {
          return http.Response(
            jsonEncode({
              'totalPending': 1250.75,
              'totalOverdue': 1250.75,
              'totalOutstanding': 2501.5,
              'items': [
                _scheduleItem('55555555-5555-4555-8555-555555555555', 0),
                _scheduleItem('66666666-6666-4666-8666-666666666666', 2),
              ],
            }),
            200,
          );
        }
        if (request.url.path == '/api/rent-schedules/outstanding/mine') {
          return http.Response(
            jsonEncode({
              'totalPending': 1250.75,
              'totalOverdue': 1250.75,
              'totalOutstanding': 2501.5,
              'items': [
                _scheduleItem('55555555-5555-4555-8555-555555555555', 0),
                _scheduleItem('66666666-6666-4666-8666-666666666666', 2),
              ],
            }),
            200,
          );
        }
        if (request.url.path == '/api/payments/mine') {
          return http.Response(jsonEncode([_paymentJson()]), 200);
        }
        if (request.url.path ==
            '/api/payments/88888888-8888-4888-8888-888888888888') {
          return http.Response(jsonEncode(_paymentJson()), 200);
        }
        if (request.method == 'POST' && request.url.path == '/api/payments') {
          return http.Response(jsonEncode(_paymentJson()), 201);
        }
        if (request.url.path == '/api/rental-offers/mine') {
          return http.Response(jsonEncode([_offerJson()]), 200);
        }
        if (request.url.path ==
            '/api/rental-offers/11111111-1111-4111-8111-111111111111') {
          return http.Response(jsonEncode(_offerJson()), 200);
        }
        return http.Response('{}', 404);
      }),
    );
    addTearDown(apiClient.close);
    final offerService = RentalOfferApiService(apiClient);
    final leaseService = LeaseAgreementApiService(apiClient);
    final rentScheduleService = RentScheduleApiService(apiClient);
    final paymentService = PaymentApiService(apiClient);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: SharedAppShell(
          user: _user(UserRole.tenant),
          rentalOfferApiService: offerService,
          leaseAgreementApiService: leaseService,
          rentScheduleApiService: rentScheduleService,
          paymentApiService: paymentService,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(requests, isEmpty);

    await tester.ensureVisible(find.text('My Lease'));
    await tester.tap(find.text('My Lease'));
    await tester.pumpAndSettle();
    expect(find.byType(MyLeasesScreen), findsOneWidget);
    expect(find.byType(MyRentalOffersScreen), findsNothing);
    expect(find.text('Your leases'), findsOneWidget);
    expect(
      identical(
        tester
            .widget<MyLeasesScreen>(find.byType(MyLeasesScreen))
            .rentalOfferApiService,
        offerService,
      ),
      isTrue,
    );
    expect(
      identical(
        tester
            .widget<MyLeasesScreen>(find.byType(MyLeasesScreen))
            .leaseAgreementApiService,
        leaseService,
      ),
      isTrue,
    );
    expect(identical(leaseService.apiClient, apiClient), isTrue);
    expect(requests.map((request) => request.url.path), [
      '/api/lease-agreements/mine',
    ]);
    expect(
      requests.single.headers['Authorization'],
      'Bearer tenant-offer-token',
    );

    await tester.tap(
      find.byKey(
        const ValueKey('lease-card-11111111-1111-4111-8111-111111111111'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(LeaseDetailsScreen), findsOneWidget);
    expect(
      requests.last.url.path,
      '/api/lease-agreements/11111111-1111-4111-8111-111111111111',
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(MyLeasesScreen), findsOneWidget);
    expect(requests.last.url.path, '/api/lease-agreements/mine');

    await tester.tap(
      find.byKey(
        const ValueKey('lease-card-11111111-1111-4111-8111-111111111111'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('rent-schedule-entry')),
    );
    await tester.tap(find.byKey(const ValueKey('rent-schedule-entry')));
    await tester.pumpAndSettle();
    expect(find.byType(LeaseRentScheduleScreen), findsOneWidget);
    expect(
      find.textContaining('Rent schedule details will appear here'),
      findsNothing,
    );
    final scheduleScreen = tester.widget<LeaseRentScheduleScreen>(
      find.byType(LeaseRentScheduleScreen),
    );
    expect(
      identical(scheduleScreen.rentScheduleApiService, rentScheduleService),
      isTrue,
    );
    expect(
      scheduleScreen.leaseAgreementId,
      '11111111-1111-4111-8111-111111111111',
    );
    expect(
      identical(scheduleScreen.rentScheduleApiService.apiClient, apiClient),
      isTrue,
    );
    expect(identical(scheduleScreen.paymentApiService, paymentService), isTrue);
    expect(
      requests
          .map((request) => request.url.path)
          .where((path) => path.startsWith('/api/rent-schedules/')),
      [
        '/api/rent-schedules/lease/11111111-1111-4111-8111-111111111111',
        '/api/rent-schedules/lease/11111111-1111-4111-8111-111111111111/outstanding',
      ],
    );
    expect(
      find.byKey(
        const ValueKey(
          'rent-payment-placeholder-55555555-5555-4555-8555-555555555555',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey(
          'rent-payment-placeholder-66666666-6666-4666-8666-666666666666',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey(
          'rent-payment-placeholder-77777777-7777-4777-8777-777777777777',
        ),
      ),
      findsNothing,
    );
    await tester.ensureVisible(
      find.byKey(
        const ValueKey(
          'rent-payment-placeholder-55555555-5555-4555-8555-555555555555',
        ),
      ),
    );
    await tester.tap(
      find.byKey(
        const ValueKey(
          'rent-payment-placeholder-55555555-5555-4555-8555-555555555555',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(PayRentScreen), findsOneWidget);
    var payScreen = tester.widget<PayRentScreen>(find.byType(PayRentScreen));
    expect(
      payScreen.initialRentScheduleItemId,
      '55555555-5555-4555-8555-555555555555',
    );
    expect(identical(payScreen.paymentApiService, paymentService), isTrue);
    expect(
      identical(payScreen.rentScheduleApiService, rentScheduleService),
      isTrue,
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(LeaseRentScheduleScreen), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(
        const ValueKey(
          'rent-payment-placeholder-66666666-6666-4666-8666-666666666666',
        ),
      ),
    );
    await tester.tap(
      find.byKey(
        const ValueKey(
          'rent-payment-placeholder-66666666-6666-4666-8666-666666666666',
        ),
      ),
    );
    await tester.pumpAndSettle();
    payScreen = tester.widget<PayRentScreen>(find.byType(PayRentScreen));
    expect(
      payScreen.initialRentScheduleItemId,
      '66666666-6666-4666-8666-666666666666',
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(LeaseRentScheduleScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(LeaseDetailsScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(MyLeasesScreen), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('rental-offers-entry')));
    await tester.pumpAndSettle();
    expect(find.byType(MyRentalOffersScreen), findsOneWidget);
    final openedOffers = tester.widget<MyRentalOffersScreen>(
      find.byType(MyRentalOffersScreen),
    );
    expect(identical(openedOffers.rentalOfferApiService, offerService), isTrue);
    expect(
      identical(openedOffers.rentalOfferApiService.apiClient, apiClient),
      isTrue,
    );
    expect(requests.last.url.path, '/api/rental-offers/mine');

    await tester.tap(
      find.byKey(
        const ValueKey('offer-card-11111111-1111-4111-8111-111111111111'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(RentalOfferDetailsScreen), findsOneWidget);
    expect(
      requests.last.url.path,
      '/api/rental-offers/11111111-1111-4111-8111-111111111111',
    );
    expect(requests.last.headers['Authorization'], 'Bearer tenant-offer-token');

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(MyRentalOffersScreen), findsOneWidget);
    expect(requests.last.url.path, '/api/rental-offers/mine');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(MyLeasesScreen), findsOneWidget);
    expect(requests.last.url.path, '/api/rental-offers/mine');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(MyLeasesScreen), findsNothing);
    expect(find.text('My Lease'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);

    await tester.ensureVisible(find.text('Pay Rent'));
    await tester.tap(find.text('Pay Rent'));
    await tester.pumpAndSettle();
    expect(find.byType(PayRentScreen), findsOneWidget);
    payScreen = tester.widget<PayRentScreen>(find.byType(PayRentScreen));
    expect(payScreen.initialRentScheduleItemId, isNull);
    expect(identical(payScreen.paymentApiService, paymentService), isTrue);
    expect(
      identical(payScreen.rentScheduleApiService, rentScheduleService),
      isTrue,
    );
    final historyCard = find.byKey(
      const ValueKey(
        'payment-history-card-88888888-8888-4888-8888-888888888888',
      ),
    );
    await tester.ensureVisible(historyCard);
    await tester.pumpAndSettle();
    await tester.tap(historyCard);
    await tester.pumpAndSettle();
    expect(find.byType(PaymentDetailsScreen), findsOneWidget);
    final paymentDetails = tester.widget<PaymentDetailsScreen>(
      find.byType(PaymentDetailsScreen),
    );
    expect(paymentDetails.paymentId, '88888888-8888-4888-8888-888888888888');
    expect(identical(paymentDetails.paymentApiService, paymentService), isTrue);
    expect(
      requests.last.url.path,
      '/api/payments/88888888-8888-4888-8888-888888888888',
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(PayRentScreen), findsOneWidget);
  });

  for (final role in [UserRole.landlord, UserRole.admin]) {
    testWidgets('$role navigation does not expose tenant offers', (
      tester,
    ) async {
      var offerRequests = 0;
      final apiClient = ApiClient(
        baseUrl: 'http://test',
        tokenStorage: _MemoryTokenStorage(),
        httpClient: MockClient((_) async {
          offerRequests++;
          return http.Response('[]', 200);
        }),
      );
      addTearDown(apiClient.close);
      final leaseService = LeaseAgreementApiService(apiClient);
      final offerService = RentalOfferApiService(apiClient);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(),
          home: SharedAppShell(
            user: _user(role),
            leaseAgreementApiService: leaseService,
            rentalOfferApiService: offerService,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('My Lease'), findsNothing);
      expect(find.byType(MyRentalOffersScreen), findsNothing);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(offerRequests, 0);
    });
  }
}

Map<String, dynamic> _scheduleItem(String id, int status) => {
  'id': id,
  'leaseAgreementId': '11111111-1111-4111-8111-111111111111',
  'dueDate': status == 2 ? '2030-01-28' : '2030-02-28',
  'amount': 1250.75,
  'status': status,
  'createdAt': '2030-01-15T09:00:00Z',
  'updatedAt': null,
};

Map<String, dynamic> _paymentJson() => {
  'id': '88888888-8888-4888-8888-888888888888',
  'rentScheduleItemId': '55555555-5555-4555-8555-555555555555',
  'tenantId': '33333333-3333-4333-8333-333333333333',
  'amount': 1250.75,
  'paymentMethod': 'Bank transfer',
  'transactionReference': null,
  'status': 1,
  'paidAt': '2030-01-16T09:00:00Z',
  'createdAt': '2030-01-15T09:00:00Z',
  'updatedAt': null,
};
