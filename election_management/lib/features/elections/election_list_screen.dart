import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/admin_drawer.dart';
import '../../shared/widgets/shimmer_loaders.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/responsive_layout.dart';
import '../../shared/widgets/glass_card.dart';

class ElectionListScreen extends ConsumerWidget {
  const ElectionListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final electionsAsync = ref.watch(electionsProvider);
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      drawer: (user != null && user.canManageElections) ? const AdminDrawer() : null,
      appBar: AppBar(
        title: const Text('Elections'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/dashboard');
            }
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(electionsProvider),
          ),
        ],
      ),
      body: ResponsivePageWrapper(
        child: electionsAsync.when(
          loading: () => const CardListSkeleton(count: 5),
          error: (e, _) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 40),
                const SizedBox(height: 12),
                Text('Failed to load elections', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: () => ref.invalidate(electionsProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
          data: (elections) {
            if (elections.isEmpty) {
              return EmptyStateWidget(
                icon: Icons.ballot_outlined,
                title: 'No Elections Yet',
                subtitle: 'Elections created by your admin will appear here.',
              );
            }
            return RefreshIndicator(
              onRefresh: () async => ref.invalidate(electionsProvider),
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: elections.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, i) => _ElectionListTile(election: elections[i], user: user),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ElectionListTile extends StatelessWidget {
  final ElectionModel election;
  final UserModel? user;
  const _ElectionListTile({required this.election, this.user});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final stateColor = _stateColor(election.state, isDark);

    return GlassCard(
      padding: EdgeInsets.zero,
      onTap: () => context.pushNamed('election-detail',
          pathParameters: {'electionId': election.id}),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (election.logoUrl.isNotEmpty) ...[
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF27272A) : const Color(0xFFF4F4F5),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Theme.of(context).dividerColor),
                      image: DecorationImage(
                        image: NetworkImage(election.logoUrl),
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (election.prefix.isNotEmpty) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                election.prefix,
                                style: const TextStyle(
                                  color: AppColors.primaryLight,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Expanded(
                            child: Text(
                              election.title,
                              style: Theme.of(context).textTheme.titleMedium,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      if (election.contactNumber.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.phone_outlined, size: 12, color: AppColors.textMuted),
                            const SizedBox(width: 4),
                            Text(
                              election.contactNumber,
                              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _StateBadge(state: election.state, color: stateColor),
              ],
            ),
            if (election.description.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(election.description,
                  style: Theme.of(context).textTheme.bodyMedium,
                  maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                _InfoChip(icon: Icons.work_outline_rounded,
                    label: '${election.positions.length} Position(s)'),
                const SizedBox(width: 8),
                if (election.isSecretBallot)
                  const _InfoChip(icon: Icons.lock_outline_rounded, label: 'Secret Ballot'),
              ],
            ),
            // Voting active — show CTA
            if (election.isVotingActive) ...[
              const SizedBox(height: 14),
              ElevatedButton.icon(
                onPressed: () => context.pushNamed('ballot',
                    pathParameters: {'electionId': election.id}),
                icon: const Icon(Icons.how_to_vote_rounded, size: 18),
                label: const Text('Vote Now'),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.stateVoting),
              ),
            ],
            if (election.hasResults) ...[
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: () => context.pushNamed('results',
                    pathParameters: {'electionId': election.id}),
                icon: const Icon(Icons.emoji_events_outlined, size: 18),
                label: const Text('View Results'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _stateColor(String state, bool isDark) {
    switch (state) {
      case 'draft': return isDark ? AppColors.stateDraft : AppColors.textMutedLightMode;
      case 'published': return AppColors.statePublished;
      case 'nominations_open': case 'nominations_closed': return AppColors.stateNominations;
      case 'voting_open': return AppColors.stateVoting;
      case 'voting_closed': return AppColors.stateClosed;
      case 'results_provisional': case 'results_final': return AppColors.stateResults;
      default: return isDark ? AppColors.textMuted : AppColors.textMutedLightMode;
    }
  }
}

class _StateBadge extends StatelessWidget {
  final String state;
  final Color color;
  const _StateBadge({required this.state, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        state.replaceAll('_', ' ').toUpperCase(),
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? AppColors.surfaceVariant : AppColors.surfaceVariantLight;
    final textColor = isDark ? AppColors.textMuted : AppColors.textSecondaryLightMode;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: textColor),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: textColor, fontSize: 12)),
        ],
      ),
    );
  }
}
