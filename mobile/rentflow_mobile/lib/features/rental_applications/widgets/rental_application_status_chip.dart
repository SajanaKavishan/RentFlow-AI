import 'package:flutter/material.dart';

import '../../../shared/widgets/shared_widgets.dart';
import '../models/rental_application.dart';

class RentalApplicationStatusChip extends StatelessWidget {
  const RentalApplicationStatusChip({super.key, required this.status});

  final RentalApplicationStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, icon, tone) = switch (status) {
      RentalApplicationStatus.draft => (
        'Draft',
        Icons.edit_note_outlined,
        StatusTone.neutral,
      ),
      RentalApplicationStatus.submitted => (
        'Submitted',
        Icons.send_outlined,
        StatusTone.pending,
      ),
      RentalApplicationStatus.underReview => (
        'Under Review',
        Icons.manage_search_outlined,
        StatusTone.progress,
      ),
      RentalApplicationStatus.changesRequested => (
        'Changes Requested',
        Icons.priority_high_rounded,
        StatusTone.danger,
      ),
      RentalApplicationStatus.approved => (
        'Approved',
        Icons.check_circle_outline,
        StatusTone.success,
      ),
      RentalApplicationStatus.rejected => (
        'Rejected',
        Icons.cancel_outlined,
        StatusTone.danger,
      ),
      RentalApplicationStatus.withdrawn => (
        'Withdrawn',
        Icons.undo_outlined,
        StatusTone.neutral,
      ),
    };

    return Semantics(
      label: 'Application status: $label',
      excludeSemantics: true,
      child: StatusChip(label: label, icon: icon, tone: tone),
    );
  }
}
