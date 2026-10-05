import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';
import '../../features/maintenance/services/maintenance_api_service.dart';
import '../../features/notifications/services/notification_api_service.dart';
import '../../features/properties/models/property.dart';
import '../../features/properties/models/property_matching.dart';
import '../../features/properties/services/property_api_service.dart';
import '../../features/rental_applications/models/rental_application.dart';
import '../../features/rental_applications/services/rental_application_api_service.dart';
import '../../features/tenant_lease_payments/services/tenant_lease_payments_api_service.dart';
import '../../features/viewings/models/viewing.dart';
import '../../features/viewings/services/viewing_api_service.dart';
import '../navigation/role_navigation.dart';

class TenantActivity {
  const TenantActivity({
    required this.title,
    required this.subtitle,
    required this.timestamp,
    required this.icon,
    this.destination,
    this.isNotification = false,
  });
  final String title;
  final String subtitle;
  final DateTime timestamp;
  final IconData icon;
  final RoleDestinationId? destination;
  final bool isNotification;
}

class TenantJourney {
  const TenantJourney({
    required this.status,
    required this.title,
    required this.subtitle,
    required this.helper,
    this.destination,
  });
  final String status;
  final String title;
  final String subtitle;
  final String helper;
  final RoleDestinationId? destination;
}

class TenantDashboardSnapshot {
  const TenantDashboardSnapshot({
    required this.activities,
    required this.journey,
    required this.failedSources,
    required this.successfulSources,
  });
  final List<TenantActivity> activities;
  final TenantJourney? journey;
  final List<String> failedSources;
  final int successfulSources;
  bool get journeyUnavailable =>
      journey == null &&
      (successfulSources == 0 ||
          failedSources.any(
            (source) => ['applications', 'viewings', 'leases'].contains(source),
          ));
}

class TenantRecommendation {
  const TenantRecommendation(this.property, this.match);
  final Property property;
  final PropertyMatch match;
}

class TenantRecommendations {
  const TenantRecommendations({
    required this.configured,
    this.items = const [],
    this.partialFailure = false,
    this.matches,
  });
  final bool configured;
  final List<TenantRecommendation> items;
  final bool partialFailure;
  final PropertyMatchingResponse? matches;
}

/// Each source keeps its own API contract and can fail independently.
class TenantDashboardService {
  const TenantDashboardService(this.apiClient);
  final ApiClient apiClient;

