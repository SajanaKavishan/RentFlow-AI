import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rentflow_mobile/core/auth/token_storage.dart';
import 'package:rentflow_mobile/core/constants/api_constants.dart';
import 'package:rentflow_mobile/core/network/api_client.dart';
import 'package:rentflow_mobile/features/lease_agreements/models/lease_agreement.dart';
import 'package:rentflow_mobile/features/lease_agreements/services/lease_agreement_api_service.dart';

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

const _leaseId = '11111111-1111-4111-8111-111111111111';

Map<String, dynamic> _leaseJson({int status = 0}) => {
  'id': _leaseId,
  'rentalOfferId': '22222222-2222-4222-8222-222222222222',
  'tenantId': '33333333-3333-4333-8333-333333333333',
  'propertyId': '44444444-4444-4444-8444-444444444444',
  'monthlyRent': 1250.75,
  'securityDeposit': 2500,
  'startDate': '2030-01-31',
  'endDate': '2031-01-30',
  'status': status,
  'createdAt': '2029-11-20T09:00:00Z',
  'updatedAt': '2029-11-21T12:15:00-04:00',
};

ApiClient _client(
  Future<http.Response> Function(http.Request) handler, {
  _MemoryTokenStorage? storage,
}) => ApiClient(
  baseUrl: 'http://test',
  httpClient: MockClient(handler),
  tokenStorage: storage ?? _MemoryTokenStorage('lease-token'),
);

void main() {
  group('LeaseAgreement model', () {
    test(
      'parses required fields, decimals, DateOnly, and offset timestamps',
      () {
        final lease = LeaseAgreement.fromJson(_leaseJson());

        expect(lease.id, _leaseId);
        expect(lease.rentalOfferId, '22222222-2222-4222-8222-222222222222');
        expect(lease.tenantId, '33333333-3333-4333-8333-333333333333');
        expect(lease.propertyId, '44444444-4444-4444-8444-444444444444');
        expect(lease.monthlyRent, 1250.75);
        expect(lease.securityDeposit, 2500.0);
        expect(lease.startDate, DateTime(2030, 1, 31));
        expect(lease.endDate, DateTime(2031, 1, 30));
        expect(lease.status, LeaseAgreementStatus.pending);
        expect(lease.createdAt, DateTime.utc(2029, 11, 20, 9));
        expect(lease.updatedAt, DateTime.utc(2029, 11, 21, 16, 15));
      },
    );

    test('parses nullable updatedAt', () {
      final lease = LeaseAgreement.fromJson(_leaseJson()..['updatedAt'] = null);
      expect(lease.updatedAt, isNull);
    });

    test(
      'maps all numeric statuses and rejects unknown or nonnumeric values',
      () {
        expect([
          for (var status = 0; status <= 3; status++)
            LeaseAgreement.fromJson(_leaseJson(status: status)).status,
        ], LeaseAgreementStatus.values);
        expect(
          () => LeaseAgreement.fromJson(_leaseJson(status: 4)),
          throwsFormatException,
        );
        expect(
          () => LeaseAgreement.fromJson(_leaseJson()..['status'] = 'Active'),
          throwsFormatException,
        );
      },
    );

    test('rejects missing and malformed required fields', () {
      final missing = _leaseJson()..remove('tenantId');
      final malformed = _leaseJson()..['monthlyRent'] = '1250.75';
      final invalidDate = _leaseJson()..['startDate'] = '2030-02-30';
      final invalidTimestamp = _leaseJson()..['createdAt'] = 'yesterday';

      expect(() => LeaseAgreement.fromJson(missing), throwsFormatException);
      expect(() => LeaseAgreement.fromJson(malformed), throwsFormatException);
      expect(() => LeaseAgreement.fromJson(invalidDate), throwsFormatException);
      expect(
        () => LeaseAgreement.fromJson(invalidTimestamp),
        throwsFormatException,
      );
    });
  });

  group('LeaseAgreementApiService', () {
    test(
      'GET mine uses exact route, bearer header, and parses a list',
      () async {
        final requests = <http.Request>[];
        final apiClient = _client((request) async {
          requests.add(request);
          return http.Response(jsonEncode([_leaseJson()]), 200);
        });
        addTearDown(apiClient.close);
        final service = LeaseAgreementApiService(apiClient);

        final leases = await service.getMyLeases();

        expect(requests.single.method, 'GET');
        expect(requests.single.url.path, '/api/lease-agreements/mine');
        expect(requests.single.headers['authorization'], 'Bearer lease-token');
        expect(leases, hasLength(1));
        expect(leases.single, isA<LeaseAgreement>());
        expect(leases.single.id, _leaseId);
      },
    );

    test('GET detail uses exact route and parses a lease', () async {
      final requests = <http.Request>[];
      final apiClient = _client((request) async {
        requests.add(request);
        return http.Response(jsonEncode(_leaseJson(status: 1)), 200);
      });
      addTearDown(apiClient.close);
      final service = LeaseAgreementApiService(apiClient);

      final lease = await service.getLease(_leaseId);

      expect(requests.single.method, 'GET');
      expect(requests.single.url.path, '/api/lease-agreements/$_leaseId');
      expect(requests.single.headers['authorization'], 'Bearer lease-token');
      expect(lease, isA<LeaseAgreement>());
      expect(lease.status, LeaseAgreementStatus.active);
    });

    for (final statusCode in [401, 403, 404, 500]) {
      test('safely handles HTTP $statusCode', () async {
        final apiClient = _client(
          (_) async =>
              http.Response('{"detail":"internal detail"}', statusCode),
        );
        addTearDown(apiClient.close);
        final service = LeaseAgreementApiService(apiClient);

        await expectLater(
          service.getMyLeases(),
          throwsA(
            isA<LeaseAgreementApiException>()
                .having((error) => error.statusCode, 'statusCode', statusCode)
                .having((error) => error.message, 'message', isNotEmpty),
          ),
        );
      });
    }

    test('uses a safe message for 5xx responses', () async {
      final apiClient = _client(
        (_) async => http.Response('{"detail":"database password"}', 503),
      );
      addTearDown(apiClient.close);
      final service = LeaseAgreementApiService(apiClient);

      await expectLater(
        service.getLease(_leaseId),
        throwsA(
          isA<LeaseAgreementApiException>().having(
            (error) => error.message,
            'message',
            'The lease agreement request failed. Please try again.',
          ),
        ),
      );
    });

    test(
      'converts malformed JSON and invalid DTO payloads to safe errors',
      () async {
        for (final body in ['not json', '{}', '[{}]']) {
          final apiClient = _client((_) async => http.Response(body, 200));
          addTearDown(apiClient.close);
          final service = LeaseAgreementApiService(apiClient);

          await expectLater(
            service.getMyLeases(),
            throwsA(isA<LeaseAgreementApiException>()),
          );
        }
      },
    );

    test('converts connection errors to a safe API exception', () async {
      final apiClient = _client((_) async {
        throw http.ClientException('private connection detail');
      });
      addTearDown(apiClient.close);
      final service = LeaseAgreementApiService(apiClient);

      await expectLater(
        service.getMyLeases(),
        throwsA(
          isA<LeaseAgreementApiException>().having(
            (error) => error.message,
            'message',
            'Unable to connect to the lease agreement service.',
          ),
        ),
      );
    });
  });

  test('defines the expected lease agreement route prefix', () {
    expect(ApiConstants.leaseAgreementsPath, '/api/lease-agreements');
  });
}
