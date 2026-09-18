import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rentflow_mobile/core/auth/token_storage.dart';
import 'package:rentflow_mobile/core/network/api_client.dart';
import 'package:rentflow_mobile/features/auth/controllers/auth_controller.dart';
import 'package:rentflow_mobile/features/auth/models/current_user.dart';
import 'package:rentflow_mobile/features/auth/screens/login_screen.dart';
import 'package:rentflow_mobile/features/auth/screens/register_screen.dart';
import 'package:rentflow_mobile/features/auth/services/auth_service.dart';
import 'package:rentflow_mobile/features/landing/screens/public_landing_screen.dart';
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

  testWidgets('login and registration display the compact RentFlow branding', (
    tester,
  ) async {
    final controller = buildController(MemoryTokenStorage());
    final mark = find.byWidgetPredicate(
      (widget) =>
          widget is Image &&
          widget.image is AssetImage &&
          (widget.image as AssetImage).assetName ==
              'assets/brand/auth-mark.png',
    );
    await tester.pumpWidget(MyApp(authController: controller));
    await tester.pumpAndSettle();
    expect(mark, findsOneWidget);
    expect(find.text('Find your perfect home, smarter.'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('login-register-link')));
    await tester.tap(find.byKey(const Key('login-register-link')));
    await tester.pumpAndSettle();
    expect(mark, findsOneWidget);
    expect(find.text('Find your perfect home, smarter.'), findsOneWidget);
  });

  testWidgets('public landing connects the native welcome and auth flows', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    final controller = buildController(MemoryTokenStorage());
    await tester.pumpWidget(
      MyApp(authController: controller, showPublicLanding: true),
    );
    await tester.pumpAndSettle();

    expect(find.byType(PublicLandingScreen), findsOneWidget);
    expect(find.byKey(const Key('public-hero-title')), findsOneWidget);

    await tester.tap(find.byKey(const Key('public-sign-in')));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);

    Navigator.of(tester.element(find.byType(LoginScreen))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('public-get-started')));
    await tester.pumpAndSettle();
    expect(find.byType(RegisterScreen), findsOneWidget);
  });

  testWidgets('public landing hero fills the viewport and Explore scrolls', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    final controller = buildController(MemoryTokenStorage());
    await tester.pumpWidget(
      MyApp(authController: controller, showPublicLanding: true),
    );
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byKey(const Key('public-hero'))).height, 844);
    await tester.tap(find.byKey(const Key('public-explore')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('public-platform')), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const Key('public-platform'))).dy,
      lessThan(80),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'public landing lower sections include the product rail and footer',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);

      final controller = buildController(MemoryTokenStorage());
      await tester.pumpWidget(
        MyApp(authController: controller, showPublicLanding: true),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(const Key('product-highlights-rail')),
        650,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('RENTING, SIMPLIFIED'), findsOneWidget);
      expect(find.byKey(const Key('product-highlights-rail')), findsOneWidget);
      expect(find.text('Easy property discovery'), findsWidgets);
      expect(find.text('Clear status updates'), findsWidgets);
      expect(find.textContaining('testimonial'), findsNothing);

      await tester.scrollUntilVisible(
        find.byKey(const Key('public-footer')),
        650,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const Key('public-footer-brand')), findsNothing);
      expect(
        find.text('© 2026 RentFlow AI. All rights reserved.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('feedback validates and never fakes an unavailable delivery', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    final controller = buildController(MemoryTokenStorage());
    await tester.pumpWidget(
      MyApp(authController: controller, showPublicLanding: true),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('feedback-section')),
      700,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.byKey(const Key('feedback-submit')));
    await tester.pump();

    await tester.tap(find.byKey(const Key('feedback-submit')));
    await tester.pump();
    expect(find.text('Name is required.'), findsOneWidget);
    expect(find.text('Email is required.'), findsOneWidget);
    expect(find.text('Message is required.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('feedback-name')), 'Alex Rent');
    await tester.enterText(
      find.byKey(const Key('feedback-email')),
      'not-an-email',
    );
    await tester.enterText(
      find.byKey(const Key('feedback-message')),
      'I have a question about my rental journey.',
    );
    await tester.tap(find.byKey(const Key('feedback-submit')));
    await tester.pump();
    expect(find.text('Enter a valid email address.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('feedback-email')),
      'alex@example.com',
    );
    await tester.ensureVisible(find.byKey(const Key('feedback-submit')));
    await tester.tap(find.byKey(const Key('feedback-submit')));
    await tester.pump();
    await tester.pump();

    expect(
      find.text(
        'Message delivery is not connected yet. Your details have not been sent.',
      ),
      findsOneWidget,
    );
    expect(find.text('Message sent.'), findsNothing);
    expect(find.text('Alex Rent'), findsOneWidget);
    expect(find.text('alex@example.com'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final width in [360.0, 390.0, 412.0, 430.0]) {
    testWidgets('public landing lower sections fit a $width mobile screen', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 800);
      addTearDown(tester.view.reset);

      final controller = buildController(MemoryTokenStorage());
      await tester.pumpWidget(
        MyApp(authController: controller, showPublicLanding: true),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('product-highlights-rail')),
        700,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        tester.getSize(find.byKey(const Key('product-highlights-rail'))).width,
        lessThanOrEqualTo(width - 40),
      );

      await tester.scrollUntilVisible(
        find.byKey(const Key('feedback-section')),
        700,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        tester.getSize(find.byKey(const Key('feedback-section'))).width,
        width,
      );
      expect(find.byKey(const Key('feedback-submit')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in [360.0, 390.0, 412.0, 430.0]) {
    testWidgets('auth cards fit a $width logical pixel mobile screen', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 780);
      addTearDown(tester.view.reset);

      final controller = buildController(MemoryTokenStorage());
      await tester.pumpWidget(MyApp(authController: controller));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byKey(const Key('auth-background')), findsOneWidget);
      expect(find.byKey(const Key('auth-brand')), findsOneWidget);
      expect(find.byKey(const Key('auth-card')), findsOneWidget);
      expect(find.text('Sign in to RentFlow'), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const Key('auth-brand'))).width,
        lessThan(230),
      );
      expect(
        tester.getSize(find.byKey(const Key('auth-card'))).width,
        width - 48 > 380 ? 380 : width - 48,
      );
      expect(
        tester.getTopLeft(find.byKey(const Key('auth-brand'))).dy,
        lessThan(tester.getTopLeft(find.byKey(const Key('auth-hero'))).dy),
      );
      expect(
        tester.getTopLeft(find.byKey(const Key('auth-hero'))).dy,
        lessThan(tester.getTopLeft(find.byKey(const Key('auth-card'))).dy),
      );
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(find.byKey(const Key('login-register-link')));

      await tester.tap(find.byKey(const Key('login-register-link')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('auth-background')), findsOneWidget);
      expect(find.byKey(const Key('auth-card')), findsOneWidget);
      for (final key in [
        'register-name',
        'register-email',
        'register-phone',
        'register-role',
        'register-password',
        'register-confirm',
      ]) {
        expect(find.byKey(Key(key)), findsOneWidget);
      }
      await tester.ensureVisible(find.byKey(const Key('register-submit')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'login visibility toggle and submission use the real controller',
    (tester) async {
      final storage = MemoryTokenStorage();
      final controller = buildController(storage);
      await tester.pumpWidget(MyApp(authController: controller));
      await tester.pumpAndSettle();

      final password = find.byKey(const Key('login-password'));
      final passwordInput = find.descendant(
        of: password,
        matching: find.byType(TextField),
      );
      expect(tester.widget<TextField>(passwordInput).obscureText, isTrue);
      await tester.tap(find.byTooltip('Show password'));
      await tester.pump();
      expect(tester.widget<TextField>(passwordInput).obscureText, isFalse);

      await tester.enterText(
        find.byKey(const Key('login-email')),
        'tenant@example.com',
      );
      await tester.enterText(password, 'Password1!');
      await tester.tap(find.byKey(const Key('login-submit')));
      await tester.pumpAndSettle();
      expect(controller.isAuthenticated, isTrue);
      expect(storage.token, 'new-token');
    },
  );

  testWidgets('auth navigation stays reachable on a short 360px screen', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 640);
    addTearDown(tester.view.reset);

    final controller = buildController(MemoryTokenStorage());
    await tester.pumpWidget(MyApp(authController: controller));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('auth-hero')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('login-register-link')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('login-register-link')));
    await tester.pumpAndSettle();
    expect(find.text('Create your account'), findsOneWidget);
    expect(find.byTooltip('Back to sign in'), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('register-submit')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'registration only offers Tenant and Landlord in the role field',
    (tester) async {
      final controller = buildController(MemoryTokenStorage());
      await tester.pumpWidget(MyApp(authController: controller));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('login-register-link')));
      await tester.tap(find.byKey(const Key('login-register-link')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('register-role')));
      await tester.tap(find.byKey(const Key('register-role')));
      await tester.pumpAndSettle();
      expect(find.text('Tenant'), findsWidgets);
      expect(find.text('Landlord'), findsOneWidget);
      await tester.tap(find.text('Landlord').last);
      await tester.pumpAndSettle();
      expect(find.text('Landlord'), findsOneWidget);
    },
  );

  testWidgets(
    'registration password visibility controls both password fields',
    (tester) async {
      final controller = buildController(MemoryTokenStorage());
      await tester.pumpWidget(MyApp(authController: controller));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('login-register-link')));
      await tester.tap(find.byKey(const Key('login-register-link')));
      await tester.pumpAndSettle();

      TextField passwordInput(String key) => tester.widget<TextField>(
        find.descendant(
          of: find.byKey(Key(key)),
          matching: find.byType(TextField),
        ),
      );

      expect(passwordInput('register-password').obscureText, isTrue);
      expect(passwordInput('register-confirm').obscureText, isTrue);
      await tester.ensureVisible(find.byTooltip('Show passwords'));
      await tester.tap(find.byTooltip('Show passwords'));
      await tester.pump();
      expect(passwordInput('register-password').obscureText, isFalse);
      expect(passwordInput('register-confirm').obscureText, isFalse);
    },
  );

  testWidgets('auth buttons remain reachable when the keyboard is open', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 740);
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    addTearDown(tester.view.reset);

    final controller = buildController(MemoryTokenStorage());
    await tester.pumpWidget(MyApp(authController: controller));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.byKey(const Key('login-register-link')));
    await tester.tap(find.byKey(const Key('login-register-link')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('register-submit')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('registration validates password confirmation', (tester) async {
    final controller = buildController(MemoryTokenStorage());
    await tester.pumpWidget(MyApp(authController: controller));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('login-register-link')));
    await tester.tap(find.byKey(const Key('login-register-link')));
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

  testWidgets('role navigation gives tenants and landlords mobile access', (
    tester,
  ) async {
    final tenantController = buildController(MemoryTokenStorage('token'));
    await tester.pumpWidget(MyApp(authController: tenantController));
    await tester.pumpAndSettle();
    expect(find.text('Book a Viewing'), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(
      find.textContaining('Property selection has not been integrated yet'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());

    final landlordController = buildController(
      MemoryTokenStorage('token'),
      role: UserRole.landlord,
    );
    await tester.pumpWidget(MyApp(authController: landlordController));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Viewing Requests'), findsWidgets);
    expect(find.text('Applications'), findsWidgets);
    expect(find.textContaining('web workspace'), findsWidgets);
  });

  testWidgets('profile logout returns to login from the authenticated shell', (
    tester,
  ) async {
    final storage = MemoryTokenStorage('token');
    final controller = buildController(storage);
    await tester.pumpWidget(MyApp(authController: controller));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is NavigationDestination && widget.label == 'Profile',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Logout'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('login-submit')), findsOneWidget);
    expect(storage.token, isNull);
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
