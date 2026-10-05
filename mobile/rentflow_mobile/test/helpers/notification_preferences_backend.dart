import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rentflow_mobile/core/network/api_client.dart';
import 'package:rentflow_mobile/features/auth/controllers/auth_controller.dart';
import 'package:rentflow_mobile/features/auth/models/current_user.dart';
import 'package:rentflow_mobile/features/auth/services/auth_service.dart';
import 'package:rentflow_mobile/features/notifications/services/notification_preferences_api_service.dart';
import 'package:rentflow_mobile/shared/profile/notification_preferences_screen.dart';
import 'package:rentflow_mobile/shared/profile/shared_profile_content.dart';
import 'package:rentflow_mobile/shared/theme/app_theme.dart';

import '../widget_test.dart' show MemoryTokenStorage, userJson;

const preferencesPath = '/api/notification-preferences';
Map<String, dynamic> preferencesJson({
  bool viewing = false,
  bool applications = true,
}) => {
  'viewingUpdatesEnabled': viewing,
  'rentalApplicationUpdatesEnabled': applications,
  'accountSecurityUpdatesEnabled': true,
};

class NotificationPreferencesBackend {
  NotificationPreferencesBackend({
    this.role = UserRole.tenant,
    Duration timeout = const Duration(seconds: 20),
  }) {
    client = ApiClient(
      baseUrl: 'https://preferences.test',
      tokenStorage: storage,
      requestTimeout: timeout,
      httpClient: MockClient(_respond),
    );
    service = NotificationPreferencesApiService(client);
    auth = AuthController(
      authService: AuthService(client),
      tokenStorage: storage,
    );
    client.setUnauthorizedHandler(auth.handleUnauthorized);
  }
  final UserRole role;
  final storage = MemoryTokenStorage('preferences-token');
  late final ApiClient client;
  late final NotificationPreferencesApiService service;
  late final AuthController auth;
  final requests = <http.Request>[];
  Map<String, dynamic> preferences = preferencesJson();
  String? getBody;
  String? putBody;
  int getStatus = 200;
  int putStatus = 200;
  bool failNetwork = false;
  Completer<http.Response>? pendingGet;
  Completer<http.Response>? pendingPut;

  List<http.Request> get loads => requests
      .where((r) => r.method == 'GET' && r.url.path == preferencesPath)
      .toList();
  List<http.Request> get saves => requests
      .where((r) => r.method == 'PUT' && r.url.path == preferencesPath)
      .toList();

  Future<http.Response> _respond(http.Request request) async {
    requests.add(request);
    if (request.url.path == preferencesPath) {
      if (failNetwork) throw http.ClientException('private network detail');
      if (request.method == 'GET') {
        if (pendingGet != null) return pendingGet!.future;
        return http.Response(getBody ?? jsonEncode(preferences), getStatus);
      }
      if (pendingPut != null) return pendingPut!.future;
      if (putStatus == 200 && putBody == null) {
        preferences = jsonDecode(request.body) as Map<String, dynamic>;
      }
      return http.Response(putBody ?? jsonEncode(preferences), putStatus);
    }
    if (request.url.path == '/api/auth/me') {
      return http.Response(jsonEncode(userJson(role)), 200);
    }
    if (request.url.path.endsWith('/unread-count')) {
      return http.Response('{"unreadCount":0}', 200);
    }
    return http.Response('[]', 200);
  }

  Future<void> pump(
    WidgetTester tester, {
    double scale = 1,
    bool fromProfile = false,
    bool settle = true,
  }) async {
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
          home: fromProfile
              ? Scaffold(body: SharedProfileContent(user: auth.currentUser!))
              : NotificationPreferencesScreen(service: service),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  void dispose() {
    client.close();
    auth.dispose();
  }
}

Switch preferenceSwitch(WidgetTester tester, String key) =>
    tester.widget<Switch>(find.byKey(Key(key)));
FilledButton preferencesSave(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byKey(const Key('preferences-save')));

Future<void> togglePreference(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> savePreferences(WidgetTester tester, {bool settle = true}) async {
  final finder = find.byKey(const Key('preferences-save'));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}
