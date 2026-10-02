import 'package:flutter/material.dart';

import '../../../core/network/api_client.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/shared_widgets.dart';
import '../models/viewing.dart';
import '../services/viewing_api_service.dart';
import '../widgets/viewing_status_chip.dart';
import 'landlord_viewing_request_details_screen.dart';

class LandlordViewingRequestsScreen extends StatefulWidget {
  const LandlordViewingRequestsScreen({
    super.key,
    this.propertyId,
    this.viewingApiService,
  });

  final String? propertyId;
  final ViewingApiService? viewingApiService;

  @override
  State<LandlordViewingRequestsScreen> createState() =>
      _LandlordViewingRequestsScreenState();
}

class _LandlordViewingRequestsScreenState
    extends State<LandlordViewingRequestsScreen> {
  ApiClient? _ownedApiClient;
  late final ViewingApiService _apiService;
  Future<List<Viewing>>? _requests;

  bool get _hasPropertyReference =>
      widget.propertyId != null && widget.propertyId!.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    if (widget.viewingApiService case final service?) {
      _apiService = service;
    } else {
      _ownedApiClient = ApiClient();
      _apiService = ViewingApiService(_ownedApiClient!);
    }
    _load();
  }

  @override
  void dispose() {
    _ownedApiClient?.close();
    super.dispose();
  }

  void _load() {
    _requests = _hasPropertyReference
        ? _apiService.getViewingsByProperty(widget.propertyId!.trim())
        : null;
  }

  Future<void> _refresh() async {
    if (!_hasPropertyReference) return;
    final request = _apiService.getViewingsByProperty(
      widget.propertyId!.trim(),
    );
    setState(() {
      _requests = request;
    });
    try {
      await request;
    } catch (_) {
      // FutureBuilder renders the authoritative error response.
    }
  }

  Future<void> _openDetails(Viewing viewing) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => LandlordViewingRequestDetailsScreen(
          viewing: viewing,
          viewingApiService: _apiService,
        ),
      ),
    );
    if (mounted) await _refresh();
  }

  List<Viewing> _pendingFirst(List<Viewing> viewings) {
    final indexed = viewings.asMap().entries.toList(growable: false);
    indexed.sort((left, right) {
      final leftRank = left.value.status == ViewingStatus.pending ? 0 : 1;
      final rightRank = right.value.status == ViewingStatus.pending ? 0 : 1;
      final statusOrder = leftRank.compareTo(rightRank);
      return statusOrder != 0 ? statusOrder : left.key.compareTo(right.key);
    });
    return indexed.map((entry) => entry.value).toList(growable: false);
  }

  String _safeError(Object? error) {
    if (error is ViewingApiException) return error.message;
    return 'Unable to load viewing requests. Please try again.';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppPalette.background,
    appBar: AppBar(
      title: const Text('Viewing Requests'),
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(1),
        child: Divider(height: 1),
      ),
    ),
    body: !_hasPropertyReference
        ? const ModuleUnavailableState(
            title: 'Viewing queue unavailable',
            explanation:
                'A real landlord property reference is required to load viewing requests. Property integration is not available in the mobile app yet.',
            owner: 'Property management',
          )
        : FutureBuilder<List<Viewing>>(
            future: _requests,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const LoadingState(
                  title: 'Loading viewing requests',
                  message: 'Checking the latest requests for this property.',
                );
              }
              if (snapshot.hasError) {
                return ErrorState(
                  message: _safeError(snapshot.error),
                  onRetry: _refresh,
                );
              }
              final requests = _pendingFirst(
                snapshot.data ?? const <Viewing>[],
              );
              if (requests.isEmpty) {
                return const EmptyState(
                  title: 'No viewing requests',
                  message:
                      'Real tenant viewing requests for this property will appear here.',
                );
              }
              return RefreshIndicator(
                color: AppPalette.olive,
                onRefresh: _refresh,
                child: ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: AppSpacing.page,
                  itemCount: requests.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.base),
                        child: SectionHeader(
                          title: 'Request queue',
                          subtitle: 'Pending requests appear first.',
                          trailing: StatusChip(
                            label:
                                '${requests.length} ${requests.length == 1 ? 'request' : 'requests'}',
                            tone: StatusTone.neutral,
                          ),
                        ),
                      );
                    }
                    final request = requests[index - 1];
                    return Padding(
                      padding: EdgeInsets.only(
                        bottom: index == requests.length ? 0 : AppSpacing.md,
                      ),
                      child: _ViewingRequestCard(
                        viewing: request,
                        onOpen: () => _openDetails(request),
                      ),
                    );
                  },
                ),
              );
            },
          ),
  );
}

class _ViewingRequestCard extends StatelessWidget {
  const _ViewingRequestCard({required this.viewing, required this.onOpen});

  final Viewing viewing;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final local = viewing.requestedLocalDate == null
        ? viewing.requestedDateTime.toLocal()
        : DateTime.parse(viewing.requestedLocalDate!);
    final localizations = MaterialLocalizations.of(context);
    final date = localizations.formatMediumDate(local);
    final time = viewing.requestedDisplayTime == null
        ? localizations.formatTimeOfDay(TimeOfDay.fromDateTime(local))
        : '${viewing.requestedDisplayTime} (${viewing.timeZoneId})';
    return AppCard(
      key: ValueKey('landlord-viewing-card-${viewing.id}'),
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: viewing.status == ViewingStatus.pending
                      ? AppPalette.pending
                      : AppPalette.sage,
                  borderRadius: BorderRadius.circular(AppRadii.small),
                ),
                child: const Icon(
                  Icons.calendar_month_outlined,
                  color: AppPalette.darkOlive,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(date, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: AppSpacing.xs),
                    Text(time, style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              ViewingStatusChip(status: viewing.status),
            ],
          ),
          const SizedBox(height: AppSpacing.base),
          _QueueReference(
            label: 'Property reference',
            value: viewing.propertyId,
          ),
          const SizedBox(height: AppSpacing.sm),
          _QueueReference(label: 'Tenant reference', value: viewing.tenantId),
          if (_hasText(viewing.tenantMessage)) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppPalette.softCream,
                borderRadius: BorderRadius.circular(AppRadii.small),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tenant message',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: AppPalette.olive,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    viewing.tenantMessage!.trim(),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onOpen,
              icon: const Icon(Icons.arrow_forward, size: 18),
              label: const Text('View details'),
            ),
          ),
        ],
      ),
    );
  }

  bool _hasText(String? value) => value != null && value.trim().isNotEmpty;
}

class _QueueReference extends StatelessWidget {
  const _QueueReference({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 116,
        child: Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: AppPalette.muted),
        ),
      ),
      const SizedBox(width: AppSpacing.sm),
      Expanded(
        child: Text(
          value,
          textAlign: TextAlign.end,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: AppPalette.text),
        ),
      ),
    ],
  );
}
