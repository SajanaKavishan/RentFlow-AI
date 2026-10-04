import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/validation/phone_number.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/shared_widgets.dart';
import '../models/landlord_contact.dart';
import '../services/property_api_service.dart';

Uri? landlordDialerUri(String number) {
  final phone = usablePhoneNumber(number);
  return phone == null
      ? null
      : Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'[^+0-9]'), ''));
}

class LandlordContactCard extends StatefulWidget {
  const LandlordContactCard({
    super.key,
    required this.propertyId,
    required this.service,
    this.refreshVersion = 0,
  });
  final String propertyId;
  final PropertyApiService service;
  final int refreshVersion;

  @override
  State<LandlordContactCard> createState() => _LandlordContactCardState();
}

class _LandlordContactCardState extends State<LandlordContactCard>
    with WidgetsBindingObserver {
  LandlordContact? _contact;
  int _version = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void didUpdateWidget(LandlordContactCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.propertyId != widget.propertyId ||
        oldWidget.refreshVersion != widget.refreshVersion) {
      _refresh();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final version = ++_version;
    setState(() => _contact = null);
    try {
      final contact = await widget.service.getLandlordContact(
        widget.propertyId,
      );
      if (mounted && version == _version) setState(() => _contact = contact);
    } catch (_) {
      /* Optional contact fails closed. */
    }
  }

  Future<void> _call() async {
    final contact = _contact;
    if (contact == null) return;
    final uri = landlordDialerUri(contact.phoneNumber);
    try {
      if (uri != null &&
          await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        return;
      }
    } catch (_) {
      /* Devices without a dialer keep the number visible. */
    }
    if (mounted) {
      AppSnackbars.show(
        context,
        message: 'Calling is not available on this device.',
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final contact = _contact;
    if (contact == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.base),
      child: AppCard(
        color: AppPalette.white,
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Contact landlord', style: AppTypography.cardTitle),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: SelectableText(
                    contact.phoneNumber,
                    style: AppTypography.body.copyWith(
                      color: AppPalette.primaryText,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                IconButton.filledTonal(
                  key: const Key('landlord-call'),
                  tooltip: 'Call landlord',
                  style: IconButton.styleFrom(
                    minimumSize: const Size(44, 44),
                    backgroundColor: AppPalette.softCream,
                    foregroundColor: AppPalette.olive,
                  ),
                  onPressed: _call,
                  icon: const Icon(
                    Icons.phone_outlined,
                    size: 22,
                    semanticLabel: 'Call landlord',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
