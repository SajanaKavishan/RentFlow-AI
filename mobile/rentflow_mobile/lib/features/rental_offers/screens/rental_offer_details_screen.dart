import 'dart:async';

import 'package:flutter/material.dart';

import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/shared_widgets.dart';
import '../models/rental_offer.dart';
import '../services/rental_offer_api_service.dart';

class RentalOfferDetailsScreen extends StatefulWidget {
  const RentalOfferDetailsScreen({
    super.key,
    required this.offerId,
    required this.rentalOfferApiService,
  });

  final String offerId;
  final RentalOfferApiService rentalOfferApiService;

  @override
  State<RentalOfferDetailsScreen> createState() =>
      _RentalOfferDetailsScreenState();
}

class _RentalOfferDetailsScreenState extends State<RentalOfferDetailsScreen> {
  late Future<RentalOffer> _offer;
  Timer? _expiryTimer;
  bool _acting = false;
  String? _actionError;

  @override
  void initState() {
    super.initState();
    _offer = _fetchOffer();
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    super.dispose();
  }

  Future<RentalOffer> _fetchOffer() async {
    final offer = await widget.rentalOfferApiService.getOffer(widget.offerId);
    if (mounted) _scheduleExpiry(offer);
    return offer;
  }

  void _scheduleExpiry(RentalOffer offer) {
    _expiryTimer?.cancel();
    if (offer.status != RentalOfferStatus.pending) return;
    final remaining = offer.expiresAt.toUtc().difference(
      DateTime.now().toUtc(),
    );
    if (remaining.isNegative || remaining == Duration.zero) return;
    _expiryTimer = Timer(remaining, () {
      if (mounted) setState(() {});
    });
  }

  Future<void> _refresh({bool clearActionError = true}) async {
    final request = _fetchOffer();
    if (!mounted) return;
    setState(() {
      _offer = request;
      if (clearActionError) _actionError = null;
    });
    try {
      await request;
    } catch (_) {
      // FutureBuilder displays the safe fetch error and retry control.
    }
  }

  String _safeError(Object? error) {
    if (error is RentalOfferApiException) return error.message;
    return 'Unable to load this rental offer. Please try again.';
  }

  bool _canRespond(RentalOffer offer) =>
      offer.status == RentalOfferStatus.pending &&
      DateTime.now().toUtc().isBefore(offer.expiresAt.toUtc());

  Future<void> _confirmResponse(
    RentalOffer offer, {
    required bool accept,
  }) async {
    if (_acting || !_canRespond(offer)) {
      if (mounted) setState(() {});
      return;
    }

    final verb = accept ? 'Accept' : 'Reject';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$verb this offer?'),
        content: Text(
          accept
              ? 'Confirm that you want to accept these rental terms.'
              : 'Confirm that you want to reject this rental offer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('$verb offer'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true || _acting) return;
    if (!_canRespond(offer)) {
      setState(() {});
      return;
    }

    setState(() {
      _acting = true;
      _actionError = null;
    });
    try {
      final updated = accept
          ? await widget.rentalOfferApiService.acceptOffer(widget.offerId)
          : await widget.rentalOfferApiService.rejectOffer(widget.offerId);
      if (!mounted) return;
      _scheduleExpiry(updated);
      setState(() {
        _offer = Future.value(updated);
        _acting = false;
      });
      AppSnackbars.show(
        context,
        message: accept ? 'Offer accepted.' : 'Offer rejected.',
        tone: SnackTone.success,
      );
    } on RentalOfferApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _acting = false;
        _actionError = error.message;
      });
      AppSnackbars.show(context, message: error.message, tone: SnackTone.error);
      if (error.statusCode == 409 || error.statusCode == 404) {
        await _refresh(clearActionError: false);
      }
    } catch (_) {
      if (!mounted) return;
      const message = 'Unable to update this offer. Please try again.';
      setState(() {
        _acting = false;
        _actionError = message;
      });
      AppSnackbars.show(context, message: message, tone: SnackTone.error);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppPalette.background,
    appBar: AppBar(title: const Text('Offer details')),
    body: FutureBuilder<RentalOffer>(
      future: _offer,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const LoadingState(title: 'Loading offer details');
        }
        if (snapshot.hasError) {
          return ErrorState(
            message: _safeError(snapshot.error),
            onRetry: _refresh,
          );
        }
        final offer = snapshot.data!;
        return AuthenticatedPage(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                title: 'Rental offer',
                subtitle: 'Review the offered terms.',
                trailing: IconButton(
                  tooltip: 'Refresh offer details',
                  onPressed: _acting ? null : _refresh,
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
                      child: _OfferStatusChip(status: offer.status),
                    ),
                    const SizedBox(height: AppSpacing.base),
                    _Fact(label: 'Property reference', value: offer.propertyId),
                    _Fact(
                      label: 'Application reference',
                      value: offer.rentalApplicationId,
                    ),
                    _Fact(
                      label: 'Monthly rent',
                      value: offer.monthlyRent.toStringAsFixed(2),
                    ),
                    _Fact(
                      label: 'Security deposit',
                      value: offer.securityDeposit.toStringAsFixed(2),
                    ),
                    _Fact(
                      label: 'Proposed start',
                      value: _date(offer.proposedStartDate),
                    ),
                    _Fact(
                      label: 'Proposed end',
                      value: _date(offer.proposedEndDate),
                    ),
                    _Fact(
                      label: 'Expires',
                      value: _localDateTime(offer.expiresAt),
                    ),
                    _Fact(
                      label: 'Created',
                      value: _localDateTime(offer.createdAt),
                    ),
                    if (offer.updatedAt case final updatedAt?)
                      _Fact(label: 'Updated', value: _localDateTime(updatedAt)),
                    if (offer.landlordNote case final note?) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'Landlord note',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(note),
                    ],
                  ],
                ),
              ),
              if (_actionError case final error?) ...[
                const SizedBox(height: AppSpacing.base),
                Text(
                  error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (_canRespond(offer)) ...[
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        key: const ValueKey('accept-offer-action'),
                        onPressed: _acting
                            ? null
                            : () => _confirmResponse(offer, accept: true),
                        child: const Text('Accept offer'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: OutlinedButton(
                        key: const ValueKey('reject-offer-action'),
                        onPressed: _acting
                            ? null
                            : () => _confirmResponse(offer, accept: false),
                        child: const Text('Reject offer'),
                      ),
                    ),
                  ],
                ),
              ],
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
        Text(value),
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
