import 'package:flutter/material.dart';

import '../../features/support/models/support_ticket.dart';
import '../../features/support/services/support_ticket_api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/shared_widgets.dart';
import 'create_support_request_screen.dart';
import 'profile_page.dart';

class HelpSupportScreen extends StatefulWidget {
  const HelpSupportScreen({super.key, required this.service});
  final SupportTicketApiService service;
  @override
  State<HelpSupportScreen> createState() => _HelpSupportScreenState();
}

class _HelpSupportScreenState extends State<HelpSupportScreen> {
  List<SupportTicket>? _tickets;
  bool _loading = true;
  String? _error;
  String? _success;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tickets = await widget.service.getMySupportTickets();
      if (mounted) setState(() => _tickets = tickets);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is SupportTicketApiException
              ? error.message
              : 'Your support requests could not be loaded. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    if (_loading) return;
    final ticket = await Navigator.of(context).push<SupportTicket>(
      MaterialPageRoute(
        builder: (_) => CreateSupportRequestScreen(service: widget.service),
      ),
    );
    if (!mounted || ticket == null) return;
    setState(() {
      // Creation is authoritative; keep the existing GET order behind it.
      _tickets = [ticket, ...?_tickets?.where((item) => item.id != ticket.id)];
      _success = 'Support request submitted.';
    });
  }

  @override
  Widget build(BuildContext context) => ProfileSurface(
    child: Scaffold(
      appBar: profilePageAppBar(context, title: 'Help & support'),
      body: AuthenticatedPage(
        maxWidth: 580,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Need help?', style: AppTypography.sectionTitle),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Send us a support request and track its status.',
              style: AppTypography.body,
            ),
            const SizedBox(height: AppSpacing.base),
            FilledButton.icon(
              key: const Key('support-new-request'),
              onPressed: _loading ? null : _create,
              icon: const Icon(Icons.add, size: 20),
              label: const Text('New support request'),
            ),
            if (_success != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.base),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    _success!,
                    style: AppTypography.body.copyWith(
                      color: AppPalette.success,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: AppSpacing.lg),
            const Text(
              'My support requests',
              style: AppTypography.sectionTitle,
            ),
            const SizedBox(height: AppSpacing.base),
            if (_loading)
              Semantics(
                liveRegion: true,
                child: const LoadingState(
                  title: 'Loading support requests…',
                  compact: true,
                ),
              ),
            if (_error != null)
              Semantics(
                liveRegion: true,
                child: SharedState(
                  title: 'Support requests unavailable',
                  message: _error,
                  icon: Icons.cloud_off_outlined,
                  actionLabel: 'Retry',
                  onAction: _load,
                  compact: true,
                ),
              ),
            if (!_loading && _error == null && _tickets!.isEmpty)
              const AppCard(
                child: SharedState(
                  title: 'No support requests yet.',
                  message:
                      'Need help? Create a request and our team can review it.',
                  compact: true,
                ),
              ),
            for (final ticket in _tickets ?? <SupportTicket>[]) ...[
              SupportTicketCard(
                key: ValueKey('support-ticket-${ticket.id}'),
                ticket: ticket,
              ),
              const SizedBox(height: AppSpacing.md),
            ],
          ],
        ),
      ),
    ),
  );
}

class SupportTicketCard extends StatelessWidget {
  const SupportTicketCard({super.key, required this.ticket});
  final SupportTicket ticket;
  String _date(BuildContext context, DateTime timestamp) =>
      MaterialLocalizations.of(context).formatShortDate(timestamp.toLocal());
  @override
  Widget build(BuildContext context) => AppCard(
    padding: EdgeInsets.zero,
    child: ExpansionTile(
      iconColor: AppPalette.olive,
      collapsedIconColor: AppPalette.olive,
      textColor: AppPalette.primaryText,
      collapsedTextColor: AppPalette.primaryText,
      tilePadding: AppSpacing.card,
      childrenPadding: AppSpacing.card,
      shape: const Border(),
      collapsedShape: const Border(),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              StatusChip(
                label: ticket.status.label,
                tone: switch (ticket.status) {
                  SupportStatus.open => StatusTone.pending,
                  SupportStatus.inProgress => StatusTone.progress,
                  SupportStatus.resolved => StatusTone.success,
                },
              ),
              Text(ticket.category.label, style: AppTypography.bodySmall),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(ticket.subject, style: AppTypography.cardTitle),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Created ${_date(context, ticket.createdAt)}',
            style: AppTypography.bodySmall,
          ),
        ],
      ),
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Original message',
              style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpacing.sm),
            SelectableText(ticket.message, style: AppTypography.body),
            const SizedBox(height: AppSpacing.base),
            Text(
              'Updated ${_date(context, ticket.updatedAt)}',
              style: AppTypography.bodySmall,
            ),
          ],
        ),
      ],
    ),
  );
}
