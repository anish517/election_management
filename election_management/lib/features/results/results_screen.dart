import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/network/api_constants.dart';
import '../../core/network/api_client.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/admin_providers.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/shimmer_loaders.dart';
import '../../shared/widgets/responsive_layout.dart';

class ResultsScreen extends ConsumerStatefulWidget {
  final String electionId;
  const ResultsScreen({super.key, required this.electionId});

  @override
  ConsumerState<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends ConsumerState<ResultsScreen> {
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    // Smart Polling: Refresh results every 5 seconds for near real-time dashboard
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      ref.invalidate(resultsProvider(widget.electionId));
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final resultsAsync = ref.watch(resultsProvider(widget.electionId));
    final electionAsync = ref.watch(electionProvider(widget.electionId));
    final user = ref.watch(currentUserProvider);

    final election = electionAsync.valueOrNull;
    final isLive = election?.state == 'voting_open';

    return Scaffold(
      appBar: AppBar(
        title: Text(isLive ? 'Live Tally 🔴' : 'Election Results'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => context.pop(),
        ),
        actions: [
          if (user != null && user.canManageElections)
            IconButton(
              icon: const Icon(Icons.bar_chart_rounded),
              tooltip: 'Live Analytics',
              onPressed: () => context.pushNamed('analytics',
                  pathParameters: {'electionId': widget.electionId}),
            ),
          if (!isLive)
            IconButton(
              icon: const Icon(Icons.download_rounded),
              tooltip: 'Download CSV Report',
              onPressed: () async {
                final token = await JwtInterceptor.getAccessToken();
                final url = Uri.parse('${ApiConstants.baseUrl}/elections/${widget.electionId}/results/export_csv/?token=$token');
                if (await canLaunchUrl(url)) {
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                } else {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not launch export URL')));
                  }
                }
              },
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              ref.invalidate(resultsProvider(widget.electionId));
              ref.invalidate(electionProvider(widget.electionId));
            },
          ),
        ],
      ),
      body: resultsAsync.when(
        loading: () => const ListSkeleton(count: 4),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.bar_chart_rounded, color: AppColors.textMuted, size: 48),
              const SizedBox(height: 16),
              Text('Results not available yet', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text('Voting may still be in progress or results are not published yet.',
                  style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => context.pop(),
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('Go Back'),
              ),
            ],
          ),
        ),
        data: (tally) => ResponsivePageWrapper(child: _buildResults(context, tally, election, user)),
      ),
    );
  }

  Widget _buildResults(BuildContext context, TallyResult tally, ElectionModel? election, UserModel? user) {
    final isLive = election?.state == 'voting_open';
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildResultsHeader(context, tally, election, user),
          const SizedBox(height: 24),
          ...tally.results.map((posResult) => _buildPositionResult(context, posResult, isLive)),
        ],
      ),
    );
  }

  Widget _buildResultsHeader(BuildContext context, TallyResult tally, ElectionModel? election, UserModel? user) {
    final state = election?.state ?? 'voting_open';
    final isLive = state == 'voting_open';

    Color headerBg1 = const Color(0xFF0F2B6F);
    Color headerBg2 = const Color(0xFF1E3A8A);
    if (isLive) {
      headerBg1 = const Color(0xFF1A1A2E);
      headerBg2 = const Color(0xFF16213E);
    } else if (state == 'results_provisional') {
      headerBg1 = const Color(0xFF7C2D12);
      headerBg2 = const Color(0xFFC2410C);
    } else if (state == 'results_final') {
      headerBg1 = const Color(0xFF064E3B);
      headerBg2 = const Color(0xFF047857);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [headerBg1, headerBg2]),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildStateBadge(state),
              if (user != null && user.canManageElections)
                Text('Admin View', style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          Text(tally.electionTitle,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            state == 'voting_open'
                ? 'Voting is in progress — tally updates in real time'
                : state == 'voting_closed'
                    ? 'Voting has closed. Results are ready to be published.'
                    : state == 'results_provisional'
                        ? 'Provisional Results (Subject to review/claim period)'
                        : 'Official Final Results',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: 16),
          // Turnout Stats
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildTurnoutStat('Turnout', '${tally.turnoutPercentage}%'),
                _buildTurnoutStat('Voted', '${tally.ballotsCast}'),
                _buildTurnoutStat('Total Voters', '${tally.totalVoters}'),
              ],
            ),
          ),
          // Admin Publish Actions
          if (user != null && user.canManageElections && (state == 'voting_closed' || state == 'results_provisional')) ...[
            const SizedBox(height: 16),
            const Divider(color: Colors.white24),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                if (state == 'voting_closed')
                  ElevatedButton.icon(
                    onPressed: () => _advanceState(context, 'results_provisional', 'Provisional Results Published!'),
                    icon: const Icon(Icons.rate_review_outlined, size: 18),
                    label: const Text('Publish Provisional Results'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange.shade700,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ElevatedButton.icon(
                  onPressed: () => _advanceState(context, 'results_final', 'Official Final Results Published!'),
                  icon: const Icon(Icons.verified_rounded, size: 18),
                  label: const Text('Publish Final Results'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStateBadge(String state) {
    if (state == 'voting_open') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.error.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.error, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            const Text('LIVE TALLY', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w800, fontSize: 12)),
          ],
        ),
      );
    } else if (state == 'voting_closed') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.amber.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.amber),
        ),
        child: const Text('VOTING CLOSED (UNPUBLISHED)', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12)),
      );
    } else if (state == 'results_provisional') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.orange),
        ),
        child: const Text('PROVISIONAL RESULTS', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 12)),
      );
    } else if (state == 'results_final') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.success.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.success),
        ),
        child: const Text('FINAL OFFICIAL RESULTS', style: TextStyle(color: AppColors.success, fontWeight: FontWeight.bold, fontSize: 12)),
      );
    }
    return const SizedBox.shrink();
  }

  Future<void> _advanceState(BuildContext context, String targetState, String successMsg) async {
    final title = targetState == 'results_provisional' ? 'Publish Provisional Results?' : 'Publish Official Final Results?';
    final desc = targetState == 'results_provisional'
        ? 'This will make provisional results visible to voters and participants.'
        : 'This will finalize and officially publish final results for this election.';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(desc),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: targetState == 'results_provisional' ? Colors.orange.shade700 : AppColors.success,
              foregroundColor: Colors.white,
            ),
            child: const Text('Yes, Publish'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await ref.read(publishElectionProvider.notifier).advanceElectionState(widget.electionId, targetState);
      ref.invalidate(electionProvider(widget.electionId));
      ref.invalidate(resultsProvider(widget.electionId));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(successMsg)));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  Widget _buildTurnoutStat(String label, String value) {
    return Column(
      children: [
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
  }

  Widget _buildPositionResult(BuildContext context, PositionResult posResult, bool isLive) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surface : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? AppColors.surfaceVariant : Colors.black.withValues(alpha: 0.05)),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Position header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.star_rounded, color: AppColors.accent, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(posResult.title, style: Theme.of(context).textTheme.titleMedium),
                      Text('${posResult.totalValidBallots} vote(s) cast',
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Divider(color: isDark ? AppColors.surfaceVariant : Colors.black.withValues(alpha: 0.05), height: 1),
          // Candidates
          ...posResult.breakdown.asMap().entries.map((entry) {
            final i = entry.key;
            final score = entry.value;
            final isTopCandidate = posResult.winners.contains(score.candidateId);
            final totalVotes = posResult.totalValidBallots;
            final pct = totalVotes > 0 ? score.score / totalVotes : 0.0;

            return _CandidateResultTile(
              rank: i + 1,
              score: score,
              // During live voting, no one is the "winner" yet. Also requires at least 1 vote.
              isWinner: !isLive && isTopCandidate && score.score > 0,
              isLeading: isLive && isTopCandidate && score.score > 0,
              percentage: pct,
              totalVotes: totalVotes,
            );
          }),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _CandidateResultTile extends StatelessWidget {
  final int rank;
  final CandidateScore score;
  final bool isWinner;
  final bool isLeading;
  final double percentage;
  final int totalVotes;

  const _CandidateResultTile({
    required this.rank,
    required this.score,
    required this.isWinner,
    required this.isLeading,
    required this.percentage,
    required this.totalVotes,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isHighlighted = isWinner || isLeading;
    final barColor = isWinner ? AppColors.success : (isLeading ? AppColors.accent : AppColors.primaryLight);
    
    // Convert alpha instead of opacity to avoid deprecated warnings if using newer flutter
    final borderColor = isHighlighted ? barColor.withValues(alpha: 0.5) : (isDark ? AppColors.surfaceVariant : Colors.black.withValues(alpha: 0.05));
    final bgColor = isHighlighted ? barColor.withValues(alpha: 0.05) : Colors.transparent;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Large Premium Image
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: isDark ? AppColors.surfaceVariant : Colors.grey.shade200,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: score.photoUrl.isNotEmpty
                  ? Image.network(
                      score.photoUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => _buildPlaceholder(isDark),
                    )
                  : _buildPlaceholder(isDark),
            ),
          ),
          const SizedBox(width: 16),
          // Info Column
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name & Rank Badge
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isWinner ? AppColors.success : (isLeading ? AppColors.accent : (isDark ? AppColors.surfaceVariant : Colors.grey.shade200)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        isWinner ? 'WINNER' : (isLeading ? 'LEADING' : '#$rank'),
                        style: TextStyle(
                          color: isHighlighted ? Colors.white : (isDark ? Colors.white70 : Colors.black54),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        score.name,
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Stats Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${score.score == score.score.toInt() ? score.score.toInt() : score.score.toStringAsFixed(2)} votes',
                      style: TextStyle(color: barColor, fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${(percentage * 100).toStringAsFixed(1)}%',
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // Progress Bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: percentage.clamp(0.0, 1.0),
                    backgroundColor: isDark ? AppColors.surfaceVariant : Colors.grey.shade200,
                    valueColor: AlwaysStoppedAnimation<Color>(barColor),
                    minHeight: 8,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholder(bool isDark) {
    return Center(
      child: Icon(Icons.person_rounded, color: isDark ? Colors.white24 : Colors.grey.shade400, size: 36),
    );
  }
}

