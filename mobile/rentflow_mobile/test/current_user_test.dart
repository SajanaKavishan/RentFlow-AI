import 'package:flutter_test/flutter_test.dart';
import 'package:rentflow_mobile/features/auth/models/current_user.dart';
import 'package:rentflow_mobile/core/validation/phone_number.dart';

void main() {
  test(
    'profile phone keeps length/punctuation rules separate from public contact',
    () {
      expect(isValidProfilePhone('1234567'), isTrue);
      expect(isValidProfilePhone('1' * 32), isTrue);
      expect(isValidProfilePhone('1' * 33), isFalse);
      expect(isValidProfilePhone('123456'), isFalse);
      expect(isValidProfilePhone('+94 (77) 123-4567'), isTrue);
      expect(isValidProfilePhone('  +94771234567  '), isTrue);
      expect(isValidProfilePhone('1' * 16), isTrue);
      expect(usablePhoneNumber('1' * 16), isNull);
    },
  );
  final profile = <String, dynamic>{
    'id': 'user',
    'fullName': 'Amara Silva',
    'email': 'amara@example.test',
    'phoneNumber': '+94771234567',
    'role': 'Landlord',
  };

  test('parses image presence and preserves landlord contact fields', () {
    final user = CurrentUser.fromJson({
      ...profile,
      'hasProfileImage': true,
      'publicContactPhone': '+94112223344',
      'publicContactEnabled': true,
    });
    expect(user.id, 'user');
    expect(user.fullName, 'Amara Silva');
    expect(user.email, 'amara@example.test');
    expect(user.phoneNumber, '+94771234567');
    expect(user.role, UserRole.landlord);
    expect(user.hasProfileImage, isTrue);
    expect(user.publicContactPhone, '+94112223344');
    expect(user.publicContactEnabled, isTrue);
  });

  test('missing optional image and contact fields are safe', () {
    final user = CurrentUser.fromJson(profile);
    expect(user.hasProfileImage, isFalse);
    expect(user.publicContactPhone, isNull);
    expect(user.publicContactEnabled, isFalse);
    expect(
      CurrentUser.fromJson({
        ...profile,
        'hasProfileImage': null,
      }).hasProfileImage,
      isFalse,
    );
  });

  test('other roles do not retain landlord-only contact fields', () {
    for (final role in [
      UserRole.tenant,
      UserRole.admin,
      UserRole.maintenanceTechnician,
    ]) {
      final user = CurrentUser.fromJson({
        ...profile,
        'role': role.value,
        'hasProfileImage': true,
        'publicContactPhone': '+94112223344',
        'publicContactEnabled': true,
      });
      expect(user.hasProfileImage, isTrue);
      expect(user.publicContactPhone, isNull);
      expect(user.publicContactEnabled, isFalse);
    }
  });

  test('required identity and role validation remains strict', () {
    expect(
      () => CurrentUser.fromJson({...profile, 'id': null}),
      throwsFormatException,
    );
    expect(
      () => CurrentUser.fromJson({...profile, 'role': 'Unknown'}),
      throwsFormatException,
    );
  });
}
