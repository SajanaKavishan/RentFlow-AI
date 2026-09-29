import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rentflow_mobile/core/auth/token_storage.dart';
import 'package:rentflow_mobile/core/network/api_client.dart';
import 'package:rentflow_mobile/features/auth/models/current_user.dart';
import 'package:rentflow_mobile/features/rental_offers/screens/my_rental_offers_screen.dart';
import 'package:rentflow_mobile/features/rental_offers/screens/rental_offer_details_screen.dart';
import 'package:rentflow_mobile/features/rental_offers/services/rental_offer_api_service.dart';
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

void main() {
  testWidgets('tenant My Lease uses injected service and back returns home', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final apiClient = ApiClient(
      baseUrl: 'http://test',
      tokenStorage: _MemoryTokenStorage(),
      httpClient: MockClient((request) async {
        requests.add(request);
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
    final service = RentalOfferApiService(apiClient);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: SharedAppShell(
          user: _user(UserRole.tenant),
          rentalOfferApiService: service,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(requests, isEmpty);

    await tester.ensureVisible(find.text('My Lease'));
    await tester.tap(find.text('My Lease'));
    await tester.pumpAndSettle();
    expect(find.byType(MyRentalOffersScreen), findsOneWidget);
    expect(find.text('Your offers'), findsOneWidget);
    expect(
      identical(
        tester
            .widget<MyRentalOffersScreen>(find.byType(MyRentalOffersScreen))
            .rentalOfferApiService,
        service,
      ),
      isTrue,
    );
    expect(identical(service.apiClient, apiClient), isTrue);
    expect(requests.map((request) => request.url.path), [
      '/api/rental-offers/mine',
    ]);
    expect(
      requests.single.headers['Authorization'],
      'Bearer tenant-offer-token',
    );

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
    expect(find.byType(MyRentalOffersScreen), findsNothing);
    expect(find.text('My Lease'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);

    await tester.ensureVisible(find.text('Pay Rent'));
    await tester.tap(find.text('Pay Rent'));
    await tester.pumpAndSettle();
    expect(find.text('Integration pending'), findsOneWidget);
    expect(find.textContaining('payment module is integrated'), findsOneWidget);
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
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(),
          home: SharedAppShell(
            user: _user(role),
            rentalOfferApiService: RentalOfferApiService(apiClient),
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
