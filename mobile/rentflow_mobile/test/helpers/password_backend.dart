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
import 'package:rentflow_mobile/shared/profile/password_security_screen.dart';
import 'package:rentflow_mobile/shared/profile/shared_profile_content.dart';
import 'package:rentflow_mobile/shared/theme/app_theme.dart';

const oldPassword = 'OldPassword1!';
const newPassword = 'NewPassword2!';
const oldToken = 'old-session-token';
const replacementToken = 'replacement-session-token';
const passwordPath = '/api/auth/change-password';

class PasswordTokenStorage implements TokenStorage {
  String? token = oldToken;
  bool failSave = false;
  bool failDelete = false;
  bool discardSave = false;
  Completer<void>? pendingSave;
  final events = <String>[];

  @override
  Future<void> saveToken(String value) async {
    events.add('save-start');
    if (pendingSave != null) await pendingSave!.future;
    if (failSave) throw StateError('private storage failure');
    if (!discardSave) token = value;
    events.add('save-end');
  }

  @override
  Future<String?> readToken() async => token;
  @override
  Future<void> deleteToken() async {
    events.add('delete');
    if (failDelete) throw StateError('private deletion failure');
    token = null;
  }
}

class PasswordBackend {
  PasswordBackend({
    UserRole role = UserRole.tenant,
    Duration timeout = const Duration(seconds: 20),
  }) {
    profile = {
      'id': 'password-user',
      'fullName': 'Amara Silva',
      'email': 'amara@example.com',
      'phoneNumber': '+94771234567',
      'role': role.value,
      if (role == UserRole.landlord) ...{
        'publicContactPhone': '+94711234567',
        'publicContactEnabled': true,
      },
    };
    client = ApiClient(
      baseUrl: 'https://password.test',
      tokenStorage: storage,
      requestTimeout: timeout,
      httpClient: MockClient(_respond),
    );
    auth = AuthController(
      authService: AuthService(client),
      tokenStorage: storage,
    );
    client.setUnauthorizedHandler(auth.handleUnauthorized);
  }

  final storage = PasswordTokenStorage();
  late final Map<String, dynamic> profile;
  late final ApiClient client;
  late final AuthController auth;
  final requests = <http.Request>[];
  int status = 200;
  Object response = {
    'message': 'Your password was changed successfully.',
    'accessToken': replacementToken,
    'expiresAt': '2030-10-04T12:00:00Z',
  };
  bool networkFailure = false;
  Completer<http.Response>? pendingResponse;
  Completer<http.Response>? pendingProtected;

  List<http.Request> get changes =>
      requests.where((r) => r.url.path == passwordPath).toList();

  Future<http.Response> _respond(http.Request request) async {
    requests.add(request);
    if (request.url.path == '/api/protected' && pendingProtected != null) {
      return pendingProtected!.future;
    }
    if (request.url.path == passwordPath) {
      if (networkFailure) {
        throw http.ClientException('private network error $oldToken');
      }
      if (pendingResponse != null) return pendingResponse!.future;
      return http.Response(jsonEncode(response), status);
    }
    if (request.url.path == '/api/auth/me' ||
        request.url.path == '/api/auth/profile') {
      if (request.method == 'PUT') {
        profile.addAll(jsonDecode(request.body) as Map<String, dynamic>);
      }
      return http.Response(jsonEncode(profile), 200);
    }
    if (request.url.path.endsWith('/unread-count')) {
      return http.Response('{"unreadCount":0}', 200);
    }
    return http.Response('[]', 200);
  }

  Future<void> change() => auth.changePassword(
    currentPassword: oldPassword,
    newPassword: newPassword,
    newPasswordConfirmation: newPassword,
  );

  Future<void> pump(WidgetTester tester, {double scale = 1}) async {
    await auth.restoreSession();
    await tester.pumpWidget(
      AuthScope(
        controller: auth,
        child: MaterialApp(
          theme: AppTheme.build(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(body: SharedProfileContent(user: auth.currentUser!)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Password & security'));
    await tester.tap(find.text('Password & security'));
    await tester.pumpAndSettle();
    expect(find.byType(PasswordSecurityScreen), findsOneWidget);
  }

  void dispose() {
    client.close();
    auth.dispose();
  }
}

Future<void> fillPasswords(
  WidgetTester tester, {
  String current = oldPassword,
  String password = newPassword,
  String? confirmation,
}) async {
  for (final entry in {
    'password-current': current,
    'password-new': password,
    'password-confirmation': confirmation ?? password,
  }.entries) {
    final finder = find.byKey(Key(entry.key));
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.enterText(finder, entry.value);
  }
}

Future<void> submitPassword(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('password-submit')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('password-submit')));
  await tester.pumpAndSettle();
}
