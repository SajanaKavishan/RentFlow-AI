import 'package:flutter/material.dart';

import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/shared_widgets.dart';
import '../models/payment.dart';
import '../services/payment_api_service.dart';

typedef _PaymentLoadResult = ({Payment? payment, Object? error});

class PaymentDetailsScreen extends StatefulWidget {
  const PaymentDetailsScreen({
    super.key,
    required this.paymentApiService,
    required this.paymentId,
  });

  final PaymentApiService paymentApiService;
  final String paymentId;

  @override
  State<PaymentDetailsScreen> createState() => _PaymentDetailsScreenState();
}

class _PaymentDetailsScreenState extends State<PaymentDetailsScreen> {
  late Future<_PaymentLoadResult> _payment;

  @override
  void initState() {
    super.initState();
    _payment = _load();
  }

  Future<_PaymentLoadResult> _load() async {
    try {
      return (
        payment: await widget.paymentApiService.getPayment(widget.paymentId),
        error: null,
      );
    } catch (error) {
      return (payment: null, error: error);
    }
  }

  void _retry() {
    setState(() {
      _payment = _load();
    });
  }

  String _safeError(Object? error) {
    if (error is PaymentApiException) {
      return switch (error.statusCode) {
        401 => 'Your session has expired. Sign in again to view this payment.',
        403 => 'You do not have permission to view this payment.',
        404 => 'This payment was not found or is no longer available.',
        _ => 'Unable to load payment details. Please try again.',
      };
    }
    return 'Unable to load payment details. Please try again.';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Payment Details')),
    backgroundColor: AppPalette.background,
    body: FutureBuilder<_PaymentLoadResult>(
      future: _payment,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: LoadingState(title: 'Loading payment'));
        }
        final result = snapshot.data;
        if (snapshot.hasError || result?.error != null) {
          return ErrorState(
            message: _safeError(snapshot.error ?? result?.error),
            onRetry: _retry,
          );
        }
        return _details(result!.payment!);
      },
    ),
  );

  Widget _details(Payment payment) {
    final (status, tone, explanation) = _status(payment.status);
    return ListView(
      padding: AppSpacing.page,
      children: [
        const PageHeader(
          title: 'Payment Details',
          subtitle: 'Read-only information for this payment record.',
        ),
        const SizedBox(height: AppSpacing.lg),
        AppCard(
          key: const ValueKey('payment-details-card'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StatusChip(label: status, tone: tone),
              const SizedBox(height: AppSpacing.sm),
              Text(explanation),
              const Divider(height: AppSpacing.xl),
              _DetailFact(
                label: 'Amount',
                value: payment.amount.toStringAsFixed(2),
              ),
              _DetailFact(
                label: 'Payment method',
                value: payment.paymentMethod,
              ),
              if (payment.transactionReference case final reference?
                  when reference.trim().isNotEmpty)
                _DetailFact(label: 'Transaction reference', value: reference),
              _DetailFact(
                label: 'Rent schedule item ID',
                value: payment.rentScheduleItemId,
              ),
              _DetailFact(
                label: 'Created',
                value: _dateTime(payment.createdAt),
              ),
              if (payment.paidAt case final paidAt?)
                _DetailFact(label: 'Paid at', value: _dateTime(paidAt)),
              if (payment.updatedAt case final updatedAt?)
                _DetailFact(label: 'Updated', value: _dateTime(updatedAt)),
            ],
          ),
        ),
      ],
    );
  }
}

class _DetailFact extends StatelessWidget {
  const _DetailFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: AppSpacing.xs),
        SelectableText(value),
      ],
    ),
  );
}

(String, StatusTone, String) _status(PaymentStatus status) => switch (status) {
  PaymentStatus.pending => (
    'Pending',
    StatusTone.pending,
    'This payment record is awaiting later processing or review.',
  ),
  PaymentStatus.completed => (
    'Completed',
    StatusTone.success,
    'The backend has marked this payment record completed.',
  ),
  PaymentStatus.failed => (
    'Failed',
    StatusTone.danger,
    'This payment record failed. The associated rent schedule item may remain payable.',
  ),
};

String _dateTime(DateTime value) {
  final local = value.toLocal();
  final date =
      '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  return '$date ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}
