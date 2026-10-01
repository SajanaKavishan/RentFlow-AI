import 'package:flutter/material.dart';

import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/shared_widgets.dart';
import '../format_lkr.dart';
import 'payment_details_screen.dart';
import '../../rent_schedules/models/rent_schedule_item.dart';
import '../../rent_schedules/models/rent_schedule_outstanding_summary.dart';
import '../../rent_schedules/services/rent_schedule_api_service.dart';
import '../models/payment.dart';
import '../services/payment_api_service.dart';
import '../services/stripe_payment_sheet_service.dart';

class PayRentScreen extends StatefulWidget {
  const PayRentScreen({
    super.key,
    required this.rentScheduleApiService,
    required this.paymentApiService,
    this.initialRentScheduleItemId,
    this.stripePaymentSheetService = const NativeStripePaymentSheetService(),
  });

  final RentScheduleApiService rentScheduleApiService;
  final PaymentApiService paymentApiService;
  final String? initialRentScheduleItemId;
  final StripePaymentSheetService stripePaymentSheetService;

  @override
  State<PayRentScreen> createState() => _PayRentScreenState();
}

typedef _PayRentData = ({
  RentScheduleOutstandingSummary outstanding,
  List<Payment> payments,
});

class _PayRentScreenState extends State<PayRentScreen> {
  late Future<_PayRentData> _data;
  Future<_PayRentData>? _activeLoad;
  String? _selectedItemId;
  bool _initialSelectionResolved = false;
  bool _submitting = false;
  String? _flowMessage;

  @override
  void initState() {
    super.initState();
    _data = _startLoad();
  }

  Future<_PayRentData> _loadBoth() async {
    final results = await Future.wait<Object>([
      widget.rentScheduleApiService.getMyOutstanding(),
      widget.paymentApiService.getMyPayments(),
    ]);
    final outstanding = results[0] as RentScheduleOutstandingSummary;
    final payments = results[1] as List<Payment>;
    final itemIds = outstanding.items.map((item) => item.id).toSet();

    if (!_initialSelectionResolved) {
      final initialId = widget.initialRentScheduleItemId;
      _selectedItemId = initialId != null && itemIds.contains(initialId)
          ? initialId
          : null;
      _initialSelectionResolved = true;
    } else if (_selectedItemId != null && !itemIds.contains(_selectedItemId)) {
      _selectedItemId = null;
    }

    return (outstanding: outstanding, payments: payments);
  }

  Future<_PayRentData> _startLoad() {
    final request = _loadBoth();
    _activeLoad = request;
    request.then<void>(
      (_) {
        if (identical(_activeLoad, request)) _activeLoad = null;
      },
      onError: (_, _) {
        if (identical(_activeLoad, request)) _activeLoad = null;
      },
    );
    return request;
  }

  Future<void> _refresh() async {
    final active = _activeLoad;
    final request = active ?? _startLoad();
    if (active == null && mounted) {
      setState(() {
        _data = request;
      });
    }
    try {
      await request;
    } catch (_) {
      // FutureBuilder displays a safe retry state.
    }
  }

  Future<void> _pay(_PayRentData data) async {
    if (_submitting) return;
    final item = _selectedItem(data.outstanding.items);
    if (item == null) return;

    setState(() {
      _submitting = true;
      _flowMessage = 'Preparing secure payment…';
    });
    var sheetReturned = false;
    try {
      final intent = await widget.paymentApiService.createStripeIntent(item.id);
      if ((intent.amount - item.amount).abs() > 0.005) {
        throw const PaymentApiException(
          'The payment amount changed. Refresh and try again.',
        );
      }
      final clientSecret = intent.clientSecret;
      if (intent.paymentStatus != PaymentStatus.completed &&
          clientSecret != null &&
          clientSecret.isNotEmpty) {
        await widget.stripePaymentSheetService.initialize(
          publishableKey: intent.publishableKey,
          clientSecret: clientSecret,
        );
        await widget.stripePaymentSheetService.present();
        sheetReturned = true;
      }
      if (!mounted) return;
      setState(() => _flowMessage = 'Confirming payment…');
      await _reconcile(intent.paymentId);
    } on StripePaymentSheetCanceledException {
      if (!mounted) return;
      setState(
        () => _flowMessage =
            'Payment canceled. You can resume this payment later.',
      );
      await _refresh();
    } on StripePaymentSheetException {
      if (!mounted) return;
      setState(
        () => _flowMessage =
            'Payment could not be completed. You can retry safely.',
      );
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      final message = error is PaymentApiException
          ? sheetReturned
                ? 'Unable to confirm payment yet. Check its status before retrying.'
                : error.message
          : 'Unable to start payment. Please try again.';
      setState(() => _flowMessage = message);
      if (error is PaymentApiException && error.statusCode == 409) {
        await _refresh();
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _reconcile(String paymentId) async {
    final status = await widget.paymentApiService.getStripeStatus(paymentId);
    await _refresh();
    if (!mounted) return;
    setState(() {
      _flowMessage = switch (status.paymentStatus) {
        PaymentStatus.completed => 'Payment completed successfully.',
        PaymentStatus.pending =>
          'Payment is processing. Check payment status shortly.',
        PaymentStatus.failed =>
          'This payment attempt ended. Refresh to try again.',
      };
    });
  }

  Future<void> _checkPending(Payment payment) async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _flowMessage = 'Checking payment status…';
    });
    try {
      await _reconcile(payment.id);
    } catch (_) {
      if (mounted) {
        setState(
          () => _flowMessage =
              'Unable to check payment status. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _openPaymentDetails(Payment payment) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => PaymentDetailsScreen(
          paymentApiService: widget.paymentApiService,
          paymentId: payment.id,
        ),
      ),
    );
    if (mounted) await _refresh();
  }

