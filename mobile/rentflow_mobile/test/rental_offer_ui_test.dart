import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rentflow_mobile/core/auth/token_storage.dart';
import 'package:rentflow_mobile/core/network/api_client.dart';
import 'package:rentflow_mobile/features/rental_offers/screens/my_rental_offers_screen.dart';
import 'package:rentflow_mobile/features/rental_offers/screens/rental_offer_details_screen.dart';
import 'package:rentflow_mobile/features/rental_offers/services/rental_offer_api_service.dart';
import 'package:rentflow_mobile/shared/theme/app_theme.dart';

class _MemoryTokenStorage implements TokenStorage {
  @override
  Future<void> deleteToken() async {}

  @override
  Future<String?> readToken() async => 'offer-ui-token';

  @override
  Future<void> saveToken(String token) async {}
}

Map<String, dynamic> _offerJson(
  int status, {
  String? id,
  String? note,
  String? expiresAt,
  String? updatedAt,
}) => {
  'id': id ?? '11111111-1111-4111-8111-111111111111',
  'rentalApplicationId': '22222222-2222-4222-8222-222222222222',
  'tenantId': '33333333-3333-4333-8333-333333333333',
  'propertyId': '44444444-4444-4444-8444-444444444444',
  'monthlyRent': 1250.75,
  'securityDeposit': 2500,
  'proposedStartDate': '2030-01-31',
  'proposedEndDate': '2031-01-30',
  'expiresAt': expiresAt ?? '2029-12-01T18:30:00+05:30',
  'status': status,
  'landlordNote': note,
  'createdAt': '2029-11-20T09:00:00Z',
  'updatedAt': updatedAt,
};

Future<void> _pump(
  WidgetTester tester,
  Future<http.Response> Function(http.Request) handler,
) async {
  final client = ApiClient(
    baseUrl: 'http://test',
    httpClient: MockClient(handler),
    tokenStorage: _MemoryTokenStorage(),
  );
  addTearDown(client.close);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.build(),
      home: MyRentalOffersScreen(
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
  final client = ApiClient(
    baseUrl: 'http://test',
    httpClient: MockClient(handler),
    tokenStorage: _MemoryTokenStorage(),
  );
  addTearDown(client.close);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.build(),
      home: RentalOfferDetailsScreen(
        offerId: '11111111-1111-4111-8111-111111111111',
        rentalOfferApiService: RentalOfferApiService(client),
      ),
    ),
  );
}

