import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/network/api_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/admin_drawer.dart';
import '../../shared/widgets/shimmer_loaders.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/responsive_layout.dart';
import 'package:flutter_animate/flutter_animate.dart';

class ElectionListScreen extends ConsumerStatefulWidget {
  const ElectionListScreen({super.key});

  @override
  ConsumerState<ElectionListScreen> createState() => _ElectionListScreenState();
}

class _ElectionListScreenState extends ConsumerState<ElectionListScreen> {
  String _searchQuery = '';
  String _selectedFilter = 'all';

  @override
  Widget build(BuildContext context) {
    final electionsAsync = ref.watch(electionsProvider);
    final user = ref.watch(currentUserProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final isOrgAdmin = user != null && (user.isOrgAdmin || user.role == 'super_admin');
    final isAdmin = user != null && user.canManageElections;
    final isVoterLike = !isAdmin;

    return Scaffold(
      drawer: isAdmin ? const AdminDrawer() : null,
      appBar: AppBar(
        title: const Text('Elections Directory'),
        leading: isOrgAdmin
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_rounded),
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/dashboard');
                  }
                },
              )
            : null,
        actions: [
          if (isVoterLike) ...[
            IconButton(
              icon: const Icon(Icons.history_rounded),
              tooltip: 'Voting History',
              onPressed: () => context.pushNamed('voting-history'),
            ),
          ],
          if (!isOrgAdmin)
            IconButton(
              icon: const Icon(Icons.logout_rounded),
              tooltip: 'Logout',
              onPressed: () async {
                await ref.read(authProvider.notifier).logout();
              },
            ),
          IconButton(
            tooltip: 'Refresh',
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
                subtitle: isOrgAdmin
                    ? 'Create your first election to get started.'
                    : 'No elections have been scheduled for your organization.',
              );
            }

            // Filter logic
            final filtered = elections.where((e) {
              final query = _searchQuery.toLowerCase().trim();
              final matchesQuery = query.isEmpty ||
                  e.title.toLowerCase().contains(query) ||
                  e.prefix.toLowerCase().contains(query);

              if (!matchesQuery) return false;

              if (_selectedFilter == 'all') return true;
              if (_selectedFilter == 'voting_open') return e.state == 'voting_open';
              if (_selectedFilter == 'nominations') {
                return e.state == 'nomination_open' ||
                    e.state == 'nomination_closed' ||
                    e.state == 'nominations_open' ||
                    e.state == 'nominations_closed';
              }
              if (_selectedFilter == 'results') {
                return e.state == 'results_provisional' || e.state == 'results_final' || e.state == 'voting_closed';
              }
              if (_selectedFilter == 'draft') return e.state == 'draft' || e.state == 'published';
              return true;
            }).toList();

            return RefreshIndicator(
              onRefresh: () async => ref.invalidate(electionsProvider),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                children: [
                  // Search & Filter Header
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.surface : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.shade200,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.02),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: TextField(
                      decoration: const InputDecoration(
                        hintText: 'Search elections by title or prefix...',
                        prefixIcon: Icon(Icons.search_rounded, size: 20),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 12),
                      ),
                      onChanged: (val) => setState(() => _searchQuery = val),
                    ),
                  ),

                  // Filter Chips
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Row(
                      children: [
                        _buildFilterChip('all', 'All Elections (${elections.length})'),
                        const SizedBox(width: 8),
                        _buildFilterChip('voting_open', '🗳️ Voting Active'),
                        const SizedBox(width: 8),
                        _buildFilterChip('nominations', '📝 Nominations'),
                        const SizedBox(width: 8),
                        _buildFilterChip('results', '🏆 Results Ready'),
                        if (isAdmin) ...[
                          const SizedBox(width: 8),
                          _buildFilterChip('draft', '📋 Draft / Published'),
                        ],
                      ],
                    ),
                  ),

                  if (filtered.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(Icons.search_off_rounded, size: 48, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            const Text('No elections match your filter.', style: TextStyle(color: Colors.grey, fontSize: 15)),
                          ],
                        ),
                      ),
                    )
                  else
                    ...filtered.asMap().entries.map(
                          (entry) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _ElectionListTile(
                              election: entry.value,
                              user: user,
                              isDark: isDark,
                            )
                            .animate()
                            .fade(delay: Duration(milliseconds: 40 * entry.key))
                            .slideY(begin: 0.08, end: 0, curve: Curves.easeOutQuad),
                          ),
                        ),
                ],
              ),
            );
          },
        ),
      ),
      floatingActionButton: (user != null && user.isOrgAdmin)
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/elections/new'),
              icon: const Icon(Icons.add_rounded),
              label: const Text('New Election', style: TextStyle(fontWeight: FontWeight.bold)),
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 4,
            )
          : null,
    );
  }

  Widget _buildFilterChip(String key, String label) {
    final isSelected = _selectedFilter == key;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return FilterChip(
      selected: isSelected,
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected
              ? Colors.white
              : (isDark ? Colors.white70 : Colors.grey.shade800),
        ),
      ),
      selectedColor: AppColors.primary,
      backgroundColor: isDark ? AppColors.surface : Colors.white,
      side: BorderSide(
        color: isSelected
            ? AppColors.primary
            : (isDark ? Colors.white12 : Colors.grey.shade300),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      onSelected: (_) => setState(() => _selectedFilter = key),
    );
  }
}

