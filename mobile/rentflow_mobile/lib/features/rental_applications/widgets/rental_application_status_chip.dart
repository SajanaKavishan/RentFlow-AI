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
        icon: Icons.edit_note_outlined,
        foreground: Color(0xFF626262),
        background: Color(0xFFE9E7E2),
      ),
      RentalApplicationStatus.submitted => const _StatusAppearance(
        label: 'Submitted',
        icon: Icons.send_outlined,
        foreground: Color(0xFF765B13),
        background: Color(0xFFFFF1C7),
      ),
      RentalApplicationStatus.underReview => const _StatusAppearance(
        label: 'Under Review',
        icon: Icons.manage_search_outlined,
        foreground: Color(0xFF43556A),
        background: Color(0xFFDDE7EF),
      ),
      RentalApplicationStatus.changesRequested => const _StatusAppearance(
        label: 'Changes Requested',
        icon: Icons.priority_high_rounded,
        foreground: Color(0xFF755028),
        background: Color(0xFFF2E4D2),
      ),
      RentalApplicationStatus.approved => const _StatusAppearance(
        label: 'Approved',
        icon: Icons.check_circle_outline,
        foreground: Color(0xFF35613B),
        background: Color(0xFFDDEDDD),
      ),
      RentalApplicationStatus.rejected => const _StatusAppearance(
        label: 'Rejected',
        icon: Icons.cancel_outlined,
        foreground: Color(0xFF8A3535),
        background: Color(0xFFF5DDDC),
      ),
      RentalApplicationStatus.withdrawn => const _StatusAppearance(
        label: 'Withdrawn',
        icon: Icons.undo_outlined,
        foreground: Color(0xFF626262),
        background: Color(0xFFE9E7E2),
      ),
    };

    return Semantics(
      label: 'Application status: ${appearance.label}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: appearance.background,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: appearance.foreground.withValues(alpha: 0.18),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(appearance.icon, size: 14, color: appearance.foreground),
            const SizedBox(width: 4),
            Text(
              appearance.label,
              style: TextStyle(
                color: appearance.foreground,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusAppearance {
  const _StatusAppearance({
    required this.label,
    required this.icon,
    required this.foreground,
    required this.background,
  });

  final String label;
  final IconData icon;
  final Color foreground;
  final Color background;
}
