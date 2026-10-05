import 'package:flutter/material.dart';

import '../../../shared/home/tenant_dashboard_data.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/shared_widgets.dart';
import '../../properties/services/property_api_service.dart';
import '../services/tenant_lease_payments_api_service.dart';

enum TenantAccountSection { lease, rent }

class TenantLeasePaymentsScreen extends StatefulWidget {
  const TenantLeasePaymentsScreen({
    super.key,
    required this.section,
    this.apiService,
    this.propertyApiService,
  });
  final TenantAccountSection section;
  final TenantLeasePaymentsApiService? apiService;
  final PropertyApiService? propertyApiService;
  @override
  State<TenantLeasePaymentsScreen> createState() =>
      _TenantLeasePaymentsScreenState();
}

class _TenantLeasePaymentsScreenState extends State<TenantLeasePaymentsScreen> {
  Future<_LeaseData>? _leases;
  Future<_ScheduleData>? _schedule;
  Future<List<Map<String, dynamic>>>? _payments;
  bool get _isRent => widget.section == TenantAccountSection.rent;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    if (widget.apiService == null) return;
    _leases = _loadLeases();
    if (_isRent) {
      _schedule = _loadSchedule(_leases!);
      _payments = widget.apiService!.getMyPayments();
    }
  }

  Future<_LeaseData> _loadLeases() async {
    final leases = await widget.apiService!.getMyLeases();
    leases.sort(
      (a, b) => (a['status'] == 1 ? 0 : 1).compareTo(b['status'] == 1 ? 0 : 1),
    );
    final names = <String, String>{};
    final service = widget.propertyApiService;
    if (service != null) {
      await Future.wait(
        leases.map((lease) async {
          final id = lease['propertyId'];
          if (id is! String || id.isEmpty) return;
          try {
            final property = await service.getPropertyById(id);
            if (property.id == id) names[id] = property.title;
          } catch (_) {
            /* Property names are optional. */
          }
        }),
      );
    }
    return _LeaseData(leases, names);
  }

  Future<_ScheduleData> _loadSchedule(Future<_LeaseData> request) async {
    final leases = await request;
    final rows = <_RentItem>[];
    var failed = 0;
    await Future.wait(
      leases.items.map((lease) async {
        final id = lease['id'];
        if (id is! String || id.isEmpty) {
          failed++;
          return;
        }
        try {
          final items = await widget.apiService!.getSchedule(id);
          rows.addAll(
            items.map((item) => _RentItem(item, leases.propertyName(lease))),
          );
        } catch (_) {
          failed++;
        }
      }),
    );
    rows.sort(
      (a, b) =>
          (DateTime.tryParse(a.item['dueDate']?.toString() ?? '') ??
                  DateTime(9999))
              .compareTo(
                DateTime.tryParse(b.item['dueDate']?.toString() ?? '') ??
                    DateTime(9999),
              ),
    );
    return _ScheduleData(rows, failed);
  }

  Future<void> _refresh() async {
    setState(_load);
    await Future.wait([
      if (_leases != null) _leases!.then<void>((_) {}, onError: (_) {}),
      if (_schedule != null) _schedule!.then<void>((_) {}, onError: (_) {}),
      if (_payments != null) _payments!.then<void>((_) {}, onError: (_) {}),
    ]);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_isRent ? 'Pay Rent' : 'My Lease')),
    body: RefreshIndicator(
      onRefresh: _refresh,
      child: AuthenticatedPage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: _isRent ? 'Rent & payments' : 'Your lease',
              subtitle: _isRent
                  ? 'Review rent due and submit your payment details.'
                  : 'Your rental terms and lease information.',
            ),
            const SizedBox(height: 24),
            if (widget.apiService == null)
              const _AccountMessage(
                'Account information unavailable',
                'Please try again when your account is connected.',
              )
            else if (_isRent)
              _rentContent()
            else
              FutureBuilder<_LeaseData>(
                future: _leases,
                builder: (context, result) {
                  if (result.connectionState != ConnectionState.done) {
                    return const _AccountMessage(
                      'Loading your leases',
                      'Checking your account.',
                      loading: true,
                    );
                  }
                  if (result.hasError) {
                    return _AccountMessage(
                      'Could not load your leases',
                      'Please try again.',
                      onRetry: _refresh,
                    );
                  }
                  final data = result.data!;
                  if (data.items.isEmpty) {
                    return const _AccountMessage(
                      'No leases yet',
                      'Your lease will appear here when your landlord creates it.',
                    );
                  }
                  return Column(
                    children: [
                      for (final lease in data.items)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: AppCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  data.propertyName(lease),
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 12),
                                _Fact(
                                  'Status',
                                  _status(lease['status'], [
                                    'Pending',
                                    'Active',
                                    'Terminated',
                                    'Completed',
                                  ]),
                                ),
                                _Fact(
                                  'Monthly rent',
                                  _money(lease['monthlyRent']),
                                ),
                                _Fact(
                                  'Security deposit',
                                  _money(lease['securityDeposit']),
                                ),
                                _Fact('Start date', _date(lease['startDate'])),
                                _Fact('End date', _date(lease['endDate'])),
                              ],
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    ),
  );
  Widget _rentContent() => FutureBuilder<List<Map<String, dynamic>>>(
    future: _payments,
    builder: (context, payments) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Rent schedule', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        FutureBuilder<_ScheduleData>(
          future: _schedule,
          builder: (context, result) {
            if (result.connectionState != ConnectionState.done) {
              return const _AccountMessage(
                'Loading rent schedule',
                'Checking your rent due.',
                loading: true,
              );
            }
            if (result.hasError) {
              return _AccountMessage(
                'Could not load rent schedule',
                'Please try again.',
                onRetry: _refresh,
              );
            }
            final data = result.data!;
            if (data.items.isEmpty) {
              return _AccountMessage(
                data.failed > 0
                    ? 'Rent schedule unavailable'
                    : 'No rent scheduled',
                data.failed > 0
                    ? 'We could not load your rent schedule.'
                    : 'Rent will appear here once your landlord adds a schedule.',
                onRetry: data.failed > 0 ? _refresh : null,
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (data.failed > 0)
                  _AccountMessage(
                    'Some rent schedules could not be loaded',
                    'The available schedules are shown below.',
                    onRetry: _refresh,
                  ),
                for (final row in data.items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            row.propertyName,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          _Fact('Due date', _date(row.item['dueDate'])),
                          _Fact('Amount', _money(row.item['amount'])),
                          _Fact(
                            'Status',
                            _status(row.item['status'], [
                              'Pending',
                              'Paid',
                              'Overdue',
                            ]),
                          ),
                          if (row.item['status'] == 0 ||
                              row.item['status'] == 2) ...[
                            const SizedBox(height: 8),
                            if (payments.data?.any(
                                  (payment) =>
                                      payment['rentScheduleItemId'] ==
                                          row.item['id'] &&
                                      payment['status'] == 0,
                                ) ==
                                true)
                              const Text(
                                'Payment submitted · Awaiting landlord confirmation',
                              )
                            else
                              FilledButton(
                                onPressed:
                                    payments.hasData &&
                                        row.item['id'] is String &&
                                        row.item['amount'] is num
                                    ? () => _openPayment(row)
                                    : null,
                                child: const Text('Submit payment details'),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 24),
        Text('Payment history', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        if (payments.connectionState != ConnectionState.done)
          const _AccountMessage(
            'Loading payments',
            'Checking your payment history.',
            loading: true,
          )
        else if (payments.hasError)
          _AccountMessage(
            'Could not load payments',
            'Please retry to view or submit payment details.',
            onRetry: _refresh,
          )
        else if (payments.data!.isEmpty)
          const _AccountMessage(
            'No payments yet',
            'Submitted payment details will appear here.',
          )
        else
          ...payments.data!.map(
            (payment) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Fact('Amount', _money(payment['amount'])),
                    _Fact(
                      'Status',
                      _status(payment['status'], [
                        'Pending',
                        'Completed',
                        'Failed',
                      ]),
                    ),
                    _Fact('Payment method', _text(payment['paymentMethod'])),
                    if (payment['transactionReference'] != null)
                      _Fact(
                        'Reference',
                        _text(payment['transactionReference']),
                      ),
                    _Fact(
                      payment['paidAt'] != null ? 'Paid on' : 'Submitted on',
                      _date(payment['paidAt'] ?? payment['createdAt']),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    ),
  );
  Future<void> _openPayment(_RentItem row) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _PaymentForm(row: row, service: widget.apiService!),
    );
    if (saved == true && mounted) {
      AppSnackbars.show(
        context,
        message: 'Payment details submitted. Awaiting landlord confirmation.',
      );
      await _refresh();
    }
  }
}

class _PaymentForm extends StatefulWidget {
  const _PaymentForm({required this.row, required this.service});
  final _RentItem row;
  final TenantLeasePaymentsApiService service;
  @override
  State<_PaymentForm> createState() => _PaymentFormState();
}

class _PaymentFormState extends State<_PaymentForm> {
  final _form = GlobalKey<FormState>();
  final _method = TextEditingController();
  final _reference = TextEditingController();
  bool _submitting = false;
  String? _error;
  @override
  void dispose() {
    _method.dispose();
    _reference.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || !_form.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.service.createPayment(
        scheduleItemId: widget.row.item['id'] as String,
        paymentMethod: _method.text,
        transactionReference: _reference.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is TenantLeasePaymentsApiException
              ? error.message
              : 'Unable to submit payment details. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_submitting,
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Submit payment details',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text(widget.row.propertyName),
            _Fact('Amount', _money(widget.row.item['amount'])),
            _Fact('Due date', _date(widget.row.item['dueDate'])),
            const SizedBox(height: 12),
            const Text(
              'This submits a payment record for your landlord to confirm. Funds are not transferred in this app.',
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _method,
              enabled: !_submitting,
              maxLength: 100,
              decoration: const InputDecoration(
                labelText: 'Payment method',
                hintText: 'e.g. Bank transfer',
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Enter a payment method.'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _reference,
              enabled: !_submitting,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: 'Transaction reference (optional)',
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  _error!,
                  style: const TextStyle(color: AppPalette.danger),
                ),
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: Text(
                _submitting ? 'Submitting…' : 'Submit for confirmation',
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _LeaseData {
  const _LeaseData(this.items, this.names);
  final List<Map<String, dynamic>> items;
  final Map<String, String> names;
  String propertyName(Map<String, dynamic> lease) =>
      names[lease['propertyId']] ?? 'Rental property';
}

class _RentItem {
  const _RentItem(this.item, this.propertyName);
  final Map<String, dynamic> item;
  final String propertyName;
}

class _ScheduleData {
  const _ScheduleData(this.items, this.failed);
  final List<_RentItem> items;
  final int failed;
}

class _AccountMessage extends StatelessWidget {
  const _AccountMessage(
    this.title,
    this.message, {
    this.onRetry,
    this.loading = false,
  });
  final String title, message;
  final VoidCallback? onRetry;
  final bool loading;
  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(message),
        if (loading) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
        ],
        if (onRetry != null)
          TextButton(onPressed: onRetry, child: const Text('Try again')),
      ],
    ),
  );
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        Text(value, style: Theme.of(context).textTheme.bodyLarge),
      ],
    ),
  );
}

String _text(Object? value) =>
    value is String && value.trim().isNotEmpty ? value : 'Unavailable';
String _money(Object? value) => value is num
    ? 'Rs. ${dashboardMoney(value.toDouble())}'
    : 'Amount unavailable';
String _date(Object? value) {
  final date = DateTime.tryParse(value?.toString() ?? '');
  return date == null ? 'Date unavailable' : dashboardDate(date);
}

String _status(Object? value, List<String> labels) =>
    value is int && value >= 0 && value < labels.length
    ? labels[value]
    : 'Status unavailable';
