import 'package:flutter/material.dart';

import '../models/viewing.dart';

class ViewingStatusChip extends StatelessWidget {
  const ViewingStatusChip({super.key, required this.status});

  final ViewingStatus status;

  @override
  Widget build(BuildContext context) {
    final appearance = switch (status) {
      ViewingStatus.pending => const _StatusAppearance(
        label: 'Pending',
        icon: Icons.schedule_outlined,
        foreground: Color(0xFF765B13),
        background: Color(0xFFFFF1C7),
      ),
      ViewingStatus.approved => const _StatusAppearance(
        label: 'Approved',
        icon: Icons.check_circle_outline,
        foreground: Color(0xFF35613B),
        background: Color(0xFFDDEDDD),
      ),
      ViewingStatus.rejected => const _StatusAppearance(
        label: 'Rejected',
        icon: Icons.cancel_outlined,
        foreground: Color(0xFF8A3535),
        background: Color(0xFFF5DDDC),
      ),
      ViewingStatus.cancelled => const _StatusAppearance(
        label: 'Cancelled',
        icon: Icons.event_busy_outlined,
        foreground: Color(0xFF626262),
        background: Color(0xFFE9E7E2),
      ),
      ViewingStatus.completed => const _StatusAppearance(
        label: 'Completed',
        icon: Icons.task_alt_outlined,
        foreground: Color(0xFF43556A),
        background: Color(0xFFDDE7EF),
      ),
    };

    return Semantics(
      label: 'Viewing status: ${appearance.label}',
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