  Future<TenantDashboardSnapshot> load({
    required String tenantId,
    required DateTime now,
    ViewingApiService? viewings,
    RentalApplicationApiService? applications,
    NotificationApiService? notifications,
    MaintenanceApiService? maintenance,
    PropertyApiService? properties,
  }) async {
    final activities = <TenantActivity>[];
    final failed = <String>[];
    var successful = 0;
    var applicationItems = <RentalApplication>[];
    var viewingItems = <Viewing>[];
    var leaseItems = <Map<String, dynamic>>[];
    var schedules = <Map<String, dynamic>>[];
    Future<void> source(String name, Future<void> Function() read) async {
      try {
        await read();
        successful++;
      } catch (_) {
        failed.add(name);
      }
    }

    await Future.wait([
      if (applications != null)
        source('applications', () async {
          applicationItems = await applications.getMyApplications();
          activities.addAll(
            applicationItems.map(
              (item) => TenantActivity(
                title: applicationTitle(item.status),
                subtitle: item.landlordResponse?.trim().isNotEmpty == true
                    ? item.landlordResponse!
                    : 'Current status: ${applicationTitle(item.status).replaceFirst('Application ', '').toLowerCase()}.',
                timestamp: item.updatedAt ?? item.submittedAt ?? item.createdAt,
                icon: Icons.description_outlined,
                destination: RoleDestinationId.applications,
              ),
            ),
          );
        }),
      if (viewings != null)
        source('viewings', () async {
          viewingItems = await viewings.getMyViewings();
          activities.addAll(
            viewingItems.map(
              (item) => TenantActivity(
                title: viewingTitle(item.status),
                subtitle:
                    'Appointment ${dashboardDateTime(item.requestedDateTime)}',
                timestamp: item.updatedAt ?? item.createdAt,
                icon: Icons.calendar_month_outlined,
                destination: RoleDestinationId.viewings,
              ),
            ),
          );
        }),
      if (notifications != null)
        source('notifications', () async {
          final page = await notifications.getNotifications(pageSize: 20);
          activities.addAll(
            page.items.map(
              (item) => TenantActivity(
                title: item.title,
                subtitle: item.message,
                timestamp: item.createdAt,
                icon: notificationIcon(item.eventType),
                isNotification: true,
              ),
            ),
          );
        }),
      if (maintenance != null)
        source('maintenance', () async {
          final items = await maintenance.getMyMaintenanceRequests(
            tenantId: tenantId,
          );
          const titles = [
            'Maintenance request submitted',
            'Maintenance request triaged',
            'Technician assigned',
            'Repair estimate pending',
            'Repair estimate submitted',
            'Awaiting landlord approval',
            'Repair approved',
            'Repair rejected',
            'Repair in progress',
            'Repair completed',
            'Maintenance request cancelled',
          ];
          activities.addAll(
            items.map(
              (item) => TenantActivity(
                title: titles[item.status.value],
                subtitle: item.title,
                timestamp: item.updatedAt ?? item.completedAt ?? item.createdAt,
                icon: Icons.build_outlined,
              ),
            ),
          );
        }),
      source('leases', () async {
        final items = await TenantLeasePaymentsApiService(
          apiClient,
        ).getMyLeases();
        const titles = [
          'Lease pending',
          'Lease activated',
          'Lease terminated',
          'Lease completed',
        ];
        final rows = items
            .map(
              (item) => TenantActivity(
                title: _statusTitle(item, titles, 'Lease updated'),
                subtitle:
                    'Lease term ${dashboardDate(_date(item, 'startDate'))} to ${dashboardDate(_date(item, 'endDate'))}',
                timestamp: _timestamp(item),
                icon: Icons.article_outlined,
              ),
            )
            .toList();
        leaseItems = items;
        activities.addAll(rows);
      }),
      source('payments', () async {
        final items = await TenantLeasePaymentsApiService(
          apiClient,
        ).getMyPayments();
        const titles = [
          'Payment pending',
          'Payment received',
          'Payment failed',
        ];
        activities.addAll(
          items
              .map(
                (item) => TenantActivity(
                  title: _statusTitle(item, titles, 'Payment updated'),
                  subtitle: item['amount'] is num
                      ? 'Rs. ${dashboardMoney((item['amount'] as num).toDouble())}'
                      : 'Amount unavailable',
                  timestamp: _timestamp(item, preferred: 'paidAt'),
                  icon: Icons.payments_outlined,
                ),
              )
              .toList(),
        );
      }),
    ]);
    final activeLeases = leaseItems
        .where((item) => item['status'] == 1)
        .toList();
    await Future.wait(
      activeLeases.map(
        (lease) => source('rent schedule', () async {
          final id = lease['id'];
          if (id is! String || id.isEmpty) throw const FormatException();
          final items = await TenantLeasePaymentsApiService(
            apiClient,
          ).getSchedule(id);
          final rows = items
              .map(
                (item) => TenantActivity(
                  title: switch (item['status']) {
                    0 => 'Rent scheduled',
                    1 => 'Rent schedule paid',
                    2 => 'Rent overdue',
                    _ => 'Rent schedule updated',
                  },
                  subtitle:
                      '${item['amount'] is num ? 'Rs. ${dashboardMoney((item['amount'] as num).toDouble())} · ' : ''}Due ${dashboardDate(_date(item, 'dueDate'))}',
                  timestamp: _timestamp(item),
                  icon: Icons.event_note_outlined,
                ),
              )
              .toList();
          schedules.addAll(items);
          activities.addAll(rows);
        }),
      ),
    );
    TenantJourney? journey;
    final activeApplications =
        applicationItems
            .where(
              (item) =>
                  item.status != RentalApplicationStatus.rejected &&
                  item.status != RentalApplicationStatus.withdrawn,
            )
            .toList()
          ..sort(
            (a, b) => (b.updatedAt ?? b.createdAt).compareTo(
              a.updatedAt ?? a.createdAt,
            ),
          );
    final upcoming =
        viewingItems
            .where(
              (item) =>
                  item.status == ViewingStatus.approved &&
                  item.requestedDateTime.isAfter(now),
            )
            .toList()
          ..sort((a, b) => a.requestedDateTime.compareTo(b.requestedDateTime));
    String? propertyId;
    if (activeApplications.isNotEmpty) {
      final item = activeApplications.first;
      propertyId = item.propertyId;
      journey = TenantJourney(
        status: 'In progress',
        title: switch (item.status) {
          RentalApplicationStatus.underReview =>
            'Your application is being reviewed',
          RentalApplicationStatus.draft => 'Your application is in draft',
          RentalApplicationStatus.submitted => 'Your application is submitted',
          RentalApplicationStatus.changesRequested =>
            'Your application needs changes',
          RentalApplicationStatus.approved => 'Your application is approved',
          _ => 'Rental application',
        },
        subtitle: '',
        helper: 'Move-in requested for ${dashboardDate(item.moveInDate)}',
        destination: RoleDestinationId.applications,
      );
    } else if (upcoming.isNotEmpty) {
      final item = upcoming.first;
      propertyId = item.propertyId;
      journey = TenantJourney(
        status: 'Upcoming',
        title: 'Viewing confirmed',
        subtitle: '',
        helper: dashboardDateTime(item.requestedDateTime),
        destination: RoleDestinationId.viewings,
      );
    } else if (activeLeases.isNotEmpty) {
      activeLeases.sort((a, b) => _timestamp(b).compareTo(_timestamp(a)));
      final item = activeLeases.first;
      propertyId = item['propertyId'] as String?;
      final outstanding =
          schedules
              .where((row) => row['status'] == 0 || row['status'] == 2)
              .toList()
            ..sort(
              (a, b) => _date(a, 'dueDate').compareTo(_date(b, 'dueDate')),
            );
      journey = TenantJourney(
        status: 'Active',
        title: 'Lease is active',
        subtitle: '',
        helper: outstanding.isNotEmpty
            ? 'Next rent due ${dashboardDate(_date(outstanding.first, 'dueDate'))}'
            : failed.contains('rent schedule')
            ? 'Rent schedule unavailable'
            : 'Lease ends ${dashboardDate(_date(item, 'endDate'))}',
      );
    }
    if (journey != null && propertyId != null && properties != null) {
      try {
        final property = await properties.getPropertyById(propertyId);
        journey = TenantJourney(
          status: journey.status,
          title: journey.title,
          subtitle: property.title,
          helper: journey.helper,
          destination: journey.destination,
        );
      } catch (_) {
        /* Property names are optional; never invent one. */
      }
    }
    activities.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return TenantDashboardSnapshot(
      activities: activities,
      journey: journey,
      failedSources: failed,
      successfulSources: successful,
    );
  }

