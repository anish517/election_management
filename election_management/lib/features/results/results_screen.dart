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
  bool _showTableView = true;

  @override
  void initState() {
    super.initState();
    // Smart Polling: Refresh results every 6 seconds during live voting
    _pollingTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      final election = ref.read(electionProvider(widget.electionId)).valueOrNull;
      if (election?.state == 'voting_open' || election?.state == 'voting_closed') {
        ref.invalidate(resultsProvider(widget.electionId));
      }
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _exportCsv() async {
    try {
      final token = await JwtInterceptor.getAccessToken();
      final url = Uri.parse('${ApiConstants.baseUrl}/elections/${widget.electionId}/results/export_csv/?token=$token');
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not launch export URL')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final resultsAsync = ref.watch(resultsProvider(widget.electionId));
    final electionAsync = ref.watch(electionProvider(widget.electionId));
    final user = ref.watch(currentUserProvider);

    final election = electionAsync.valueOrNull;
    final isLive = election?.state == 'voting_open';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.background : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isLive ? 'Live Ballot Tally' : 'Election Results',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                if (isLive) ...[
                  const SizedBox(width: 8),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(color: Colors.greenAccent, shape: BoxShape.circle),
                  ),
                ],
              ],
            ),
            Text(
              isLive ? 'प्रत्यक्ष मतगणना तथा नतिजा' : 'अन्तिम निर्वाचन नतिजा तथा विवरण',
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => context.pop(),
        ),
        actions: [
          if (user != null && user.canManageElections)
            IconButton(
              icon: const Icon(Icons.analytics_outlined),
              tooltip: 'Live Analytics',
              onPressed: () => context.pushNamed('analytics', pathParameters: {'electionId': widget.electionId}),
            ),
          if (!isLive)
            IconButton(
              icon: const Icon(Icons.download_rounded),
              tooltip: 'Download CSV Report',
              onPressed: _exportCsv,
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Results',
            onPressed: () {
              ref.invalidate(resultsProvider(widget.electionId));
              ref.invalidate(electionProvider(widget.electionId));
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: resultsAsync.when(
        loading: () => const ListSkeleton(count: 4),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.bar_chart_rounded, color: AppColors.textMuted, size: 54),
              const SizedBox(height: 16),
              Text('Results Not Available Yet', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  'Voting may still be in progress or election officers have not yet published the tally.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                ),
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: () => context.pop(),
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('Back to Dashboard'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ),
        data: (tally) => ResponsivePageWrapper(child: _buildResults(context, tally, election, user, isDark)),
      ),
    );
  }

  Widget _buildResults(BuildContext context, TallyResult tally, ElectionModel? election, UserModel? user, bool isDark) {
    final isLive = election?.state == 'voting_open';
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildResultsHeader(context, tally, election, user, isDark),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.military_tech_rounded, size: 20, color: AppColors.primaryLight),
                  const SizedBox(width: 8),
                  Text(
                    'Contested Offices & Results Table (पदगत नतिजा विवरण)',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ],
              ),
              // Toggle Table vs Card View
              Container(
                decoration: BoxDecoration(
                  color: isDark ? AppColors.surfaceVariant : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      onTap: () => setState(() => _showTableView = true),
                      borderRadius: const BorderRadius.horizontal(left: Radius.circular(10)),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: _showTableView ? AppColors.primary : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.table_chart_rounded, size: 15, color: _showTableView ? Colors.white : (isDark ? Colors.white70 : Colors.black87)),
                            const SizedBox(width: 5),
                            Text('Table', style: TextStyle(color: _showTableView ? Colors.white : (isDark ? Colors.white70 : Colors.black87), fontSize: 12, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () => setState(() => _showTableView = false),
                      borderRadius: const BorderRadius.horizontal(right: Radius.circular(10)),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: !_showTableView ? AppColors.primary : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.view_agenda_rounded, size: 15, color: !_showTableView ? Colors.white : (isDark ? Colors.white70 : Colors.black87)),
                            const SizedBox(width: 5),
                            Text('Cards', style: TextStyle(color: !_showTableView ? Colors.white : (isDark ? Colors.white70 : Colors.black87), fontSize: 12, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...tally.results.map((posResult) => _buildPositionResult(context, posResult, isLive, isDark)),
        ],
      ),
    );
  }

  Widget _buildResultsHeader(BuildContext context, TallyResult tally, ElectionModel? election, UserModel? user, bool isDark) {
    final state = election?.state ?? 'voting_open';
    final isLive = state == 'voting_open';

    List<Color> gradientColors;
    if (isLive) {
      gradientColors = isDark
          ? [const Color(0xFF1E1B4B), const Color(0xFF312E81)]
          : [const Color(0xFF4338CA), const Color(0xFF6366F1)];
    } else if (state == 'results_provisional') {
      gradientColors = isDark
          ? [const Color(0xFF7C2D12), const Color(0xFF9A3412)]
          : [const Color(0xFFC2410C), const Color(0xFFEA580C)];
    } else if (state == 'results_final') {
      gradientColors = isDark
          ? [const Color(0xFF064E3B), const Color(0xFF065F46)]
          : [const Color(0xFF047857), const Color(0xFF10B981)];
    } else {
      gradientColors = isDark
          ? [const Color(0xFF1E293B), const Color(0xFF334155)]
          : [const Color(0xFF334155), const Color(0xFF475569)];
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: gradientColors.first.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildStateBadge(state),
              if (user != null && user.canManageElections)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('Election Administration', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            tally.electionTitle,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 22),
          ),
          const SizedBox(height: 4),
          Text(
            state == 'voting_open'
                ? 'Voting franchise is actively open — real-time tally telemetry'
                : state == 'voting_closed'
                    ? 'Polls have closed. Results tally is computed and awaiting publication.'
                    : state == 'results_provisional'
                        ? 'Provisional Results (Published for scrutiny & claim period)'
                        : 'Official Final Certified Results & Mandate',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13),
          ),
          const SizedBox(height: 20),

          // Telemetry Stats Row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildTurnoutStat('Turnout Rate', '${tally.turnoutPercentage}%'),
                Container(width: 1, height: 28, color: Colors.white24),
                _buildTurnoutStat('Votes Cast', '${tally.ballotsCast}'),
                Container(width: 1, height: 28, color: Colors.white24),
                _buildTurnoutStat('Elector Roll', '${tally.totalVoters}'),
              ],
            ),
          ),

          // Admin Publish Actions
          if (user != null && user.canManageElections && (state == 'voting_closed' || state == 'results_provisional')) ...[
            const SizedBox(height: 18),
            const Divider(color: Colors.white24, height: 1),
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              children: [
                if (state == 'voting_closed')
                  FilledButton.icon(
                    onPressed: () => _advanceState(context, 'results_provisional', 'Provisional Results Published!'),
                    icon: const Icon(Icons.rate_review_outlined, size: 18),
                    label: const Text('Publish Provisional Results (प्रारम्भिक नतिजा)'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.orange.shade800,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                FilledButton.icon(
                  onPressed: () => _advanceState(context, 'results_final', 'Official Final Results Published!'),
                  icon: const Icon(Icons.verified_rounded, size: 18),
                  label: const Text('Publish Final Results (अन्तिम नतिजा)'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
          color: Colors.white.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.fiber_manual_record, color: Colors.greenAccent, size: 12),
            SizedBox(width: 6),
            Text('LIVE TALLY', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11.5)),
          ],
        ),
      );
    } else if (state == 'voting_closed') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.amber.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.amberAccent),
        ),
        child: const Text('POLLS CLOSED (UNPUBLISHED)', style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 11.5)),
      );
    } else if (state == 'results_provisional') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
        ),
        child: const Text('PROVISIONAL RESULTS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11.5)),
      );
    } else if (state == 'results_final') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.verified_rounded, color: Colors.white, size: 14),
            SizedBox(width: 5),
            Text('OFFICIAL FINAL RESULTS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11.5)),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Future<void> _advanceState(BuildContext context, String targetState, String successMsg) async {
    final title = targetState == 'results_provisional' ? 'Publish Provisional Results?' : 'Publish Official Final Results?';
    final desc = targetState == 'results_provisional'
        ? 'This will release provisional results to all voters and electors for statutory scrutiny and claims.'
        : 'This will officially certify and lock the final mandate results for this election.';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title),
        content: Text(desc),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: targetState == 'results_provisional' ? Colors.orange.shade800 : const Color(0xFF10B981),
            ),
            child: const Text('Confirm & Publish'),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white),
                const SizedBox(width: 10),
                Text(successMsg),
              ],
            ),
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
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
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
      ],
    );
  }

  Widget _buildPositionResult(BuildContext context, PositionResult posResult, bool isLive, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surface : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? AppColors.surfaceVariant : Colors.grey.shade200),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
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
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.star_rounded, color: AppColors.primaryLight, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              posResult.title,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${posResult.seatsAvailable} Seat${posResult.seatsAvailable > 1 ? 's' : ''} (${posResult.seatsAvailable} सिट)',
                              style: const TextStyle(
                                color: AppColors.primaryLight,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${posResult.totalValidBallots} vote(s) cast across candidates',
                        style: TextStyle(color: isDark ? Colors.white60 : AppColors.textMuted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Tie Detection Alert Banner
          if (posResult.hasTie)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.shade700, width: 1.2),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.amber.shade800, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'बराबरी मत (Tie Detected): अन्तिम सिटका लागि उम्मेदवारहरूबीच बराबर मत प्राप्त भएको छ। निर्वाचन समितिद्वारा गोलाप्रथा वा निर्देशिका बमोजिम निर्णय गरिनेछ।',
                      style: TextStyle(color: Colors.amber.shade900, fontSize: 11.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),

          Divider(color: isDark ? AppColors.surfaceVariant : Colors.grey.shade200, height: 1),

          // Structured Results Table vs Cards
          if (_showTableView)
            _buildResultsTable(context, posResult, isLive, isDark)
          else ...[
            // Candidates Card List
            ...posResult.breakdown.asMap().entries.map((entry) {
              final i = entry.key;
              final score = entry.value;
              final isTopCandidate = posResult.winners.contains(score.candidateId) || score.isElected;
              final totalVotes = posResult.totalValidBallots;
              final pct = totalVotes > 0 ? score.score / totalVotes : 0.0;

              return _CandidateResultTile(
                rank: score.rank > 0 ? score.rank : (i + 1),
                score: score,
                isWinner: !isLive && isTopCandidate && score.score > 0,
                isLeading: isLive && isTopCandidate && score.score > 0,
                percentage: pct,
                totalVotes: totalVotes,
              );
            }),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildResultsTable(BuildContext context, PositionResult posResult, bool isLive, bool isDark) {
    final totalVotes = posResult.totalValidBallots;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width - 72),
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(
            isDark ? AppColors.surfaceVariant.withValues(alpha: 0.5) : const Color(0xFFF1F5F9),
          ),
          columnSpacing: 20,
          horizontalMargin: 16,
          columns: const [
            DataColumn(label: Text('Position (पद)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5))),
            DataColumn(label: Text('Seats (सिट)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5))),
            DataColumn(label: Text('Candidate Name (उम्मेदवार)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5))),
            DataColumn(label: Text('Votes Received (प्राप्त मत)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5))),
            DataColumn(label: Text('Status / Result (नतिजा)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5))),
          ],
          rows: posResult.breakdown.asMap().entries.map((entry) {
            final idx = entry.key;
            final score = entry.value;
            final isNoVoteOrBoycott = score.candidateId == '__BOYCOTT__' ||
                score.candidateId == '__NO_VOTE__' ||
                score.candidateId == 'NOTA' ||
                score.name.toLowerCase().contains('no vote') ||
                score.name.toLowerCase().contains('boycott');

            final isElected = !isLive && !isNoVoteOrBoycott && (posResult.winners.contains(score.candidateId) || score.isElected) && score.score > 0;
            final isLeading = isLive && !isNoVoteOrBoycott && (posResult.winners.contains(score.candidateId) || score.isElected) && score.score > 0;
            final isTie = score.isTie;
            final pct = totalVotes > 0 ? (score.score / totalVotes * 100) : 0.0;

            Color? rowBg;
            if (isElected) {
              rowBg = const Color(0xFF10B981).withValues(alpha: isDark ? 0.15 : 0.08);
            } else if (isTie) {
              rowBg = Colors.amber.withValues(alpha: isDark ? 0.15 : 0.08);
            } else if (isNoVoteOrBoycott) {
              rowBg = const Color(0xFFD97706).withValues(alpha: isDark ? 0.08 : 0.04);
            }

            return DataRow(
              color: rowBg != null ? WidgetStateProperty.all(rowBg) : null,
              cells: [
                // 1. Position Title (only display title text on first row for clean grouping)
                DataCell(
                  Text(
                    idx == 0 ? posResult.title : '',
                    style: TextStyle(
                      fontWeight: idx == 0 ? FontWeight.bold : FontWeight.normal,
                      color: isDark ? Colors.white : Colors.black87,
                      fontSize: 13,
                    ),
                  ),
                ),
                // 2. Position Seats
                DataCell(
                  idx == 0
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${posResult.seatsAvailable} Seat${posResult.seatsAvailable > 1 ? 's' : ''}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppColors.primaryLight),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                // 3. Candidate Name
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: isNoVoteOrBoycott
                              ? const Color(0xFFD97706).withValues(alpha: 0.15)
                              : (isDark ? AppColors.surfaceVariant : Colors.grey.shade200),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: isNoVoteOrBoycott
                              ? const Center(child: Icon(Icons.do_not_disturb_alt_rounded, color: Color(0xFFD97706), size: 16))
                              : (score.photoUrl.isNotEmpty
                                  ? Image.network(
                                      score.photoUrl,
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) => const Icon(Icons.person_rounded, size: 18),
                                    )
                                  : const Icon(Icons.person_rounded, size: 18)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          score.name,
                          style: TextStyle(
                            fontWeight: isElected ? FontWeight.bold : (isNoVoteOrBoycott ? FontWeight.w500 : FontWeight.w600),
                            fontSize: 13,
                            color: isElected
                                ? const Color(0xFF10B981)
                                : (isDark ? Colors.white : Colors.black87),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // 4. Votes Received
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${score.score == score.score.toInt() ? score.score.toInt() : score.score.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13.5,
                          color: isElected ? const Color(0xFF10B981) : (isDark ? Colors.white : Colors.black87),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '(${pct.toStringAsFixed(1)}%)',
                        style: TextStyle(fontSize: 11.5, color: isDark ? Colors.white60 : AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
                // 5. Status / Mandate Badge
                DataCell(
                  _buildStatusBadge(isElected, isLeading, isTie, isNoVoteOrBoycott, score.rank > 0 ? score.rank : (idx + 1)),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(bool isElected, bool isLeading, bool isTie, bool isNoVoteOrBoycott, int rank) {
    if (isNoVoteOrBoycott) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFD97706).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Text(
          '⚪ NOTA / Abstained',
          style: TextStyle(color: Color(0xFFD97706), fontSize: 11, fontWeight: FontWeight.bold),
        ),
      );
    }
    if (isElected) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF10B981),
          borderRadius: BorderRadius.circular(6),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF10B981).withValues(alpha: 0.3),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.military_tech_rounded, size: 14, color: Colors.white),
            SizedBox(width: 4),
            Text('🏆 ELECTED (विजयी)', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
          ],
        ),
      );
    }
    if (isLeading) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.amber.shade700,
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.trending_up_rounded, size: 13, color: Colors.white),
            SizedBox(width: 4),
            Text('🟢 LEADING', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
          ],
        ),
      );
    }
    if (isTie) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.amber.shade100,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.amber.shade800),
        ),
        child: Text(
          '⚠️ TIED (बराबरी)',
          style: TextStyle(color: Colors.amber.shade900, fontSize: 11, fontWeight: FontWeight.bold),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '#$rank',
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
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
    final isNoVoteOrBoycott = score.candidateId == '__BOYCOTT__' ||
        score.candidateId == '__NO_VOTE__' ||
        score.candidateId == 'NOTA' ||
        score.name.toLowerCase().contains('no vote') ||
        score.name.toLowerCase().contains('boycott');

    final effectiveWinner = isNoVoteOrBoycott ? false : isWinner;
    final effectiveLeading = isNoVoteOrBoycott ? false : isLeading;
    final isHighlighted = effectiveWinner || effectiveLeading;

    final barColor = isNoVoteOrBoycott
        ? const Color(0xFFD97706)
        : (effectiveWinner
            ? const Color(0xFF10B981)
            : (effectiveLeading ? Colors.amber.shade700 : AppColors.primaryLight));

    final borderColor = isNoVoteOrBoycott
        ? const Color(0xFFD97706).withValues(alpha: 0.35)
        : (isHighlighted
            ? barColor.withValues(alpha: 0.5)
            : (isDark ? AppColors.surfaceVariant : Colors.grey.shade200));

    final bgColor = isNoVoteOrBoycott
        ? const Color(0xFFD97706).withValues(alpha: isDark ? 0.08 : 0.04)
        : (isHighlighted ? barColor.withValues(alpha: isDark ? 0.1 : 0.05) : Colors.transparent);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: isHighlighted ? 1.5 : 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Candidate Photo / Avatar / No Vote Icon
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: isNoVoteOrBoycott
                  ? const Color(0xFFD97706).withValues(alpha: 0.12)
                  : (isDark ? AppColors.surfaceVariant : Colors.grey.shade200),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: isNoVoteOrBoycott
                  ? const Center(
                      child: Icon(Icons.do_not_disturb_alt_rounded, color: Color(0xFFD97706), size: 30),
                    )
                  : (score.photoUrl.isNotEmpty
                      ? Image.network(
                          score.photoUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => _buildPlaceholder(isDark),
                        )
                      : _buildPlaceholder(isDark)),
            ),
          ),
          const SizedBox(width: 16),

          // Candidate Info & Progress
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isNoVoteOrBoycott
                            ? const Color(0xFFD97706).withValues(alpha: 0.15)
                            : (effectiveWinner
                                ? const Color(0xFF10B981)
                                : (effectiveLeading ? Colors.amber.shade700 : (isDark ? AppColors.surfaceVariant : Colors.grey.shade200))),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isNoVoteOrBoycott
                            ? '⚪ ABSTAINED / NOTA'
                            : (effectiveWinner ? '🏆 ELECTED' : (effectiveLeading ? '🟢 LEADING' : '#$rank')),
                        style: TextStyle(
                          color: isNoVoteOrBoycott
                              ? const Color(0xFFD97706)
                              : (isHighlighted ? Colors.white : (isDark ? Colors.white70 : Colors.black54)),
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
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Stats Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${score.score == score.score.toInt() ? score.score.toInt() : score.score.toStringAsFixed(2)} votes',
                      style: TextStyle(color: barColor, fontSize: 13.5, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${(percentage * 100).toStringAsFixed(1)}%',
                      style: TextStyle(
                        color: isDark ? Colors.white60 : AppColors.textMuted,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
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
                    minHeight: 7,
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
      child: Icon(Icons.person_rounded, color: isDark ? Colors.white24 : Colors.grey.shade400, size: 32),
    );
  }
}

