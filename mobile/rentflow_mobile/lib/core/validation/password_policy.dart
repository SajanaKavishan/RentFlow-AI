/// Mirrors the backend's UTF-16 length and character-category checks.
class PasswordPolicy {
  PasswordPolicy(this.password);

  final String password;
  bool get hasLength => password.length >= 8 && password.length <= 128;
  bool _has(String pattern) => password.codeUnits.any(
    (unit) =>
        RegExp(pattern, unicode: true).hasMatch(String.fromCharCode(unit)),
  );
  bool get hasUppercase => _has(r'\p{Lu}');
  bool get hasLowercase => _has(r'\p{Ll}');
  bool get hasNumber => _has(r'\p{Nd}');
  bool get hasSpecial => _has(r'[^\p{L}\p{Nd}]');

  String? validate({required String currentPassword}) {
    if (password.isEmpty) return 'Enter a new password.';
    if (!hasLength) return 'Use between 8 and 128 characters.';
    if (!hasUppercase) return 'Include an uppercase letter.';
    if (!hasLowercase) return 'Include a lowercase letter.';
    if (!hasNumber) return 'Include a number.';
    if (!hasSpecial) return 'Include a special character.';
    if (password == currentPassword) {
      return 'New password must differ from your current password.';
    }
    return null;
  }
}
