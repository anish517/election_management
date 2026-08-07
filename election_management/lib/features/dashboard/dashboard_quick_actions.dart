import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/models.dart';

class DashboardQuickActions extends StatelessWidget {
  final UserModel user;

  const DashboardQuickActions({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    List<Widget> actions = [];

    if (user.isOrgAdmin) {
      actions = [
        _buildAction(context, Icons.how_to_vote, 'Elections', 'elections', AppColors.stateVoting),
        _buildAction(context, Icons.people, 'Members', 'members', AppColors.primaryLight),
        _buildAction(context, Icons.settings, 'Settings', 'org-settings', AppColors.accent),
      ];
    } else if (user.isElectionOfficer) {
      actions = [
        _buildAction(context, Icons.how_to_vote, 'Elections', 'elections', AppColors.stateVoting),
        _buildAction(context, Icons.person_add, 'Nominations', 'nominations', AppColors.primaryLight),
      ];
    } else {
      actions = [
        _buildAction(context, Icons.history, 'History', 'voting-history', AppColors.primaryLight),
      ];
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Quick Actions', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: actions.map((action) => Padding(
            padding: const EdgeInsets.only(right: 16),
            child: action,
          )).toList(),
        ),
      ],
    );
  }

  Widget _buildAction(BuildContext context, IconData icon, String label, String routeName, Color color) {
    return InkWell(
      onTap: () => context.pushNamed(routeName),
      borderRadius: BorderRadius.circular(12),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withValues(alpha: 0.2)),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
