import 'package:flutter/material.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/shared_widgets.dart';
import '../../properties/screens/property_list_screen.dart';
import '../../properties/services/property_api_service.dart';
import '../../properties/widgets/property_photo.dart';
import '../../viewings/screens/my_viewings_screen.dart';
import '../../viewings/services/viewing_api_service.dart';
import '../models/application_eligibility.dart';
import '../services/rental_application_api_service.dart';
import 'rental_application_form_screen.dart';

class EligibleApplicationPropertiesScreen extends StatefulWidget {
  const EligibleApplicationPropertiesScreen({
    super.key,
    required this.apiService,
    required this.propertyApiService,
  });
  final RentalApplicationApiService apiService;
  final PropertyApiService propertyApiService;
  @override
  State<EligibleApplicationPropertiesScreen> createState() =>
      _EligibleApplicationPropertiesScreenState();
}

class _EligibleApplicationPropertiesScreenState
    extends State<EligibleApplicationPropertiesScreen>
    with WidgetsBindingObserver {
  late Future<List<EligibleApplicationProperty>> _properties;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _properties = widget.apiService.getEligibleProperties();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        (ModalRoute.of(context)?.isCurrent ?? false)) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    final request = widget.apiService.getEligibleProperties();
    setState(() {
      _properties = request;
    });
    try {
      await request;
    } catch (_) {
      /* FutureBuilder presents the error. */
    }
  }

  Future<void> _navigate(Widget screen) async {
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => screen));
    if (mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppPalette.background,
    appBar: AppBar(
      title: const Text('Choose a property'),
      actions: [
        IconButton(
          tooltip: 'Refresh eligible properties',
          onPressed: _refresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: FutureBuilder<List<EligibleApplicationProperty>>(
      future: _properties,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const LoadingState(
            title: 'Loading properties',
            message: 'Checking properties you have viewed.',
          );
        }
        if (snapshot.hasError) {
          return ErrorState(
            message: 'Unable to load eligible properties. Please try again.',
            onRetry: _refresh,
          );
        }
        final properties = snapshot.data ?? [];
        return RefreshIndicator(
          onRefresh: _refresh,
          child: AuthenticatedPage(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'You can apply for properties after completing a viewing.',
                ),
                const SizedBox(height: 20),
                if (properties.isEmpty) ...[
                  Text(
                    'No properties ready to apply',
                    style: AppTypography.sectionTitle,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Complete a property viewing before starting a rental application.',
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () => _navigate(
                      Scaffold(
                        appBar: AppBar(title: const Text('Browse properties')),
                        body: PropertyListScreen(
                          propertyApiService: widget.propertyApiService,
                          rentalApplicationApiService: widget.apiService,
                        ),
                      ),
                    ),
                    child: const Text('Browse properties'),
                  ),
                  OutlinedButton(
                    onPressed: () => _navigate(
                      MyViewingsScreen(
                        viewingApiService: ViewingApiService(
                          widget.apiService.apiClient,
                        ),
                      ),
                    ),
                    child: const Text('My viewings'),
                  ),
                ],
                for (final property in properties)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: AppCard(
                      onTap: () => _navigate(
                        RentalApplicationFormScreen(
                          propertyId: property.id,
                          propertyTitle: property.title,
                          rentalApplicationApiService: widget.apiService,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            height: 140,
                            child: PropertyPhoto(
                              propertyId: property.id,
                              propertyApiService: widget.propertyApiService,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(property.title, style: AppTypography.cardTitle),
                          Text('${property.address}, ${property.city}'),
                          Text(
                            'LKR ${property.monthlyRent.toStringAsFixed(0)} / month',
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Completed viewing',
                            style: AppTypography.label,
                          ),
                          TextButton(
                            onPressed: () => _navigate(
                              RentalApplicationFormScreen(
                                propertyId: property.id,
                                propertyTitle: property.title,
                                rentalApplicationApiService: widget.apiService,
                              ),
                            ),
                            child: const Text('Start application'),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
