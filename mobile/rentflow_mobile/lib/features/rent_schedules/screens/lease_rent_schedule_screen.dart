import 'package:flutter/material.dart';

import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/shared_widgets.dart';
import '../../payments/format_lkr.dart';
import '../../payments/screens/pay_rent_screen.dart';
import '../../payments/services/payment_api_service.dart';
import '../models/rent_schedule_item.dart';
import '../models/rent_schedule_outstanding_summary.dart';
import '../services/rent_schedule_api_service.dart';

class LeaseRentScheduleScreen extends StatefulWidget {
  const LeaseRentScheduleScreen({
    super.key,
    required this.rentScheduleApiService,
    required this.leaseAgreementId,
    this.paymentApiService,
  });

  final RentScheduleApiService rentScheduleApiService;
  final String leaseAgreementId;
  final PaymentApiService? paymentApiService;

  @override
  State<LeaseRentScheduleScreen> createState() =>
      _LeaseRentScheduleScreenState();
}

typedef _RentScheduleData = ({
  List<RentScheduleItem> items,
  RentScheduleOutstandingSummary summary,
});

class _LeaseRentScheduleScreenState extends State<LeaseRentScheduleScreen> {
  late Future<_RentScheduleData> _data;
  Future<_RentScheduleData>? _activeLoad;

  @override
  void initState() {
    super.initState();
    _data = _startLoad();
  }

  Future<_RentScheduleData> _loadBoth() async {
    final responses = await Future.wait<Object>([
      widget.rentScheduleApiService.getByLease(widget.leaseAgreementId),
      widget.rentScheduleApiService.getOutstandingByLease(
        widget.leaseAgreementId,
      ),
    ]);
    return (
      items: responses[0] as List<RentScheduleItem>,
      summary: responses[1] as RentScheduleOutstandingSummary,
    );
  }

  Future<_RentScheduleData> _startLoad() {
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
    final existing = _activeLoad;
    final request = existing ?? _startLoad();
    if (existing == null && mounted) {
      setState(() {
        _data = request;
      });
    }
    try {
      await request;
    } catch (_) {
      // FutureBuilder turns failures into a safe retry state.
    }
  }

  String _safeError(Object? error) {
    if (error is RentScheduleApiException) return error.message;
    return 'Unable to load this rent schedule. Please try again.';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppPalette.background,
    appBar: AppBar(title: const Text('Rent Schedule')),
    body: FutureBuilder<_RentScheduleData>(
      future: _data,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _scrollable([
            const LoadingState(title: 'Loading rent schedule'),
          ]);
        }
        if (snapshot.hasError) {
          return _scrollable([
            ErrorState(message: _safeError(snapshot.error), onRetry: _refresh),
          ]);
        }

        final data = snapshot.data!;
        return _scrollable([
          PageHeader(
            title: 'Rent Schedule',
            subtitle: 'Review rent due dates and outstanding amounts.',
            trailing: IconButton(
              tooltip: 'Refresh rent schedule',
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _OutstandingCard(summary: data.summary),
          const SizedBox(height: AppSpacing.lg),
          const SectionHeader(title: 'Schedule items'),
          const SizedBox(height: AppSpacing.md),
          if (data.items.isEmpty)
            const EmptyState(
              title: 'No rent schedule items',
              message: 'Schedule items for this lease will appear here.',
              compact: true,
            )
          else
            for (final item in data.items) ...[
              _RentScheduleItemCard(
                item: item,
                rentScheduleApiService: widget.rentScheduleApiService,
                paymentApiService: widget.paymentApiService,
              ),
              const SizedBox(height: AppSpacing.md),
            ],
        ]);
      },
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

class _OutstandingCard extends StatelessWidget {
  const _OutstandingCard({required this.summary});

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
        _SummaryFact(label: 'Pending', amount: summary.totalPending),
        _SummaryFact(label: 'Overdue', amount: summary.totalOverdue),
        _SummaryFact(
          label: 'Total outstanding',
          amount: summary.totalOutstanding,
          emphasize: true,
        ),
      ],
    ),
  );
}

class _SummaryFact extends StatelessWidget {
  const _SummaryFact({
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
        Expanded(
          child: Text(
            label,
            style: emphasize ? Theme.of(context).textTheme.titleMedium : null,
          ),
        ),
        Text(
          formatLkr(amount),
          key: ValueKey(
            'rent-summary-${label.toLowerCase().replaceAll(' ', '-')}',
          ),
          style: emphasize ? Theme.of(context).textTheme.titleMedium : null,
        ),
      ],
    ),
  );
}

class _RentScheduleItemCard extends StatelessWidget {
  const _RentScheduleItemCard({
    required this.item,
    required this.rentScheduleApiService,
    required this.paymentApiService,
  });

  final RentScheduleItem item;
  final RentScheduleApiService rentScheduleApiService;
  final PaymentApiService? paymentApiService;

  @override
  Widget build(BuildContext context) {
    final (label, tone) = switch (item.status) {
      RentScheduleStatus.pending => ('Pending', StatusTone.pending),
      RentScheduleStatus.paid => ('Paid', StatusTone.success),
      RentScheduleStatus.overdue => ('Overdue', StatusTone.danger),
    };

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(child: Text('Rent schedule item')),
              StatusChip(label: label, tone: tone),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _ItemFact(label: 'Due date', value: _date(item.dueDate)),
          _ItemFact(label: 'Amount', value: formatLkr(item.amount)),
          _ItemFact(label: 'Created', value: _dateTime(item.createdAt)),
          if (item.updatedAt case final updatedAt?)
            _ItemFact(label: 'Updated', value: _dateTime(updatedAt)),
          if (item.status != RentScheduleStatus.paid) ...[
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              key: ValueKey('rent-payment-placeholder-${item.id}'),
              onPressed: () => _openPayment(context),
              icon: const Icon(Icons.payments_outlined),
              label: const Text('Pay securely'),
            ),
          ],
        ],
      ),
    );
  }

  void _openPayment(BuildContext context) {
    final paymentService = paymentApiService;
    if (paymentService != null) {
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => PayRentScreen(
            rentScheduleApiService: rentScheduleApiService,
            paymentApiService: paymentService,
            initialRentScheduleItemId: item.id,
          ),
        ),
      );
      return;
    }
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Pay securely')),
          body: const ModuleUnavailableState(
            title: 'Pay securely',
            explanation:
                'Payment services are unavailable right now. Return to the lease and try again. No payment has been made.',
            owner: 'Payments',
          ),
        ),
      ),
    );
  }
}

class _ItemFact extends StatelessWidget {
  const _ItemFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        Expanded(child: Text(value)),
      ],
    ),
  );
}

String _date(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

String _dateTime(DateTime value) {
  final local = value.toLocal();
  return '${_date(local)} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}
