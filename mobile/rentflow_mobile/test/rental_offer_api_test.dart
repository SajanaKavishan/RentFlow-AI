import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rentflow_mobile/core/auth/token_storage.dart';
import 'package:rentflow_mobile/core/network/api_client.dart';
import 'package:rentflow_mobile/features/rental_offers/models/rental_offer.dart';
import 'package:rentflow_mobile/features/rental_offers/services/rental_offer_api_service.dart';

class _MemoryTokenStorage implements TokenStorage {
  _MemoryTokenStorage(this.token);

  String? token;

  @override
  Future<void> deleteToken() async => token = null;

  @override
  Future<String?> readToken() async => token;

  @override
  Future<void> saveToken(String value) async => token = value;
}

const _offerId = '11111111-1111-4111-8111-111111111111';

Map<String, dynamic> _offerJson({int status = 0}) => {
  'id': _offerId,
  'rentalApplicationId': '22222222-2222-4222-8222-222222222222',
  'tenantId': '33333333-3333-4333-8333-333333333333',
  'propertyId': '44444444-4444-4444-8444-444444444444',
  'monthlyRent': 1250.75,
  'securityDeposit': 2500,
  'proposedStartDate': '2030-01-31',
  'proposedEndDate': '2031-01-30',
  'expiresAt': '2029-12-01T18:30:00+05:30',
  'status': status,
  'landlordNote': 'Please review the terms.',
  'createdAt': '2029-11-20T09:00:00Z',
  'updatedAt': '2029-11-21T12:15:00-04:00',
};

ApiClient _client(
  Future<http.Response> Function(http.Request) handler, {
  TokenStorage? storage,
}) => ApiClient(
  baseUrl: 'http://test',
  httpClient: MockClient(handler),
  tokenStorage: storage ?? _MemoryTokenStorage('test-token'),
);

