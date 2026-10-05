class PasswordChangeResult {
  const PasswordChangeResult({
    required this.message,
    required this.accessToken,
    required this.expiresAt,
  });

  final String message;
  final String accessToken;
  final DateTime expiresAt;
}