void main() {
  testWidgets('shows loading, then all offer statuses and available terms', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 6000);
    addTearDown(tester.view.reset);
    final response = Completer<http.Response>();
    var calls = 0;
    await _pump(tester, (request) {
      calls++;
      expect(request.url.path, '/api/rental-offers/mine');
      expect(request.headers['Authorization'], 'Bearer offer-ui-token');
      return response.future;
    });

    expect(find.text('Loading rental offers'), findsOneWidget);
    response.complete(
      http.Response(
        jsonEncode([
          for (var status = 0; status <= 4; status++)
            _offerJson(
              status,
              id: '11111111-1111-4111-8111-11111111111$status',
            ),
        ]),
        200,
      ),
    );
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(find.byType(Card), findsNWidgets(5));
    for (final status in [
      'Pending',
      'Accepted',
      'Rejected',
      'Withdrawn',
      'Expired',
    ]) {
      expect(find.text(status), findsOneWidget);
    }
    expect(find.text('44444444-4444-4444-8444-444444444444'), findsNWidgets(5));
    expect(find.text('1250.75'), findsNWidgets(5));
    expect(find.text('2500.00'), findsNWidgets(5));
    expect(find.text('2030-01-31'), findsNWidgets(5));
    expect(find.text('2031-01-30'), findsNWidgets(5));
    expect(find.text('Expires'), findsNWidgets(5));
    expect(find.textContaining('(local time)'), findsNWidgets(5));
    expect(find.text('View details'), findsNothing);
    expect(find.text('Accept offer'), findsNothing);
    expect(find.text('Reject offer'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty response shows shared empty state', (tester) async {
    await _pump(tester, (_) async => http.Response('[]', 200));
    await tester.pumpAndSettle();
    expect(find.text('No rental offers yet'), findsOneWidget);
    expect(
      find.text('Offers from landlords will appear here.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('nullable landlord note and multiple offers do not break list', (
    tester,
  ) async {
    await _pump(
      tester,
      (_) async => http.Response(
        jsonEncode([
          _offerJson(0),
          _offerJson(1, id: '55555555-5555-4555-8555-555555555555'),
        ]),
        200,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Card), findsNWidgets(2));
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('Accepted'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('403 error is safe and retry fetches offers again', (
    tester,
  ) async {
    var calls = 0;
    await _pump(tester, (_) async {
      calls++;
      return calls == 1
          ? http.Response('private backend details', 403)
          : http.Response(jsonEncode([_offerJson(0)]), 200);
    });
    await tester.pumpAndSettle();
    expect(find.text('Something went wrong'), findsOneWidget);
    expect(
      find.text('You do not have permission to access this resource.'),
      findsOneWidget,
    );
    expect(find.textContaining('private backend details'), findsNothing);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('Pending'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('malformed and server responses show retryable safe errors', (
    tester,
  ) async {
    var calls = 0;
    await _pump(tester, (_) async {
      calls++;
      return calls == 1
          ? http.Response('{', 200)
          : http.Response('private server details', 500);
    });
    await tester.pumpAndSettle();
    expect(
      find.text('The rental offer service returned an invalid response.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(
      find.text('The rental offer request failed. Please try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('private server details'), findsNothing);
  });

  testWidgets('refresh action requests the list again', (tester) async {
    var calls = 0;
    await _pump(tester, (_) async {
      calls++;
      return http.Response(jsonEncode([_offerJson(calls == 1 ? 0 : 1)]), 200);
    });
    await tester.pumpAndSettle();
    expect(find.text('Pending'), findsOneWidget);

    await tester.tap(find.byTooltip('Refresh rental offers'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('Accepted'), findsOneWidget);
  });

  testWidgets('details fetches by ID and renders terms and optional metadata', (
    tester,
  ) async {
    final response = Completer<http.Response>();
    var detailCalls = 0;
    await _pumpDetails(tester, (request) {
      detailCalls++;
      expect(request.method, 'GET');
      expect(
        request.url.path,
        '/api/rental-offers/11111111-1111-4111-8111-111111111111',
      );
      expect(request.headers['Authorization'], 'Bearer offer-ui-token');
      return response.future;
    });
    expect(find.text('Loading offer details'), findsOneWidget);
    response.complete(
      http.Response(
        jsonEncode(
          _offerJson(
            0,
            note: 'Review the proposed terms.',
            updatedAt: '2029-11-21T12:15:00Z',
          ),
        ),
        200,
      ),
    );
    await tester.pumpAndSettle();

    expect(detailCalls, 1);
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('44444444-4444-4444-8444-444444444444'), findsOneWidget);
    expect(find.text('22222222-2222-4222-8222-222222222222'), findsOneWidget);
    expect(find.text('1250.75'), findsOneWidget);
    expect(find.text('2500.00'), findsOneWidget);
    expect(find.text('2030-01-31'), findsOneWidget);
    expect(find.text('2031-01-30'), findsOneWidget);
    expect(find.text('Expires'), findsOneWidget);
    expect(find.text('Created'), findsOneWidget);
    expect(find.text('Updated'), findsOneWidget);
    expect(find.text('Review the proposed terms.'), findsOneWidget);
    expect(find.text('Accept offer'), findsOneWidget);
    expect(find.text('Reject offer'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('null note and updated timestamp omit optional sections', (
    tester,
  ) async {
    await _pumpDetails(
      tester,
      (_) async => http.Response(jsonEncode(_offerJson(0)), 200),
    );
    await tester.pumpAndSettle();
    expect(find.text('Landlord note'), findsNothing);
    expect(find.text('Updated'), findsNothing);
    expect(find.text('Pending'), findsOneWidget);
  });

  for (final (status, label) in [
    (1, 'Accepted'),
    (2, 'Rejected'),
    (3, 'Withdrawn'),
    (4, 'Expired'),
  ]) {
    testWidgets('$label detail hides tenant actions', (tester) async {
      await _pumpDetails(
        tester,
        (_) async => http.Response(jsonEncode(_offerJson(status)), 200),
      );
      await tester.pumpAndSettle();
      expect(find.text(label), findsOneWidget);
      expect(find.text('Accept offer'), findsNothing);
      expect(find.text('Reject offer'), findsNothing);
    });
  }

  testWidgets('locally expired pending offer hides tenant actions', (
    tester,
  ) async {
    await _pumpDetails(
      tester,
      (_) async => http.Response(
        jsonEncode(_offerJson(0, expiresAt: '2020-01-01T00:00:00Z')),
        200,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('Accept offer'), findsNothing);
    expect(find.text('Reject offer'), findsNothing);
  });

  for (final (status, message) in [
    (403, 'You do not have permission to access this resource.'),
    (404, 'The requested rental offer is unavailable.'),
  ]) {
    testWidgets('$status detail fetch shows safe error', (tester) async {
      await _pumpDetails(
        tester,
        (_) async => http.Response('private backend details', status),
      );
      await tester.pumpAndSettle();
      expect(find.text(message), findsOneWidget);
      expect(find.textContaining('private backend details'), findsNothing);
      expect(find.text('Try again'), findsOneWidget);
    });
  }

  testWidgets('detail retry recovers from server error', (tester) async {
    var calls = 0;
    await _pumpDetails(tester, (_) async {
      calls++;
      return calls == 1
          ? http.Response('private server details', 500)
          : http.Response(jsonEncode(_offerJson(0)), 200);
    });
    await tester.pumpAndSettle();
    expect(
      find.text('The rental offer request failed. Please try again.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('Pending'), findsOneWidget);
  });

  testWidgets('detail connection error is retryable', (tester) async {
    await _pumpDetails(
      tester,
      (_) async => throw http.ClientException('secret'),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Unable to connect to the rental offer service.'),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
    expect(find.textContaining('secret'), findsNothing);
  });

  for (final (action, resultStatus, resultLabel) in [
    ('accept', 1, 'Accepted'),
    ('reject', 2, 'Rejected'),
  ]) {
    testWidgets(
      '$action requires confirmation and cancellation sends no PATCH',
      (tester) async {
        var patchCalls = 0;
        await _pumpDetails(tester, (request) async {
          if (request.method == 'PATCH') patchCalls++;
          return http.Response(jsonEncode(_offerJson(0)), 200);
        });
        await tester.pumpAndSettle();
        final button = action == 'accept' ? 'Accept offer' : 'Reject offer';
        await tester.tap(find.text(button));
        await tester.pumpAndSettle();
        expect(
          find.text('${action == 'accept' ? 'Accept' : 'Reject'} this offer?'),
          findsOneWidget,
        );
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(patchCalls, 0);
        expect(find.text('Pending'), findsOneWidget);
      },
    );

    testWidgets('$action submits once, updates status, and shows success', (
      tester,
    ) async {
      final patchResponse = Completer<http.Response>();
      var patchCalls = 0;
      await _pumpDetails(tester, (request) {
        if (request.method == 'PATCH') {
          patchCalls++;
          expect(request.url.path, endsWith('/$action'));
          expect(request.body, isEmpty);
          return patchResponse.future;
        }
        return Future.value(http.Response(jsonEncode(_offerJson(0)), 200));
      });
      await tester.pumpAndSettle();
      final button = action == 'accept' ? 'Accept offer' : 'Reject offer';
      await tester.tap(find.text(button));
      await tester.pumpAndSettle();
      final dialog = find.byType(AlertDialog);
      await tester.tap(
        find.descendant(of: dialog, matching: find.text(button)),
      );
      await tester.pump();
      expect(patchCalls, 1);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('accept-offer-action')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('reject-offer-action')),
            )
            .onPressed,
        isNull,
      );

      patchResponse.complete(
        http.Response(jsonEncode(_offerJson(resultStatus)), 200),
      );
      await tester.pumpAndSettle();
      expect(find.text(resultLabel), findsOneWidget);
      expect(find.text('Accept offer'), findsNothing);
      expect(find.text('Reject offer'), findsNothing);
      expect(
        find.text(action == 'accept' ? 'Offer accepted.' : 'Offer rejected.'),
        findsOneWidget,
      );
      expect(find.textContaining('Lease created'), findsNothing);
      expect(patchCalls, 1);
    });

    testWidgets('$action conflict refetches authoritative status', (
      tester,
    ) async {
      var detailCalls = 0;
      var patchCalls = 0;
      await _pumpDetails(tester, (request) async {
        if (request.method == 'PATCH') {
          patchCalls++;
          return http.Response('private conflict details', 409);
        }
        detailCalls++;
        return http.Response(
          jsonEncode(_offerJson(detailCalls == 1 ? 0 : resultStatus)),
          200,
        );
      });
      await tester.pumpAndSettle();
      final button = action == 'accept' ? 'Accept offer' : 'Reject offer';
      await tester.tap(find.text(button));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(button),
        ),
      );
      await tester.pumpAndSettle();
      expect(patchCalls, 1);
      expect(detailCalls, 2);
      expect(find.text(resultLabel), findsOneWidget);
      expect(
        find.text('This offer has changed. Refresh and try again.'),
        findsWidgets,
      );
      expect(find.textContaining('private conflict details'), findsNothing);
      expect(find.text('Accept offer'), findsNothing);
      expect(find.text('Reject offer'), findsNothing);
    });
  }

  testWidgets('404 action refetch shows unavailable state', (tester) async {
    var detailCalls = 0;
    await _pumpDetails(tester, (request) async {
      if (request.method == 'PATCH') return http.Response('{}', 404);
      detailCalls++;
      return detailCalls == 1
          ? http.Response(jsonEncode(_offerJson(0)), 200)
          : http.Response('{}', 404);
    });
    await tester.pumpAndSettle();
    await tester.tap(find.text('Accept offer'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Accept offer'),
      ),
    );
    await tester.pumpAndSettle();
    expect(detailCalls, 2);
    expect(
      find.text('The requested rental offer is unavailable.'),
      findsWidgets,
    );
    expect(find.text('Try again'), findsOneWidget);
  });

  for (final (status, message) in [
    (403, 'You do not have permission to access this resource.'),
    (500, 'The rental offer request failed. Please try again.'),
  ]) {
    testWidgets('$status action keeps offer and displays safe error', (
      tester,
    ) async {
      await _pumpDetails(
        tester,
        (request) async => request.method == 'PATCH'
            ? http.Response('private details', status)
            : http.Response(jsonEncode(_offerJson(0)), 200),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Accept offer'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Accept offer'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Pending'), findsOneWidget);
      expect(find.text(message), findsWidgets);
      expect(find.textContaining('private details'), findsNothing);
      expect(find.text('Accept offer'), findsOneWidget);
    });
  }

  testWidgets('list card opens detail and refreshes after return', (
    tester,
  ) async {
    var listCalls = 0;
    var detailCalls = 0;
    await _pump(tester, (request) async {
      if (request.url.path.endsWith('/mine')) {
        listCalls++;
        return http.Response(
          jsonEncode([_offerJson(listCalls == 1 ? 0 : 1)]),
          200,
        );
      }
      detailCalls++;
      return http.Response(jsonEncode(_offerJson(0)), 200);
    });
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey('offer-card-11111111-1111-4111-8111-111111111111'),
      ),
    );
    await tester.pumpAndSettle();
    expect(detailCalls, 1);
    expect(find.text('Offer details'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(listCalls, 2);
    expect(find.text('Accepted'), findsOneWidget);
  });
}