void main() {
  test(
    'parses complete offer, decimal numbers, dates, and offset timestamps',
    () {
      final offer = RentalOffer.fromJson(_offerJson());
      expect(offer.id, _offerId);
      expect(offer.rentalApplicationId, '22222222-2222-4222-8222-222222222222');
      expect(offer.tenantId, '33333333-3333-4333-8333-333333333333');
      expect(offer.propertyId, '44444444-4444-4444-8444-444444444444');
      expect(offer.monthlyRent, 1250.75);
      expect(offer.securityDeposit, 2500.0);
      expect(offer.proposedStartDate, DateTime(2030, 1, 31));
      expect(offer.proposedEndDate, DateTime(2031, 1, 30));
      expect(offer.expiresAt, DateTime.utc(2029, 12, 1, 13));
      expect(offer.status, RentalOfferStatus.pending);
      expect(offer.landlordNote, 'Please review the terms.');
      expect(offer.createdAt, DateTime.utc(2029, 11, 20, 9));
      expect(offer.updatedAt, DateTime.utc(2029, 11, 21, 16, 15));
    },
  );

  test('accepts nullable note and update timestamp', () {
    final offer = RentalOffer.fromJson(
      _offerJson()
        ..['landlordNote'] = null
        ..['updatedAt'] = null,
    );
    expect(offer.landlordNote, isNull);
    expect(offer.updatedAt, isNull);
  });

  test('maps all numeric statuses and rejects unknown values', () {
    expect([
      for (var status = 0; status <= 4; status++)
        RentalOffer.fromJson(_offerJson(status: status)).status,
    ], RentalOfferStatus.values);
    expect(
      () => RentalOffer.fromJson(_offerJson(status: 5)),
      throwsFormatException,
    );
    expect(
      () => RentalOffer.fromJson(_offerJson()..['status'] = 'Pending'),
      throwsFormatException,
    );
  });

  test('rejects missing and malformed required fields', () {
    expect(
      () => RentalOffer.fromJson(_offerJson()..remove('id')),
      throwsFormatException,
    );
    expect(
      () => RentalOffer.fromJson(_offerJson()..['monthlyRent'] = '1250'),
      throwsFormatException,
    );
    expect(
      () => RentalOffer.fromJson(_offerJson()..['landlordNote'] = 1),
      throwsFormatException,
    );
    expect(
      () => RentalOffer.fromJson(
        _offerJson()..['proposedStartDate'] = '2030-02-30',
      ),
      throwsFormatException,
    );
    expect(
      () => RentalOffer.fromJson(_offerJson()..['expiresAt'] = '2029-12-01'),
      throwsFormatException,
    );
    expect(
      () => RentalOffer.fromJson(_offerJson()..['updatedAt'] = 1),
      throwsFormatException,
    );
  });

  test(
    'all four tenant calls use exact routes, bearer token, and bodyless PATCH',
    () async {
      final requests = <http.Request>[];
      final client = _client((request) async {
        requests.add(request);
        final status = request.url.path.endsWith('/accept')
            ? 1
            : request.url.path.endsWith('/reject')
            ? 2
            : 0;
        return http.Response(
          jsonEncode(
            request.url.path.endsWith('/mine')
                ? [_offerJson()]
                : _offerJson(status: status),
          ),
          200,
        );
      });
      addTearDown(client.close);
      final service = RentalOfferApiService(client);

      final offers = await service.getMyOffers();
      final detail = await service.getOffer(_offerId);
      final accepted = await service.acceptOffer(_offerId);
      final rejected = await service.rejectOffer(_offerId);

      expect(offers, hasLength(1));
      expect(offers.single.id, _offerId);
      expect(detail.id, _offerId);
      expect(accepted.status, RentalOfferStatus.accepted);
      expect(rejected.status, RentalOfferStatus.rejected);
      expect(requests.map((request) => request.method), [
        'GET',
        'GET',
        'PATCH',
        'PATCH',
      ]);
      expect(requests.map((request) => request.url.path), [
        '/api/rental-offers/mine',
        '/api/rental-offers/$_offerId',
        '/api/rental-offers/$_offerId/accept',
        '/api/rental-offers/$_offerId/reject',
      ]);
      for (final request in requests) {
        expect(request.url.queryParameters, isEmpty);
        expect(request.headers['Authorization'], 'Bearer test-token');
      }
      expect(requests[2].body, isEmpty);
      expect(requests[3].body, isEmpty);
    },
  );

  for (final (status, message) in [
    (401, 'Your session has expired.'),
    (403, 'You do not have permission to access this resource.'),
    (404, 'The requested rental offer is unavailable.'),
    (409, 'This offer has changed. Refresh and try again.'),
    (500, 'The rental offer request failed. Please try again.'),
  ]) {
    test('handles $status with a safe message', () async {
      final storage = _MemoryTokenStorage('test-token');
      final client = _client(
        (_) async => http.Response('Internal server details', status),
        storage: storage,
      );
      addTearDown(client.close);
      await expectLater(
        RentalOfferApiService(client).getOffer(_offerId),
        throwsA(
          isA<RentalOfferApiException>()
              .having((error) => error.statusCode, 'statusCode', status)
              .having((error) => error.message, 'message', message),
        ),
      );
      if (status == 401) expect(storage.token, isNull);
    });
  }

  test('wraps connection errors', () async {
    final client = _client(
      (_) async => throw http.ClientException('socket detail'),
    );
    addTearDown(client.close);
    await expectLater(
      RentalOfferApiService(client).getMyOffers(),
      throwsA(
        isA<RentalOfferApiException>().having(
          (error) => error.message,
          'message',
          'Unable to connect to the rental offer service.',
        ),
      ),
    );
  });

  test('rejects malformed object, list, and DTO responses', () async {
    for (final (path, body) in [
      ('/mine', '{'),
      ('/mine', '{}'),
      ('/mine', '[{}]'),
      ('/$_offerId', '[]'),
      ('/$_offerId', '{}'),
    ]) {
      final client = _client((_) async => http.Response(body, 200));
      try {
        final service = RentalOfferApiService(client);
        await expectLater(
          path == '/mine' ? service.getMyOffers() : service.getOffer(_offerId),
          throwsA(
            isA<RentalOfferApiException>().having(
              (error) => error.message,
              'message',
              'The rental offer service returned an invalid response.',
            ),
          ),
        );
      } finally {
        client.close();
      }
    }
  });
}
