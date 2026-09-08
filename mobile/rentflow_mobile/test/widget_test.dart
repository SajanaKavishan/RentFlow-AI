import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rentflow_mobile/core/auth/token_storage.dart';
import 'package:rentflow_mobile/core/network/api_client.dart';
import 'package:rentflow_mobile/features/auth/controllers/auth_controller.dart';
import 'package:rentflow_mobile/features/auth/models/current_user.dart';
import 'package:rentflow_mobile/features/auth/screens/register_screen.dart';
import 'package:rentflow_mobile/features/auth/services/auth_service.dart';
import 'package:rentflow_mobile/main.dart';

class MemoryTokenStorage implements TokenStorage {
  MemoryTokenStorage([this.token]);
  String? token;

  @override
  Future<void> deleteToken() async => token = null;
  @override
  Future<String?> readToken() async => token;
  @override
  Future<void> saveToken(String value) async => token = value;
}

Map<String, dynamic> userJson(UserRole role) => {
  'id': '11111111-1111-1111-1111-111111111112',
  'fullName': role == UserRole.tenant ? 'Taylor Tenant' : 'Larry Landlord',
  'email': 'user@example.com',
  'phoneNumber': '+94 77 123 4567',
  'role': role.value,
};

AuthController buildController(
  MemoryTokenStorage storage, {
  UserRole role = UserRole.tenant,
  int meStatus = 200,
}) {
  final client = MockClient((request) async {
    if (request.url.path.endsWith('/login')) {
      return http.Response(
        jsonEncode({'accessToken': 'new-token', 'user': userJson(role)}),
        200,
      );
    }
    if (request.url.path.endsWith('/register')) {
      return http.Response(
        jsonEncode({'accessToken': 'registered-token', 'user': userJson(role)}),
        201,
      );
    }
    return http.Response(
      meStatus == 200 ? jsonEncode(userJson(role)) : '{}',
      meStatus,
    );
  });
  final apiClient = ApiClient(
    baseUrl: 'http://test',
    httpClient: client,
    tokenStorage: storage,
  );
  final controller = AuthController(
    authService: AuthService(apiClient),
    tokenStorage: storage,
  );
  apiClient.setUnauthorizedHandler(controller.handleUnauthorized);
  return controller;
}

void main() {
  testWidgets('login validates required credentials', (tester) async {
    final controller = buildController(MemoryTokenStorage());
    await tester.pumpWidget(MyApp(authController: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pump();
    expect(find.text('Enter a valid email address.'), findsOneWidget);
    expect(find.text('Enter your password.'), findsOneWidget);
  });

  testWidgets('registration validates password confirmation', (tester) async {
    final controller = buildController(MemoryTokenStorage());
    await tester.pumpWidget(MyApp(authController: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create an account'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('register-name')),
      'Taylor Tenant',
    );
    await tester.enterText(
      find.byKey(const Key('register-email')),
      'tenant@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('register-phone')),
      '+94771234567',
    );
    await tester.enterText(
      find.byKey(const Key('register-password')),
      'Password1!',
    );
    await tester.enterText(
      find.byKey(const Key('register-confirm')),
      'Different1!',
    );
    await tester.ensureVisible(find.byKey(const Key('register-submit')));
    await tester.tap(find.byKey(const Key('register-submit')));
    await tester.pump();
    expect(find.text('Passwords do not match.'), findsOneWidget);
  });

  test('successful login updates auth state and persists token', () async {
    final storage = MemoryTokenStorage();
    final controller = buildController(storage);
    await controller.login(email: 'tenant@example.com', password: 'Password1!');
    expect(controller.isAuthenticated, isTrue);
    expect(controller.currentUser?.role, UserRole.tenant);
    expect(storage.token, 'new-token');
  });

  test('logout clears stored authentication', () async {
    final storage = MemoryTokenStorage('stored-token');
    final controller = buildController(storage);
    await controller.restoreSession();
    await controller.logout();
    expect(controller.isAuthenticated, isFalse);
    expect(storage.token, isNull);
  });

  test(
    'session restoration restores valid user and clears invalid token',
    () async {
      final validStorage = MemoryTokenStorage('valid-token');
      final validController = buildController(validStorage);
      await validController.restoreSession();
      expect(validController.currentUser?.fullName, 'Taylor Tenant');

      final invalidStorage = MemoryTokenStorage('expired-token');
      final invalidController = buildController(invalidStorage, meStatus: 401);
      await invalidController.restoreSession();
      expect(invalidController.isAuthenticated, isFalse);
      expect(invalidStorage.token, isNull);
    },
  );

  testWidgets('role navigation shows tenant actions only to tenants', (
    tester,
  ) async {
    final tenantController = buildController(MemoryTokenStorage('token'));
    await tester.pumpWidget(MyApp(authController: tenantController));
    await tester.pumpAndSettle();
    expect(find.text('Book a Viewing'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());

    final landlordController = buildController(
      MemoryTokenStorage('token'),
      role: UserRole.landlord,
    );
    await tester.pumpWidget(MyApp(authController: landlordController));
    await tester.pumpAndSettle();
    expect(find.text('Book a Viewing'), findsNothing);
    expect(find.textContaining('web dashboard'), findsOneWidget);
  });

  test('registration exposes only public roles', () {
    expect(RegisterScreen.publicRoles, [UserRole.tenant, UserRole.landlord]);
    expect(RegisterScreen.publicRoles, isNot(contains(UserRole.admin)));
    expect(
      RegisterScreen.publicRoles,
      isNot(contains(UserRole.maintenanceTechnician)),
    );
  });
}
