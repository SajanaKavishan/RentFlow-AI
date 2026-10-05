import 'package:flutter/material.dart';

import '../features/auth/controllers/auth_controller.dart';
import '../features/maintenance/screens/my_maintenance_requests_screen.dart';
import '../shared/theme/app_theme.dart';
import 'maintenance_preview_dependencies.dart';

/// Run explicitly: flutter run --debug -t lib/debug/maintenance_preview.dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaintenancePreviewApp());
}

class MaintenancePreviewApp extends StatefulWidget {
  const MaintenancePreviewApp({super.key});

  @override
  State<MaintenancePreviewApp> createState() => _MaintenancePreviewAppState();
}

class _MaintenancePreviewAppState extends State<MaintenancePreviewApp> {
  late final MaintenancePreviewDependencies _dependencies;
  late final Future<void> _ready;

  @override
  void initState() {
    super.initState();
    // The dependency factory rejects profile/release builds before setup.
    _dependencies = MaintenancePreviewDependencies();
    _ready = _dependencies.auth.restoreSession();
  }

  @override
  void dispose() {
    _dependencies.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AuthScope(
    controller: _dependencies.auth,
    child: MaterialApp(
      title: 'Maintenance UI Preview',
      theme: AppTheme.build(),
      debugShowCheckedModeBanner: false,
      builder: (context, child) => Banner(
        message: 'PREVIEW',
        location: BannerLocation.topEnd,
        color: AppPalette.darkOlive,
        child: child!,
      ),
      home: FutureBuilder<void>(
        future: _ready,
        builder: (context, snapshot) =>
            snapshot.connectionState == ConnectionState.done
            ? MyMaintenanceRequestsScreen(
                maintenanceApiService: _dependencies.maintenance,
                photoPicker: _dependencies.photoPicker,
              )
            : const Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
    ),
  );
}
