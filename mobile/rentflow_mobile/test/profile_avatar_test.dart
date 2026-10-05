import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rentflow_mobile/features/auth/controllers/auth_controller.dart';
import 'package:rentflow_mobile/features/auth/models/profile_image_file.dart';
import 'package:rentflow_mobile/shared/profile/profile_avatar.dart';
import 'package:rentflow_mobile/shared/profile/shared_profile_content.dart';

import 'helpers/profile_backend.dart';

void main() {
  test('initials match first two words, including empty names', () {
    expect(profileInitials('Chamodya Sayanjali'), 'CS');
    expect(profileInitials('  Pansilu   Ruwantha Perera '), 'PR');
    expect(profileInitials(''), '?');
    expect(profileInitials('   '), '?');
  });

  test('JPEG, PNG and WEBP signatures accepted with matching extension', () {
    for (final image in [
      ProfileImageFile(name: 'photo.PNG', bytes: profilePng),
      ProfileImageFile(
        name: 'photo.jpeg',
        bytes: Uint8List.fromList([255, 216, 255]),
      ),
      ProfileImageFile(
        name: 'photo.webp',
        bytes: Uint8List.fromList([82, 73, 70, 70, 0, 0, 0, 0, 87, 69, 66, 80]),
      ),
    ]) {
      expect(image.validate(), isNull);
    }
    final exactLimit = Uint8List(ProfileImageFile.maximumBytes)
      ..setRange(0, profilePng.length, profilePng);
    expect(
      ProfileImageFile(name: 'photo.png', bytes: exactLimit).validate(),
      isNull,
    );
  });

  testWidgets('no image displays initials without fetching', (tester) async {
    final backend = ProfileBackend();
    addTearDown(backend.dispose);
    await backend.pump(
      tester,
      (user) => Scaffold(body: SharedProfileContent(user: user)),
    );
    expect(find.text('AS'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(backend.imageLoads, isEmpty);
  });

  testWidgets('authenticated image bytes render in main Profile', (
    tester,
  ) async {
    final backend = ProfileBackend(hasImage: true);
    addTearDown(backend.dispose);
    await backend.pump(
      tester,
      (user) => Scaffold(body: SharedProfileContent(user: user)),
    );
    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<MemoryImage>());
    expect((image.image as MemoryImage).bytes, profilePng);
    expect(
      backend.imageLoads.single.headers['authorization'],
      'Bearer profile-token',
    );
    expect(find.text('Amara Silva'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('initials render immediately while an image fetch is pending', (
    tester,
  ) async {
    final backend = ProfileBackend(hasImage: true)
      ..pendingImage = Completer<http.Response>();
    addTearDown(backend.dispose);
    await backend.pump(
      tester,
      (user) => Scaffold(body: SharedProfileContent(user: user)),
    );
    expect(find.text('AS'), findsOneWidget);
    expect(find.text('Amara Silva'), findsOneWidget);
    backend.pendingImage!.complete(http.Response.bytes(profilePng, 200));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets(
    'main Profile fits requested displays with long identity at 200%',
    (tester) async {
      final backend = ProfileBackend();
      addTearDown(backend.dispose);
      addTearDown(tester.view.reset);
      backend.profile['fullName'] =
          'Chamodya Sayanjali with a very long account name for layout testing';
      backend.profile['email'] =
          'averylongemail.for.profile.layout.testing@example.test';
      for (final display in [
        (const Size(320, 640), 1.0),
        (const Size(720, 1560), 2.0),
        (const Size(1080, 2340), 3.0),
      ]) {
        tester.view.physicalSize = display.$1;
        tester.view.devicePixelRatio = display.$2;
        await backend.pump(
          tester,
          (user) => Scaffold(
            appBar: AppBar(title: const Text('Profile')),
            body: SharedProfileContent(user: user),
          ),
          scale: 2,
        );
        await tester.ensureVisible(find.text('Sign out'));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
    },
  );

  testWidgets(
    'fetch failure falls back to initials without breaking account page',
    (tester) async {
      final backend = ProfileBackend(hasImage: true)..failImageLoad = true;
      addTearDown(backend.dispose);
      await backend.pump(
        tester,
        (user) => Scaffold(body: SharedProfileContent(user: user)),
      );
      expect(find.text('AS'), findsOneWidget);
      expect(find.text('Personal information'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'bad image bytes fall back to initials without decode exception',
    (tester) async {
      final backend = ProfileBackend(hasImage: true)
        ..image = Uint8List.fromList([1, 2, 3]);
      addTearDown(backend.dispose);
      await backend.pump(
        tester,
        (user) => Scaffold(body: SharedProfileContent(user: user)),
      );
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(find.text('AS'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'mounted avatars share fetch and refresh when existing photo replaced',
    (tester) async {
      final backend = ProfileBackend(hasImage: true);
      addTearDown(backend.dispose);
      await backend.pump(
        tester,
        (user) => Scaffold(
          body: Builder(
            builder: (context) {
              final current = AuthScope.of(context).currentUser!;
              return Column(
                children: [
                  ProfileAvatar(user: current),
                  ProfileAvatar(user: current),
                ],
              );
            },
          ),
        ),
      );
      expect(backend.imageLoads, hasLength(1));
      final replacement = Uint8List.fromList([...profilePng, 0]);
      backend.image = replacement;
      await backend.auth.uploadProfileImage(
        ProfileImageFile(name: 'new.png', bytes: replacement),
      );
      await tester.pumpAndSettle();
      expect(backend.imageLoads, hasLength(2));
      expect(find.byType(Image), findsNWidgets(2));
      for (final image in tester.widgetList<Image>(find.byType(Image))) {
        expect((image.image as MemoryImage).bytes, replacement);
      }
    },
  );

  test(
    'logout discards image bytes from an in-flight authenticated fetch',
    () async {
      final backend = ProfileBackend(hasImage: true)
        ..pendingImage = Completer<http.Response>();
      addTearDown(backend.dispose);
      await backend.auth.restoreSession();
      final photo = backend.auth.loadProfileImage();
      await Future<void>.delayed(Duration.zero);
      await backend.auth.logout();
      backend.pendingImage!.complete(http.Response.bytes(profilePng, 200));
      expect(await photo, isNull);
      expect(backend.auth.currentUser, isNull);
    },
  );

  test('late account save cannot restore a signed-out user', () async {
    final backend = ProfileBackend()..pendingSave = Completer<http.Response>();
    addTearDown(backend.dispose);
    await backend.auth.restoreSession();
    final save = backend.auth.updateProfile(
      fullName: 'Late Name',
      phoneNumber: '+94771234567',
    );
    await Future<void>.delayed(Duration.zero);
    await backend.auth.logout();
    backend.pendingSave!.complete(backend.json());
    await save;
    expect(backend.auth.currentUser, isNull);
  });
}
