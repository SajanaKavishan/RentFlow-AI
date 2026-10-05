import 'package:flutter/material.dart';

import '../../../shared/theme/app_theme.dart';
import '../models/maintenance_request.dart';

String maintenanceLabel(Enum value) {
  if (value is MaintenanceCategory) {
    return switch (value) {
      MaintenanceCategory.hvac => 'HVAC / A/C',
      MaintenanceCategory.appliance => 'Appliances',
      MaintenanceCategory.pest => 'Pest Control',
      MaintenanceCategory.locksDoors => 'Locks / Doors',
      _ => _enumLabel(value),
    };
  }
  return _enumLabel(value);
}

String _enumLabel(Enum value) => value.name
    .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}')
    .split(' ')
    .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
    .join(' ');

IconData maintenanceCategoryIcon(MaintenanceCategory category) =>
    switch (category) {
      MaintenanceCategory.plumbing => Icons.plumbing_outlined,
      MaintenanceCategory.electrical => Icons.bolt_outlined,
      MaintenanceCategory.appliance => Icons.kitchen_outlined,
      MaintenanceCategory.structural => Icons.foundation_outlined,
      MaintenanceCategory.security => Icons.lock_outline,
      MaintenanceCategory.pest => Icons.pest_control_outlined,
      MaintenanceCategory.other => Icons.build_outlined,
      MaintenanceCategory.hvac => Icons.ac_unit_outlined,
      MaintenanceCategory.locksDoors => Icons.lock_outline,
    };

const tenantCreateCategories = [
  MaintenanceCategory.plumbing,
  MaintenanceCategory.electrical,
  MaintenanceCategory.hvac,
  MaintenanceCategory.appliance,
  MaintenanceCategory.structural,
  MaintenanceCategory.pest,
  MaintenanceCategory.locksDoors,
  MaintenanceCategory.other,
];

const tenantCreatePriorities = [
  MaintenancePriority.emergency,
  MaintenancePriority.high,
  MaintenancePriority.normal,
];

String maintenanceCreatePriorityLabel(MaintenancePriority priority) =>
    priority == MaintenancePriority.high
    ? 'High Priority'
    : maintenanceLabel(priority);

/// Presentation groups only; exact workflow statuses remain on each card.
enum TenantMaintenanceFilter {
  all('All'),
  open('Open'),
  inProgress('In progress'),
  resolved('Resolved');

  const TenantMaintenanceFilter(this.label);
  final String label;

  bool includes(MaintenanceRequestStatus status) => switch (this) {
    all => true,
    open => switch (status) {
      MaintenanceRequestStatus.submitted ||
      MaintenanceRequestStatus.triaged ||
      MaintenanceRequestStatus.assigned ||
      MaintenanceRequestStatus.estimatePending ||
      MaintenanceRequestStatus.estimateSubmitted ||
      MaintenanceRequestStatus.awaitingLandlordApproval ||
      MaintenanceRequestStatus.approved => true,
      _ => false,
    },
    inProgress => status == MaintenanceRequestStatus.inProgress,
    resolved => status == MaintenanceRequestStatus.completed,
  };
}

class MaintenanceBadge extends StatelessWidget {
  const MaintenanceBadge({
    super.key,
    required this.label,
    this.foreground = AppPalette.darkOlive,
    this.background = AppPalette.progress,
  });
  final String label;
  final Color foreground;
  final Color background;

  factory MaintenanceBadge.status(MaintenanceRequestStatus status) {
    final completed = status == MaintenanceRequestStatus.completed;
    final closed =
        status == MaintenanceRequestStatus.cancelled ||
        status == MaintenanceRequestStatus.rejected;
    final progressing = status == MaintenanceRequestStatus.inProgress;
    return MaintenanceBadge(
      label: maintenanceLabel(status),
      foreground: completed
          ? AppPalette.success
          : closed
          ? AppPalette.neutral
          : progressing
          ? AppPalette.darkOlive
          : AppPalette.warning,
      background: completed
          ? const Color(0xFFEAF2E5)
          : closed
          ? AppPalette.softCream
          : progressing
          ? AppPalette.progress
          : AppPalette.pending,
    );
  }

  factory MaintenanceBadge.priority(MaintenancePriority priority) =>
      MaintenanceBadge(
        label: maintenanceLabel(priority),
        foreground: priority == MaintenancePriority.emergency
            ? AppPalette.danger
            : priority == MaintenancePriority.high
            ? AppPalette.warning
            : AppPalette.darkOlive,
        background: priority == MaintenancePriority.emergency
            ? const Color(0xFFF8EAE7)
            : priority == MaintenancePriority.high
            ? AppPalette.pending
            : AppPalette.progress,
      );

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: foreground,
      ),
    ),
  );
}

class MaintenanceSurface extends StatelessWidget {
  const MaintenanceSurface({
    super.key,
    required this.child,
    this.selected = false,
    this.padding = const EdgeInsets.all(14),
    this.radius = 14,
    this.selectedBackground = AppPalette.progress,
    this.selectedBorder = AppPalette.olive,
  });
  final Widget child;
  final bool selected;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color selectedBackground;
  final Color selectedBorder;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: selected ? selectedBackground : AppPalette.white,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: selected ? selectedBorder : AppPalette.outline),
    ),
    child: child,
  );
}
