import 'package:flutter/material.dart';

import '../../../core/network/api_client.dart';
import '../../auth/controllers/auth_controller.dart';
import '../../properties/models/property.dart';
import '../models/maintenance_request.dart';
import '../services/maintenance_api_service.dart';
import 'create_maintenance_request_screen.dart';

String _maintenanceEnumLabel(Enum value) {
  return value.name
      .replaceAllMapped(
        RegExp(r'([a-z])([A-Z])'),
        (match) => '${match.group(1)} ${match.group(2)}',
      )
      .replaceAll('_', ' ')
      .split(' ')
      .map(
        (part) => part.isEmpty
            ? part
            : '${part[0].toUpperCase()}${part.substring(1)}',
      )
      .join(' ');
}

class MyMaintenanceRequestsScreen extends StatefulWidget {
  const MyMaintenanceRequestsScreen({super.key, this.maintenanceApiService});

  final MaintenanceApiService? maintenanceApiService;

  @override
  State<MyMaintenanceRequestsScreen> createState() =>
      _MyMaintenanceRequestsScreenState();
}

class _MyMaintenanceRequestsScreenState
    extends State<MyMaintenanceRequestsScreen> {
  static const _olive = Color(0xFF5D6842);
  static const _warmBackground = Color(0xFFF7F5EF);

  ApiClient? _ownedApiClient;
  late final MaintenanceApiService _apiService;
  late Future<List<MaintenanceRequest>> _requests;
  bool _didLoad = false;
  bool _isLoadingProperties = false;

  @override
  void initState() {
    super.initState();
    if (widget.maintenanceApiService case final service?) {
      _apiService = service;
    } else {
      _ownedApiClient = ApiClient();
      _apiService = MaintenanceApiService(_ownedApiClient!);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didLoad) return;
    _didLoad = true;
    final currentUser = AuthScope.of(context).currentUser;
    if (currentUser == null) {
      _requests = Future.value(const <MaintenanceRequest>[]);
    } else {
      _requests = _apiService.getMyMaintenanceRequests(
        tenantId: currentUser.id,
      );
    }
  }

  @override
  void dispose() {
    _ownedApiClient?.close();
    super.dispose();
  }

  Future<void> _refresh() async {
    final currentUser = AuthScope.of(context).currentUser;
    if (currentUser == null) {
      setState(() {
        _requests = Future.value(const <MaintenanceRequest>[]);
      });
      return;
    }

    final request = _apiService.getMyMaintenanceRequests(
      tenantId: currentUser.id,
    );
    setState(() {
      _requests = request;
    });

    try {
      await request;
    } catch (_) {
      // FutureBuilder displays a safe error state for this request.
    }
  }

  Future<Property?> _selectProperty(List<Property> properties) async {
    if (properties.isEmpty) return null;
    return showDialog<Property>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Choose a property'),
        children: properties
            .map(
              (property) => SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop(property),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      property.title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      '${property.address}, ${property.city}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Future<void> _createRequest() async {
    if (_isLoadingProperties) return;
    setState(() => _isLoadingProperties = true);
    Property? property;
    try {
      final properties = await _apiService.getTenantProperties();
      if (!mounted) return;
      setState(() => _isLoadingProperties = false);
      if (properties.isEmpty) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('No associated properties'),
            content: const Text(
              'A maintenance request can only be created for a property '
              'associated with your account.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        );
        return;
      }
      property = await _selectProperty(properties);
    } on MaintenanceApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error.message)));
      return;
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Unable to load your associated properties.'),
          ),
        );
      return;
    } finally {
      if (mounted) setState(() => _isLoadingProperties = false);
    }

    if (!mounted || property == null) return;
    final created = await Navigator.of(context).push<MaintenanceRequest>(
      MaterialPageRoute<MaintenanceRequest>(
        builder: (_) => CreateMaintenanceRequestScreen(
          propertyId: property!.id,
          maintenanceApiService: _apiService,
        ),
      ),
    );
    if (created != null && mounted) {
      await _refresh();
    }
  }

  Future<void> _showRequestDetails(MaintenanceRequest request) async {
    final detailFuture = _apiService.getMaintenanceRequestById(request.id);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(request.title),
        content: FutureBuilder<MaintenanceRequest>(
          future: detailFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                height: 64,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError) {
              return Text(_safeErrorMessage(snapshot.error));
            }
            final detail = snapshot.data!;
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Status: ${_maintenanceEnumLabel(detail.status)}'),
                  Text('Category: ${_maintenanceEnumLabel(detail.category)}'),
                  Text('Priority: ${_maintenanceEnumLabel(detail.priority)}'),
                  const SizedBox(height: 12),
                  Text(detail.description),
                  if (detail.tenantAccessNotes != null) ...[
                    const SizedBox(height: 12),
                    Text('Access notes: ${detail.tenantAccessNotes}'),
                  ],
                ],
              ),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _safeErrorMessage(Object? error) {
    if (error is MaintenanceApiException) {
      return error.message;
    }
    return 'Unable to load your maintenance requests. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _warmBackground,
      appBar: AppBar(
        backgroundColor: _olive,
        foregroundColor: Colors.white,
        title: const Text('My Maintenance Requests'),
        actions: [
          IconButton(
            tooltip: 'Create maintenance request',
            onPressed: _isLoadingProperties ? null : _createRequest,
            icon: _isLoadingProperties
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add),
          ),
          IconButton(
            tooltip: 'Refresh maintenance requests',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<List<MaintenanceRequest>>(
          future: _requests,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: _olive),
              );
            }

            if (snapshot.hasError) {
              return _MessageState(
                icon: Icons.cloud_off_outlined,
                title: 'Could not load maintenance requests',
                message: _safeErrorMessage(snapshot.error),
                actionLabel: 'Try again',
                onAction: _refresh,
              );
            }

            final requests = snapshot.data ?? const <MaintenanceRequest>[];
            if (requests.isEmpty) {
              return _MessageState(
                icon: Icons.handyman_outlined,
                title: 'No maintenance requests yet',
                message: 'Your maintenance requests will appear here.',
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
                itemCount: requests.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final request = requests[index];
                  return _MaintenanceRequestCard(
                    request: request,
                    onTap: () => _showRequestDetails(request),
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

class _MaintenanceRequestCard extends StatelessWidget {
  const _MaintenanceRequestCard({required this.request, required this.onTap});

  final MaintenanceRequest request;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final createdAt = request.createdAt.toLocal();
    final createdDate = MaterialLocalizations.of(
      context,
    ).formatFullDate(createdAt);

    return Card(
      color: Colors.white,
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.build_outlined,
                    color: _MyMaintenanceRequestsScreenState._olive,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          request.title,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Created $createdDate',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  _StatusChip(status: request.status),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  _InfoPill(
                    label: 'Category',
                    value: _maintenanceEnumLabel(request.category),
                  ),
                  _InfoPill(
                    label: 'Priority',
                    value: _maintenanceEnumLabel(request.priority),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFECEFDF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: RichText(
        text: TextSpan(
          style: Theme.of(context).textTheme.bodyMedium,
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(
                color: Color(0xFF5D6842),
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final MaintenanceRequestStatus status;

  @override
  Widget build(BuildContext context) {
    final label = _maintenanceEnumLabel(status);

    final Color background;
    final Color foreground;

    switch (status) {
      case MaintenanceRequestStatus.submitted:
      case MaintenanceRequestStatus.triaged:
      case MaintenanceRequestStatus.assigned:
        background = const Color(0xFFE5F1FF);
        foreground = const Color(0xFF1D4ED8);
      case MaintenanceRequestStatus.estimatePending:
      case MaintenanceRequestStatus.estimateSubmitted:
      case MaintenanceRequestStatus.awaitingLandlordApproval:
        background = const Color(0xFFFFF3CD);
        foreground = const Color(0xFF925F00);
      case MaintenanceRequestStatus.approved:
      case MaintenanceRequestStatus.inProgress:
      case MaintenanceRequestStatus.completed:
        background = const Color(0xFFE8F7ED);
        foreground = const Color(0xFF216E4E);
      case MaintenanceRequestStatus.rejected:
      case MaintenanceRequestStatus.cancelled:
        background = const Color(0xFFFDECEC);
        foreground = const Color(0xFF9F2D2D);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w700,
        ),
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
              color: _MyMaintenanceRequestsScreenState._olive,
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
