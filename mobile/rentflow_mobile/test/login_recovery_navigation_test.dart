import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rentflow_mobile/core/network/api_client.dart';
import 'package:rentflow_mobile/features/auth/controllers/auth_controller.dart';
import 'package:rentflow_mobile/features/auth/screens/forgot_password_screen.dart';
import 'package:rentflow_mobile/features/auth/screens/login_screen.dart';
import 'package:rentflow_mobile/features/auth/screens/register_screen.dart';
import 'package:rentflow_mobile/features/auth/services/auth_service.dart';
import 'package:rentflow_mobile/features/landing/screens/public_landing_screen.dart';
import 'package:rentflow_mobile/shared/theme/app_theme.dart';

import 'widget_test.dart' as fixtures;

class RecoveryHarness {
  RecoveryHarness(Future<http.Response> Function(http.Request) respond) {
    api = ApiClient(
      baseUrl: 'https://recovery.test',
      tokenStorage: storage,
      httpClient: MockClient((request) async {
        requests.add(request);
        return respond(request);
      }),
    );
    service = AuthService(api);
    auth = AuthController(authService: service, tokenStorage: storage);
    api.setUnauthorizedHandler(auth.handleUnauthorized);
    addTearDown(() {
      auth.dispose();
      api.close();
    });
  }

  final storage = fixtures.MemoryTokenStorage('existing-session');
  final requests = <http.Request>[];
  late final ApiClient api;
  late final AuthService service;
  late final AuthController auth;

