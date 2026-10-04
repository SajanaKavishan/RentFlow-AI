import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rentflow_mobile/features/auth/controllers/auth_controller.dart';
import 'package:rentflow_mobile/features/auth/services/auth_service.dart';

import 'helpers/password_backend.dart';

void main() {
  late PasswordBackend backend;
  setUp(() => backend = PasswordBackend());
  tearDown(() => backend.dispose());

  Future<dynamic> serviceChange() => backend.auth.authService.changePassword(
    currentPassword: oldPassword,
    newPassword: newPassword,
    newPasswordConfirmation: newPassword,
  );

  test(
    'authenticated PUT sends exact body and parses message, JWT and expiry',
    () async {
      final result = await serviceChange();
      final request = backend.changes.single;
      expect(request.method, 'PUT');
      expect(request.headers['Authorization'], 'Bearer $oldToken');
      expect(jsonDecode(request.body), {
        'currentPassword': oldPassword,
        'newPassword': newPassword,
        'newPasswordConfirmation': newPassword,
      });
      expect(result.accessToken, replacementToken);
      expect(result.message, 'Your password was changed successfully.');
      expect(result.expiresAt, DateTime.utc(2030, 10, 4, 12));
    },
  );

  for (final token in [
    null,
    '',
    ' ',
    123,
    'token with spaces',
    'token\r\nheader',
    'token\n',
  ]) {
    test('rejects unusable replacement token: ${jsonEncode(token)}', () async {
      backend.response = {
        'message': 'Changed.',
        'accessToken': token,
        'expiresAt': '2030-10-04T12:00:00Z',
      };
      await expectLater(
        serviceChange(),
        throwsA(isA<PasswordChangeSessionException>()),
      );
    });
  }
  for (final invalid in [
    <String, Object>{},
    {
      'accessToken': replacementToken,
      'message': 'Changed.',
      'expiresAt': 'not-a-date',
    },
    {
      'accessToken': replacementToken,
      'message': 42,
      'expiresAt': '2030-10-04T12:00:00Z',
    },
    ['not-an-object'],
  ]) {
    test('malformed successful response rejected: $invalid', () async {
      backend.response = invalid;
      await expectLater(
        serviceChange(),
        throwsA(isA<PasswordChangeSessionException>()),
      );
    });
  }

  test('400 ProblemDetails preserves useful current-password error', () async {
    backend.status = 400;
    backend.response = {
      'title': 'Bad Request',
      'detail': 'The current password is incorrect.',
    };
    await expectLater(
      serviceChange(),
      throwsA(
        isA<AuthException>()
            .having((e) => e.statusCode, 'status', 400)
            .having(
              (e) => e.message,
              'message',
              'The current password is incorrect.',
            ),
      ),
    );
  });
  test('validation errors without a title are preserved', () async {
    backend.status = 400;
    backend.response = {
      'errors': {
        'NewPassword': ['Include an uppercase letter.'],
      },
    };
    await expectLater(
      serviceChange(),
      throwsA(
        isA<AuthException>().having(
          (e) => e.message,
          'message',
          'Include an uppercase letter.',
        ),
      ),
    );
  });
  for (final detail in [
    'trace containing $newPassword',
    'Bearer $replacementToken',
    'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.signature',
  ]) {
    test('server errors cannot echo credentials or JWT: $detail', () async {
      backend.status = 400;
      backend.response = {'detail': detail};
      await expectLater(
        serviceChange(),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'safe error',
            'Unable to change your password. Please try again.',
          ),
        ),
      );
    });
  }
  test('network failure exposes a safe retry message', () async {
    backend.networkFailure = true;
    await expectLater(
      serviceChange(),
      throwsA(
        isA<AuthException>()
            .having((e) => e.isConnectionFailure, 'connection', true)
            .having(
              (e) => e.message,
              'safe error',
              'Unable to connect. Please try again.',
            ),
      ),
    );
  });

  test(
    'replacement stays authenticated and next requests/restoration use new JWT',
    () async {
      await backend.auth.restoreSession();
      final user = backend.auth.currentUser;
      final logs = <String>[];
      final originalPrint = debugPrint;
      debugPrint = (message, {wrapWidth}) {
        if (message != null) logs.add(message);
      };
      try {
        await backend.change();
        expect(backend.storage.token, replacementToken);
        expect(backend.auth.currentUser, same(user));
        expect(backend.auth.isAuthenticated, isTrue);
        expect(backend.auth.isLoading, isFalse);
        await backend.auth.updateProfile(
          fullName: 'Updated name',
          phoneNumber: '+94771234567',
        );
        final profileWrite = backend.requests.last;
        expect(
          profileWrite.headers['Authorization'],
          'Bearer $replacementToken',
        );
        expect(
          jsonDecode(profileWrite.body).keys,
          isNot(contains('publicContactPhone')),
        );
        await backend.auth.updatePublicContact(
          backend.auth.currentUser!,
          '+94712223333',
          true,
        );
        expect(
          backend.requests.last.headers['Authorization'],
          'Bearer $replacementToken',
        );
        expect(
          jsonDecode(backend.requests.last.body)['fullName'],
          'Updated name',
        );
        final restored = AuthController(
          authService: backend.auth.authService,
          tokenStorage: backend.storage,
        );
        addTearDown(restored.dispose);
        await restored.restoreSession();
        expect(restored.isAuthenticated, isTrue);
        expect(
          backend.requests.last.headers['Authorization'],
          'Bearer $replacementToken',
        );
        await backend.auth.logout();
        expect(backend.auth.isAuthenticated, isFalse);
        expect(backend.storage.token, isNull);
        expect(logs.join('\n'), isNot(contains(oldToken)));
        expect(logs.join('\n'), isNot(contains(replacementToken)));
        expect(logs.join('\n'), isNot(contains(newPassword)));
      } finally {
        debugPrint = originalPrint;
      }
    },
  );

  test(
    'success and authenticated requests wait for durable token replacement',
    () async {
      await backend.auth.restoreSession();
      backend.storage.pendingSave = Completer<void>();
      var done = false;
      final change = backend.change().then((_) => done = true);
      await Future<void>.delayed(Duration.zero);
      expect(backend.storage.events, ['save-start']);
      expect(done, isFalse);
      expect(backend.storage.token, oldToken);
      final count = backend.requests.length;
      final following = backend.auth.authService.getCurrentUser();
      await Future<void>.delayed(Duration.zero);
      expect(backend.requests.length, count);
      backend.storage.pendingSave!.complete();
      await change;
      await following;
      expect(backend.storage.events, ['save-start', 'save-end']);
      expect(
        backend.requests.last.headers['Authorization'],
        'Bearer $replacementToken',
      );
    },
  );

  for (final failure in ['write', 'discarded-write', 'write-and-delete']) {
    test(
      'persistence failure $failure clears stale session with truthful message',
      () async {
        await backend.auth.restoreSession();
        backend.storage.failSave = failure != 'discarded-write';
        backend.storage.discardSave = failure == 'discarded-write';
        backend.storage.failDelete = failure == 'write-and-delete';
        await expectLater(
          backend.change(),
          throwsA(
            isA<PasswordChangeSessionException>().having(
              (e) => e.message,
              'message',
              'Your password was changed. Please sign in again.',
            ),
          ),
        );
        expect(backend.auth.isAuthenticated, isFalse);
        expect(
          backend.auth.signInNotice,
          'Your password was changed. Please sign in again.',
        );
        if (!backend.storage.failDelete) expect(backend.storage.token, isNull);
        await backend.auth.authService.getCurrentUser();
        expect(backend.requests.last.headers['Authorization'], isNull);
      },
    );
  }
  test(
    'write timeout clears session; late write never resumes authentication',
    () async {
      backend.dispose();
      backend = PasswordBackend(timeout: const Duration(milliseconds: 30));
      await backend.auth.restoreSession();
      backend.storage.pendingSave = Completer<void>();
      await expectLater(
        backend.change(),
        throwsA(isA<PasswordChangeSessionException>()),
      );
      expect(backend.auth.isAuthenticated, isFalse);
      backend.storage.pendingSave!.complete();
      await Future<void>.delayed(Duration.zero);
      expect(backend.storage.token, isNull);
      await backend.auth.authService.getCurrentUser();
      expect(backend.requests.last.headers['Authorization'], isNull);
    },
  );
  test(
    'malformed 2xx response clears old session instead of retaining invalid JWT',
    () async {
      await backend.auth.restoreSession();
      backend.response = {'message': 'Changed.'};
      await expectLater(
        backend.change(),
        throwsA(isA<PasswordChangeSessionException>()),
      );
      expect(backend.auth.isAuthenticated, isFalse);
      expect(backend.storage.token, isNull);
      expect(
        backend.auth.signInNotice,
        'Your password may have changed. Please sign in again.',
      );
    },
  );
  test(
    'success returning the old JWT is rejected and clears the invalid session',
    () async {
      await backend.auth.restoreSession();
      backend.response = {
        'message': 'Changed.',
        'accessToken': oldToken,
        'expiresAt': '2030-10-04T12:00:00Z',
      };
      await expectLater(
        backend.change(),
        throwsA(isA<PasswordChangeSessionException>()),
      );
      expect(backend.auth.isAuthenticated, isFalse);
      expect(backend.storage.token, isNull);
    },
  );
  test('401 uses existing unauthorized session flow', () async {
    await backend.auth.restoreSession();
    backend.status = 401;
    backend.response = {'detail': 'Your session is no longer valid.'};
    await expectLater(
      backend.change(),
      throwsA(isA<AuthException>().having((e) => e.statusCode, 'status', 401)),
    );
    expect(backend.auth.isAuthenticated, isFalse);
    expect(backend.storage.token, isNull);
  });
  for (final duringSave in [false, true]) {
    test(
      'delayed old-token 401 ${duringSave ? 'during persistence' : 'after replacement'} preserves new session',
      () async {
        await backend.auth.restoreSession();
        backend.pendingProtected = Completer<http.Response>();
        final previous = backend.client.get(
          backend.client.buildUri('/api/protected'),
        );
        await Future<void>.delayed(Duration.zero);
        expect(
          backend.requests.last.headers['Authorization'],
          'Bearer $oldToken',
        );
        if (duringSave) backend.storage.pendingSave = Completer<void>();
        final change = backend.change();
        await Future<void>.delayed(Duration.zero);
        backend.pendingProtected!.complete(http.Response('{}', 401));
        if (duringSave) backend.storage.pendingSave!.complete();
        await change;
        await previous;
        expect(backend.auth.isAuthenticated, isTrue);
        expect(backend.storage.token, replacementToken);
        await backend.auth.authService.getCurrentUser();
        expect(
          backend.requests.last.headers['Authorization'],
          'Bearer $replacementToken',
        );
      },
    );
  }
  test(
    'late response after logout cannot install replacement or reauthenticate',
    () async {
      await backend.auth.restoreSession();
      backend.pendingResponse = Completer<http.Response>();
      final change = backend.change();
      final assertion = expectLater(change, throwsA(isA<AuthException>()));
      await Future<void>.delayed(Duration.zero);
      await backend.auth.logout();
      backend.pendingResponse!.complete(
        http.Response(jsonEncode(backend.response), 200),
      );
      await assertion;
      expect(backend.storage.token, isNull);
      expect(backend.auth.isAuthenticated, isFalse);
      expect(backend.storage.events, isNot(contains('save-start')));
    },
  );
  test('controller prevents concurrent submissions', () async {
    await backend.auth.restoreSession();
    backend.pendingResponse = Completer<http.Response>();
    final first = backend.change();
    await expectLater(backend.change(), throwsA(isA<AuthException>()));
    await Future<void>.delayed(Duration.zero);
    expect(backend.changes, hasLength(1));
    expect(backend.auth.isChangingPassword, isTrue);
    backend.pendingResponse!.complete(
      http.Response(jsonEncode(backend.response), 200),
    );
    await first;
    expect(backend.auth.isChangingPassword, isFalse);
  });
}
