import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers/app_providers.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/models.dart';

class ResultsScreen extends ConsumerWidget {
  final String electionId;
  const ResultsScreen({super.key, required this.electionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resultsAsync = ref.watch(resultsProvider(electionId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Election Results'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(resultsProvider(electionId)),
          ),
        ],
      ),
      body: resultsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
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
        data: (tally) => _buildResults(context, tally),
      ),
    );
  }

  Widget _buildResults(BuildContext context, TallyResult tally) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildResultsHeader(context, tally),
          const SizedBox(height: 24),
          ...tally.results.map((posResult) => _buildPositionResult(context, posResult)),
        ],
      ),
    );
  }

  Widget _buildResultsHeader(BuildContext context, TallyResult tally) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F2B6F), Color(0xFF1E3A8A)],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.emoji_events_rounded, color: AppColors.accent, size: 32),
          const SizedBox(height: 12),
          Text(tally.electionTitle,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: Colors.white)),
          const SizedBox(height: 8),
          Text('Election Results',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white60)),
        ],
      ),
    );
  }

  Widget _buildPositionResult(BuildContext context, PositionResult posResult) {
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
                      Text('${posResult.totalValidBallots} valid ballot(s)',
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
            final isWinner = posResult.winners.contains(score.candidateId);
            final totalVotes = posResult.totalValidBallots;
            final pct = totalVotes > 0 ? score.score / totalVotes : 0.0;

            return _CandidateResultTile(
              rank: i + 1,
              score: score,
              isWinner: isWinner,
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
  final double percentage;
  final int totalVotes;

  const _CandidateResultTile({
    required this.rank,
    required this.score,
    required this.isWinner,
    required this.percentage,
    required this.totalVotes,
  });

  @override
  Widget build(BuildContext context) {
    final barColor = isWinner ? AppColors.success : AppColors.primaryLight;

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
                  color: isWinner ? AppColors.accent.withValues(alpha: 0.2) : AppColors.surfaceVariant,
                  shape: BoxShape.circle,
                ),
                child: isWinner
                    ? const Icon(Icons.emoji_events_rounded, color: AppColors.accent, size: 18)
                    : Center(
                        child: Text('#$rank',
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.bold))),
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
                              color: isWinner ? AppColors.textPrimary : AppColors.textSecondary,
                              fontWeight: isWinner ? FontWeight.w700 : FontWeight.w400)),
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
                      ],
                    ),
                  ],
                ),
              ),
              // Score
              Text('${score.score.toStringAsFixed(0)} votes',
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
