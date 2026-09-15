import '../../features/auth/models/current_user.dart';

class RoleDestination {
  const RoleDestination(this.label, {this.available = false, this.note});
  final String label;
  final bool available;
  final String? note;
}

List<RoleDestination> destinationsFor(UserRole role) => switch (role) {
  UserRole.tenant => const [
    RoleDestination('Properties'),
    RoleDestination('Viewings', available: true),
    RoleDestination('My Applications', available: true),
    RoleDestination('Lease / Payments'),
    RoleDestination('Maintenance Requests'),
  ],
  UserRole.landlord => const [
    RoleDestination('Properties'),
    RoleDestination('Viewing Requests', note: 'Available in the web dashboard'),
    RoleDestination(
      'Rental Applications',
      note: 'Available in the web dashboard',
    ),
    RoleDestination('Pricing / Lease'),
    RoleDestination('Payments'),
    RoleDestination('Maintenance'),
    RoleDestination(
      'AI Review / Validation',
      note: 'Inside web Rental Applications',
    ),
  ],
  UserRole.maintenanceTechnician => const [
    RoleDestination('Assigned Maintenance'),
  ],
  UserRole.admin => const [
    RoleDestination('Users'),
    RoleDestination('Properties Overview'),
    RoleDestination('Applications Overview'),
    RoleDestination('Payments Overview'),
    RoleDestination('Maintenance Overview'),
    RoleDestination('AI Workflow Monitoring'),
  ],
};