  RentScheduleItem? _selectedItem(List<RentScheduleItem> items) {
    for (final item in items) {
      if (item.id == _selectedItemId) return item;
    }
    return null;
  }

  String _safeError(Object? error) {
    if (error is RentScheduleApiException || error is PaymentApiException) {
      return error.toString();
    }
    return 'Unable to load Pay Rent. Please try again.';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppPalette.background,
    appBar: AppBar(title: const Text('Pay Rent')),
    body: FutureBuilder<_PayRentData>(
      future: _data,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _scrollable([const LoadingState(title: 'Loading Pay Rent')]);
        }
        if (snapshot.hasError) {
          return _scrollable([
            ErrorState(message: _safeError(snapshot.error), onRetry: _refresh),
          ]);
        }

        final data = snapshot.data!;
        final selected = _selectedItem(data.outstanding.items);
        return _scrollable([
          PageHeader(
            title: 'Pay Rent',
            subtitle: 'Select an outstanding item and pay securely.',
            trailing: IconButton(
              tooltip: 'Refresh Pay Rent',
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _OutstandingSummaryCard(summary: data.outstanding),
          if (_flowMessage case final message?) ...[
            const SizedBox(height: AppSpacing.md),
            AppCard(
              child: Text(message, key: const ValueKey('payment-flow-message')),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          const SectionHeader(title: 'Outstanding rent items'),
          const SizedBox(height: AppSpacing.md),
          if (data.outstanding.items.isEmpty)
            const EmptyState(
              title: 'No outstanding rent payments.',
              message: 'Any outstanding rent items will appear here.',
              compact: true,
            )
          else
            for (final item in data.outstanding.items) ...[
              _OutstandingItemCard(
                item: item,
                selected: item.id == _selectedItemId,
                pendingPayment: _pendingPaymentFor(item, data.payments),
                onSelect: () => setState(() => _selectedItemId = item.id),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
          if (selected != null) ...[
            const SizedBox(height: AppSpacing.md),
            _selectedItemDetails(selected),
            const SizedBox(height: AppSpacing.md),
            if (_pendingPaymentFor(selected, data.payments) case final pending?)
              _PendingPaymentGuard(
                payment: pending,
                busy: _submitting,
                onResume: () => _pay(data),
                onCheck: () => _checkPending(pending),
              )
            else
              _StripePaymentAction(busy: _submitting, onPay: () => _pay(data)),
          ],
          const SizedBox(height: AppSpacing.xl),
          const SectionHeader(title: 'Payment history'),
          const SizedBox(height: AppSpacing.md),
          if (data.payments.isEmpty)
            const EmptyState(
              title: 'No payment records yet',
              message: 'Your payments will appear here.',
              compact: true,
            )
          else
            for (final payment in data.payments) ...[
              _PaymentHistoryCard(
                payment: payment,
                onTap: () => _openPaymentDetails(payment),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
        ]);
      },
    ),
  );

  Widget _selectedItemDetails(RentScheduleItem item) => AppCard(
    key: const ValueKey('selected-payment-item'),
    color: AppPalette.sage,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Selected item', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        Text('Amount: ${formatLkr(item.amount)}'),
        Text('Due date: ${_date(item.dueDate)}'),
        Text('Status: ${_scheduleStatus(item.status).$1}'),
      ],
    ),
  );

  Widget _scrollable(List<Widget> children) => RefreshIndicator(
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
              children: children,
            ),
          ),
        ),
      ],
    ),
  );
}

Payment? _pendingPaymentFor(RentScheduleItem item, List<Payment> payments) {
  for (final payment in payments) {
    if (payment.rentScheduleItemId == item.id &&
        payment.status == PaymentStatus.pending) {
      return payment;
    }
  }
  return null;
}

class _OutstandingSummaryCard extends StatelessWidget {
  const _OutstandingSummaryCard({required this.summary});

  final RentScheduleOutstandingSummary summary;

  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Outstanding summary',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.md),
        _AmountFact(label: 'Total pending', amount: summary.totalPending),
        _AmountFact(label: 'Total overdue', amount: summary.totalOverdue),
        _AmountFact(
          label: 'Total outstanding',
          amount: summary.totalOutstanding,
          emphasize: true,
        ),
      ],
    ),
  );
}

