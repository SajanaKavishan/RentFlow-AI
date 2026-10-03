import '../../../core/validation/phone_number.dart';

class LandlordContact {
  const LandlordContact({required this.displayName, required this.phoneNumber});
  final String displayName;
  final String phoneNumber;

  static LandlordContact? fromJson(Map<String, dynamic> json) {
    final name = json['displayName'];
    final rawPhone = json['phoneNumber'];
    final phone = rawPhone is String ? usablePhoneNumber(rawPhone) : null;
    return name is String && name.trim().isNotEmpty && phone != null
        ? LandlordContact(displayName: name.trim(), phoneNumber: phone)
        : null;
  }
}