  static Future<TenantRecommendations> recommendations(
    PropertyApiService service,
  ) async {
    if (!await service.hasSavedMatchPreferences()) {
      return const TenantRecommendations(configured: false);
    }
    final result = await service.getSavedPropertyMatches();
    final sorted = [...result.matches]
      ..sort((a, b) => (b.matchScore ?? -1).compareTo(a.matchScore ?? -1));
    final items = <TenantRecommendation>[];
    final seen = <String>{};
    var partial = false;
    for (final match in sorted) {
      if (match.propertyId.isEmpty || !seen.add(match.propertyId)) continue;
      try {
        final property = await service.getPropertyById(match.propertyId);
        if (property.id == match.propertyId && property.isAvailable) {
          items.add(TenantRecommendation(property, match));
        }
      } catch (_) {
        partial = true;
      }
      if (items.length == 3) break;
    }
    return TenantRecommendations(
      configured: true,
      items: items,
      partialFailure: partial,
      matches: result,
    );
  }
}

String applicationTitle(RentalApplicationStatus status) => switch (status) {
  RentalApplicationStatus.draft => 'Application draft created',
  RentalApplicationStatus.submitted => 'Application submitted',
  RentalApplicationStatus.underReview => 'Application under review',
  RentalApplicationStatus.changesRequested => 'Application changes requested',
  RentalApplicationStatus.approved => 'Application approved',
  RentalApplicationStatus.rejected => 'Application declined',
  RentalApplicationStatus.withdrawn => 'Application withdrawn',
};
String viewingTitle(ViewingStatus status) => switch (status) {
  ViewingStatus.pending => 'Viewing requested',
  ViewingStatus.approved => 'Viewing confirmed',
  ViewingStatus.rejected => 'Viewing declined',
  ViewingStatus.cancelled => 'Viewing cancelled',
  ViewingStatus.completed => 'Viewing completed',
};
IconData notificationIcon(String event) {
  if (event.startsWith('viewing.')) return Icons.calendar_month_outlined;
  if (event.startsWith('rental_application.')) {
    return Icons.description_outlined;
  }
  if (event.startsWith('lease.')) return Icons.article_outlined;
  if (event.startsWith('payment.')) return Icons.payments_outlined;
  if (event.startsWith('maintenance')) return Icons.build_outlined;
  return Icons.notifications_none_rounded;
}

DateTime _date(Map<String, dynamic> item, String key) =>
    DateTime.tryParse(item[key]?.toString() ?? '') ??
    (throw FormatException('Invalid $key.'));
DateTime _timestamp(Map<String, dynamic> item, {String? preferred}) {
  for (final key in [preferred, 'updatedAt', 'createdAt']) {
    final value = DateTime.tryParse(item[key]?.toString() ?? '');
    if (value != null) return value;
  }
  throw const FormatException('Missing activity timestamp.');
}

String _statusTitle(
  Map<String, dynamic> item,
  List<String> titles,
  String fallback,
) {
  final status = item['status'];
  return status is int && status >= 0 && status < titles.length
      ? titles[status]
      : fallback;
}

String dashboardDate(DateTime value) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[value.month - 1]} ${value.day}, ${value.year}';
}

String dashboardDateTime(DateTime value) {
  final local = value.toUtc().add(const Duration(hours: 5, minutes: 30));
  return '${dashboardDate(local)} · ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

String dashboardMoney(double value) => value
    .toStringAsFixed(value == value.roundToDouble() ? 0 : 2)
    .replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (match) => '${match[1]},',
    );
