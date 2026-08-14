import 'package:flutter/material.dart';

import '../../../core/network/api_client.dart';
import '../models/rental_application.dart';
import '../services/rental_application_api_service.dart';
import '../widgets/rental_application_status_chip.dart';

class MyRentalApplicationsScreen extends StatefulWidget {
  const MyRentalApplicationsScreen({
    super.key,
    required this.tenantId,
    this.rentalApplicationApiService,
  });

  final String tenantId;
  final RentalApplicationApiService? rentalApplicationApiService;

  @override
  State<MyRentalApplicationsScreen> createState() =>
      _MyRentalApplicationsScreenState();
}

class _MyRentalApplicationsScreenState
    extends State<MyRentalApplicationsScreen> {
  static const _olive = Color(0xFF5D6842);
  static const _warmBackground = Color(0xFFF7F5EF);

  ApiClient? _ownedApiClient;
  late final RentalApplicationApiService _apiService;
  late Future<List<RentalApplication>> _applications;
  final Set<String> _withdrawingIds = {};

  @override
  void initState() {
    super.initState();
    if (widget.rentalApplicationApiService case final service?) {
      _apiService = service;
    } else {
      _ownedApiClient = ApiClient();
      _apiService = RentalApplicationApiService(_ownedApiClient!);
    }
    _applications = _apiService.getApplicationsByTenant(widget.tenantId);
  }

  @override
  void dispose() {
    _ownedApiClient?.close();
    super.dispose();
  }

  Future<void> _refresh() async {
    final request = _apiService.getApplicationsByTenant(widget.tenantId);
    setState(() => _applications = request);
    try {
      await request;
    } catch (_) {
      // FutureBuilder displays the safe error state for this request.
    }
  }

  bool _canWithdraw(RentalApplication application) {
    return switch (application.status) {
      RentalApplicationStatus.draft ||
      RentalApplicationStatus.submitted ||
      RentalApplicationStatus.underReview ||
      RentalApplicationStatus.changesRequested => true,
      RentalApplicationStatus.approved ||
      RentalApplicationStatus.rejected ||
      RentalApplicationStatus.withdrawn => false,
    };
  }

  Future<void> _confirmWithdrawal(RentalApplication application) async {
    if (_withdrawingIds.contains(application.id)) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Withdraw this application?'),
        content: const Text(
          'The application will be withdrawn and cannot be restored.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep application'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: const Text('Withdraw'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    setState(() => _withdrawingIds.add(application.id));
    try {
      await _apiService.withdrawApplication(
        id: application.id,
        tenantId: widget.tenantId,
      );
      if (!mounted) return;
      _showMessage('Application withdrawn.');
      await _refresh();
    } on RentalApplicationApiException catch (error) {
      if (mounted) _showMessage(error.message, isError: true);
    } catch (_) {
      if (mounted) {
        _showMessage(
          'Unable to withdraw the application right now. Please try again.',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _withdrawingIds.remove(application.id));
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Colors.red.shade700 : _olive,
        ),
      );
  }

  String _safeErrorMessage(Object? error) {
    if (error is RentalApplicationApiException) return error.message;
    return 'Unable to load your rental applications. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _warmBackground,
      appBar: AppBar(
        backgroundColor: _olive,
        foregroundColor: Colors.white,
        title: const Text('My Rental Applications'),
      ),
      body: SafeArea(
        child: FutureBuilder<List<RentalApplication>>(
          future: _applications,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: _olive),
              );
            }

            if (snapshot.hasError) {
              return _MessageState(
                icon: Icons.cloud_off_outlined,
                title: 'Could not load applications',
                message: _safeErrorMessage(snapshot.error),
                actionLabel: 'Try again',
                onAction: _refresh,
              );
            }

            final applications = snapshot.data ?? const <RentalApplication>[];
            if (applications.isEmpty) {
              return _MessageState(
                icon: Icons.description_outlined,
                title: 'No applications yet',
                message: 'Your rental applications will appear here.',
                actionLabel: 'Refresh',
                onAction: _refresh,
              );
            }

            return RefreshIndicator(
              color: _olive,
              onRefresh: _refresh,
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                itemCount: applications.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final application = applications[index];
                  return _ApplicationCard(
                    application: application,
                    canWithdraw: _canWithdraw(application),
                    isWithdrawing: _withdrawingIds.contains(application.id),
                    onWithdraw: () => _confirmWithdrawal(application),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ApplicationCard extends StatelessWidget {
  const _ApplicationCard({
    required this.application,
    required this.canWithdraw,
    required this.isWithdrawing,
    required this.onWithdraw,
  });

  final RentalApplication application;
  final bool canWithdraw;
  final bool isWithdrawing;
  final VoidCallback onWithdraw;

  @override
  Widget build(BuildContext context) {
    final date = MaterialLocalizations.of(
      context,
    ).formatMediumDate(application.moveInDate);

    return Card(
      color: Colors.white,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.home_work_outlined,
                  color: _MyRentalApplicationsScreenState._olive,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Move in $date',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(application.occupation),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                RentalApplicationStatusChip(status: application.status),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _SummaryItem(
                  icon: Icons.payments_outlined,
                  label:
                      'Income ${application.monthlyIncome.toStringAsFixed(2)}',
                ),
                _SummaryItem(
                  icon: Icons.people_outline,
                  label:
                      '${application.numberOfOccupants} '
                      '${application.numberOfOccupants == 1 ? 'occupant' : 'occupants'}',
                ),
              ],
            ),
            if (_hasText(application.tenantNote)) ...[
              const SizedBox(height: 16),
              _DetailBlock(
                label: 'Your note',
                value: application.tenantNote!.trim(),
              ),
            ],
            if (_hasText(application.landlordResponse)) ...[
              const SizedBox(height: 12),
              _DetailBlock(
                label: 'Landlord response',
                value: application.landlordResponse!.trim(),
                highlighted: true,
              ),
            ],
            if (canWithdraw) ...[
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: isWithdrawing ? null : onWithdraw,
                  icon: isWithdrawing
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.undo_outlined),
                  label: Text(
                    isWithdrawing ? 'Withdrawing...' : 'Withdraw application',
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  bool _hasText(String? value) => value != null && value.trim().isNotEmpty;
}

class _SummaryItem extends StatelessWidget {
  const _SummaryItem({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F3ED),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: _MyRentalApplicationsScreenState._olive),
          const SizedBox(width: 6),
          Text(label),
        ],
      ),
    );
  }
}

class _DetailBlock extends StatelessWidget {
  const _DetailBlock({
    required this.label,
    required this.value,
    this.highlighted = false,
  });

  final String label;
  final String value;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: highlighted ? const Color(0xFFECEFDF) : const Color(0xFFF5F3ED),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: _MyRentalApplicationsScreenState._olive,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(value),
        ],
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final Future<void> Function() onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 52,
              color: _MyRentalApplicationsScreenState._olive,
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: Colors.black54),
            ),
            const SizedBox(height: 20),
            OutlinedButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}
