import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/auth_provider.dart';

class AdminDrawer extends ConsumerWidget {
  const AdminDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null || !user.canManageElections) {
      return const SizedBox.shrink(); // Shouldn't be rendered for non-admins anyway
    }

    return Drawer(
      backgroundColor: AppColors.surface,
      child: Column(
        children: [
          UserAccountsDrawerHeader(
            decoration: BoxDecoration(
              color: AppColors.primaryDark,
            ),
            accountName: Text(user.role == 'org_admin' ? 'Organization Admin' : 'Election Officer', style: const TextStyle(fontWeight: FontWeight.bold)),
            accountEmail: Text(user.email),
            currentAccountPicture: const CircleAvatar(
              backgroundColor: AppColors.primary,
              child: Icon(Icons.admin_panel_settings_rounded, color: Colors.white, size: 30),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.dashboard_rounded),
            title: const Text('Dashboard'),
            onTap: () {
              context.pop();
              context.goNamed('dashboard');
            },
          ),
          ListTile(
            leading: const Icon(Icons.how_to_vote_rounded),
            title: const Text('Elections'),
            onTap: () {
              context.pop();
              context.goNamed('elections');
            },
          ),
          if (user.role == 'org_admin')
            ListTile(
              leading: const Icon(Icons.people_alt_rounded),
              title: const Text('Members'),
              onTap: () {
                context.pop();
                context.goNamed('members');
              },
            ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout_rounded, color: AppColors.error),
            title: const Text('Logout', style: TextStyle(color: AppColors.error)),
            onTap: () {
              context.pop();
              ref.read(authProvider.notifier).logout();
            },
          ),
        ],
      ),
    );
  }
}
