import 'dart:ui';
import 'package:flutter/material.dart';import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/org_providers.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/admin_drawer.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/shimmer_loaders.dart';
import '../../shared/widgets/responsive_layout.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dashboard_quick_actions.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final electionsAsync = ref.watch(electionsProvider);

    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      drawer: (user != null && user.canManageElections) ? const AdminDrawer() : null,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            border: Border(bottom: BorderSide(color: isDark ? const Color(0xFF27272A) : const Color(0xFFE4E4E7))),
          ),
          child: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            centerTitle: false,
            leading: (user != null && user.canManageElections) 
              ? Builder(
                  builder: (context) => IconButton(
                    icon: const Icon(Icons.menu_rounded),
                    onPressed: () => Scaffold.of(context).openDrawer(),
                  ),
                )
              : null,
            title: Row(
              children: [
                if (user?.organizationLogoUrl.isNotEmpty == true) ...[
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.white,
                    backgroundImage: NetworkImage(user!.organizationLogoUrl),
                  ),
                  const SizedBox(width: 12),
                ],
                Text(user?.organizationName ?? 'Dashboard', 
                     style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              ],
            ).animate().fade().slideX(begin: -0.1, duration: 400.ms),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 20),
                onPressed: () => ref.invalidate(electionsProvider),
              ).animate().fade().scale(delay: 200.ms),
              PopupMenuButton(
                offset: const Offset(0, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: isDark ? const Color(0xFF27272A) : const Color(0xFFE4E4E7)),
                ),
                color: Theme.of(context).cardTheme.color,
                elevation: 4,
                icon: CircleAvatar(
                  radius: 16,
                  backgroundColor: AppColors.primary,
                  backgroundImage: user?.photoUrl.isNotEmpty == true ? NetworkImage(user!.photoUrl) : null,
                  child: user?.photoUrl.isNotEmpty == true 
                      ? null 
                      : Text(
                          ((user?.fullName.isNotEmpty == true) ? user!.fullName : ((user?.email.isNotEmpty == true) ? user!.email : '?')).substring(0, 1).toUpperCase(),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                ),
                itemBuilder: (_) => <PopupMenuEntry<dynamic>>[
                  PopupMenuItem(
                    child: Row(children: [
                      Icon(Icons.history_rounded, size: 18, color: Theme.of(context).iconTheme.color),
                      const SizedBox(width: 10),
                      const Text('My Voting History'),
                    ]),
                    onTap: () => context.pushNamed('voting-history'),
                  ),
                  PopupMenuItem(
                    child: Row(children: [
                      Icon(Icons.person_rounded, size: 18, color: Theme.of(context).iconTheme.color),
                      const SizedBox(width: 10),
                      const Text('My Profile'),
                    ]),
                    onTap: () => context.pushNamed('profile'),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    child: const Row(children: [
                      Icon(Icons.logout_rounded, size: 18, color: AppColors.error),
                      SizedBox(width: 10),
                      Text('Logout', style: TextStyle(color: AppColors.error)),
                    ]),
                    onTap: () async => await ref.read(authProvider.notifier).logout(),
                  ),
                ],
              ).animate().fade().scale(delay: 300.ms),
              const SizedBox(width: 16),
            ],
          ),
        ),
      ),
      body: ResponsivePageWrapper(
        child: RefreshIndicator(
          onRefresh: () async => ref.invalidate(electionsProvider),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (user != null) DashboardQuickActions(user: user),
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
              Expanded(child: _buildStatCard(context, 'Members', stats.totalMembers.toString(), Icons.people_alt_rounded)),
              const SizedBox(width: 12),
              Expanded(child: _buildStatCard(context, 'Active', stats.activeElections.toString(), Icons.how_to_vote_rounded)),
              const SizedBox(width: 12),
              Expanded(child: _buildStatCard(context, 'Total', stats.totalElections.toString(), Icons.inventory_2_rounded)),
            ],
          ).animate().fade(duration: 400.ms, delay: 100.ms).slideY(begin: 0.1, end: 0, curve: Curves.easeOutQuad),
        ),
      ],
    );
  }

  Widget _buildStatCard(BuildContext context, String title, String value, IconData icon) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Theme.of(context).iconTheme.color, size: 24),
            const SizedBox(height: 12),
            Text(value, style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 4),
            Text(title, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
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
      return GlassCard(
        padding: const EdgeInsets.all(32),
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
      ).animate().fade().scale(curve: Curves.easeOutBack);
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: elections.length > 5 ? 5 : elections.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) => _ElectionCard(election: elections[i])
          .animate()
          .fade(delay: Duration(milliseconds: 50 * i))
          .slideY(begin: 0.1, end: 0, curve: Curves.easeOutQuad),
    );
  }

  Widget _buildShimmerList() {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 3,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, __) => const GlassCard(
        padding: EdgeInsets.all(16),
        child: SizedBox(height: 90),
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
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: () => context.pushNamed('election-detail',
            pathParameters: {'electionId': election.id}),
      child: Padding(
        padding: const EdgeInsets.all(16),
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
            if (election.state == 'voting_open')
              Container(
                margin: const EdgeInsets.only(right: 12),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.how_to_vote, size: 14, color: Colors.white),
                    SizedBox(width: 4),
                    Text('VOTE NOW', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                  ],
                ),
              ).animate(onPlay: (controller) => controller.repeat(reverse: true)).fade(begin: 0.8, end: 1.0).scaleXY(begin: 0.98, end: 1.02),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
          ],
        ),
      ),
    ),
  );
}

  Color _stateColor(String state) {
    switch (state) {
      case 'draft': return AppColors.stateDraft;
      case 'published': return AppColors.statePublished;
      case 'nominations_open': case 'nominations_closed': return AppColors.stateNominations;
      case 'voting_open': return AppColors.stateVoting;
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
      case 'voting_open': return Icons.how_to_vote_rounded;
      case 'voting_closed': return Icons.lock_outline_rounded;
      case 'results_provisional': case 'results_final': return Icons.emoji_events_outlined;
      default: return Icons.circle_outlined;
    }
  }

  String _stateLabel(String state) {
    return state.replaceAll('_', ' ').toUpperCase();
  }
}
