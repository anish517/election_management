import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/network/api_constants.dart';
import '../../core/network/api_client.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/shimmer_loaders.dart';

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

    // isLive = voting is open and user is NOT an admin
    final isLive = electionAsync.whenData((e) => e.state == 'voting_open' && !(user?.canManageElections ?? false)).value ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text(isLive ? 'Live Tally 🔴' : 'Election Results'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => context.pop(),
        ),
        actions: [
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
            onPressed: () => ref.invalidate(resultsProvider(widget.electionId)),
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
              Text('Voting may still be in progress.',
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
        data: (tally) => _buildResults(context, tally, isLive),
      ),
    );
  }

  Widget _buildResults(BuildContext context, TallyResult tally, bool isLive) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildResultsHeader(context, tally, isLive),
          const SizedBox(height: 24),
          ...tally.results.map((posResult) => _buildPositionResult(context, posResult, isLive)),
        ],
      ),
    );
  }

  Widget _buildResultsHeader(BuildContext context, TallyResult tally, bool isLive) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isLive
              ? [const Color(0xFF1A1A2E), const Color(0xFF16213E)]
              : [const Color(0xFF0F2B6F), const Color(0xFF1E3A8A)],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isLive)
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.error.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(width: 8, height: 8,
                        decoration: const BoxDecoration(color: AppColors.error, shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      const Text('LIVE', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w800, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            )
          else
            const Icon(Icons.emoji_events_rounded, color: AppColors.accent, size: 32),
          const SizedBox(height: 12),
          Text(tally.electionTitle,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: Colors.white)),
          const SizedBox(height: 8),
          Text(isLive ? 'Voting is in progress — results may change' : 'Election Results',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white60)),
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
                _buildTurnoutStat('Total', '${tally.totalVoters}'),
              ],
            ),
          ),
        ],
      ),
    );
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
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceVariant),
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
          const Divider(color: AppColors.surfaceVariant, height: 1),
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
              // During live voting, no one is the "winner" yet
              isWinner: !isLive && isTopCandidate,
              isLeading: isLive && isTopCandidate,
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
    final isHighlighted = isWinner || isLeading;
    final barColor = isWinner ? AppColors.success : (isLeading ? AppColors.accent : AppColors.primaryLight);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        children: [
          Row(
            children: [
              // Rank badge
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: isHighlighted ? AppColors.accent.withValues(alpha: 0.2) : AppColors.surfaceVariant,
                  shape: BoxShape.circle,
                ),
                child: isWinner
                    ? const Icon(Icons.emoji_events_rounded, color: AppColors.accent, size: 18)
                    : Center(
                        child: Text('#$rank',
                            style: TextStyle(color: isLeading ? AppColors.accent : AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.bold))),
              ),
              const SizedBox(width: 12),
              // Name
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(score.name, style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: isHighlighted ? AppColors.textPrimary : AppColors.textSecondary,
                              fontWeight: isHighlighted ? FontWeight.w700 : FontWeight.w400)),
                        if (isWinner) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.success.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('Winner',
                                style: TextStyle(color: AppColors.success, fontSize: 10, fontWeight: FontWeight.w700)),
                          ),
                        ],
                        if (isLeading) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.accent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('Leading',
                                style: TextStyle(color: AppColors.accent, fontSize: 10, fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              // Score
              Text('${score.score == score.score.toInt() ? score.score.toInt() : score.score.toStringAsFixed(2)} votes',
                  style: TextStyle(
                      color: isWinner ? AppColors.success : AppColors.textMuted,
                      fontWeight: FontWeight.w700, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 8),
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: percentage.clamp(0.0, 1.0),
              backgroundColor: AppColors.surfaceVariant,
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: Text('${(percentage * 100).toStringAsFixed(1)}%',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
          ),
        ],
      ),
    );
  }
}
