import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rentflow_mobile/core/network/api_client.dart';
import 'package:rentflow_mobile/features/auth/controllers/auth_controller.dart';
import 'package:rentflow_mobile/features/auth/models/current_user.dart';
import 'package:rentflow_mobile/features/auth/screens/login_screen.dart';
import 'package:rentflow_mobile/features/auth/services/auth_service.dart';
import 'package:rentflow_mobile/main.dart';
import 'package:rentflow_mobile/shared/profile/shared_profile_content.dart';
import 'package:rentflow_mobile/shared/shell/shared_app_shell.dart';

import 'shared_shell_test.dart' show navigationDestination;
import 'widget_test.dart' show MemoryTokenStorage, userJson;

void main() {
  for (final restored in [false, true]) {
    testWidgets(
      'Admin ${restored ? 'restores session' : 'uses normal login'} with Home/Profile and normal sign out',
      (tester) async {
        final requests = <http.Request>[];
        final storage = MemoryTokenStorage(restored ? 'admin-token' : null);
        final api = ApiClient(
          baseUrl: 'https://auth.test',
          tokenStorage: storage,
          httpClient: MockClient((request) async {
            requests.add(request);
            switch (request.url.path) {
              case '/api/auth/login':
                return http.Response(
                  jsonEncode({
                    'accessToken': 'admin-token',
                    'user': userJson(UserRole.admin),
                  }),
                  200,
                );
              case '/api/auth/me':
                return http.Response(jsonEncode(userJson(UserRole.admin)), 200);
              case '/api/notifications/unread-count':
                return http.Response('{"unreadCount":0}', 200);
              default:
                return http.Response('', 404);
            }
          }),
        );
        final auth = AuthController(
          authService: AuthService(api),
          tokenStorage: storage,
        );
        api.setUnauthorizedHandler(auth.handleUnauthorized);
        addTearDown(() {
          auth.dispose();
          api.close();
        });
        await tester.pumpWidget(MyApp(authController: auth));
        await tester.pumpAndSettle();
        if (!restored) {
          expect(find.byType(LoginScreen), findsOneWidget);
          expect(find.byType(DropdownButtonFormField<UserRole>), findsNothing);
          await tester.enterText(
            find.byKey(const Key('login-email')),
            'admin@example.com',
          );
          await tester.enterText(
            find.byKey(const Key('login-password')),
            'Password1!',
          );
          await tester.ensureVisible(find.byKey(const Key('login-submit')));
          await tester.tap(find.byKey(const Key('login-submit')));
          await tester.pumpAndSettle();
          final login = requests.singleWhere(
            (request) => request.url.path == '/api/auth/login',
          );
          expect(jsonDecode(login.body), {
            'email': 'admin@example.com',
            'password': 'Password1!',
          });
          expect(login.headers['Authorization'], isNull);
        }
        expect(auth.currentUser!.role, UserRole.admin);
        expect(storage.token, 'admin-token');
        expect(find.byType(SharedAppShell), findsOneWidget);
        expect(find.text('ADMIN WORKSPACE'), findsOneWidget);
        expect(
          find.text(
            'A lightweight mobile overview with secure profile access.',
          ),
          findsOneWidget,
        );
        expect(
          tester
              .widgetList<NavigationDestination>(
                find.byType(NavigationDestination),
              )
              .map((widget) => widget.label),
          ['Home', 'Profile'],
        );
        await tester.tap(navigationDestination('Profile'));
        await tester.pumpAndSettle();
        expect(find.byType(SharedProfileContent), findsOneWidget);
        for (final title in [
          'Personal information',
          'Password & security',
          'Sign out',
        ]) {
          expect(find.text(title), findsOneWidget);
        }
        for (final title in [
          'Application documents',
          'Public contact',
          'Reviews',
          'Preferences',
          'Notifications',
          'Match preferences',
          'Support',
          'Help & support',
          'Language',
          'Feedback',
        ]) {
          expect(find.text(title), findsNothing);
        }
        expect(
          requests.every(
            (request) => [
              '/api/auth/login',
              '/api/auth/me',
              '/api/notifications/unread-count',
            ].contains(request.url.path),
          ),
          isTrue,
        );
        expect(
          requests
              .where((request) => request.url.path == '/api/auth/me')
              .single
              .headers['Authorization'],
          'Bearer admin-token',
        );
        await tester.ensureVisible(find.byKey(const Key('profile-sign-out')));
        await tester.tap(find.byKey(const Key('profile-sign-out')));
        await tester.pumpAndSettle();
        expect(storage.token, isNull);
        expect(auth.currentUser, isNull);
        expect(find.byType(LoginScreen), findsOneWidget);
        expect(find.byType(SharedAppShell), findsNothing);
        if (restored) {
          expect(
            requests.where((request) => request.method == 'POST'),
            isEmpty,
          );
        }
      },
    );
  }
}
