enum UserRole {
  tenant('Tenant'),
  landlord('Landlord'),
  maintenanceTechnician('MaintenanceTechnician'),
  admin('Admin');

  const UserRole(this.value);
  final String value;

  static UserRole parse(Object? value) => values.firstWhere(
    (role) => role.value == value,
    orElse: () => throw const FormatException('Unsupported user role.'),
  );
}

class CurrentUser {
  const CurrentUser({
    required this.id,
    required this.fullName,
    required this.email,
    required this.phoneNumber,
    required this.role,
  });

  final String id;
  final String fullName;
  final String email;
  final String phoneNumber;
  final UserRole role;

  factory CurrentUser.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final fullName = json['fullName'];
    final email = json['email'];
    final phoneNumber = json['phoneNumber'];
    if (id is! String ||
        fullName is! String ||
        email is! String ||
        phoneNumber is! String) {
      throw const FormatException('Invalid user profile.');
    }
    return CurrentUser(
      id: id,
      fullName: fullName,
      email: email,
      phoneNumber: phoneNumber,
      role: UserRole.parse(json['role']),
    );
  }
}
