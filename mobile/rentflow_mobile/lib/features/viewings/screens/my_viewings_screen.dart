import 'package:flutter/material.dart';

import '../../../core/network/api_client.dart';
import '../models/viewing.dart';
import '../services/viewing_api_service.dart';
import '../widgets/viewing_status_chip.dart';

class MyViewingsScreen extends StatefulWidget {
  const MyViewingsScreen({
    super.key,
    required this.tenantId,
    this.viewingApiService,
  });

  final String tenantId;
  final ViewingApiService? viewingApiService;

  @override
  State<MyViewingsScreen> createState() => _MyViewingsScreenState();
}

class _MyViewingsScreenState extends State<MyViewingsScreen> {
  static const _olive = Color(0xFF5D6842);
  static const _warmBackground = Color(0xFFF7F5EF);

  ApiClient? _ownedApiClient;
  late final ViewingApiService _viewingApiService;
  late Future<List<Viewing>> _viewings;
  final Set<String> _cancellingIds = {};

  @override
  void initState() {
    super.initState();
    if (widget.viewingApiService case final service?) {
      _viewingApiService = service;
    } else {
      _ownedApiClient = ApiClient();
      _viewingApiService = ViewingApiService(_ownedApiClient!);
    }
    _viewings = _viewingApiService.getViewingsByTenant(widget.tenantId);
  }

  @override
  void dispose() {
    _ownedApiClient?.close();
    super.dispose();
  }

  Future<void> _refresh() async {
    final request = _viewingApiService.getViewingsByTenant(widget.tenantId);
    setState(() => _viewings = request);
    try {
      await request;
    } catch (_) {
      // FutureBuilder presents the safe error state for this same request.
    }
  }

  bool _canCancel(Viewing viewing) {
    return viewing.status == ViewingStatus.pending ||
        viewing.status == ViewingStatus.approved;
  }

  Future<void> _confirmCancellation(Viewing viewing) async {
    if (_cancellingIds.contains(viewing.id)) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this viewing?'),
        content: const Text(
          'The viewing request will be cancelled and cannot be restored.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep viewing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: const Text('Cancel viewing'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _cancellingIds.add(viewing.id));
    try {
      await _viewingApiService.cancelViewing(
        id: viewing.id,
        tenantId: widget.tenantId,
      );
      if (!mounted) return;
      _showMessage('Viewing cancelled.');
      await _refresh();
    } on ViewingApiException catch (error) {
      if (mounted) _showMessage(error.message, isError: true);
    } catch (_) {
      if (mounted) {
        _showMessage(
          'Unable to cancel the viewing right now. Please try again.',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _cancellingIds.remove(viewing.id));
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
    if (error is ViewingApiException) return error.message;
    return 'Unable to load your viewings. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _warmBackground,
      appBar: AppBar(
        backgroundColor: _olive,
        foregroundColor: Colors.white,
        title: const Text('My Viewings'),
      ),
      body: SafeArea(
        child: FutureBuilder<List<Viewing>>(
          future: _viewings,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: _olive),
              );
            }

            if (snapshot.hasError) {
              return _MessageState(
                icon: Icons.cloud_off_outlined,
                title: 'Could not load viewings',
                message: _safeErrorMessage(snapshot.error),
                actionLabel: 'Try again',
                onAction: _refresh,
              );
            }

            final viewings = snapshot.data ?? const <Viewing>[];
            if (viewings.isEmpty) {
              return _MessageState(
                icon: Icons.event_available_outlined,
                title: 'No viewings yet',
                message: 'Your requested property viewings will appear here.',
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
                itemCount: viewings.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final viewing = viewings[index];
                  return _ViewingCard(
                    viewing: viewing,
                    canCancel: _canCancel(viewing),
                    isCancelling: _cancellingIds.contains(viewing.id),
                    onCancel: () => _confirmCancellation(viewing),
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

class _ViewingCard extends StatelessWidget {
  const _ViewingCard({
    required this.viewing,
    required this.canCancel,
    required this.isCancelling,
    required this.onCancel,
  });

  final Viewing viewing;
  final bool canCancel;
  final bool isCancelling;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    final localDateTime = viewing.requestedDateTime.toLocal();
    final date = localizations.formatFullDate(localDateTime);
    final time = localizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(localDateTime),
    );

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
                  Icons.calendar_month_outlined,
                  color: _MyViewingsScreenState._olive,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        date,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(time, style: Theme.of(context).textTheme.bodyLarge),
                    ],
                  ),
                ),
                ViewingStatusChip(status: viewing.status),
              ],
            ),
            if (_hasText(viewing.tenantMessage)) ...[
              const SizedBox(height: 16),
              _DetailBlock(
                label: 'Your message',
                value: viewing.tenantMessage!.trim(),
              ),
            ],
            if (_hasText(viewing.landlordResponse)) ...[
              const SizedBox(height: 12),
              _DetailBlock(
                label: 'Owner response',
                value: viewing.landlordResponse!.trim(),
                highlighted: true,
              ),
            ],
            if (canCancel) ...[
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: isCancelling ? null : onCancel,
                  icon: isCancelling
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.close),
                  label: Text(isCancelling ? 'Cancelling…' : 'Cancel viewing'),
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
              color: _MyViewingsScreenState._olive,
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
            Icon(icon, size: 52, color: _MyViewingsScreenState._olive),
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
