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
        foreground: Color(0xFF765B13),
        background: Color(0xFFFFF1C7),
      ),
      ViewingStatus.approved => const _StatusAppearance(
        label: 'Approved',
        foreground: Color(0xFF35613B),
        background: Color(0xFFDDEDDD),
      ),
      ViewingStatus.rejected => const _StatusAppearance(
        label: 'Rejected',
        foreground: Color(0xFF8A3535),
        background: Color(0xFFF5DDDC),
      ),
      ViewingStatus.cancelled => const _StatusAppearance(
        label: 'Cancelled',
        foreground: Color(0xFF626262),
        background: Color(0xFFE9E7E2),
      ),
      ViewingStatus.completed => const _StatusAppearance(
        label: 'Completed',
        foreground: Color(0xFF43556A),
        background: Color(0xFFDDE7EF),
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
