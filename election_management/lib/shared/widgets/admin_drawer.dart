import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/network/api_constants.dart';
import '../../core/providers/auth_provider.dart';

class AdminDrawer extends ConsumerWidget {
  final bool isPersistent;
  const AdminDrawer({super.key, this.isPersistent = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null || !user.canManageElections) {
      return const SizedBox.shrink();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentRoute = GoRouterState.of(context).matchedLocation;

    void handleNav(String routeName, String path) {
      if (!isPersistent && Scaffold.of(context).isDrawerOpen) {
        context.pop();
      }
      context.goNamed(routeName);
    }

    String getRoleBadgeText(String role) {
      switch (role.toLowerCase()) {
        case 'superadmin':
          return 'Super Admin';
        case 'org_admin':
          return 'Organization Admin';
        case 'officer':
        case 'election_officer':
          return 'Election Officer';
        case 'auditor':
          return 'Auditor';
        default:
          return 'Administrator';
      }
    }

    return Drawer(
      elevation: 0,
      backgroundColor: isDark ? const Color(0xFF18181B) : Colors.white,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(
              color: isDark ? const Color(0xFF27272A) : const Color(0xFFE4E4E7),
              width: 1,
            ),
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // ══════════════════════════════════════════════════════════
              // EXECUTIVE HEADER & IDENTITY
              // ══════════════════════════════════════════════════════════
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF202024) : const Color(0xFFF8FAFC),
                  border: Border(
                    bottom: BorderSide(
                      color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    // Organization / Admin Avatar
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF4F46E5).withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: user.organizationLogoUrl.isNotEmpty
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(
                                ApiConstants.getFullImageUrl(user.organizationLogoUrl) ?? user.organizationLogoUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (ctx, err, stack) => const Icon(Icons.corporate_fare_rounded, color: Colors.white, size: 22),
                              ),
                            )
                          : const Icon(Icons.corporate_fare_rounded, color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 12),

                    // Admin Role & User Metadata
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              getRoleBadgeText(user.role),
                              style: const TextStyle(
                                color: AppColors.primaryLight,
                                fontWeight: FontWeight.bold,
                                fontSize: 10.5,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            user.fullName.isNotEmpty ? user.fullName : user.email,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            user.email,
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? Colors.white54 : Colors.grey.shade600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // ══════════════════════════════════════════════════════════
              // CATEGORIZED NAVIGATION ITEMS
              // ══════════════════════════════════════════════════════════
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  children: [
                    // Group 1: Workspace
                    _buildSectionHeader('WORKSPACE (कार्यक्षेत्र)', isDark),
                    _buildNavItem(
                      context,
                      title: 'Dashboard',
                      icon: Icons.dashboard_rounded,
                      isActive: currentRoute == '/dashboard' || currentRoute == '/',
                      onTap: () => handleNav('dashboard', '/dashboard'),
                      isDark: isDark,
                    ),
                    _buildNavItem(
                      context,
                      title: 'Elections',
                      icon: Icons.how_to_vote_rounded,
                      isActive: currentRoute.startsWith('/elections'),
                      onTap: () => handleNav('elections', '/elections'),
                      isDark: isDark,
                    ),

                    // Group 2: Management
                    if (user.role == 'org_admin' || user.role == 'superadmin' || user.role == 'election_officer') ...[
                      const SizedBox(height: 12),
                      _buildSectionHeader('FINANCE & PAYMENTS (भुक्तानी व्यवस्थापन)', isDark),
                      _buildNavItem(
                        context,
                        title: 'Payment History & Ledger',
                        icon: Icons.receipt_long_rounded,
                        isActive: currentRoute.contains('/admin/payments') || currentRoute.contains('payments'),
                        onTap: () => handleNav('admin-payments', '/admin/payments'),
                        isDark: isDark,
                      ),
                      if (user.role == 'org_admin' || user.role == 'superadmin')
                        _buildNavItem(
                          context,
                          title: 'Payment QR & Settings',
                          icon: Icons.qr_code_2_rounded,
                          isActive: currentRoute.contains('payment-settings'),
                          onTap: () => handleNav('payment-settings', '/payment-settings'),
                          isDark: isDark,
                        ),
                    ],

                    // Group 3: Management
                    if (user.role == 'org_admin' || user.role == 'superadmin') ...[
                      const SizedBox(height: 12),
                      _buildSectionHeader('MANAGEMENT (व्यवस्थापन)', isDark),
                      _buildNavItem(
                        context,
                        title: 'Organization Settings',
                        icon: Icons.tune_rounded,
                        isActive: currentRoute.contains('org-settings'),
                        onTap: () => handleNav('org-settings', '/org-settings'),
                        isDark: isDark,
                      ),
                      _buildNavItem(
                        context,
                        title: 'Election Rules',
                        icon: Icons.gavel_rounded,
                        isActive: currentRoute.contains('rules'),
                        onTap: () => handleNav('election-rules', '/election-rules'),
                        isDark: isDark,
                      ),
                    ],

                    // Group 3: Account
                    const SizedBox(height: 12),
                    _buildSectionHeader('ACCOUNT (खाता)', isDark),
                    _buildNavItem(
                      context,
                      title: 'My Profile',
                      icon: Icons.person_outline_rounded,
                      isActive: currentRoute.startsWith('/profile'),
                      onTap: () => handleNav('profile', '/profile'),
                      isDark: isDark,
                    ),
                  ],
                ),
              ),

              // ══════════════════════════════════════════════════════════
              // FOOTER & LOGOUT
              // ══════════════════════════════════════════════════════════
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E1E22) : const Color(0xFFFAFAFA),
                  border: Border(
                    top: BorderSide(
                      color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
                    ),
                  ),
                ),
                child: Column(
                  children: [
                    InkWell(
                      onTap: () {
                        if (!isPersistent && Scaffold.of(context).isDrawerOpen) {
                          context.pop();
                        }
                        ref.read(authProvider.notifier).logout();
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: isDark ? 0.12 : 0.06),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.logout_rounded, color: Colors.redAccent, size: 18),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Sign Out (लगआउट)',
                                style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 12.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'EMS Secure Electoral Suite • v2.4',
                      style: TextStyle(fontSize: 10, color: isDark ? Colors.white30 : Colors.grey.shade400),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(left: 12, top: 8, bottom: 6),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.8,
          color: isDark ? Colors.white38 : Colors.grey.shade500,
        ),
      ),
    );
  }

  Widget _buildNavItem(
    BuildContext context, {
    required String title,
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isActive
                ? AppColors.primary.withValues(alpha: isDark ? 0.2 : 0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isActive
                  ? AppColors.primary.withValues(alpha: 0.35)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: isActive
                    ? AppColors.primaryLight
                    : (isDark ? Colors.white70 : Colors.grey.shade700),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                    color: isActive
                        ? AppColors.primaryLight
                        : (isDark ? Colors.white : Colors.black87),
                  ),
                ),
              ),
              if (isActive)
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: AppColors.primaryLight,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