  Future<void> mount(WidgetTester tester, {Widget? home}) async {
    await tester.pumpWidget(
      AuthScope(
        controller: auth,
        child: MaterialApp(
          theme: AppTheme.build(),
          home: home ?? const LoginScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }
}

http.Response confirmed({String? developmentLink}) => http.Response(
  jsonEncode({
    'message': AuthService.passwordResetConfirmation,
    'developmentResetLink': ?developmentLink,
  }),
  200,
);

Future<void> tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

String emailValue(WidgetTester tester, String key) =>
    tester.widget<TextFormField>(find.byKey(Key(key))).controller!.text;

void main() {
  test(
    'recovery uses existing anonymous endpoint with only trimmed email',
    () async {
      final harness = RecoveryHarness((_) async => confirmed());
      var sessionNotifications = 0;
      harness.auth.addListener(() => sessionNotifications++);
      await harness.auth.requestPasswordReset(email: '  alex@example.com  ');
      final request = harness.requests.single;
      expect(request.method, 'POST');
      expect(request.url.path, '/api/auth/forgot-password');
      expect(jsonDecode(request.body), {'email': 'alex@example.com'});
      expect(request.headers.containsKey('Authorization'), isFalse);
      expect(harness.storage.token, 'existing-session');
      expect(sessionNotifications, 0);
    },
  );

  test('service rejects invalid and overlong email before transport', () async {
    final harness = RecoveryHarness((_) async => confirmed());
    for (final email in [
      '',
      '   ',
      'wrong',
      'two@@example.com',
      '${'a' * 309}@example.com',
    ]) {
      await expectLater(
        harness.service.requestPasswordReset(email: email),
        throwsA(isA<AuthException>()),
      );
    }
    expect(harness.requests, isEmpty);
    // The backend allows at most 320 characters, measured after trimming.
    await harness.service.requestPasswordReset(
      email: ' ${'a' * 308}@example.com ',
    );
    expect(
      (jsonDecode(harness.requests.single.body)['email'] as String).length,
      320,
    );
  });

  for (final body in [
    '{}',
    '<html>internal trace</html>',
    '{"message":null}',
  ]) {
    test('malformed success is never presented as confirmed: $body', () async {
      final harness = RecoveryHarness((_) async => http.Response(body, 200));
      await expectLater(
        harness.service.requestPasswordReset(email: 'alex@example.com'),
        throwsA(
          isA<AuthException>().having(
            (error) => error.message,
            'safe message',
            'Password reset instructions could not be confirmed. Please try again.',
          ),
        ),
      );
    });
  }

  testWidgets('Password and recovery share a row above input and Sign in', (
    tester,
  ) async {
    final harness = RecoveryHarness((_) async => confirmed());
    await harness.mount(tester);
    final label = tester.getRect(find.text('Password'));
    final link = tester.getRect(find.byKey(const Key('login-forgot-password')));
    final input = tester.getRect(find.byKey(const Key('login-password')));
    final submit = tester.getRect(find.byKey(const Key('login-submit')));
    expect(label.center.dy, closeTo(link.center.dy, 1));
    expect(label.right, lessThan(link.left));
    expect(link.bottom, lessThan(input.top));
    expect(input.bottom, lessThan(submit.top));
    expect(link.height, greaterThanOrEqualTo(48));
    final passwordInput = find.descendant(
      of: find.byKey(const Key('login-password')),
      matching: find.byType(TextField),
    );
    expect(tester.widget<TextField>(passwordInput).obscureText, isTrue);
    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(tester.widget<TextField>(passwordInput).obscureText, isFalse);
    expect(find.byTooltip('Hide password'), findsOneWidget);
    await tapKey(tester, 'login-register-link');
    expect(find.byType(RegisterScreen), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  for (final initialEmail in ['', '  login@example.com  ']) {
    testWidgets(
      'recovery prefill and back preserve Login email "$initialEmail"',
      (tester) async {
        final harness = RecoveryHarness((_) async => confirmed());
        await harness.mount(tester);
        await tester.enterText(
          find.byKey(const Key('login-email')),
          initialEmail,
        );
        await tapKey(tester, 'login-forgot-password');
        expect(find.byType(ForgotPasswordScreen), findsOneWidget);
        expect(emailValue(tester, 'recovery-email'), initialEmail);
        await tester.enterText(
          find.byKey(const Key('recovery-email')),
          'changed@example.com',
        );
        await tapKey(tester, 'recovery-back');
        expect(find.byType(LoginScreen), findsOneWidget);
        expect(emailValue(tester, 'login-email'), initialEmail);
        await tapKey(tester, 'login-forgot-password');
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(LoginScreen), findsOneWidget);
        expect(emailValue(tester, 'login-email'), initialEmail);
      },
    );
  }

  testWidgets('recovery blocks empty invalid and overlong input', (
    tester,
  ) async {
    final harness = RecoveryHarness((_) async => confirmed());
    await harness.mount(tester, home: const ForgotPasswordScreen());
    for (final entry in {
      '': 'Email is required.',
      'incorrect': 'Enter a valid email address.',
      '${'a' * 309}@example.com': 'Email must be 320 characters or fewer.',
    }.entries) {
      await tester.enterText(
        find.byKey(const Key('recovery-email')),
        entry.key,
      );
      await tapKey(tester, 'recovery-submit');
      expect(find.text(entry.value), findsOneWidget);
    }
    expect(harness.requests, isEmpty);
  });

  testWidgets(
    'pending request blocks duplicates and success hides reset secrets',
    (tester) async {
      final response = Completer<http.Response>();
      final harness = RecoveryHarness((_) => response.future);
      await harness.mount(tester);
      await tester.enterText(
        find.byKey(const Key('login-email')),
        'alex@example.com',
      );
      await tapKey(tester, 'login-forgot-password');
      final submit = find.byKey(const Key('recovery-submit'));
      await tester.ensureVisible(submit);
      await tester.pumpAndSettle();
      await tester.tap(submit);
      await tester.pump();
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('recovery-email')))
            .enabled,
        isFalse,
      );
      expect(emailValue(tester, 'recovery-email'), 'alex@example.com');
      await tester.tap(submit);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(harness.requests, hasLength(1));
      response.complete(
        confirmed(
          developmentLink:
              'https://web.test/reset-password#token=private-token',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Request confirmed'), findsOneWidget);
      expect(find.text(AuthService.passwordResetConfirmation), findsOneWidget);
      expect(find.textContaining('private-token'), findsNothing);
      expect(find.textContaining('alex@example.com'), findsNothing);
      expect(find.byKey(const Key('recovery-email')), findsNothing);
      await tapKey(tester, 'recovery-back');
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(emailValue(tester, 'login-email'), 'alex@example.com');
    },
  );

  for (final failure in ['400', '429', '500', 'network']) {
    testWidgets('$failure failure keeps email and safely retries', (
      tester,
    ) async {
      var attempts = 0;
      final harness = RecoveryHarness((_) async {
        if (++attempts > 1) return confirmed();
        if (failure == 'network') {
          throw http.ClientException('raw-private-details');
        }
        return http.Response(
          '{"detail":"raw-private-details: account exists token=secret"}',
          int.parse(failure),
        );
      });
      await harness.mount(tester);
      await tapKey(tester, 'login-forgot-password');
      await tester.enterText(
        find.byKey(const Key('recovery-email')),
        '  retry@example.com  ',
      );
      await tapKey(tester, 'recovery-submit');
      expect(find.byKey(const Key('recovery-error')), findsOneWidget);
      expect(find.byKey(const Key('recovery-confirmation')), findsNothing);
      expect(find.textContaining('raw-private-details'), findsNothing);
      expect(emailValue(tester, 'recovery-email'), '  retry@example.com  ');
      if (failure == '429') {
        expect(
          find.text(
            'Too many password reset requests. Wait a minute and try again.',
          ),
          findsOneWidget,
        );
      }
      expect(harness.storage.token, 'existing-session');
      await tapKey(tester, 'recovery-submit');
      expect(find.byKey(const Key('recovery-confirmation')), findsOneWidget);
      expect(harness.requests, hasLength(2));
    });
  }

  testWidgets(
    'all successful account cases use identical generic confirmation',
    (tester) async {
      for (final serverMessage in [
        AuthService.passwordResetConfirmation,
        'account exists: secret internal data',
      ]) {
        final harness = RecoveryHarness(
          (_) async =>
              http.Response(jsonEncode({'message': serverMessage}), 200),
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await harness.mount(
          tester,
          home: const ForgotPasswordScreen(initialEmail: 'alex@example.com'),
        );
        await tapKey(tester, 'recovery-submit');
        expect(
          find.text(AuthService.passwordResetConfirmation),
          findsOneWidget,
        );
        expect(find.textContaining('secret internal data'), findsNothing);
      }
    },
  );

  final devices = [
    (size: const Size(320, 780), dpr: 1.0),
    (size: const Size(720, 1560), dpr: 2.0),
    (size: const Size(1080, 2340), dpr: 3.0),
  ];
  for (final device in devices) {
    for (final scale in [1.0, 2.0]) {
      for (final keyboard in [false, true]) {
        testWidgets(
          'Login/recovery fit ${device.size} DPR ${device.dpr} scale $scale keyboard $keyboard',
          (tester) async {
            tester.view.devicePixelRatio = device.dpr;
            tester.view.physicalSize = device.size;
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            if (keyboard) {
              tester.view.viewInsets = FakeViewPadding(
                bottom: 300 * device.dpr,
              );
            }
            addTearDown(tester.view.reset);
            addTearDown(
              tester.platformDispatcher.clearTextScaleFactorTestValue,
            );
            final harness = RecoveryHarness((_) async => confirmed());
            await harness.mount(tester);
            await tester.enterText(
              find.byKey(const Key('login-email')),
              'alex@example.com',
            );
            await tapKey(tester, 'login-forgot-password');
            expect(tester.takeException(), isNull);
            await tester.enterText(
              find.byKey(const Key('recovery-email')),
              'retry@example.com',
            );
            await tester.ensureVisible(
              find.byKey(const Key('recovery-submit')),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await tapKey(tester, 'recovery-back');
            await tester.ensureVisible(
              find.byKey(const Key('login-register-link')),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expect(emailValue(tester, 'login-email'), 'alex@example.com');
          },
        );
      }
    }
  }

  for (final size in [
    const Size(320, 780),
    const Size(360, 780),
    const Size(390, 844),
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('landing CTAs and section anchor at $size scale $scale', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final harness = RecoveryHarness((_) async => confirmed());
        await harness.mount(tester, home: const PublicLandingScreen());
        expect(tester.takeException(), isNull, reason: 'initial landing');
        await tapKey(tester, 'public-sign-in');
        expect(find.byType(LoginScreen), findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(PublicLandingScreen), findsOneWidget);
        await tapKey(tester, 'public-get-started');
        expect(find.byType(RegisterScreen), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'registration');
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        final navigator = Navigator.of(
          tester.element(find.byType(PublicLandingScreen)),
        );
        expect(navigator.canPop(), isFalse);
        final heroHeight = tester
            .getSize(find.byKey(const Key('public-hero')))
            .height;
        await tapKey(tester, 'public-explore');
        expect(find.byType(PublicLandingScreen), findsOneWidget);
        expect(find.byType(RegisterScreen), findsNothing);
        expect(find.byType(LoginScreen), findsNothing);
        expect(navigator.canPop(), isFalse);
        expect(
          tester.getTopLeft(find.byKey(const Key('public-platform'))).dy,
          closeTo(0, 1),
        );
        final scrollable = tester.state<ScrollableState>(
          find.byType(Scrollable).first,
        );
        expect(scrollable.position.pixels, closeTo(heroHeight, 1));
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('auth fields and navigation expose semantic action labels', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final harness = RecoveryHarness((_) async => confirmed());
    await harness.mount(tester);
    for (final label in ['Email', 'Password', 'Forgot password?', 'Sign in']) {
      expect(find.bySemanticsLabel(label), findsWidgets);
    }
    expect(
      tester
          .getSemantics(find.byTooltip('Show password'))
          .getSemanticsData()
          .tooltip,
      'Show password',
    );
    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(
      tester
          .getSemantics(find.byTooltip('Hide password'))
          .getSemanticsData()
          .tooltip,
      'Hide password',
    );
    expect(find.bySemanticsLabel(RegExp('Create an account')), findsWidgets);
    await tapKey(tester, 'login-forgot-password');
    for (final label in [
      'Email',
      'Send reset instructions',
      'Back to sign in',
    ]) {
      expect(find.bySemanticsLabel(label), findsWidgets);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await harness.mount(tester, home: const PublicLandingScreen());
    for (final label in ['Get Started', 'Explore the platform']) {
      expect(find.bySemanticsLabel(label), findsWidgets);
    }
    final explore = tester.getSemantics(
      find.byKey(const Key('public-explore')),
    );
    expect(
      explore.getSemanticsData().hint,
      contains('Scroll to platform features'),
    );
    semantics.dispose();
  });
}
