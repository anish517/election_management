import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/models.dart';

class DashboardQuickActions extends StatelessWidget {
  final UserModel user;

  const DashboardQuickActions({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    List<_ActionItem> actions = [];

    if (user.isOrgAdmin) {
      actions = [
        _ActionItem(
          icon: Icons.how_to_vote_rounded,
          title: 'Elections',
          subtitle: 'Manage & create elections',
          routeName: 'elections',
          color: AppColors.stateVoting,
        ),
        _ActionItem(
          icon: Icons.people_alt_rounded,
          title: 'Member Directory',
          subtitle: 'Voters & roll verification',
          routeName: 'members',
          color: AppColors.primary,
        ),
        _ActionItem(
          icon: Icons.tune_rounded,
          title: 'Organization Settings',
          subtitle: 'Branding & preferences',
          routeName: 'org-settings',
          color: AppColors.accent,
        ),
      ];
    } else if (user.isElectionOfficer) {
      actions = [
        _ActionItem(
          icon: Icons.how_to_vote_rounded,
          title: 'Assigned Elections',
          subtitle: 'Monitor polling & voting',
          routeName: 'elections',
          color: AppColors.stateVoting,
        ),
        _ActionItem(
          icon: Icons.assignment_ind_rounded,
          title: 'Review Nominations',
          subtitle: 'Scrutinize candidate forms',
          routeName: 'nominations',
          color: AppColors.primaryLight,
        ),
      ];
    } else {
      actions = [
        _ActionItem(
          icon: Icons.how_to_vote_rounded,
          title: 'Active Elections',
          subtitle: 'Browse & cast your vote',
          routeName: 'elections',
          color: AppColors.stateVoting,
        ),
        _ActionItem(
          icon: Icons.history_rounded,
          title: 'Voting History',
          subtitle: 'View receipts & past votes',
          routeName: 'voting-history',
          color: AppColors.primaryLight,
        ),
        _ActionItem(
          icon: Icons.badge_outlined,
          title: 'My Profile',
          subtitle: 'Account details & security',
          routeName: 'profile',
          color: AppColors.accent,
        ),
      ];
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.flash_on_rounded, size: 18, color: AppColors.accent),
            const SizedBox(width: 8),
            Text(
              'Quick Actions',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 650;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: actions.asMap().entries.map((entry) {
                final action = entry.value;
                final width = isWide
                    ? (constraints.maxWidth - (actions.length - 1) * 12) / actions.length
                    : (constraints.maxWidth > 400 ? (constraints.maxWidth - 12) / 2 : constraints.maxWidth);

                return SizedBox(
                  width: width,
                  child: _buildActionCard(context, action)
                      .animate()
                      .fade(delay: Duration(milliseconds: 80 * entry.key))
                      .slideY(begin: 0.1, end: 0, curve: Curves.easeOutQuad),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildActionCard(BuildContext context, _ActionItem action) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: isDark ? AppColors.surface : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () => context.pushNamed(action.routeName),
        borderRadius: BorderRadius.circular(14),
        hoverColor: action.color.withValues(alpha: 0.08),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.shade200,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.02),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: action.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(action.icon, color: action.color, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      action.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      action.subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white54 : Colors.grey.shade600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 12,
                color: isDark ? Colors.white30 : Colors.grey.shade400,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionItem {
  final IconData icon;
  final String title;
  final String subtitle;
  final String routeName;
  final Color color;

  _ActionItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.routeName,
    required this.color,
  });
}


