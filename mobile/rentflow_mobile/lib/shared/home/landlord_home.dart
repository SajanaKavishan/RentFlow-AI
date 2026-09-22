import 'package:flutter/material.dart';

import '../../features/auth/models/current_user.dart';
import '../navigation/role_navigation.dart';
import '../theme/app_theme.dart';
import '../widgets/shared_widgets.dart';

class LandlordHome extends StatelessWidget {
  const LandlordHome({
    super.key,
    required this.user,
    required this.onDestinationSelected,
  });

  final CurrentUser user;
  final ValueChanged<RoleDestinationId> onDestinationSelected;

  @override
  Widget build(BuildContext context) => AuthenticatedPage(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          eyebrow: 'Landlord home',
          title: 'Hello, ${_firstName(user.fullName)}',
          subtitle: 'Review tenant requests from your authenticated workspace.',
        ),
        const SizedBox(height: AppSpacing.lg),
        const SectionHeader(
          title: 'Quick actions',
          subtitle: 'Open the landlord workflows available from mobile.',
        ),
        const SizedBox(height: AppSpacing.md),
        _LandlordQuickActions(onSelected: onDestinationSelected),
        const SizedBox(height: AppSpacing.lg),
        const AppCard(
          color: AppPalette.sage,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.devices_outlined, color: AppPalette.darkOlive),
              SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  'Full management tools are available on the RentFlow web workspace.',
                  style: TextStyle(
                    color: AppPalette.darkOlive,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _LandlordQuickActions extends StatelessWidget {
  const _LandlordQuickActions({required this.onSelected});

  final ValueChanged<RoleDestinationId> onSelected;

  @override
  Widget build(BuildContext context) {
    final actions = [
      (
        label: 'Viewing Requests',
        icon: Icons.calendar_month_outlined,
        destination: RoleDestinationId.viewingRequests,
      ),
      (
        label: 'Rental Applications',
        icon: Icons.description_outlined,
        destination: RoleDestinationId.applications,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = AppSpacing.md;
        final cardWidth = (constraints.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final action in actions)
              SizedBox(
                width: cardWidth,
                child: AppCard(
                  onTap: () => onSelected(action.destination),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 104),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Icon(action.icon, color: AppPalette.olive),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          action.label,
                          maxLines: 2,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(color: AppPalette.primaryText),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

String _firstName(String fullName) {
  final trimmed = fullName.trim();
  return trimmed.isEmpty ? 'there' : trimmed.split(RegExp(r'\s+')).first;
}
