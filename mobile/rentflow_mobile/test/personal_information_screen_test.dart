import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rentflow_mobile/features/auth/models/current_user.dart';
import 'package:rentflow_mobile/features/auth/models/profile_image_file.dart';
import 'package:rentflow_mobile/shared/profile/personal_information_screen.dart';
import 'package:rentflow_mobile/shared/profile/shared_profile_content.dart';

import 'helpers/profile_backend.dart';

final nameField = find.byKey(const Key('profile-full-name'));
final phoneField = find.byKey(const Key('profile-phone-number'));
final saveButton = find.byKey(const Key('profile-save'));

Future<void> tapSave(WidgetTester tester) async {
  await tester.pump();
  await tester.ensureVisible(saveButton);
  await tester.tap(saveButton);
  await tester.pumpAndSettle();
}

void main() {
  late ProfileBackend backend;
  setUp(() => backend = ProfileBackend());
  tearDown(() => backend.dispose());

  Future<void> open(WidgetTester tester, {ProfileImagePicker? picker}) =>
      backend.pump(
        tester,
        (user) => PersonalInformationScreen(user: user, imagePicker: picker),
      );

  testWidgets(
    'prefills account fields, email read-only and unchanged save disabled',
    (tester) async {
      await open(tester);
      expect(
        tester.widget<TextFormField>(nameField).controller!.text,
        'Amara Silva',
      );
      expect(
        tester.widget<TextFormField>(phoneField).controller!.text,
        '+94 77 123 4567',
      );
      final email = tester.widget<TextFormField>(
        find.byKey(const Key('profile-email')),
      );
      expect(email.initialValue, 'amara.silva@example.com');
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byKey(const Key('profile-email')),
                matching: find.byType(TextField),
              ),
            )
            .readOnly,
        isTrue,
      );
      expect(tester.widget<FilledButton>(saveButton).onPressed, isNull);
      await tester.enterText(nameField, '  Amara Silva  ');
      expect(tester.widget<FilledButton>(saveButton).onPressed, isNull);
      expect(find.byTooltip('Back to Profile'), findsOneWidget);
    },
  );

  testWidgets(
    'name save trims, accepts server response, and refreshes main identity',
    (tester) async {
      backend.authoritativeName = 'Updated Server Name';
      await backend.pump(
        tester,
        (user) => Scaffold(body: SharedProfileContent(user: user)),
      );
      await tester.tap(find.text('Personal information'));
      await tester.pumpAndSettle();
      await tester.enterText(nameField, '  Updated Name  ');
      await tapSave(tester);
      expect(jsonDecode(backend.writes.single.body), {
        'fullName': 'Updated Name',
        'phoneNumber': '+94 77 123 4567',
      });
      expect(
        backend.writes.single.headers['authorization'],
        'Bearer profile-token',
      );
      expect(backend.auth.currentUser!.fullName, 'Updated Server Name');
      expect(
        tester.widget<TextFormField>(nameField).controller!.text,
        'Updated Server Name',
      );
      expect(find.text('Profile updated successfully.'), findsOneWidget);
      expect(tester.widget<FilledButton>(saveButton).onPressed, isNull);
      await tester.tap(find.byTooltip('Back to Profile'));
      await tester.pumpAndSettle();
      expect(find.text('Updated Server Name'), findsOneWidget);
    },
  );

  testWidgets(
    'phone update uses compatible punctuation without public digit limits',
    (tester) async {
      await open(tester);
      await tester.ensureVisible(phoneField);
      await tester.enterText(phoneField, '  +94 (77) 123-4567  ');
      await tapSave(tester);
      expect(backend.auth.currentUser!.phoneNumber, '+94 (77) 123-4567');
      expect(
        jsonDecode(backend.writes.single.body)['phoneNumber'],
        '+94 (77) 123-4567',
      );
    },
  );

  for (final invalid in ['', ' ', 'A']) {
    testWidgets('blocks invalid full name "$invalid"', (tester) async {
      await open(tester);
      await tester.enterText(nameField, invalid);
      await tapSave(tester);
      expect(backend.writes, isEmpty);
      expect(
        find.text('Full name must be between 2 and 200 characters.'),
        findsOneWidget,
      );
      expect(tester.widget<TextFormField>(nameField).controller!.text, invalid);
    });
  }

  for (final invalid in ['', '123456', 'phone123', '+94/771234567']) {
    testWidgets('blocks invalid phone "$invalid"', (tester) async {
      await open(tester);
      await tester.ensureVisible(phoneField);
      await tester.enterText(phoneField, invalid);
      await tapSave(tester);
      expect(backend.writes, isEmpty);
      expect(
        find.text('Enter a valid phone number (7–32 characters).'),
        findsOneWidget,
      );
    });
  }

  testWidgets('API failure keeps drafts and permits a successful retry', (
    tester,
  ) async {
    backend.failSave = true;
    await open(tester);
    await tester.enterText(nameField, 'Draft Name');
    await tapSave(tester);
    expect(
      tester.widget<TextFormField>(nameField).controller!.text,
      'Draft Name',
    );
    expect(backend.auth.currentUser!.fullName, 'Amara Silva');
    expect(find.text('Unable to save profile.'), findsOneWidget);
    backend.failSave = false;
    await tapSave(tester);
    expect(backend.auth.currentUser!.fullName, 'Draft Name');
  });

  testWidgets(
    'pending save disables controls and prevents duplicate submission',
    (tester) async {
      backend.pendingSave = Completer<http.Response>();
      await open(tester);
      await tester.enterText(nameField, 'Pending Name');
      await tester.pump();
      await tester.ensureVisible(saveButton);
      await tester.tap(saveButton);
      await tester.pump();
      expect(find.text('Saving changes…'), findsOneWidget);
      expect(tester.widget<FilledButton>(saveButton).onPressed, isNull);
      expect(tester.widget<TextFormField>(nameField).enabled, isFalse);
      expect(tester.widget<TextFormField>(phoneField).enabled, isFalse);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Change photo'),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is IconButton && widget.tooltip == 'Back to Profile',
              ),
            )
            .onPressed,
        isNull,
      );
      expect(backend.writes, hasLength(1));
      backend.pendingSave!.complete(backend.json());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'landlord private phone save preserves published contact and editor',
    (tester) async {
      backend.dispose();
      backend = ProfileBackend(role: UserRole.landlord);
      await backend.pump(
        tester,
        (user) => Scaffold(body: SharedProfileContent(user: user)),
      );
      await tester.tap(find.text('Personal information'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(phoneField);
      await tester.enterText(phoneField, '+94779876543');
      await tapSave(tester);
      final body =
          jsonDecode(backend.writes.single.body) as Map<String, dynamic>;
      expect(body.containsKey('publicContactPhone'), isFalse);
      expect(body.containsKey('publicContactEnabled'), isFalse);
      expect(backend.auth.currentUser!.publicContactPhone, '+94711234567');
      expect(backend.auth.currentUser!.publicContactEnabled, isTrue);
      await tester.tap(find.byTooltip('Back to Profile'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Public contact'));
      await tester.pumpAndSettle();
      expect(find.text('Use my profile phone number'), findsOneWidget);
      expect(find.text('Use a different number'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '+94711234567',
      );
    },
  );

  testWidgets(
    'photo selection previews and uploads authenticated multipart file',
    (tester) async {
      await open(
        tester,
        picker: () async =>
            ProfileImageFile(name: 'photo.png', bytes: profilePng),
      );
      await tester.tap(find.text('Change photo'));
      await tester.pumpAndSettle();
      expect(find.text('Selected: photo.png'), findsOneWidget);
      expect(
        tester.widget<Image>(find.byType(Image)).image,
        isA<MemoryImage>(),
      );
      expect(backend.writes, isEmpty);
      await tapSave(tester);
      final upload = backend.writes.single;
      expect(upload.method, 'POST');
      expect(upload.url.path, '/api/auth/profile-image');
      expect(upload.headers['authorization'], 'Bearer profile-token');
      final body = utf8.decode(upload.bodyBytes, allowMalformed: true);
      expect(body, contains('name="file"; filename="photo.png"'));
      expect(body, contains('image/png'));
      expect(backend.auth.currentUser!.hasProfileImage, isTrue);
      expect(backend.imageLoads, hasLength(1));
      expect(find.text('Selected: photo.png'), findsNothing);
      expect(find.byType(Image), findsOneWidget);
    },
  );

  testWidgets('invalid image choices never enable upload', (tester) async {
    final choices = [
      ProfileImageFile(
        name: 'large.png',
        bytes: Uint8List(ProfileImageFile.maximumBytes + 1),
      ),
      ProfileImageFile(name: 'photo.gif', bytes: profilePng),
      ProfileImageFile(name: 'spoof.png', bytes: Uint8List.fromList([1, 2, 3])),
      ProfileImageFile(name: 'empty.png', bytes: Uint8List(0)),
    ];
    var choice = 0;
    await open(tester, picker: () async => choices[choice++]);
    for (var i = 0; i < choices.length; i++) {
      await tester.tap(find.text('Change photo'));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(saveButton).onPressed, isNull);
      expect(find.textContaining('Choose a'), findsOneWidget);
      expect(backend.writes, isEmpty);
    }
  });

  testWidgets(
    'account save precedes upload, partial success preserves image retry',
    (tester) async {
      backend.failUpload = true;
      await open(
        tester,
        picker: () async =>
            ProfileImageFile(name: 'photo.png', bytes: profilePng),
      );
      await tester.tap(find.text('Change photo'));
      await tester.pumpAndSettle();
      await tester.enterText(nameField, 'Saved Name');
      await tapSave(tester);
      expect(backend.writes.map((r) => r.method), ['PUT', 'POST']);
      expect(backend.auth.currentUser!.fullName, 'Saved Name');
      expect(
        find.textContaining(
          'information was saved, but the photo upload failed',
        ),
        findsOneWidget,
      );
      expect(find.text('Selected: photo.png'), findsOneWidget);
      expect(find.text('Profile updated successfully.'), findsNothing);
      backend.failUpload = false;
      await tapSave(tester);
      expect(backend.writes.map((r) => r.method), ['PUT', 'POST', 'POST']);
      expect(backend.auth.currentUser!.hasProfileImage, isTrue);
      expect(find.text('Profile updated successfully.'), findsOneWidget);
    },
  );

  testWidgets(
    'account failure prevents selected photo upload and keeps both drafts',
    (tester) async {
      backend.failSave = true;
      await open(
        tester,
        picker: () async =>
            ProfileImageFile(name: 'photo.png', bytes: profilePng),
      );
      await tester.tap(find.text('Change photo'));
      await tester.pumpAndSettle();
      await tester.enterText(nameField, 'Draft Name');
      await tapSave(tester);
      expect(backend.writes.single.method, 'PUT');
      expect(find.text('Selected: photo.png'), findsOneWidget);
      expect(
        tester.widget<TextFormField>(nameField).controller!.text,
        'Draft Name',
      );
    },
  );

  testWidgets('picker cancellation and failure preserve account drafts', (
    tester,
  ) async {
    var attempt = 0;
    await open(
      tester,
      picker: () async {
        if (attempt++ == 0) return null;
        throw StateError('picker failure');
      },
    );
    await tester.enterText(nameField, 'Draft Name');
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.text('Change photo'));
      await tester.pumpAndSettle();
    }
    expect(
      tester.widget<TextFormField>(nameField).controller!.text,
      'Draft Name',
    );
    expect(
      find.text('Unable to choose a photo. Please try again.'),
      findsOneWidget,
    );
    expect(backend.writes, isEmpty);
  });

  testWidgets('personal information fits requested displays at 200% scaling', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    backend.profile['fullName'] =
        'A very long personal account name with multiple words for layout testing';
    backend.profile['email'] =
        'averylongemailaddress.for.layout.testing@example.test';
    for (final display in [
      (const Size(320, 640), 1.0),
      (const Size(720, 1560), 2.0),
      (const Size(1080, 2340), 3.0),
    ]) {
      tester.view.physicalSize = display.$1;
      tester.view.devicePixelRatio = display.$2;
      await backend.pump(
        tester,
        (user) => PersonalInformationScreen(user: user),
        scale: 2,
      );
      await tester.ensureVisible(saveButton);
      expect(tester.takeException(), isNull);
      expect(
        tester.getBottomRight(saveButton).dx,
        lessThanOrEqualTo(display.$1.width / display.$2),
      );
      await tester.pumpWidget(const SizedBox());
    }
  });
}
