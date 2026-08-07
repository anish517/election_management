import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/org_providers.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/admin_drawer.dart';
import '../../shared/widgets/shimmer_loaders.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final electionsAsync = ref.watch(electionsProvider);

    return Scaffold(
      drawer: (user != null && user.canManageElections) ? const AdminDrawer() : null,
      appBar: AppBar(
        leading: (user != null && user.canManageElections) 
          ? Builder(
              builder: (context) => IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () => Scaffold.of(context).openDrawer(),
              ),
            )
          : null,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Welcome, ${user?.organizationName ?? ''}',
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            Text(user?.email ?? '', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(electionsProvider),
          ),
          PopupMenuButton(
            icon: const CircleAvatar(
              backgroundColor: AppColors.primaryLight,
              child: Icon(Icons.person, color: Colors.white, size: 18),
            ),
            itemBuilder: (_) => [
              PopupMenuItem(
                child: const Row(children: [
                  Icon(Icons.history_rounded, size: 18),
                  SizedBox(width: 10),
                  Text('My Voting History'),
                ]),
                onTap: () {
                  context.pushNamed('voting-history');
                },
              ),
              PopupMenuItem(
                child: const Row(children: [
                  Icon(Icons.person_rounded, size: 18),
                  SizedBox(width: 10),
                  Text('My Profile'),
                ]),
                onTap: () {
                  context.pushNamed('profile');
                },
              ),
              PopupMenuItem(
                child: const Row(children: [
                  Icon(Icons.logout_rounded, size: 18),
                  SizedBox(width: 10),
                  Text('Logout'),
                ]),
                onTap: () async {
                  await ref.read(authProvider.notifier).logout();
                },
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(electionsProvider),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildRoleBanner(context, user),
              if (user != null && user.role == 'org_admin') ...[
                const SizedBox(height: 24),
                _buildOverviewSection(context, ref),
              ],
              const SizedBox(height: 24),
              _buildSectionHeader(context, 'Your Elections', Icons.how_to_vote_rounded,
                  onTap: () => context.pushNamed('elections')),
              const SizedBox(height: 12),
              electionsAsync.when(
                loading: () => _buildShimmerList(),
                error: (e, _) => _buildError(e.toString(), () => ref.invalidate(electionsProvider)),
                data: (elections) => _buildElectionList(context, elections, user),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: (user != null && user.isOrgAdmin)
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/elections/new'),
              icon: const Icon(Icons.add),
              label: const Text('New Election'),
              backgroundColor: AppColors.primary,
            )
          : null,
    );
  }

  Widget _buildRoleBanner(BuildContext context, UserModel? user) {
    if (user == null) return const SizedBox.shrink();
    Color color;
    String roleLabel;
    IconData icon;
    switch (user.role) {
      case 'org_admin':
        color = AppColors.primaryLight; roleLabel = 'Organization Admin'; icon = Icons.admin_panel_settings_rounded;
      case 'election_officer':
        color = AppColors.accent; roleLabel = 'Election Officer'; icon = Icons.manage_accounts_rounded;
      case 'observer':
        color = AppColors.warning; roleLabel = 'Observer'; icon = Icons.visibility_rounded;
      default:
        color = AppColors.success; roleLabel = 'Voter'; icon = Icons.how_to_vote_rounded;
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.15), color.withValues(alpha: 0.05)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.2), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(roleLabel, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 15)),
              Text(user.organizationName, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewSection(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(orgStatsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(context, 'Organization Overview', Icons.insights_rounded),
        const SizedBox(height: 12),
        statsAsync.when(
          loading: () => const DashboardSkeleton(),
          error: (e, _) => Text('Error loading stats: $e'),
          data: (stats) => Row(
            children: [
              Expanded(child: _buildStatCard(context, 'Members', stats.totalMembers.toString(), Icons.people_alt_rounded, AppColors.primary)),
              const SizedBox(width: 12),
              Expanded(child: _buildStatCard(context, 'Active Elections', stats.activeElections.toString(), Icons.how_to_vote_rounded, AppColors.stateVoting)),
              const SizedBox(width: 12),
              Expanded(child: _buildStatCard(context, 'Total Elections', stats.totalElections.toString(), Icons.inventory_2_rounded, AppColors.textSecondary)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(BuildContext context, String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 12),
          Text(value, style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: color, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(title, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title, IconData icon,
      {VoidCallback? onTap}) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primaryLight, size: 20),
        const SizedBox(width: 8),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const Spacer(),
        if (onTap != null)
          TextButton(onPressed: onTap, child: const Text('See All')),
      ],
    );
  }

  Widget _buildElectionList(BuildContext context, List<ElectionModel> elections, UserModel? user) {
    if (elections.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            const Icon(Icons.ballot_outlined, size: 48, color: AppColors.textMuted),
            const SizedBox(height: 16),
            Text('No elections yet', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              user?.canManageElections == true
                  ? 'Create your first election to get started.'
                  : 'No elections have been created for your organization.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: elections.length > 5 ? 5 : elections.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) => _ElectionCard(election: elections[i]),
    );
  }

  Widget _buildShimmerList() {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 3,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, __) => Container(
        height: 90,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }

  Widget _buildError(String message, VoidCallback onRetry) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 32),
          const SizedBox(height: 8),
          Text('Failed to load elections', style: TextStyle(color: AppColors.error)),
          const SizedBox(height: 8),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _ElectionCard extends StatelessWidget {
  final ElectionModel election;
  const _ElectionCard({required this.election});

  @override
  Widget build(BuildContext context) {
    final stateColor = _stateColor(election.state);
    return InkWell(
      onTap: () => context.pushNamed('election-detail',
          pathParameters: {'electionId': election.id}),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.surfaceVariant),
        ),
        child: Row(
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: stateColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(_stateIcon(election.state), color: stateColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(election.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 15),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: stateColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _stateLabel(election.state),
                          style: TextStyle(color: stateColor, fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('${election.positions.length} position(s)',
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }

  Color _stateColor(String state) {
    switch (state) {
      case 'draft': return AppColors.stateDraft;
      case 'published': return AppColors.statePublished;
      case 'nominations_open': case 'nominations_closed': return AppColors.stateNominations;
      case 'voting_active': return AppColors.stateVoting;
      case 'voting_closed': return AppColors.stateClosed;
      case 'results_provisional': case 'results_final': return AppColors.stateResults;
      default: return AppColors.textMuted;
    }
  }

  IconData _stateIcon(String state) {
    switch (state) {
      case 'draft': return Icons.edit_outlined;
      case 'published': return Icons.public_rounded;
      case 'nominations_open': case 'nominations_closed': return Icons.person_add_alt_1_outlined;
      case 'voting_active': return Icons.how_to_vote_rounded;
      case 'voting_closed': return Icons.lock_outline_rounded;
      case 'results_provisional': case 'results_final': return Icons.emoji_events_outlined;
      default: return Icons.circle_outlined;
    }
  }

  String _stateLabel(String state) {
    return state.replaceAll('_', ' ').toUpperCase();
  }
}
