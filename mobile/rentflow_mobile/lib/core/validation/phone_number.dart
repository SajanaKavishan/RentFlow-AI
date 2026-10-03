String? usablePhoneNumber(String? value) {
  final phone = value?.trim() ?? '';
  final digits = phone.replaceAll(RegExp(r'[^0-9]'), '').length;
  return RegExp(r'^[+0-9][0-9\s().-]{6,31}$').hasMatch(phone) &&
          digits >= 7 &&
          digits <= 15
      ? phone
      : null;
}