class _AmountFact extends StatelessWidget {
  const _AmountFact({
    required this.label,
    required this.amount,
    this.emphasize = false,
  });

  final String label;
  final double amount;
  final bool emphasize;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(
          formatLkr(amount),
          key: ValueKey('pay-rent-${label.toLowerCase().replaceAll(' ', '-')}'),
          style: emphasize ? Theme.of(context).textTheme.titleMedium : null,
        ),
      ],
    ),
  );
}

class _OutstandingItemCard extends StatelessWidget {
  const _OutstandingItemCard({
    required this.item,
    required this.selected,
    required this.pendingPayment,
    required this.onSelect,
  });

  final RentScheduleItem item;
  final bool selected;
  final Payment? pendingPayment;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final (status, tone) = _scheduleStatus(item.status);
    return AppCard(
      key: ValueKey('outstanding-item-card-${item.id}'),
      color: selected ? AppPalette.softCream : null,
      onTap: onSelect,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('Due ${_date(item.dueDate)}')),
              StatusChip(label: status, tone: tone),
              RadioGroup<String>(
                groupValue: selected ? item.id : null,
                onChanged: (_) => onSelect(),
                child: Radio<String>(
                  key: ValueKey('select-outstanding-item-${item.id}'),
                  value: item.id,
                ),
              ),
            ],
          ),
          Text('Amount: ${formatLkr(item.amount)}'),
          Text('Lease reference: ${item.leaseAgreementId}'),
          if (pendingPayment != null) ...[
            const SizedBox(height: AppSpacing.sm),
            StatusChip(
              label: pendingPayment!.paymentMethod == 'Stripe'
                  ? 'Payment in progress'
                  : 'Manual payment pending',
              tone: StatusTone.warning,
            ),
          ],
        ],
      ),
    );
  }
}

class _PendingPaymentGuard extends StatelessWidget {
  const _PendingPaymentGuard({
    required this.payment,
    required this.busy,
    required this.onResume,
    required this.onCheck,
  });

  final Payment payment;
  final bool busy;
  final VoidCallback onResume;
  final VoidCallback onCheck;

  @override
  Widget build(BuildContext context) => AppCard(
    key: ValueKey('pending-payment-guard-${payment.rentScheduleItemId}'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StatusChip(
          label: payment.paymentMethod == 'Stripe'
              ? 'Payment in progress'
              : 'Manual payment pending',
          tone: StatusTone.warning,
        ),
        const SizedBox(height: AppSpacing.sm),
        if (payment.paymentMethod == 'Stripe') ...[
          const Text('Resume this payment or check its latest status.'),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              FilledButton(
                key: const ValueKey('resume-stripe-payment'),
                onPressed: busy ? null : onResume,
                child: const Text('Resume payment'),
              ),
              OutlinedButton(
                key: const ValueKey('check-stripe-status'),
                onPressed: busy ? null : onCheck,
                child: const Text('Check payment status'),
              ),
            ],
          ),
        ] else
          const Text(
            'Resolve the existing manual payment before starting a Stripe payment.',
          ),
      ],
    ),
  );
}

class _StripePaymentAction extends StatelessWidget {
  const _StripePaymentAction({required this.busy, required this.onPay});

  final bool busy;
  final VoidCallback onPay;

  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Secure payment', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.md),
        FilledButton.icon(
          key: const ValueKey('pay-securely'),
          onPressed: busy ? null : onPay,
          icon: busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.lock_outline),
          label: Text(busy ? 'Please wait…' : 'Pay securely'),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Payment details are entered securely in Stripe PaymentSheet.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );
}

class _PaymentHistoryCard extends StatelessWidget {
  const _PaymentHistoryCard({required this.payment, required this.onTap});

  final Payment payment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (status, tone) = _paymentStatus(payment.status);
    return AppCard(
      key: ValueKey('payment-history-card-${payment.id}'),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(formatLkr(payment.amount))),
              StatusChip(label: status, tone: tone),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text('Payment method: ${payment.paymentMethod}'),
          if (payment.transactionReference case final reference?
              when reference.trim().isNotEmpty)
            Text('Transaction reference: $reference'),
          Text('Created: ${_dateTime(payment.createdAt)}'),
          if (payment.paidAt case final paidAt?)
            Text('Paid at: ${_dateTime(paidAt)}'),
        ],
      ),
    );
  }
}

(String, StatusTone) _scheduleStatus(RentScheduleStatus status) =>
    switch (status) {
      RentScheduleStatus.pending => ('Pending', StatusTone.pending),
      RentScheduleStatus.overdue => ('Overdue', StatusTone.danger),
      RentScheduleStatus.paid => ('Paid', StatusTone.success),
    };

(String, StatusTone) _paymentStatus(PaymentStatus status) => switch (status) {
  PaymentStatus.pending => ('Pending', StatusTone.pending),
  PaymentStatus.completed => ('Completed', StatusTone.success),
  PaymentStatus.failed => ('Failed', StatusTone.danger),
};

String _date(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

String _dateTime(DateTime value) {
  final local = value.toLocal();
  return '${_date(local)} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}
