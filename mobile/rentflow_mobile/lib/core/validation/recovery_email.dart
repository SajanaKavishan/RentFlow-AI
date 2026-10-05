/// Matches the project's email form validation and the recovery DTO's limit.
String? validateRecoveryEmail(String? value) {
  final email = value?.trim() ?? '';
  if (email.isEmpty) return 'Email is required.';
  if (email.length > 320) return 'Email must be 320 characters or fewer.';
  if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
    return 'Enter a valid email address.';
  }
  return null;
}
