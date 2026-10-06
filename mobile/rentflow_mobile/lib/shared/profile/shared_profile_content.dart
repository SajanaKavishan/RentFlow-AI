import 'package:flutter/material.dart';

import '../../features/auth/controllers/auth_controller.dart';
import '../../features/auth/models/current_user.dart';
import '../../features/application_documents/screens/tenant_documents_screen.dart';
import '../../features/notifications/services/notification_preferences_api_service.dart';
import '../../features/properties/screens/match_preferences_screen.dart';
import '../../features/properties/services/property_api_service.dart';
import '../../features/rental_applications/services/rental_application_api_service.dart';
import '../../features/support/services/support_ticket_api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/shared_widgets.dart';
import 'public_contact_editor.dart';
import 'personal_information_screen.dart';
import 'profile_avatar.dart';
import 'password_security_screen.dart';
import 'notification_preferences_screen.dart';
import 'help_support_screen.dart';
import 'profile_page.dart';

class SharedProfileContent extends StatelessWidget {
  const SharedProfileContent({
    super.key,
    required this.user,
    this.onOpenDocuments,
    this.onOpenReviews,
    this.propertyApiService,
  });

  final CurrentUser user;
  final VoidCallback? onOpenDocuments;
  final VoidCallback? onOpenReviews;
  final PropertyApiService? propertyApiService;

  @override
  Widget build(BuildContext context) {
    final currentUser = AuthScope.maybeOf(context)?.currentUser ?? user;
    return ProfileSurface(
      child: AuthenticatedPage(
        maxWidth: 580,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Column(
                children: [
                  ProfileAvatar(user: currentUser),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    _availableValue(currentUser.fullName),
                    textAlign: TextAlign.center,
                    style: AppTypography.identityName.copyWith(
                      color: AppPalette.primaryText,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    _availableValue(currentUser.email),
                    textAlign: TextAlign.center,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppPalette.neutral,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.base),
            _ProfileSection(
              title: 'Account',
              children: [
                _ProfileTile(
                  icon: Icons.person_outline,
                  title: 'Personal information',
                  subtitle: 'Update your photo, name, and phone number',
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) =>
                          PersonalInformationScreen(user: currentUser),
                    ),
                  ),
                ),
                _ProfileTile(
                  icon: Icons.lock_outline,
                  title: 'Password & security',
                  subtitle: 'Change your account password',
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => const PasswordSecurityScreen(),
                    ),
                  ),
                ),
                if (currentUser.role == UserRole.landlord)
                  _ProfileTile(
                    icon: Icons.phone_outlined,
                    title: 'Public contact',
                    subtitle: 'Manage contact for your property listings',
                    onTap: () {
                      final auth = AuthScope.of(context);
                      showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        useSafeArea: true,
                        showDragHandle: true,
                        builder: (_) => PublicContactEditor(
                          loadUser: auth.authService.getCurrentUser,
                          save: auth.updatePublicContact,
                        ),
                      );
                    },
                  ),
                if (currentUser.role == UserRole.maintenanceTechnician)
                  _ProfileTile(
                    icon: Icons.phone_outlined,
                    title: 'Work contact',
                    subtitle:
                        'Manage contact for assigned maintenance requests',
                    onTap: () {
                      final auth = AuthScope.of(context);
                      showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        useSafeArea: true,
                        showDragHandle: true,
                        builder: (_) => PublicContactEditor(
                          maintenance: true,
                          loadUser: auth.authService.getCurrentUser,
                          save: auth.updateMaintenanceContact,
                        ),
                      );
                    },
                  ),
                if (currentUser.role == UserRole.tenant)
                  _ProfileTile(
                    icon: Icons.folder_outlined,
                    title: 'Application documents',
                    subtitle:
                        'View documents attached to your rental applications',
                    onTap:
                        onOpenDocuments ??
                        () {
                          final client = AuthScope.of(
                            context,
                          ).authService.apiClient;
                          Navigator.of(context).push<void>(
                            MaterialPageRoute(
                              builder: (_) => TenantDocumentsScreen(
                                rentalApplicationApiService:
                                    RentalApplicationApiService(client),
                                propertyApiService:
                                    propertyApiService ??
                                    PropertyApiService(client),
                              ),
                            ),
                          );
                        },
                  ),
                if (currentUser.role == UserRole.landlord)
                  _ProfileTile(
                    icon: Icons.star_outline,
                    title: 'Reviews',
                    subtitle: 'Read verified viewing feedback',
                    onTap: onOpenReviews,
                  ),
              ],
            ),
            if (currentUser.role == UserRole.tenant ||
                currentUser.role == UserRole.landlord) ...[
              const SizedBox(height: AppSpacing.lg),
              _ProfileSection(
                title: 'Preferences',
                children: [
                  _ProfileTile(
                    icon: Icons.notifications_none,
                    title: 'Notifications',
                    subtitle: 'Choose the updates you receive',
                    onTap: () => Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => NotificationPreferencesScreen(
                          service: NotificationPreferencesApiService(
                            AuthScope.of(context).authService.apiClient,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (currentUser.role == UserRole.tenant)
                    _ProfileTile(
                      icon: Icons.tune,
                      title: 'Match preferences',
                      subtitle: 'Update preferences used for property matching',
                      onTap: () => Navigator.of(context).push<PreferenceChange>(
                        MaterialPageRoute(
                          builder: (_) => MatchPreferencesScreen(
                            service:
                                propertyApiService ??
                                PropertyApiService(
                                  AuthScope.of(context).authService.apiClient,
                                ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
            if (currentUser.role != UserRole.admin) ...[
              const SizedBox(height: AppSpacing.lg),
              _ProfileSection(
                title: 'Support',
                children: [
                  _ProfileTile(
                    icon: Icons.help_outline,
                    title: 'Help & support',
                    subtitle: 'Send a request and track its status',
                    onTap: () => Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => HelpSupportScreen(
                          service: SupportTicketApiService(
                            AuthScope.of(context).authService.apiClient,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            OutlinedButton.icon(
              key: const Key('profile-sign-out'),
              onPressed: () => AuthScope.of(context).logout(),
              icon: const Icon(Icons.logout, size: 20),
              label: const Text('Sign out'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppPalette.danger,
                side: const BorderSide(color: AppPalette.outline),
              ),
            ),
            const SizedBox(height: AppSpacing.base),
            Text(
              'RentFlow AI v2.4.1 · © 2026',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppPalette.neutral,
                fontSize: AppTypography.captionSize,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }
}

class _ProfileSection extends StatelessWidget {
  const _ProfileSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.only(left: AppSpacing.xs),
        child: Semantics(
          header: true,
          child: Text(
            title,
            style: AppTypography.label.copyWith(color: AppPalette.neutral),
          ),
        ),
      ),
      const SizedBox(height: AppSpacing.sm),
      AppCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            for (var index = 0; index < children.length; index++) ...[
              children[index],
              if (index < children.length - 1)
                const Divider(
                  height: 1,
                  indent: 54,
                  endIndent: AppSpacing.base,
                ),
            ],
          ],
        ),
      ),
    ],
  );
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$title\n$subtitle',
    button: true,
    enabled: onTap != null,
    onTap: onTap,
    excludeSemantics: true,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: AppPalette.olive),
            const SizedBox(width: AppSpacing.base),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTypography.cardTitle.copyWith(
                      color: AppPalette.primaryText,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    subtitle,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppPalette.neutral,
                    ),
                  ),
                ],
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: AppSpacing.sm),
              const Icon(
                Icons.chevron_right,
                size: 20,
                color: AppPalette.neutral,
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

String _availableValue(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? 'Not provided' : trimmed;
}