class _ElectionListTile extends StatelessWidget {
  final ElectionModel election;
  final UserModel? user;
  final bool isDark;

  const _ElectionListTile({
    required this.election,
    this.user,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final stateColor = _stateColor(election.state, isDark);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surface : Colors.white,
        borderRadius: BorderRadius.circular(16),
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
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => context.pushNamed(
            'election-detail',
            pathParameters: {'electionId': election.id},
          ),
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
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF27272A) : const Color(0xFFF4F4F5),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark ? Colors.white12 : Colors.grey.shade300,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(11),
                          child: Image.network(
                            ApiConstants.getFullImageUrl(election.logoUrl) ?? election.logoUrl,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) => Center(
                              child: Icon(
                                Icons.how_to_vote_rounded,
                                color: isDark ? Colors.white54 : AppColors.primary,
                                size: 24,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (election.prefix.isNotEmpty) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    election.prefix,
                                    style: const TextStyle(
                                      color: AppColors.primaryLight,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                              ],
                              Expanded(
                                child: Text(
                                  election.title,
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: -0.2,
                                      ),
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
                    const SizedBox(width: 10),
                    _StateBadge(state: election.state, color: stateColor),
                  ],
                ),
                if (election.description.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    election.description,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white70 : Colors.grey.shade700,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _InfoChip(
                      icon: election.isVenueElection ? Icons.storefront_rounded : Icons.language_rounded,
                      label: election.isVenueElection
                          ? (election.venueName.isNotEmpty ? 'Venue: ${election.venueName}' : 'Physical Venue')
                          : election.onlineType == 'mobile_app'
                              ? 'Mobile App'
                              : election.onlineType == 'web_based'
                                  ? 'Web-Based'
                                  : 'Hybrid',
                    ),
                    _InfoChip(
                      icon: Icons.work_outline_rounded,
                      label: '${election.positions.length} Position(s)',
                    ),
                    if (election.isSecretBallot)
                      const _InfoChip(
                        icon: Icons.lock_outline_rounded,
                        label: 'Secret Ballot',
                      ),
                    if (election.isPaidCandidacy)
                      const _InfoChip(
                        icon: Icons.payments_outlined,
                        label: 'Paid Nomination',
                      ),
                  ],
                ),

                // Active Buttons
                if (election.isVotingActive && user != null && !user!.canManageElections && !user!.isObserver && !user!.isAuditor) ...[
                  const SizedBox(height: 14),
                  if (election.isVenueElection)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.purple.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.purple.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.storefront_rounded, color: Colors.purple, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'In-Person Booth Voting ${election.venueName.isNotEmpty ? "at ${election.venueName}" : "at Venue"} (भौतिक मतदान मात्र)',
                              style: const TextStyle(color: Colors.purple, fontWeight: FontWeight.bold, fontSize: 12.5),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (election.isWebBasedOnly)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.mark_email_read_rounded, color: Colors.blue, size: 18),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Web Single-Use Ballot Link (इमेल लिङ्क मार्फत मतदान)',
                              style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 12.5),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (kIsWeb && election.onlineType == 'mobile_app')
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.phone_android_rounded, color: Colors.blue, size: 18),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Mobile App Only (मोबाइल एपबाट मात्र मतदान सम्भव छ)',
                              style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 12.5),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => context.pushNamed(
                          'ballot',
                          pathParameters: {'electionId': election.id},
                        ),
                        icon: const Icon(Icons.how_to_vote_rounded, size: 18),
                        label: const Text('Vote Now (मतदान गर्नुहोस्)', style: TextStyle(fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.stateVoting,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                ],
                if (election.hasResults) ...[
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => context.pushNamed(
                        'results',
                        pathParameters: {'electionId': election.id},
                      ),
                      icon: const Icon(Icons.emoji_events_outlined, size: 18),
                      label: const Text('View Results (नतिजा हेर्नुहोस्)', style: TextStyle(fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _stateColor(String state, bool isDark) {
    switch (state) {
      case 'draft':
        return isDark ? AppColors.stateDraft : AppColors.textMutedLightMode;
      case 'published':
        return AppColors.statePublished;
      case 'nominations_open':
      case 'nominations_closed':
        return AppColors.stateNominations;
      case 'voting_open':
        return AppColors.stateVoting;
      case 'voting_closed':
        return AppColors.stateClosed;
      case 'results_provisional':
      case 'results_final':
        return AppColors.stateResults;
      default:
        return isDark ? AppColors.textMuted : AppColors.textMutedLightMode;
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
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800),
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
          Text(label, style: TextStyle(color: textColor, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
