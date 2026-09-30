import 'package:flutter/material.dart';

import '../../payments/services/payment_api_service.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/shared_widgets.dart';
import '../../rent_schedules/screens/lease_rent_schedule_screen.dart';
import '../../rent_schedules/services/rent_schedule_api_service.dart';
import '../models/lease_agreement.dart';
import '../services/lease_agreement_api_service.dart';

class LeaseDetailsScreen extends StatefulWidget {
  const LeaseDetailsScreen({
    super.key,
    required this.leaseId,
    required this.leaseAgreementApiService,
    this.rentScheduleApiService,
    this.paymentApiService,
  });

  final String leaseId;
  final LeaseAgreementApiService leaseAgreementApiService;
  final RentScheduleApiService? rentScheduleApiService;
  final PaymentApiService? paymentApiService;

  @override
  State<LeaseDetailsScreen> createState() => _LeaseDetailsScreenState();
}

class _LeaseDetailsScreenState extends State<LeaseDetailsScreen> {
  late Future<LeaseAgreement> _lease;

  @override
  void initState() {
    super.initState();
    _lease = widget.leaseAgreementApiService.getLease(widget.leaseId);
  }

  Future<void> _refresh() async {
    final request = widget.leaseAgreementApiService.getLease(widget.leaseId);
    if (!mounted) return;
    setState(() {
      _lease = request;
    });
    try {
      await request;
    } catch (_) {
      // FutureBuilder displays a safe message and retry control.
    }
  }

  String _safeError(Object? error) {
    if (error is LeaseAgreementApiException) return error.message;
    return 'Unable to load this lease. Please try again.';
  }

  void _openRentSchedule() {
    final rentScheduleService = widget.rentScheduleApiService;
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => rentScheduleService == null
            ? Scaffold(
                backgroundColor: AppPalette.background,
                appBar: AppBar(title: const Text('Rent Schedule')),
                body: const AuthenticatedPage(
                  child: AppCard(
                    child: IntegrationPendingState(
                      title: 'Rent Schedule',
                      message:
                          'Rent schedule details will appear here when this feature is integrated.',
                    ),
                  ),
                ),
              )
            : LeaseRentScheduleScreen(
                rentScheduleApiService: rentScheduleService,
                leaseAgreementId: widget.leaseId,
                paymentApiService: widget.paymentApiService,
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppPalette.background,
    appBar: AppBar(title: const Text('Lease details')),
    body: FutureBuilder<LeaseAgreement>(
      future: _lease,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const LoadingState(title: 'Loading lease details');
        }
        if (snapshot.hasError) {
          return ErrorState(
            message: _safeError(snapshot.error),
            onRetry: _refresh,
          );
        }
        final lease = snapshot.data!;
        return AuthenticatedPage(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                title: 'Lease agreement',
                subtitle: 'Review your read-only lease information.',
                trailing: IconButton(
                  tooltip: 'Refresh lease details',
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _LeaseStatusChip(status: lease.status),
                    ),
                    const SizedBox(height: AppSpacing.base),
                    _Fact(
                      label: 'Monthly rent',
                      value: lease.monthlyRent.toStringAsFixed(2),
                    ),
                    _Fact(
                      label: 'Security deposit',
                      value: lease.securityDeposit.toStringAsFixed(2),
                    ),
                    _Fact(label: 'Start date', value: _date(lease.startDate)),
                    _Fact(label: 'End date', value: _date(lease.endDate)),
                    _Fact(label: 'Property reference', value: lease.propertyId),
                    _Fact(
                      label: 'Rental offer reference',
                      value: lease.rentalOfferId,
                    ),
                    _Fact(label: 'Created', value: _timestamp(lease.createdAt)),
                    if (lease.updatedAt case final updatedAt?)
                      _Fact(label: 'Updated', value: _timestamp(updatedAt)),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton.icon(
                key: const ValueKey('rent-schedule-entry'),
                onPressed: _openRentSchedule,
                icon: const Icon(Icons.calendar_month_outlined),
                label: const Text('Rent Schedule'),
              ),
            ],
          ),
        );
      },
    ),
  );
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: AppSpacing.xs),
        SelectableText(value),
      ],
    ),
  );
}

class _LeaseStatusChip extends StatelessWidget {
  const _LeaseStatusChip({required this.status});

  final LeaseAgreementStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, tone) = switch (status) {
      LeaseAgreementStatus.pending => ('Pending', StatusTone.pending),
      LeaseAgreementStatus.active => ('Active', StatusTone.success),
      LeaseAgreementStatus.terminated => ('Terminated', StatusTone.danger),
      LeaseAgreementStatus.completed => ('Completed', StatusTone.neutral),
    };
    return StatusChip(label: label, tone: tone);
  }
}

String _date(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

String _timestamp(DateTime value) {
  final local = value.toLocal();
  return '${_date(local)} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')} (local time)';
}
