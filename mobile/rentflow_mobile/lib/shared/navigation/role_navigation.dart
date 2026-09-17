import 'package:flutter/material.dart';

import '../../features/auth/models/current_user.dart';

enum RoleDestinationId {
  home,
  properties,
  viewings,
  applications,
  viewingRequests,
  assignedWork,
  profile,
}

enum DestinationExperience {
  dashboard,
  feature,
  unavailable,
  webWorkspace,
  profile,
}

class RoleDestination {
  const RoleDestination({
    required this.id,
    required this.label,
    required this.icon,
    required this.experience,
    this.explanation,
    this.owner,
  });

  final RoleDestinationId id;
  final String label;
  final IconData icon;
  final DestinationExperience experience;
  final String? explanation;
  final String? owner;

  bool get isAvailable =>
      experience == DestinationExperience.feature ||
      experience == DestinationExperience.dashboard ||
      experience == DestinationExperience.profile;
}

const _home = RoleDestination(
  id: RoleDestinationId.home,
  label: 'Home',
  icon: Icons.home_outlined,
  experience: DestinationExperience.dashboard,
);

const _profile = RoleDestination(
  id: RoleDestinationId.profile,
  label: 'Profile',
  icon: Icons.person_outline,
  experience: DestinationExperience.profile,
);

List<RoleDestination> destinationsFor(UserRole role) => switch (role) {
  UserRole.tenant => const [
    _home,
    RoleDestination(
      id: RoleDestinationId.properties,
      label: 'Properties',
      icon: Icons.home_work_outlined,
      experience: DestinationExperience.unavailable,
      owner: 'Property management',
      explanation:
          'Property discovery will appear here after the property module is integrated.',
    ),
    RoleDestination(
      id: RoleDestinationId.viewings,
      label: 'Viewings',
      icon: Icons.calendar_month_outlined,
      experience: DestinationExperience.feature,
    ),
    RoleDestination(
      id: RoleDestinationId.applications,
      label: 'Applications',
      icon: Icons.description_outlined,
      experience: DestinationExperience.feature,
    ),
    _profile,
  ],
  UserRole.landlord => const [
    _home,
    RoleDestination(
      id: RoleDestinationId.viewingRequests,
      label: 'Viewing Requests',
      icon: Icons.calendar_month_outlined,
      experience: DestinationExperience.feature,
    ),
    RoleDestination(
      id: RoleDestinationId.applications,
      label: 'Applications',
      icon: Icons.description_outlined,
      experience: DestinationExperience.webWorkspace,
      explanation:
          'Application documents and AI review are available in the RentFlow web workspace.',
    ),
    _profile,
  ],
  UserRole.maintenanceTechnician => const [
    _home,
    RoleDestination(
      id: RoleDestinationId.assignedWork,
      label: 'Assigned Work',
      icon: Icons.handyman_outlined,
      experience: DestinationExperience.unavailable,
      owner: 'Maintenance',
      explanation:
          'Assigned maintenance work will appear here after the maintenance module is integrated.',
    ),
    _profile,
  ],
  UserRole.admin => const [_home, _profile],
};
