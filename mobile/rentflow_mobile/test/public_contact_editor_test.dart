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

  Future<void> open(WidgetTester tester, {double textScale = 1}) async {
    await tester.pumpWidget(
      AuthScope(
        controller: auth,
        child: MaterialApp(
          theme: AppTheme.build(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Scaffold(
            body: SharedProfileContent(user: CurrentUser.fromJson(profile)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('Public contact'));
  }

  testWidgets('explicit enabled save copies the authoritative profile phone', (
    tester,
  ) async {
    await open(tester);
    expect(find.byType(TextField), findsNothing);
    expect(requests.where((r) => r.method == 'PUT'), isEmpty);
    await tapVisible(tester, find.byType(SwitchListTile));
    expect(requests.where((r) => r.method == 'PUT'), isEmpty);
    await tapVisible(tester, find.text('Save'));
    final body = jsonDecode(requests.last.body) as Map<String, dynamic>;
    expect(body['publicContactPhone'], userJson['phoneNumber']);
    expect(body['publicContactEnabled'], true);
    expect(auth.currentUser!.publicContactPhone, userJson['phoneNumber']);
  });

  testWidgets(
    'profile choice alone and disabled save do not copy the account phone',
    (tester) async {
      await open(tester);
      await tapVisible(tester, find.text('Use a different number'));
      await tapVisible(tester, find.text('Use my profile phone number'));
      expect(find.byType(TextField), findsNothing);
      expect(requests.where((r) => r.method == 'PUT'), isEmpty);
      await tapVisible(tester, find.text('Save'));
      final body = jsonDecode(requests.last.body) as Map<String, dynamic>;
      expect(body['publicContactPhone'], '');
      expect(body['publicContactEnabled'], false);
    },
  );

  for (final phone in ['', '12-----']) {
    testWidgets('missing/invalid profile phone blocks enabled save: $phone', (
      tester,
    ) async {
      profile['phoneNumber'] = phone;
      await open(tester);
      expect(
        find.text(
          'Add a profile phone number first, or use a different number.',
        ),
        findsOneWidget,
      );
      await tapVisible(tester, find.byType(SwitchListTile));
      await tapVisible(tester, find.text('Save'));
      expect(requests.where((r) => r.method == 'PUT'), isEmpty);
      expect(find.byType(PublicContactEditor), findsOneWidget);
    });
  }

  for (final publicPhone in [
    '+94112223344',
    '+442071234567',
    '+94 11 222 3344',
  ]) {
    testWidgets(
      'stored phone $publicPhone determines the source and is preserved when disabled',
      (tester) async {
        profile['publicContactPhone'] = publicPhone;
        profile['publicContactEnabled'] = true;
        await open(tester);
        if (publicPhone == userJson['phoneNumber']) {
          expect(find.byType(TextField), findsNothing);
        } else {
          expect(
            tester.widget<TextField>(find.byType(TextField)).controller!.text,
            publicPhone,
          );
        }
        await tapVisible(tester, find.byType(SwitchListTile));
        await tapVisible(tester, find.text('Save'));
        final body = jsonDecode(requests.last.body) as Map<String, dynamic>;
        expect(body['publicContactPhone'], publicPhone);
        expect(body['publicContactEnabled'], false);
      },
    );
  }

  testWidgets(
    'later private phone changes leave the public snapshot in the custom choice',
    (tester) async {
      profile['publicContactPhone'] = userJson['phoneNumber'];
      profile['publicContactEnabled'] = true;
      profile['phoneNumber'] = '+94771234567';
      await open(tester);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        userJson['phoneNumber'],
      );
      await tapVisible(tester, find.text('Save'));
      final body = jsonDecode(requests.last.body) as Map<String, dynamic>;
      expect(body['phoneNumber'], '+94771234567');
      expect(body['publicContactPhone'], userJson['phoneNumber']);
    },
  );

  testWidgets('switching sources retains the unsaved custom draft', (
    tester,
  ) async {
    await open(tester);
    await tapVisible(tester, find.text('Use a different number'));
    await tester.enterText(find.byType(TextField), '+442071234567');
    await tapVisible(tester, find.text('Use my profile phone number'));
    expect(find.byType(TextField), findsNothing);
    await tapVisible(tester, find.text('Use a different number'));
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '+442071234567',
    );
  });

  testWidgets(
    'profile-source save failure preserves selection and the enabled switch',
    (tester) async {
      await open(tester);
      await tapVisible(tester, find.byType(SwitchListTile));
      fail = true;
      await tapVisible(tester, find.text('Save'));
      expect(find.byType(TextField), findsNothing);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        true,
      );
      expect(auth.currentUser, isNull);
      expect(
        find.textContaining('Your public contact could not be updated'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'source choices and compact switch fit large text on a narrow screen',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 720);
      addTearDown(tester.view.reset);
      await open(tester, textScale: 2);
      await tapVisible(tester, find.text('Use a different number'));
      await tester.enterText(find.byType(TextField), '+94771234567');
      await tapVisible(tester, find.byType(SwitchListTile));
      await tapVisible(tester, find.text('Save'));
      expect(find.byType(PublicContactEditor), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'landlord editor loads authoritative settings without copying account phone',
    (tester) async {
      await open(tester);
      expect(find.byType(TextField), findsNothing);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        false,
      );
      expect(requests.single.url.path, '/api/auth/me');
      await tapVisible(tester, find.text('Use a different number'));
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '',
      );
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        false,
      );
      expect(requests.single.url.path, '/api/auth/me');
      await tapVisible(tester, find.byType(SwitchListTile));
      await tapVisible(tester, find.text('Save'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Enter a valid public contact number'),
        findsOneWidget,
      );
      expect(requests.where((r) => r.method == 'PUT'), isEmpty);
      await tester.enterText(find.byType(TextField), '+44 (20) 7123-4567');
      await tapVisible(tester, find.text('Save'));
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
      await tapVisible(tester, find.text('Use a different number'));
      await tester.enterText(find.byType(TextField), '+94771234567');
      await tapVisible(tester, find.byType(SwitchListTile));
      fail = true;
      await tapVisible(tester, find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.byType(PublicContactEditor), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '+94771234567',
      );
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        true,
      );
      expect(auth.currentUser, isNull);
      expect(
        find.textContaining('Your public contact could not be updated'),
        findsOneWidget,
      );
      fail = false;
      pending = Completer<http.Response>();
      await tapVisible(tester, find.byType(SwitchListTile));
      await tester.ensureVisible(find.text('Save'));
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
