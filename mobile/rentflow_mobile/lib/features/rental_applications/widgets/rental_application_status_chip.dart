import 'package:flutter/material.dart';

import '../models/rental_application.dart';

class RentalApplicationStatusChip extends StatelessWidget {
  const RentalApplicationStatusChip({super.key, required this.status});

  final RentalApplicationStatus status;

  @override
  Widget build(BuildContext context) {
    final appearance = switch (status) {
      RentalApplicationStatus.draft => const _StatusAppearance(
        label: 'Draft',
        foreground: Color(0xFF626262),
        background: Color(0xFFE9E7E2),
      ),
      RentalApplicationStatus.submitted => const _StatusAppearance(
        label: 'Submitted',
        foreground: Color(0xFF765B13),
        background: Color(0xFFFFF1C7),
      ),
      RentalApplicationStatus.underReview => const _StatusAppearance(
        label: 'Under Review',
        foreground: Color(0xFF43556A),
        background: Color(0xFFDDE7EF),
      ),
      RentalApplicationStatus.changesRequested => const _StatusAppearance(
        label: 'Changes Requested',
        foreground: Color(0xFF755028),
        background: Color(0xFFF2E4D2),
      ),
      RentalApplicationStatus.approved => const _StatusAppearance(
        label: 'Approved',
        foreground: Color(0xFF35613B),
        background: Color(0xFFDDEDDD),
      ),
      RentalApplicationStatus.rejected => const _StatusAppearance(
        label: 'Rejected',
        foreground: Color(0xFF8A3535),
        background: Color(0xFFF5DDDC),
      ),
      RentalApplicationStatus.withdrawn => const _StatusAppearance(
        label: 'Withdrawn',
        foreground: Color(0xFF626262),
        background: Color(0xFFE9E7E2),
      ),
    };

    return Chip(
      label: Text(appearance.label),
      labelStyle: TextStyle(
        color: appearance.foreground,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
      backgroundColor: appearance.background,
      side: BorderSide.none,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _StatusAppearance {
  const _StatusAppearance({
    required this.label,
    required this.foreground,
    required this.background,
  });

  final String label;
  final Color foreground;
  final Color background;
}
