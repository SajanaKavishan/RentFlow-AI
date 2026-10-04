import 'package:flutter/material.dart';

import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/shared_widgets.dart';
import '../models/rental_offer.dart';
import '../services/rental_offer_api_service.dart';
import 'rental_offer_details_screen.dart';

class MyRentalOffersScreen extends StatefulWidget {
  const MyRentalOffersScreen({super.key, required this.rentalOfferApiService});

  final RentalOfferApiService rentalOfferApiService;

  @override
  State<MyRentalOffersScreen> createState() => _MyRentalOffersScreenState();
}

class _MyRentalOffersScreenState extends State<MyRentalOffersScreen> {
  late Future<List<RentalOffer>> _offers;

  @override
  void initState() {
    super.initState();
    _offers = widget.rentalOfferApiService.getMyOffers();
  }

  Future<void> _refresh() async {
    final request = widget.rentalOfferApiService.getMyOffers();
    if (!mounted) return;
    setState(() {
      _offers = request;
    });
    try {
      await request;
    } catch (_) {
      // FutureBuilder displays the service's safe error message.
    }
  }

  String _safeError(Object? error) {
    if (error is RentalOfferApiException) return error.message;
    return 'Unable to load your rental offers. Please try again.';
  }

  Future<void> _openDetails(RentalOffer offer) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => RentalOfferDetailsScreen(
          offerId: offer.id,
          rentalOfferApiService: widget.rentalOfferApiService,
        ),
      ),
    );
    if (mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppPalette.background,
    appBar: AppBar(title: const Text('Rental Offers')),
    body: FutureBuilder<List<RentalOffer>>(
      future: _offers,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const LoadingState(
            title: 'Loading rental offers',
            message: 'Getting your latest offers.',
          );
        }
        if (snapshot.hasError) {
          return ErrorState(
            message: _safeError(snapshot.error),
            onRetry: _refresh,
          );
        }

        final offers = snapshot.data ?? const <RentalOffer>[];
        return RefreshIndicator(
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
                        title: 'Your offers',
                        subtitle:
                            'Review the terms offered for your applications.',
                        trailing: IconButton(
                          tooltip: 'Refresh rental offers',
                          onPressed: _refresh,
                          icon: const Icon(Icons.refresh),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      if (offers.isEmpty)
                        const EmptyState(
                          title: 'No rental offers yet',
                          message: 'Offers from landlords will appear here.',
                          compact: true,
                        )
                      else
                        for (final offer in offers) ...[
                          _OfferCard(
                            offer: offer,
                            onTap: () => _openDetails(offer),
                          ),
                          const SizedBox(height: AppSpacing.md),
                        ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

class _OfferCard extends StatelessWidget {
  const _OfferCard({required this.offer, required this.onTap});

  final RentalOffer offer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AppCard(
    key: ValueKey('offer-card-${offer.id}'),
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
            _OfferStatusChip(status: offer.status),
            const SizedBox(width: AppSpacing.xs),
            const Icon(Icons.chevron_right_rounded, size: 18),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(offer.propertyId, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: AppSpacing.base),
        _Fact(
          label: 'Monthly rent',
          value: offer.monthlyRent.toStringAsFixed(2),
        ),
        _Fact(
          label: 'Security deposit',
          value: offer.securityDeposit.toStringAsFixed(2),
        ),
        _Fact(label: 'Proposed start', value: _date(offer.proposedStartDate)),
        _Fact(label: 'Proposed end', value: _date(offer.proposedEndDate)),
        _Fact(label: 'Expires', value: _localDateTime(offer.expiresAt)),
      ],
    ),
  );
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

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

class _OfferStatusChip extends StatelessWidget {
  const _OfferStatusChip({required this.status});

  final RentalOfferStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, tone) = switch (status) {
      RentalOfferStatus.pending => ('Pending', StatusTone.pending),
      RentalOfferStatus.accepted => ('Accepted', StatusTone.success),
      RentalOfferStatus.rejected => ('Rejected', StatusTone.danger),
      RentalOfferStatus.withdrawn => ('Withdrawn', StatusTone.neutral),
      RentalOfferStatus.expired => ('Expired', StatusTone.warning),
    };
    return StatusChip(label: label, tone: tone);
  }
}

String _date(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

String _localDateTime(DateTime value) {
  final local = value.toLocal();
  return '${_date(local)} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')} (local time)';
}
