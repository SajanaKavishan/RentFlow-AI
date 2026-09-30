import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MaxLengthEnforcement;

import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/shared_widgets.dart';
import '../../rent_schedules/models/rent_schedule_item.dart';
import '../../rent_schedules/models/rent_schedule_outstanding_summary.dart';
import '../../rent_schedules/services/rent_schedule_api_service.dart';
import '../models/payment.dart';
import '../services/payment_api_service.dart';

class PayRentScreen extends StatefulWidget {
  const PayRentScreen({
    super.key,
    required this.rentScheduleApiService,
    required this.paymentApiService,
    this.initialRentScheduleItemId,
  });

  final RentScheduleApiService rentScheduleApiService;
  final PaymentApiService paymentApiService;
  final String? initialRentScheduleItemId;

  @override
  State<PayRentScreen> createState() => _PayRentScreenState();
}

typedef _PayRentData = ({
  RentScheduleOutstandingSummary outstanding,
  List<Payment> payments,
});

class _PayRentScreenState extends State<PayRentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _paymentMethodController = TextEditingController();
  final _referenceController = TextEditingController();
  late Future<_PayRentData> _data;
  Future<_PayRentData>? _activeLoad;
  String? _selectedItemId;
  bool _initialSelectionResolved = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _data = _startLoad();
  }

  @override
  void dispose() {
    _paymentMethodController.dispose();
    _referenceController.dispose();
    super.dispose();
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

  Future<void> _submit(_PayRentData data) async {
    if (_submitting) return;
    final item = _selectedItem(data.outstanding.items);
    if (item == null || !_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);
    try {
      await widget.paymentApiService.createPayment(
        rentScheduleItemId: item.id,
        paymentMethod: _paymentMethodController.text.trim(),
        transactionReference: _referenceController.text.trim(),
      );
      if (!mounted) return;
      AppSnackbars.show(
        context,
        message: 'Payment record submitted.',
        tone: SnackTone.success,
      );
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      final message = error is PaymentApiException
          ? error.message
          : 'Unable to submit this payment record. Please try again.';
      AppSnackbars.show(context, message: message, tone: SnackTone.error);
      if (error is PaymentApiException && error.statusCode == 409) {
        await _refresh();
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
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
            subtitle: 'Select an outstanding item and submit a payment record.',
            trailing: IconButton(
              tooltip: 'Refresh Pay Rent',
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _OutstandingSummaryCard(summary: data.outstanding),
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
              _PendingPaymentGuard(payment: pending)
            else
              _PaymentForm(
                formKey: _formKey,
                methodController: _paymentMethodController,
                referenceController: _referenceController,
                submitting: _submitting,
                onSubmit: () => _submit(data),
              ),
          ],
          const SizedBox(height: AppSpacing.xl),
          const SectionHeader(title: 'Payment history'),
          const SizedBox(height: AppSpacing.md),
          if (data.payments.isEmpty)
            const EmptyState(
              title: 'No payment records yet',
              message: 'Payment records you submit will appear here.',
              compact: true,
            )
          else
            for (final payment in data.payments) ...[
              _PaymentHistoryCard(payment: payment),
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
        Text('Amount: ${item.amount.toStringAsFixed(2)}'),
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
          amount.toStringAsFixed(2),
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
          Text('Amount: ${item.amount.toStringAsFixed(2)}'),
          Text('Lease reference: ${item.leaseAgreementId}'),
          if (pendingPayment != null) ...[
            const SizedBox(height: AppSpacing.sm),
            const StatusChip(
              label: 'Payment record already Pending',
              tone: StatusTone.warning,
            ),
          ],
        ],
      ),
    );
  }
}

class _PendingPaymentGuard extends StatelessWidget {
  const _PendingPaymentGuard({required this.payment});

  final Payment payment;

  @override
  Widget build(BuildContext context) => AppCard(
    key: ValueKey('pending-payment-guard-${payment.rentScheduleItemId}'),
    child: const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StatusChip(
          label: 'Payment record already Pending',
          tone: StatusTone.warning,
        ),
        SizedBox(height: AppSpacing.sm),
        Text(
          'Review the existing record in Payment history before submitting another.',
        ),
      ],
    ),
  );
}

class _PaymentForm extends StatelessWidget {
  const _PaymentForm({
    required this.formKey,
    required this.methodController,
    required this.referenceController,
    required this.submitting,
    required this.onSubmit,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController methodController;
  final TextEditingController referenceController;
  final bool submitting;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) => AppCard(
    child: Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Payment record',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            key: const ValueKey('payment-method-field'),
            controller: methodController,
            maxLength: 100,
            maxLengthEnforcement: MaxLengthEnforcement.none,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Payment method',
              hintText: 'For example, Bank transfer',
            ),
            validator: (value) {
              final method = value?.trim() ?? '';
              if (method.isEmpty) return 'Payment method is required.';
              if (method.length > 100) {
                return 'Payment method must be 100 characters or fewer.';
              }
              return null;
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            key: const ValueKey('transaction-reference-field'),
            controller: referenceController,
            maxLength: 200,
            maxLengthEnforcement: MaxLengthEnforcement.none,
            decoration: const InputDecoration(
              labelText: 'Transaction reference (optional)',
            ),
            validator: (value) {
              if ((value?.trim().length ?? 0) > 200) {
                return 'Transaction reference must be 200 characters or fewer.';
              }
              return null;
            },
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton.icon(
            key: const ValueKey('submit-payment'),
            onPressed: submitting ? null : onSubmit,
            icon: submitting
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.receipt_long_outlined),
            label: Text(submitting ? 'Submitting…' : 'Record payment'),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'This submits a payment record for review. It does not process a payment.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
  );
}

class _PaymentHistoryCard extends StatelessWidget {
  const _PaymentHistoryCard({required this.payment});

  final Payment payment;

  @override
  Widget build(BuildContext context) {
    final (status, tone) = _paymentStatus(payment.status);
    return AppCard(
      key: ValueKey('payment-history-card-${payment.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(payment.amount.toStringAsFixed(2))),
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
