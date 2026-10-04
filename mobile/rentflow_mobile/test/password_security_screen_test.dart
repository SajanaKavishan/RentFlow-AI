import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rentflow_mobile/core/validation/password_policy.dart';
import 'package:rentflow_mobile/features/auth/models/current_user.dart';
import 'package:rentflow_mobile/features/auth/screens/login_screen.dart';
import 'package:rentflow_mobile/main.dart';
import 'package:rentflow_mobile/shared/profile/password_security_screen.dart';
import 'package:rentflow_mobile/shared/profile/shared_profile_content.dart';
import 'package:rentflow_mobile/shared/profile/personal_information_screen.dart';

import 'helpers/password_backend.dart';

void main() {
  late PasswordBackend backend;
  setUp(() => backend = PasswordBackend());
  tearDown(() => backend.dispose());

  TextFormField field(WidgetTester tester, String key) =>
      tester.widget<TextFormField>(find.byKey(Key(key)));
  TextField innerField(WidgetTester tester, String key) =>
      tester.widget<TextField>(
        find.descendant(
          of: find.byKey(Key(key)),
          matching: find.byType(TextField),
        ),
      );

  testWidgets(
    'password fields hide by default with independent accessible toggles',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await backend.pump(tester);
      await fillPasswords(tester);
      for (final key in [
        'password-current',
        'password-new',
        'password-confirmation',
      ]) {
        final textField = tester.widget<TextField>(
          find.descendant(
            of: find.byKey(Key(key)),
            matching: find.byType(TextField),
          ),
        );
        expect(textField.obscureText, isTrue);
        expect(textField.autocorrect, isFalse);
        expect(textField.enableSuggestions, isFalse);
      }
      for (final entry in {
        'current password': 'password-current',
        'new password': 'password-new',
        'confirm new password': 'password-confirmation',
      }.entries) {
        final button = find.byTooltip('Show ${entry.key}');
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        expect(
          tester.getSemantics(button).getSemanticsData().tooltip,
          'Show ${entry.key}',
        );
        final value = field(tester, entry.value).controller!.text;
        await tester.tap(button);
        await tester.pump();
        expect(innerField(tester, entry.value).obscureText, isFalse);
        expect(field(tester, entry.value).controller!.text, value);
        await tester.tap(find.byTooltip('Hide ${entry.key}'));
        await tester.pump();
        expect(innerField(tester, entry.value).obscureText, isTrue);
      }
      expect(backend.changes, isEmpty);
      expect(find.textContaining(oldToken), findsNothing);
      expect(find.textContaining(replacementToken), findsNothing);
      semantics.dispose();
    },
  );

  final cases =
      <
        ({
          String name,
          String current,
          String password,
          String confirmation,
          String error,
        })
      >[
        (
          name: 'current required',
          current: '',
          password: newPassword,
          confirmation: newPassword,
          error: 'Enter your current password.',
        ),
        (
          name: 'new required',
          current: oldPassword,
          password: '',
          confirmation: '',
          error: 'Enter a new password.',
        ),
        (
          name: 'minimum length',
          current: oldPassword,
          password: 'Ab1!',
          confirmation: 'Ab1!',
          error: 'Use between 8 and 128 characters.',
        ),
        (
          name: 'uppercase',
          current: oldPassword,
          password: 'password1!',
          confirmation: 'password1!',
          error: 'Include an uppercase letter.',
        ),
        (
          name: 'lowercase',
          current: oldPassword,
          password: 'PASSWORD1!',
          confirmation: 'PASSWORD1!',
          error: 'Include a lowercase letter.',
        ),
        (
          name: 'number',
          current: oldPassword,
          password: 'Password!!',
          confirmation: 'Password!!',
          error: 'Include a number.',
        ),
        (
          name: 'special character',
          current: oldPassword,
          password: 'Password12',
          confirmation: 'Password12',
          error: 'Include a special character.',
        ),
        (
          name: 'maximum length',
          current: oldPassword,
          password: 'Aa1!${'a' * 125}',
          confirmation: 'Aa1!${'a' * 125}',
          error: 'Use between 8 and 128 characters.',
        ),
        (
          name: 'unchanged',
          current: oldPassword,
          password: oldPassword,
          confirmation: oldPassword,
          error: 'New password must differ from your current password.',
        ),
        (
          name: 'confirmation required',
          current: oldPassword,
          password: newPassword,
          confirmation: '',
          error: 'Confirm your new password.',
        ),
        (
          name: 'confirmation mismatch',
          current: oldPassword,
          password: newPassword,
          confirmation: oldPassword,
          error: 'New password and confirmation must match.',
        ),
      ];
  for (final value in cases) {
    testWidgets(
      'invalid ${value.name} stays local and preserves entered values',
      (tester) async {
        await backend.pump(tester);
        await fillPasswords(
          tester,
          current: value.current,
          password: value.password,
          confirmation: value.confirmation,
        );
        await submitPassword(tester);
        expect(find.text(value.error), findsOneWidget);
        expect(backend.changes, isEmpty);
        expect(field(tester, 'password-new').controller!.text, value.password);
        expect(
          field(tester, 'password-current').controller!.text,
          value.current,
        );
        expect(
          field(tester, 'password-confirmation').controller!.text,
          value.confirmation,
        );
      },
    );
  }

  test('policy matches backend Unicode categories and UTF-16 length', () {
    expect(
      PasswordPolicy('Éé١aaaa!').validate(currentPassword: oldPassword),
      isNull,
    );
    expect(
      PasswordPolicy('Aa1${'a' * 124}!').validate(currentPassword: oldPassword),
      isNull,
    );
    expect(
      PasswordPolicy('Aa1${'a' * 125}!').validate(currentPassword: oldPassword),
      isNotNull,
    );
    expect(PasswordPolicy('Password1é').hasSpecial, isFalse);
    expect(PasswordPolicy('Password1 ').hasSpecial, isTrue);
    // .NET char predicates inspect UTF-16 code units, including surrogates.
    expect(PasswordPolicy('Password1😀').hasSpecial, isTrue);
  });

  testWidgets(
    'maximum 128 characters succeeds and returns to existing Profile',
    (tester) async {
      await backend.pump(tester);
      await fillPasswords(tester, password: 'Aa1!${'a' * 124}');
      final controllers = [
        'password-current',
        'password-new',
        'password-confirmation',
      ].map((key) => field(tester, key).controller!).toList();
      await submitPassword(tester);
      expect(
        controllers.map((controller) => controller.text),
        everyElement(isEmpty),
      );
      expect(backend.changes, hasLength(1));
      expect(backend.storage.token, replacementToken);
      expect(backend.auth.isAuthenticated, isTrue);
      expect(find.byType(PasswordSecurityScreen), findsNothing);
      expect(find.byType(SharedProfileContent), findsOneWidget);
      expect(
        find.text('Your password was changed successfully.'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Password & security'));
      await tester.tap(find.text('Password & security'));
      await tester.pumpAndSettle();
      for (final key in [
        'password-current',
        'password-new',
        'password-confirmation',
      ]) {
        expect(field(tester, key).controller!.text, isEmpty);
      }
    },
  );

  testWidgets(
    'successful replacement preserves app navigator and Personal information/sign out',
    (tester) async {
      backend.dispose();
      backend = PasswordBackend(role: UserRole.admin);
      await tester.pumpWidget(MyApp(authController: backend.auth));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Profile').last);
      await tester.pumpAndSettle();
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      await tester.ensureVisible(find.text('Password & security'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Password & security'));
      await tester.pumpAndSettle();
      await fillPasswords(tester);
      await submitPassword(tester);
      expect(
        tester.state<NavigatorState>(find.byType(Navigator)),
        same(navigator),
      );
      expect(find.byType(LoginScreen), findsNothing);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Personal information'));
      await tester.tap(find.text('Personal information'));
      await tester.pumpAndSettle();
      expect(find.byType(PersonalInformationScreen), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('profile-full-name')),
        'Changed after rotation',
      );
      await tester.ensureVisible(find.byKey(const Key('profile-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('profile-save')));
      await tester.pumpAndSettle();
      expect(backend.auth.currentUser!.fullName, 'Changed after rotation');
      expect(
        backend.requests.last.headers['Authorization'],
        'Bearer $replacementToken',
      );
      await tester.tap(find.byTooltip('Back to Profile'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('profile-sign-out')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('profile-sign-out')));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(backend.storage.token, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '401 from password change leaves authenticated UI using existing Login flow',
    (tester) async {
      backend.dispose();
      backend = PasswordBackend(role: UserRole.admin);
      await tester.pumpWidget(MyApp(authController: backend.auth));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Profile').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Password & security'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Password & security'));
      await tester.pumpAndSettle();
      backend.status = 401;
      backend.response = {'detail': 'Your session is no longer valid.'};
      await fillPasswords(tester);
      await submitPassword(tester);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(backend.auth.isAuthenticated, isFalse);
      expect(backend.storage.token, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'pending submit disables action and prevents duplicate requests',
    (tester) async {
      await backend.pump(tester);
      backend.pendingResponse = Completer<http.Response>();
      await fillPasswords(tester);
      await tester.ensureVisible(find.byKey(const Key('password-submit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('password-submit')));
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('password-submit')))
            .onPressed,
        isNull,
      );
      expect(find.text('Changing password…'), findsOneWidget);
      expect(field(tester, 'password-current').enabled, isFalse);
      await tester.tap(find.byKey(const Key('password-submit')));
      expect(backend.changes, hasLength(1));
      backend.pendingResponse!.complete(
        http.Response(jsonEncode(backend.response), 200),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SharedProfileContent), findsOneWidget);
    },
  );

  for (final status in [400, 429, 500, 0]) {
    testWidgets('error $status preserves all fields and allows retry', (
      tester,
    ) async {
      await backend.pump(tester);
      backend.status = status;
      backend.networkFailure = status == 0;
      backend.response = {
        'detail': status == 400
            ? 'The current password is incorrect.'
            : 'Try again later.',
      };
      await fillPasswords(tester);
      await submitPassword(tester);
      expect(find.byKey(const Key('password-error')), findsOneWidget);
      expect(field(tester, 'password-current').controller!.text, oldPassword);
      expect(field(tester, 'password-new').controller!.text, newPassword);
      expect(
        field(tester, 'password-confirmation').controller!.text,
        newPassword,
      );
      expect(backend.storage.token, oldToken);
      expect(backend.auth.isAuthenticated, isTrue);
      expect(
        find.text('Your password was changed successfully.'),
        findsNothing,
      );
      backend.status = 200;
      backend.networkFailure = false;
      backend.response = {
        'message': 'Changed.',
        'accessToken': replacementToken,
        'expiresAt': '2030-10-04T12:00:00Z',
      };
      await submitPassword(tester);
      expect(backend.changes, hasLength(2));
      expect(find.byType(SharedProfileContent), findsOneWidget);
    });
  }

  testWidgets(
    'failed token persistence replaces authenticated navigator with Login and truthful notice',
    (tester) async {
      backend.dispose();
      backend = PasswordBackend(role: UserRole.admin);
      await tester.pumpWidget(
        MyApp(authController: backend.auth, showPublicLanding: true),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Profile').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Password & security'));
      await tester.tap(find.text('Password & security'));
      await tester.pumpAndSettle();
      backend.storage.failSave = true;
      await fillPasswords(tester);
      await submitPassword(tester);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(PasswordSecurityScreen), findsNothing);
      expect(
        find.text('Your password was changed. Please sign in again.'),
        findsOneWidget,
      );
      expect(find.text('Password change failed'), findsNothing);
      expect(backend.auth.isAuthenticated, isFalse);
      expect(backend.storage.token, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  for (final device in [
    (width: 320.0, height: 780.0, ratio: 1.0),
    (width: 720.0, height: 1560.0, ratio: 2.0),
    (width: 1080.0, height: 2340.0, ratio: 3.0),
  ]) {
    testWidgets('form and action fit $device at 200% with keyboard', (
      tester,
    ) async {
      tester.view.physicalSize = Size(device.width, device.height);
      tester.view.devicePixelRatio = device.ratio;
      addTearDown(tester.view.reset);
      await backend.pump(tester, scale: 2);
      expect(
        MediaQuery.textScalerOf(
          tester.element(find.byType(PasswordSecurityScreen)),
        ).scale(14),
        28,
      );
      expect(tester.takeException(), isNull);
      await fillPasswords(tester);
      tester.view.viewInsets = FakeViewPadding(bottom: 260 * device.ratio);
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('password-confirmation')),
      );
      await tester.pumpAndSettle();
      final visibleHeight = device.height / device.ratio - 260;
      expect(
        tester
            .getBottomRight(find.byKey(const Key('password-confirmation')))
            .dy,
        lessThanOrEqualTo(visibleHeight),
      );
      await tester.ensureVisible(find.byKey(const Key('password-submit')));
      await tester.pumpAndSettle();
      expect(
        tester.getBottomRight(find.byKey(const Key('password-submit'))).dy,
        lessThanOrEqualTo(visibleHeight),
      );
      expect(tester.takeException(), isNull);
      await submitPassword(tester);
      expect(backend.changes, hasLength(1));
      expect(tester.takeException(), isNull);
    });
  }
}
