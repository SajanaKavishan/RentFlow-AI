import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rentflow_mobile/core/network/api_client.dart';
import 'package:rentflow_mobile/features/auth/controllers/auth_controller.dart';
import 'package:rentflow_mobile/features/auth/models/current_user.dart';
import 'package:rentflow_mobile/features/auth/services/auth_service.dart';
import 'package:rentflow_mobile/shared/theme/app_theme.dart';

import '../widget_test.dart' show MemoryTokenStorage;

final profilePng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

class ProfileBackend {
  ProfileBackend({UserRole role = UserRole.tenant, bool hasImage = false}) {
    profile = {
      'id': 'profile-user',
      'fullName': 'Amara Silva',
      'email': 'amara.silva@example.com',
      'phoneNumber': '+94 77 123 4567',
      'role': role.value,
      'hasProfileImage': hasImage,
      if (role == UserRole.landlord) ...{
        'publicContactPhone': '+94711234567',
        'publicContactEnabled': true,
      },
    };
    client = ApiClient(
      baseUrl: 'https://profile.test',
      tokenStorage: storage,
      httpClient: MockClient(_respond),
    );
    auth = AuthController(
      authService: AuthService(client),
      tokenStorage: storage,
    );
    client.setUnauthorizedHandler(auth.handleUnauthorized);
  }

  final storage = MemoryTokenStorage('profile-token');
  late final ApiClient client;
  late final AuthController auth;
  late Map<String, dynamic> profile;
  final requests = <http.Request>[];
  bool failSave = false;
  bool failUpload = false;
  bool failImageLoad = false;
  Uint8List image = profilePng;
  String? authoritativeName;
  Completer<http.Response>? pendingSave;
  Completer<http.Response>? pendingImage;

  List<http.Request> get writes =>
      requests.where((r) => r.method == 'PUT' || r.method == 'POST').toList();
  List<http.Request> get imageLoads => requests
      .where((r) => r.method == 'GET' && r.url.path.endsWith('/profile-image'))
      .toList();

  Future<http.Response> _respond(http.Request request) async {
    requests.add(request);
    if (request.url.path.endsWith('/profile-image')) {
      if (request.method == 'POST') {
        if (failUpload) {
          return http.Response('{"message":"Photo upload failed."}', 500);
        }
        profile['hasProfileImage'] = true;
        return json();
      }
      if (pendingImage != null) return pendingImage!.future;
      if (failImageLoad) return http.Response('', 404);
      return http.Response.bytes(
        image,
        200,
        headers: {'content-type': 'image/png'},
      );
    }
    if (request.method == 'PUT') {
      if (pendingSave != null) return pendingSave!.future;
      if (failSave) {
        return http.Response('{"message":"Unable to save profile."}', 400);
      }
      profile.addAll(jsonDecode(request.body) as Map<String, dynamic>);
      if (authoritativeName != null) profile['fullName'] = authoritativeName;
    }
    return json();
  }

  http.Response json() => http.Response(jsonEncode(profile), 200);

  Future<void> pump(
    WidgetTester tester,
    Widget Function(CurrentUser) screen, {
    double scale = 1,
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
          home: screen(auth.currentUser!),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  void dispose() {
    client.close();
    auth.dispose();
  }
}
