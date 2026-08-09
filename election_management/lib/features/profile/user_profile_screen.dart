import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/admin_drawer.dart'; // Just for consistency
import '../../shared/widgets/shimmer_loaders.dart';
import '../../shared/widgets/image_upload_widget.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_constants.dart';

class UserProfileScreen extends ConsumerWidget {
  const UserProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: AppColors.error),
            tooltip: 'Logout',
            onPressed: () {
              ref.read(authProvider.notifier).logout();
              context.goNamed('login');
            },
          )
        ],
      ),
      drawer: user?.isOrgAdmin == true ? const AdminDrawer() : null,
      body: user == null 
          ? const Padding(
              padding: EdgeInsets.all(24),
              child: ProfileSkeleton(),
            )
          : Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 600),
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    ImageUploadWidget(
                      initialImageUrl: user.photoUrl,
                      placeholderText: (user.fullName.isNotEmpty ? user.fullName : user.email).substring(0, 2).toUpperCase(),
                      radius: 50,
                      onImageUploaded: (url) async {
                        try {
                          final dio = ref.read(apiClientProvider);
                          await dio.patch(ApiConstants.me, data: {'photo_url': url});
                          ref.read(authProvider.notifier).refreshUser(); // Refresh user profile
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to update profile: $e')));
                          }
                        }
                      },
                    ),
                    const SizedBox(height: 24),
                    Text(
                      user.fullName.isNotEmpty ? user.fullName : user.email,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    if (user.fullName.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        user.email,
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: user.isOrgAdmin ? AppColors.accent.withValues(alpha: 0.2) : AppColors.primaryLight.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: user.isOrgAdmin ? AppColors.accent : AppColors.primaryLight,
                        ),
                      ),
                      child: Text(
                        user.role.toUpperCase(),
                        style: TextStyle(
                          color: user.isOrgAdmin ? AppColors.accent : AppColors.primaryLight,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),
                    _buildInfoTile(context, Icons.badge_rounded, 'Account ID', user.id),
                    _buildInfoTile(context, Icons.phone_rounded, 'Phone', user.phone.isNotEmpty ? user.phone : 'Not provided'),
                    _buildInfoTile(context, Icons.business_rounded, 'Organization', user.organizationName),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildInfoTile(BuildContext context, IconData icon, String title, String value) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surface : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppColors.surfaceVariant : Colors.black.withValues(alpha: 0.05),
        ),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primaryLight.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppColors.primaryLight),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title, 
                  style: TextStyle(
                    color: isDark ? AppColors.textMuted : AppColors.textSecondaryLightMode, 
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(value, style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
