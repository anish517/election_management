import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/auth_provider.dart';

class AdminDrawer extends ConsumerWidget {
  final bool isPersistent;
  const AdminDrawer({super.key, this.isPersistent = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null || !user.canManageElections) {
      return const SizedBox.shrink(); // Shouldn't be rendered for non-admins anyway
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    void handleNav(String routeName) {
      if (!isPersistent && Scaffold.of(context).isDrawerOpen) {
        context.pop();
      }
      context.goNamed(routeName);
    }

    return Drawer(
      elevation: 0,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(
              color: isDark ? const Color(0xFF27272A) : const Color(0xFFE4E4E7),
            ),
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05))),
                    ),
                    child: Row(
                      children: [
                        user.organizationLogoUrl.isNotEmpty
                            ? CircleAvatar(
                                radius: 24,
                                backgroundColor: Colors.white,
                                backgroundImage: NetworkImage(user.organizationLogoUrl),
                              )
                            : Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  gradient: AppColors.primaryGradient,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(Icons.business_rounded, color: Colors.white, size: 24),
                              ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(user.role == 'org_admin' ? 'Organization Admin' : 'Election Officer', 
                                   style: Theme.of(context).textTheme.titleSmall?.copyWith(color: AppColors.primaryLight, fontWeight: FontWeight.bold)),
                              Text(user.email, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary), overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      children: [
                        _buildNavItem(context, 'Dashboard', Icons.dashboard_rounded, () => handleNav('dashboard')),
                        _buildNavItem(context, 'Elections', Icons.how_to_vote_rounded, () => handleNav('elections')),
                        if (user.role == 'org_admin')
                          _buildNavItem(context, 'Members', Icons.people_alt_rounded, () => handleNav('members')),
                        if (user.role == 'org_admin')
                          _buildNavItem(context, 'Settings', Icons.settings_applications_rounded, () => handleNav('org-settings')),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Divider(color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05)),
                        ),
                        _buildNavItem(context, 'My Profile', Icons.person_rounded, () => handleNav('profile')),
                        _buildNavItem(context, 'Logout', Icons.logout_rounded, () {
                          if (!isPersistent && Scaffold.of(context).isDrawerOpen) context.pop();
                          ref.read(authProvider.notifier).logout();
                        }, isDestructive: true),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }

  Widget _buildNavItem(BuildContext context, String title, IconData icon, VoidCallback onTap, {bool isDestructive = false}) {
    final color = isDestructive ? AppColors.error : AppColors.textPrimary;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: Icon(icon, color: isDestructive ? color : (isDark ? AppColors.textSecondary : AppColors.textSecondaryLightMode)),
        title: Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: isDestructive ? color : null)),
        hoverColor: (isDestructive ? AppColors.error : AppColors.primaryLight).withValues(alpha: 0.1),
        onTap: onTap,
      ),
    );
  }
}
