import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rentflow_mobile/core/auth/token_storage.dart';
import 'package:rentflow_mobile/core/network/api_client.dart';
import 'package:rentflow_mobile/features/auth/controllers/auth_controller.dart';
import 'package:rentflow_mobile/features/auth/models/current_user.dart';
import 'package:rentflow_mobile/features/auth/services/auth_service.dart';
import 'package:rentflow_mobile/main.dart';

class _MemoryTokenStorage implements TokenStorage {
  _MemoryTokenStorage([this.token]);

  String? token;

  @override
  Future<void> deleteToken() async => token = null;

  @override
  Future<String?> readToken() async => token;

  @override
  Future<void> saveToken(String value) async => token = value;
}

class _HangingReadTokenStorage implements TokenStorage {
  final _pendingRead = Completer<String?>();

  @override
  Future<void> deleteToken() async {}

  @override
  Future<String?> readToken() => _pendingRead.future;

  @override
  Future<void> saveToken(String token) async {}
}

class _HangingSaveTokenStorage implements TokenStorage {
  final _pendingSave = Completer<void>();

  @override
  Future<void> deleteToken() async {}

  @override
  Future<String?> readToken() async => null;

  @override
  Future<void> saveToken(String token) => _pendingSave.future;
}

class _HangingDeleteTokenStorage implements TokenStorage {
  final _pendingDelete = Completer<void>();

  @override
  Future<void> deleteToken() => _pendingDelete.future;

  @override
  Future<String?> readToken() async => 'expired-token';

  @override
  Future<void> saveToken(String token) async {}
}

Map<String, dynamic> _userJson() => {
  'id': '11111111-1111-4111-8111-111111111112',
  'fullName': 'Taylor Tenant',
  'email': 'tenant@example.com',
  'phoneNumber': '+94771234567',
  'role': 'Tenant',
};

({ApiClient client, AuthController controller}) _setup(
  TokenStorage storage,
  Future<http.Response> Function(http.Request) handler, {
  Duration requestTimeout = const Duration(seconds: 20),
}) {
  final client = ApiClient(
    baseUrl: 'http://test',
    httpClient: MockClient(handler),
    tokenStorage: storage,
    requestTimeout: requestTimeout,
  );
  final controller = AuthController(
    authService: AuthService(client),
    tokenStorage: storage,
  );
  client.setUnauthorizedHandler(controller.handleUnauthorized);
  return (client: client, controller: controller);
}

Future<void> _enterCredentials(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('login-email')),
    'tenant@example.com',
  );
  await tester.enterText(find.byKey(const Key('login-password')), 'Password1!');
  await tester.tap(find.byKey(const Key('login-submit')));
}

