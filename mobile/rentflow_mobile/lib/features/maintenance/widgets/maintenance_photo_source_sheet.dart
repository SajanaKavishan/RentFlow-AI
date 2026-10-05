import 'package:flutter/material.dart';

import '../../../shared/theme/app_theme.dart';
import '../services/maintenance_photo_picker.dart';

Future<MaintenancePhotoSource?> showMaintenancePhotoSourceSheet(
  BuildContext context,
) => showModalBottomSheet<MaintenancePhotoSource>(
  context: context,
  backgroundColor: AppPalette.white,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Add photo',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(
              Icons.camera_alt_outlined,
              color: AppPalette.darkOlive,
            ),
            title: const Text('Take a photo'),
            onTap: () =>
                Navigator.of(context).pop(MaintenancePhotoSource.camera),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(
              Icons.photo_library_outlined,
              color: AppPalette.darkOlive,
            ),
            title: const Text('Choose from gallery'),
            onTap: () =>
                Navigator.of(context).pop(MaintenancePhotoSource.gallery),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    ),
  ),
);
