// Account profile validation intentionally has no public-contact digit limit.
bool isValidProfilePhone(String value) =>
    RegExp(r'^[+0-9][0-9\s().-]{6,31}$').hasMatch(value.trim());

String? usablePhoneNumber(String? value) {
  final phone = value?.trim() ?? '';
  final digits = phone.replaceAll(RegExp(r'[^0-9]'), '').length;
  return RegExp(r'^[+0-9][0-9\s().-]{6,31}$').hasMatch(phone) &&
          digits >= 7 &&
          digits <= 15
      ? phone
      : null;
}

Uri? phoneDialerUri(String? number) {
  final phone = usablePhoneNumber(number);
  return phone == null
      ? null
      : Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'[^+0-9]'), ''));
}
