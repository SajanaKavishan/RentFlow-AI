import 'package:flutter/material.dart';

import '../../../shared/theme/app_theme.dart';
import '../models/maintenance_request.dart';
import '../models/maintenance_status_history.dart';

String maintenanceEventLabel(MaintenanceStatusHistory event) => switch ((
  event.fromStatus,
  event.toStatus,
)) {
  (null, MaintenanceRequestStatus.submitted) => 'Request submitted',
  (MaintenanceRequestStatus.submitted, MaintenanceRequestStatus.triaged) =>
    'Request reviewed',
  (MaintenanceRequestStatus.triaged, MaintenanceRequestStatus.assigned) =>
    'Technician assigned',
  (
    MaintenanceRequestStatus.assigned,
    MaintenanceRequestStatus.estimatePending,
  ) =>
    'Estimate requested',
  (
    MaintenanceRequestStatus.estimatePending,
    MaintenanceRequestStatus.estimateSubmitted,
  ) =>
    'Estimate submitted',
  (
    MaintenanceRequestStatus.estimateSubmitted,
    MaintenanceRequestStatus.awaitingLandlordApproval,
  ) =>
    'Awaiting landlord approval',
  (
    MaintenanceRequestStatus.awaitingLandlordApproval,
    MaintenanceRequestStatus.approved,
  ) =>
    'Estimate approved',
  (
    MaintenanceRequestStatus.awaitingLandlordApproval,
    MaintenanceRequestStatus.rejected,
  ) =>
    'Estimate rejected',
  (
    MaintenanceRequestStatus.awaitingLandlordApproval,
    MaintenanceRequestStatus.estimatePending,
  ) =>
    'Estimate revision requested',
  (MaintenanceRequestStatus.approved, MaintenanceRequestStatus.inProgress) =>
    'Work started',
  (MaintenanceRequestStatus.inProgress, MaintenanceRequestStatus.completed) =>
    'Request completed',
  (_, MaintenanceRequestStatus.cancelled) => 'Request cancelled',
  _ => 'Request updated',
};

/// Only persisted records become timeline nodes. Staff notes have no Tenant-safe contract.
class MaintenanceTimeline extends StatelessWidget {
  const MaintenanceTimeline({super.key, required this.history});
  final List<MaintenanceStatusHistory> history;

  @override
  Widget build(BuildContext context) {
    final events = List<MaintenanceStatusHistory>.of(history)
      ..sort((a, b) {
        final time = a.changedAt.compareTo(b.changedAt);
        return time == 0 ? a.id.compareTo(b.id) : time;
      });
    final format = MaterialLocalizations.of(context);
    return Column(
      key: const ValueKey('maintenance-timeline'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < events.length; index++)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ExcludeSemantics(
                  child: SizedBox(
                    width: 14,
                    child: Stack(
                      children: [
                        if (index > 0)
                          Positioned(
                            left: 6,
                            top: 0,
                            height: 10,
                            child: Container(
                              width: 1,
                              color: AppPalette.outline,
                            ),
                          ),
                        if (index < events.length - 1)
                          Positioned(
                            left: 6,
                            top: 10,
                            bottom: 0,
                            child: Container(
                              key: ValueKey(
                                'timeline-connector-${events[index].id}',
                              ),
                              width: 1,
                              color: AppPalette.outline,
                            ),
                          ),
                        Positioned(
                          left: 2,
                          top: 5,
                          child: Container(
                            width: 9,
                            height: 9,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: index == events.length - 1
                                  ? AppPalette.darkOlive
                                  : AppPalette.sage,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Semantics(
                    container: true,
                    child: Padding(
                      padding: EdgeInsets.only(
                        bottom: index == events.length - 1 ? 0 : 18,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            maintenanceEventLabel(events[index]),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              height: 1.35,
                              color: index == events.length - 1
                                  ? AppPalette.darkOlive
                                  : AppPalette.primaryText,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${format.formatShortMonthDay(events[index].changedAt.toLocal())} · ${format.formatTimeOfDay(TimeOfDay.fromDateTime(events[index].changedAt.toLocal()))}',
                            style: const TextStyle(
                              fontSize: 12,
                              height: 1.4,
                              color: AppPalette.secondaryText,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