void main() {
  group('session restoration', () {
    test('no token skips /me and finishes unauthenticated', () async {
      final storage = _MemoryTokenStorage();
      var requests = 0;
      final setup = _setup(storage, (_) async {
        requests++;
        return http.Response('{}', 500);
      });
      addTearDown(setup.client.close);

      await setup.controller.restoreSession();

      expect(setup.controller.isLoading, isFalse);
      expect(setup.controller.isAuthenticated, isFalse);
      expect(storage.token, isNull);
      expect(requests, 0);
    });

    test('valid token and reachable /me restore authenticated user', () async {
      final storage = _MemoryTokenStorage('saved-token');
      final paths = <String>[];
      final setup = _setup(storage, (request) async {
        paths.add(request.url.path);
        expect(request.headers['authorization'], 'Bearer saved-token');
        return http.Response(jsonEncode(_userJson()), 200);
      });
      addTearDown(setup.client.close);

      await setup.controller.restoreSession();

      expect(paths, ['/api/auth/me']);
      expect(setup.controller.isLoading, isFalse);
      expect(setup.controller.currentUser?.fullName, 'Taylor Tenant');
    });

    test('401 clears an expired token and finishes unauthenticated', () async {
      final storage = _MemoryTokenStorage('expired-token');
      final setup = _setup(storage, (_) async => http.Response('{}', 401));
      addTearDown(setup.client.close);

      await setup.controller.restoreSession();

      expect(setup.controller.isLoading, isFalse);
      expect(setup.controller.isAuthenticated, isFalse);
      expect(storage.token, isNull);
    });

    test(
      'connection failure ends restoration with a safe login state',
      () async {
        final storage = _MemoryTokenStorage('saved-token');
        final setup = _setup(storage, (_) async {
          throw http.ClientException('private socket detail');
        });
        addTearDown(setup.client.close);

        await setup.controller.restoreSession();

        expect(setup.controller.isLoading, isFalse);
        expect(setup.controller.isAuthenticated, isFalse);
        expect(storage.token, 'saved-token');
      },
    );

    test(
      'request timeout ends restoration instead of waiting forever',
      () async {
        final storage = _MemoryTokenStorage('saved-token');
        final neverRespond = Completer<http.Response>();
        final setup = _setup(
          storage,
          (_) => neverRespond.future,
          requestTimeout: const Duration(milliseconds: 20),
        );
        addTearDown(setup.client.close);

        await setup.controller.restoreSession();

        expect(setup.controller.isLoading, isFalse);
        expect(setup.controller.isAuthenticated, isFalse);
        expect(storage.token, 'saved-token');
      },
    );

    test('secure token read timeout also ends restoration', () async {
      final storage = _HangingReadTokenStorage();
      final setup = _setup(
        storage,
        (_) async => http.Response('{}', 500),
        requestTimeout: const Duration(milliseconds: 20),
      );
      addTearDown(setup.client.close);

      await setup.controller.restoreSession();

      expect(setup.controller.isLoading, isFalse);
      expect(setup.controller.isAuthenticated, isFalse);
    });

    test('slow token deletion on 401 does not trap restoration', () async {
      final storage = _HangingDeleteTokenStorage();
      final setup = _setup(
        storage,
        (_) async => http.Response('{}', 401),
        requestTimeout: const Duration(milliseconds: 20),
      );
      addTearDown(setup.client.close);

      await setup.controller.restoreSession();

      expect(setup.controller.isLoading, isFalse);
      expect(setup.controller.isAuthenticated, isFalse);
    });

    test(
      'server failure preserves the stored token for a later retry',
      () async {
        final storage = _MemoryTokenStorage('saved-token');
        final setup = _setup(
          storage,
          (_) async =>
              http.Response('{"detail":"temporarily unavailable"}', 503),
        );
        addTearDown(setup.client.close);

        await setup.controller.restoreSession();

        expect(setup.controller.isLoading, isFalse);
        expect(setup.controller.isAuthenticated, isFalse);
        expect(storage.token, 'saved-token');
      },
    );

    test(
      'malformed profile response clears token and ends restoration',
      () async {
        final storage = _MemoryTokenStorage('saved-token');
        final setup = _setup(
          storage,
          (_) async => http.Response('{"id":null}', 200),
        );
        addTearDown(setup.client.close);

        await setup.controller.restoreSession();

        expect(setup.controller.isLoading, isFalse);
        expect(setup.controller.isAuthenticated, isFalse);
        expect(storage.token, isNull);
      },
    );
  });

  group('login', () {
    test(
      'successful login then /me sets authenticated user and stores token',
      () async {
        final storage = _MemoryTokenStorage();
        final paths = <String>[];
        final setup = _setup(storage, (request) async {
          paths.add(request.url.path);
          if (request.url.path == '/api/auth/login') {
            expect(jsonDecode(request.body)['email'], 'tenant@example.com');
            return http.Response(
              jsonEncode({'accessToken': 'new-token', 'user': _userJson()}),
              200,
            );
          }
          return http.Response(jsonEncode(_userJson()), 200);
        });
        addTearDown(setup.client.close);

        await setup.controller.login(
          email: 'tenant@example.com',
          password: 'Password1!',
        );

        expect(paths, ['/api/auth/login', '/api/auth/me']);
        expect(storage.token, 'new-token');
        expect(setup.controller.currentUser?.role, UserRole.tenant);
      },
    );

    testWidgets('bad credentials leave login usable with an error', (
      tester,
    ) async {
      final storage = _MemoryTokenStorage();
      final setup = _setup(
        storage,
        (_) async => http.Response('{"detail":"Authentication failed."}', 401),
      );
      addTearDown(setup.client.close);
      await tester.pumpWidget(MyApp(authController: setup.controller));
      await tester.pumpAndSettle();
      await _enterCredentials(tester);
      await tester.pumpAndSettle();

      expect(find.text('Authentication failed.'), findsOneWidget);
      expect(setup.controller.isLoading, isFalse);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('login-submit')))
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('connection failure leaves login usable with a safe error', (
      tester,
    ) async {
      final storage = _MemoryTokenStorage();
      final setup = _setup(storage, (_) async {
        throw http.ClientException('private network detail');
      });
      addTearDown(setup.client.close);
      await tester.pumpWidget(MyApp(authController: setup.controller));
      await tester.pumpAndSettle();
      await _enterCredentials(tester);
      await tester.pumpAndSettle();

      expect(find.text('Unable to connect. Please try again.'), findsOneWidget);
      expect(find.text('private network detail'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('login-submit')))
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('login timeout leaves submit state and reports safe error', (
      tester,
    ) async {
      final storage = _MemoryTokenStorage();
      final neverRespond = Completer<http.Response>();
      final setup = _setup(
        storage,
        (_) => neverRespond.future,
        requestTimeout: const Duration(milliseconds: 20),
      );
      addTearDown(setup.client.close);
      await tester.pumpWidget(MyApp(authController: setup.controller));
      await tester.pumpAndSettle();
      await _enterCredentials(tester);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      expect(find.text('Unable to connect. Please try again.'), findsOneWidget);
      expect(storage.token, isNull);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('login-submit')))
            .onPressed,
        isNotNull,
      );
    });

    test('profile failure after login clears the newly stored token', () async {
      final storage = _MemoryTokenStorage();
      final setup = _setup(storage, (request) async {
        if (request.url.path == '/api/auth/login') {
          return http.Response(
            jsonEncode({'accessToken': 'new-token', 'user': _userJson()}),
            200,
          );
        }
        return http.Response('{"detail":"Profile unavailable."}', 503);
      });
      addTearDown(setup.client.close);

      await expectLater(
        setup.controller.login(
          email: 'tenant@example.com',
          password: 'Password1!',
        ),
        throwsA(isA<AuthException>()),
      );

      expect(storage.token, isNull);
      expect(setup.controller.isAuthenticated, isFalse);
    });

    test(
      'secure token write timeout ends login without authenticating',
      () async {
        final storage = _HangingSaveTokenStorage();
        final setup = _setup(
          storage,
          (_) async => http.Response(
            jsonEncode({'accessToken': 'new-token', 'user': _userJson()}),
            200,
          ),
          requestTimeout: const Duration(milliseconds: 20),
        );
        addTearDown(setup.client.close);

        await expectLater(
          setup.controller.login(
            email: 'tenant@example.com',
            password: 'Password1!',
          ),
          throwsA(isA<TimeoutException>()),
        );
        expect(setup.controller.isAuthenticated, isFalse);
      },
    );
  });
}
