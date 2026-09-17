import 'package:flutter/material.dart';

import '../../../shared/widgets/shared_widgets.dart';
import '../models/viewing.dart';

class ViewingStatusChip extends StatelessWidget {
  const ViewingStatusChip({super.key, required this.status});

  final ViewingStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, icon, tone) = switch (status) {
      ViewingStatus.pending => (
        'Pending',
        Icons.schedule_outlined,
        StatusTone.pending,
      ),
      ViewingStatus.approved => (
        'Approved',
        Icons.check_circle_outline,
        StatusTone.success,
      ),
      ViewingStatus.rejected => (
        'Rejected',
        Icons.cancel_outlined,
        StatusTone.danger,
      ),
      ViewingStatus.cancelled => (
        'Cancelled',
        Icons.event_busy_outlined,
        StatusTone.neutral,
      ),
      ViewingStatus.completed => (
        'Completed',
        Icons.task_alt_outlined,
        StatusTone.progress,
      ),
    };

    return Semantics(
      label: 'Viewing status: $label',
      excludeSemantics: true,
      child: StatusChip(label: label, icon: icon, tone: tone),
    );
  }
}
