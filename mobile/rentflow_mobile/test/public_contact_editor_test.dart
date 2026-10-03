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
import 'package:rentflow_mobile/shared/profile/public_contact_editor.dart';
import 'package:rentflow_mobile/shared/profile/shared_profile_content.dart';
import 'package:rentflow_mobile/shared/theme/app_theme.dart';

import 'match_preferences_test.dart' show tapVisible;
import 'property_details_test.dart' show MemoryTokenStorage;

const userJson = {
  'id': 'landlord',
  'fullName': 'Maya Perera',
  'email': 'private@example.test',
  'phoneNumber': '+94112223344',
  'role': 'Landlord',
  'publicContactPhone': null,
  'publicContactEnabled': false,
};

void main() {
  late ApiClient client;
  late AuthController auth;
  final requests = <http.Request>[];
  Map<String, dynamic> profile = Map.of(userJson);
  bool fail = false;
  Completer<http.Response>? pending;
  setUp(() {
    requests.clear();
    profile = Map.of(userJson);
    fail = false;
    pending = null;
    client = ApiClient(
      baseUrl: 'https://test.example',
      tokenStorage: MemoryTokenStorage(),
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.method == 'PUT') {
          if (pending != null) return pending!.future;
          if (fail) return http.Response('', 500);
          profile = {
            ...profile,
            ...jsonDecode(request.body) as Map<String, dynamic>,
          };
        }
        return http.Response(jsonEncode(profile), 200);
      }),
    );
    auth = AuthController(
      authService: AuthService(client),
      tokenStorage: MemoryTokenStorage(),
    );
  });
  tearDown(() {
    client.close();
    auth.dispose();
  });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      AuthScope(
        controller: auth,
        child: MaterialApp(
          theme: AppTheme.build(),
          home: Scaffold(
            body: SharedProfileContent(user: CurrentUser.fromJson(profile)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('Public contact'));
  }

  testWidgets(
    'landlord editor loads authoritative settings without copying account phone',
    (tester) async {
      await open(tester);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '',
      );
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        false,
      );
      expect(requests.single.url.path, '/api/auth/me');
      await tester.tap(find.byType(CheckboxListTile));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Enter a valid public contact number'),
        findsOneWidget,
      );
      expect(requests.where((r) => r.method == 'PUT'), isEmpty);
      await tester.enterText(find.byType(TextField), '+44 (20) 7123-4567');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final body = jsonDecode(requests.last.body) as Map<String, dynamic>;
      expect(body['phoneNumber'], userJson['phoneNumber']);
      expect(body['publicContactPhone'], '+44 (20) 7123-4567');
      expect(body['publicContactEnabled'], true);
      expect(requests.last.headers['Authorization'], 'Bearer tenant-token');
      expect(auth.currentUser!.publicContactEnabled, true);
      expect(find.byType(PublicContactEditor), findsNothing);
    },
  );

  testWidgets(
    'save failure preserves typed values and saved state changes only after API success',
    (tester) async {
      await open(tester);
      await tester.enterText(find.byType(TextField), '+94771234567');
      await tester.tap(find.byType(CheckboxListTile));
      fail = true;
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.byType(PublicContactEditor), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '+94771234567',
      );
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        true,
      );
      expect(auth.currentUser, isNull);
      expect(
        find.textContaining('Your public contact could not be updated'),
        findsOneWidget,
      );
      fail = false;
      pending = Completer<http.Response>();
      await tester.tap(find.byType(CheckboxListTile));
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(find.byType(PublicContactEditor), findsOneWidget);
      expect(find.text('Saving…'), findsOneWidget);
      expect(auth.currentUser, isNull);
      pending!.complete(
        http.Response(
          jsonEncode({...userJson, 'publicContactPhone': '+94771234567'}),
          200,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PublicContactEditor), findsNothing);
      expect(auth.currentUser!.publicContactEnabled, false);
      expect(auth.currentUser!.publicContactPhone, '+94771234567');
    },
  );

  for (final role in ['Tenant', 'Admin', 'MaintenanceTechnician']) {
    testWidgets('$role has no public contact settings', (tester) async {
      profile['role'] = role;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SharedProfileContent(user: CurrentUser.fromJson(profile)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Public contact'), findsNothing);
    });
  }
}
