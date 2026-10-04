import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rentflow_mobile/features/notifications/models/notification_preferences.dart';
import 'package:rentflow_mobile/features/notifications/services/notification_preferences_api_service.dart';

import 'helpers/notification_preferences_backend.dart';

void main() {
  late NotificationPreferencesBackend backend;
  setUp(() => backend = NotificationPreferencesBackend());
  tearDown(() => backend.dispose());

  test(
    'GET uses authenticated existing endpoint and parses actual booleans',
    () async {
      final result = await backend.service.getNotificationPreferences();
      expect(result.viewingUpdatesEnabled, isFalse);
      expect(result.rentalApplicationUpdatesEnabled, isTrue);
      expect(result.accountSecurityUpdatesEnabled, isTrue);
      expect(backend.loads.single.url.path, preferencesPath);
      expect(backend.loads.single.url.query, isEmpty);
      expect(
        backend.loads.single.headers['Authorization'],
        'Bearer preferences-token',
      );
    },
  );

  for (final viewing in [false, true]) {
    for (final applications in [false, true]) {
      test(
        'PUT sends both optional settings $viewing/$applications and security true',
        () async {
          await backend.storage.saveToken('replacement-token');
          final result = await backend.service.updateNotificationPreferences(
            viewingUpdatesEnabled: viewing,
            rentalApplicationUpdatesEnabled: applications,
          );
          expect(backend.saves.single.url.path, preferencesPath);
          expect(
            backend.saves.single.headers['Authorization'],
            'Bearer replacement-token',
          );
          expect(
            backend.saves.single.headers['Content-Type'],
            'application/json',
          );
          expect(
            jsonDecode(backend.saves.single.body),
            preferencesJson(viewing: viewing, applications: applications),
          );
          expect(result.viewingUpdatesEnabled, viewing);
          expect(result.rentalApplicationUpdatesEnabled, applications);
          expect(result.accountSecurityUpdatesEnabled, isTrue);
        },
      );
    }
  }

  for (final key in [
    'viewingUpdatesEnabled',
    'rentalApplicationUpdatesEnabled',
    'accountSecurityUpdatesEnabled',
  ]) {
    for (final value in [null, 'true', 'false', 0, 1]) {
      test('model rejects invalid $key=$value instead of defaulting', () {
        expect(
          () => NotificationPreferences.fromJson({
            ...preferencesJson(),
            key: value,
          }),
          throwsFormatException,
        );
      });
    }
    test('model rejects missing $key', () {
      final json = preferencesJson()..remove(key);
      expect(
        () => NotificationPreferences.fromJson(json),
        throwsFormatException,
      );
    });
  }
  test(
    'security false is rejected; copyWith can change only editable fields',
    () {
      expect(
        () => NotificationPreferences.fromJson({
          ...preferencesJson(),
          'accountSecurityUpdatesEnabled': false,
        }),
        throwsFormatException,
      );
      final confirmed = NotificationPreferences.fromJson(preferencesJson());
      final draft = confirmed.copyWith(
        viewingUpdatesEnabled: true,
        rentalApplicationUpdatesEnabled: false,
      );
      expect(confirmed.viewingUpdatesEnabled, isFalse);
      expect(confirmed.rentalApplicationUpdatesEnabled, isTrue);
      expect(draft.viewingUpdatesEnabled, isTrue);
      expect(draft.rentalApplicationUpdatesEnabled, isFalse);
      expect(draft.accountSecurityUpdatesEnabled, isTrue);
    },
  );

  for (final body in [
    'not json',
    'null',
    '[]',
    '{}',
    jsonEncode({...preferencesJson(), 'viewingUpdatesEnabled': 'false'}),
    jsonEncode({...preferencesJson(), 'accountSecurityUpdatesEnabled': false}),
  ]) {
    for (final method in ['GET', 'PUT']) {
      test('$method malformed success is a safe error: $body', () async {
        backend.getBody = body;
        backend.putBody = body;
        final future = method == 'GET'
            ? backend.service.getNotificationPreferences()
            : backend.service.updateNotificationPreferences(
                viewingUpdatesEnabled: true,
                rentalApplicationUpdatesEnabled: false,
              );
        await expectLater(
          future,
          throwsA(
            isA<NotificationPreferencesApiException>().having(
              (e) => e.message,
              'message',
              'The service returned invalid notification preferences. Please try again.',
            ),
          ),
        );
      });
    }
  }

  for (final status in [400, 403, 429, 500]) {
    for (final method in ['GET', 'PUT']) {
      test(
        '$method status $status exposes safe errors without server internals',
        () async {
          backend.getStatus = status;
          backend.putStatus = status;
          backend.getBody = 'private server trace';
          backend.putBody = 'private server trace';
          final future = method == 'GET'
              ? backend.service.getNotificationPreferences()
              : backend.service.updateNotificationPreferences(
                  viewingUpdatesEnabled: true,
                  rentalApplicationUpdatesEnabled: false,
                );
          await expectLater(
            future,
            throwsA(
              isA<NotificationPreferencesApiException>()
                  .having((e) => e.statusCode, 'status', status)
                  .having(
                    (e) => e.message,
                    'message',
                    isNot(contains('private')),
                  ),
            ),
          );
        },
      );
    }
  }
  for (final method in ['GET', 'PUT']) {
    test('$method 401 uses existing session handler', () async {
      await backend.auth.restoreSession();
      backend.getStatus = 401;
      backend.putStatus = 401;
      final future = method == 'GET'
          ? backend.service.getNotificationPreferences()
          : backend.service.updateNotificationPreferences(
              viewingUpdatesEnabled: true,
              rentalApplicationUpdatesEnabled: false,
            );
      await expectLater(
        future,
        throwsA(
          isA<NotificationPreferencesApiException>().having(
            (e) => e.statusCode,
            'status',
            401,
          ),
        ),
      );
      expect(backend.auth.isAuthenticated, isFalse);
      expect(backend.storage.token, isNull);
    });
    test('$method network failure has a safe retry message', () async {
      backend.failNetwork = true;
      final future = method == 'GET'
          ? backend.service.getNotificationPreferences()
          : backend.service.updateNotificationPreferences(
              viewingUpdatesEnabled: true,
              rentalApplicationUpdatesEnabled: false,
            );
      await expectLater(
        future,
        throwsA(
          isA<NotificationPreferencesApiException>().having(
            (e) => e.message,
            'message',
            'Unable to connect. Please try again.',
          ),
        ),
      );
    });
  }
  test('request timeout is surfaced as retryable connection failure', () async {
    backend.dispose();
    backend = NotificationPreferencesBackend(
      timeout: const Duration(milliseconds: 20),
    );
    backend.pendingGet = Completer();
    await expectLater(
      backend.service.getNotificationPreferences(),
      throwsA(
        isA<NotificationPreferencesApiException>().having(
          (e) => e.message,
          'message',
          'Unable to connect. Please try again.',
        ),
      ),
    );
  });
}
