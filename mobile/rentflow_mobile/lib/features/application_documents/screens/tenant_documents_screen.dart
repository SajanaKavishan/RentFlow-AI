import 'package:flutter/material.dart';

import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/shared_widgets.dart';
import '../../properties/services/property_api_service.dart';
import '../../rental_applications/models/rental_application.dart';
import '../../rental_applications/services/rental_application_api_service.dart';
import '../services/application_document_api_service.dart';
import 'application_documents_screen.dart';

class TenantDocumentsScreen extends StatefulWidget {
  const TenantDocumentsScreen({
    super.key,
    this.rentalApplicationApiService,
    this.propertyApiService,
  });
  final RentalApplicationApiService? rentalApplicationApiService;
  final PropertyApiService? propertyApiService;
  @override
  State<TenantDocumentsScreen> createState() => _TenantDocumentsScreenState();
}

class _TenantDocumentsScreenState extends State<TenantDocumentsScreen> {
  Future<List<_DocumentGroup>>? _groups;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _groups = widget.rentalApplicationApiService == null ? null : _fetch();
  }

  Future<List<_DocumentGroup>> _fetch() async {
    final applications = await widget.rentalApplicationApiService!
        .getMyApplications();
    applications.sort(
      (a, b) =>
          (b.updatedAt ?? b.createdAt).compareTo(a.updatedAt ?? a.createdAt),
    );
    return Future.wait(
      applications.map((application) async {
        var title = 'Rental application documents';
        try {
          final property = await widget.propertyApiService?.getPropertyById(
            application.propertyId,
          );
          if (property != null && property.id == application.propertyId) {
            title = property.title;
          }
        } catch (_) {
          /* The document workspace works without a property title. */
        }
        return _DocumentGroup(application, title);
      }),
    );
  }

  Future<void> _refresh() async {
    setState(_load);
    try {
      await _groups;
    } catch (_) {
      /* The screen shows the error. */
    }
  }

  Future<void> _openDocuments(_DocumentGroup group) async {
    final service = widget.rentalApplicationApiService!;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ApplicationDocumentsScreen(
          applicationId: group.application.id,
          rentalApplicationApiService: service,
          applicationDocumentApiService: ApplicationDocumentApiService(
            service.apiClient,
          ),
        ),
      ),
    );
    if (mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Documents')),
    body: RefreshIndicator(
      onRefresh: _refresh,
      child: AuthenticatedPage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const PageHeader(
              title: 'Your documents',
              subtitle:
                  'View and manage documents for your rental applications.',
            ),
            const SizedBox(height: 24),
            FutureBuilder<List<_DocumentGroup>>(
              future: _groups,
              builder: (context, result) {
                if (_groups == null) {
                  return const AppCard(
                    child: Text(
                      'Documents are currently unavailable. Please try again when your account is connected.',
                    ),
                  );
                }
                if (result.connectionState != ConnectionState.done) {
                  return const AppCard(
                    child: Column(
                      children: [
                        Text('Loading your documents'),
                        SizedBox(height: 12),
                        LinearProgressIndicator(),
                      ],
                    ),
                  );
                }
                if (result.hasError) {
                  return AppCard(
                    child: Column(
                      children: [
                        const Text('Could not load your documents.'),
                        TextButton(
                          onPressed: _refresh,
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
                  );
                }
                if (result.data!.isEmpty) {
                  return const AppCard(
                    child: Text(
                      'No application documents yet. Documents will appear here once you create a rental application.',
                    ),
                  );
                }
                return Column(
                  children: [
                    for (final group in result.data!)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: AppCard(
                          onTap: () => _openDocuments(group),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: AppPalette.softCream,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.folder_outlined,
                                  color: AppPalette.olive,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      group.title,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'View documents',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodyMedium,
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right_rounded,
                                color: AppPalette.olive,
                              ),
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
}

class _DocumentGroup {
  const _DocumentGroup(this.application, this.title);
  final RentalApplication application;
  final String title;
}
