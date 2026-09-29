import 'package:flutter/material.dart';

import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/shared_widgets.dart';
import '../../rental_offers/screens/my_rental_offers_screen.dart';
import '../../rental_offers/services/rental_offer_api_service.dart';
import '../models/lease_agreement.dart';
import '../services/lease_agreement_api_service.dart';
import 'lease_details_screen.dart';

class MyLeasesScreen extends StatefulWidget {
  const MyLeasesScreen({
    super.key,
    required this.leaseAgreementApiService,
    required this.rentalOfferApiService,
  });

  final LeaseAgreementApiService leaseAgreementApiService;
  final RentalOfferApiService rentalOfferApiService;

  @override
  State<MyLeasesScreen> createState() => _MyLeasesScreenState();
}

class _MyLeasesScreenState extends State<MyLeasesScreen> {
  late Future<List<LeaseAgreement>> _leases;

  @override
  void initState() {
    super.initState();
    _leases = widget.leaseAgreementApiService.getMyLeases();
  }

  Future<void> _refresh() async {
    final request = widget.leaseAgreementApiService.getMyLeases();
    if (!mounted) return;
    setState(() {
      _leases = request;
    });
    try {
      await request;
    } catch (_) {
      // FutureBuilder displays a safe message and retry control.
    }
  }

  String _safeError(Object? error) {
    if (error is LeaseAgreementApiException) return error.message;
    return 'Unable to load your leases. Please try again.';
  }

  Future<void> _openDetails(LeaseAgreement lease) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => LeaseDetailsScreen(
          leaseId: lease.id,
          leaseAgreementApiService: widget.leaseAgreementApiService,
        ),
      ),
    );
    if (mounted) await _refresh();
  }

  void _openOffers() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => MyRentalOffersScreen(
          rentalOfferApiService: widget.rentalOfferApiService,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppPalette.background,
    appBar: AppBar(title: const Text('My Lease')),
    body: RefreshIndicator(
      color: AppPalette.olive,
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: AppSpacing.page,
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PageHeader(
                    title: 'Your leases',
                    subtitle:
                        'View your current and previous lease agreements.',
                    trailing: IconButton(
                      tooltip: 'Refresh leases',
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppCard(
                    key: const ValueKey('rental-offers-entry'),
                    onTap: _openOffers,
                    child: Row(
                      children: [
                        const Icon(Icons.local_offer_outlined),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Rental Offers',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              const Text(
                                'Review offers for your applications.',
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  FutureBuilder<List<LeaseAgreement>>(
                    future: _leases,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const LoadingState(
                          title: 'Loading leases',
                          message: 'Getting your lease agreements.',
                        );
                      }
                      if (snapshot.hasError) {
                        return ErrorState(
                          message: _safeError(snapshot.error),
                          onRetry: _refresh,
                        );
                      }
                      final leases = snapshot.data ?? const <LeaseAgreement>[];
                      if (leases.isEmpty) {
                        return const EmptyState(
                          title: 'No leases yet',
                          message: 'Your lease agreements will appear here.',
                          compact: true,
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final lease in leases) ...[
                            _LeaseCard(
                              lease: lease,
                              onTap: () => _openDetails(lease),
                            ),
                            const SizedBox(height: AppSpacing.md),
                          ],
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _LeaseCard extends StatelessWidget {
  const _LeaseCard({required this.lease, required this.onTap});

  final LeaseAgreement lease;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AppCard(
    key: ValueKey('lease-card-${lease.id}'),
    onTap: onTap,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Property reference',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            _LeaseStatusChip(status: lease.status),
            const SizedBox(width: AppSpacing.xs),
            const Icon(Icons.chevron_right_rounded, size: 18),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(lease.propertyId),
        const SizedBox(height: AppSpacing.base),
        _LeaseFact(
          label: 'Monthly rent',
          value: lease.monthlyRent.toStringAsFixed(2),
        ),
        _LeaseFact(
          label: 'Security deposit',
          value: lease.securityDeposit.toStringAsFixed(2),
        ),
        _LeaseFact(label: 'Start date', value: _date(lease.startDate)),
        _LeaseFact(label: 'End date', value: _date(lease.endDate)),
      ],
    ),
  );
}

class _LeaseFact extends StatelessWidget {
  const _LeaseFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 130,
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        Expanded(child: Text(value)),
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
