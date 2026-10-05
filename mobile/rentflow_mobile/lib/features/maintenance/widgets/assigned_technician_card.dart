import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/validation/phone_number.dart';
import '../../../shared/theme/app_theme.dart';

class AssignedTechnicianCard extends StatelessWidget {
  const AssignedTechnicianCard({
    super.key,
    required this.name,
    this.contactPhone,
  });
  final String name;
  final String? contactPhone;

  Future<void> _call(BuildContext context, Uri uri) async {
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {
      // A device without a dialer leaves the request and identity intact.
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Calling is not available on this device.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final parts = name.trim().split(RegExp(r'\s+'));
    final initials = [
      parts.first,
      if (parts.length > 1) parts.last,
    ].map((part) => part.characters.first).join().toUpperCase();
    final uri = phoneDialerUri(contactPhone);
    final identity = MergeSemantics(
      child: Row(
        children: [
          ExcludeSemantics(
            child: CircleAvatar(
              radius: 20,
              backgroundColor: AppPalette.progress,
              foregroundColor: AppPalette.darkOlive,
              child: Text(
                initials,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.trim(),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppPalette.primaryText,
                  ),
                ),
                const SizedBox(height: 3),
                const Text(
                  'Assigned technician',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppPalette.secondaryText,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    final call = uri == null
        ? null
        : Tooltip(
            message: 'Call assigned technician',
            child: TextButton.icon(
              key: const ValueKey('call-assigned-technician'),
              onPressed: () => _call(context, uri),
              style: TextButton.styleFrom(
                foregroundColor: AppPalette.darkOlive,
                minimumSize: const Size(44, 44),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              icon: const Icon(Icons.phone_outlined, size: 17),
              label: const Text(
                'Call',
                semanticsLabel: 'Call assigned technician',
              ),
            ),
          );
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Container(
        key: const ValueKey('assigned-technician-identity'),
        margin: const EdgeInsets.only(top: 16, bottom: 2),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppPalette.softCream,
          borderRadius: BorderRadius.circular(12),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 210 ||
                MediaQuery.textScalerOf(context).scale(1) > 1.3) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  identity,
                  if (call != null)
                    Align(alignment: Alignment.centerRight, child: call),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: identity),
                if (call != null) ...[const SizedBox(width: 6), call],
              ],
            );
          },
        ),
      ),
    );
  }
}
