import 'package:flutter/material.dart';

import 'features/application_documents/screens/application_documents_screen.dart';
import 'features/rental_applications/screens/my_rental_applications_screen.dart';
import 'features/rental_applications/screens/rental_application_form_screen.dart';
import 'features/viewings/screens/book_viewing_screen.dart';
import 'features/viewings/screens/my_viewings_screen.dart';

// TODO(dev-only): Replace with the authenticated user's tenant ID when
// authentication is implemented.
const _temporaryTenantId = '11111111-1111-1111-1111-111111111111';

// TODO(dev-only): Replace with the property ID supplied by property navigation
// when property screens are implemented.
const _temporaryPropertyId = '22222222-2222-2222-2222-222222222222';

// TODO(dev-only): Replace with an existing rental application ID belonging to
// [_temporaryTenantId] before testing document uploads.
const _temporaryApplicationId = '33333333-3333-3333-3333-333333333333';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RentFlow',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF5D6842)),
        useMaterial3: true,
      ),
      home: const ViewingDevelopmentHome(),
    );
  }
}

/// Temporary launcher for manually testing tenant development flows.
///
/// TODO(dev-only): Remove this screen when authentication and property
/// navigation provide the tenant and property context.
class ViewingDevelopmentHome extends StatelessWidget {
  const ViewingDevelopmentHome({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('RentFlow Development')),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Viewing Booking',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Temporary development entry for Android emulator testing.',
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const BookViewingScreen(
                              propertyId: _temporaryPropertyId,
                              tenantId: _temporaryTenantId,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.add_home_work_outlined),
                      label: const Text('Book a Viewing'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const MyViewingsScreen(
                              tenantId: _temporaryTenantId,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.calendar_month_outlined),
                      label: const Text('My Viewings'),
                    ),
                    const SizedBox(height: 32),
                    const Divider(),
                    const SizedBox(height: 24),
                    Text(
                      'Rental Applications',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Temporary tenant application flow for development testing.',
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const RentalApplicationFormScreen(
                              propertyId: _temporaryPropertyId,
                              tenantId: _temporaryTenantId,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.description_outlined),
                      label: const Text('Apply for Rental'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const MyRentalApplicationsScreen(
                              tenantId: _temporaryTenantId,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.folder_open_outlined),
                      label: const Text('My Applications'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const ApplicationDocumentsScreen(
                              applicationId: _temporaryApplicationId,
                              tenantId: _temporaryTenantId,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.file_upload_outlined),
                      label: const Text('Application Documents'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
