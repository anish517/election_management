import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers/analytics_provider.dart';
import '../../core/providers/app_providers.dart';
import '../../core/theme/app_theme.dart';

class AnalyticsScreen extends ConsumerWidget {
  final String electionId;
  final bool showAppBar;
  const AnalyticsScreen({super.key, required this.electionId, this.showAppBar = true});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analyticsAsync = ref.watch(analyticsProvider(electionId));
    final electionAsync = ref.watch(electionProvider(electionId));
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final isLive = electionAsync.whenData((e) => e.state == 'voting_open').value ?? false;
    final electionTitle = electionAsync.whenData((e) => e.title).value ?? 'Election';

    return Scaffold(
      backgroundColor: isDark ? AppColors.background : const Color(0xFFF8FAFC),
      appBar: !showAppBar
          ? null
          : AppBar(
              backgroundColor: isDark ? AppColors.surface : Colors.white,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios_rounded),
                onPressed: () => context.pop(),
              ),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    electionTitle,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Row(
                    children: [
                      if (isLive) ...[
                        _PulsingDot(),
                        const SizedBox(width: 5),
                        const Text('LIVE', style: TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.w800)),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        'Analytics & Telemetry Dashboard (निर्वाचन विश्लेषण)',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? AppColors.textMuted : AppColors.textSecondaryLightMode,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: 'Refresh Analytics',
                  onPressed: () => ref.invalidate(analyticsProvider(electionId)),
                ),
                const SizedBox(width: 8),
              ],
            ),
      body: analyticsAsync.when(
        loading: () => const _AnalyticsSkeleton(),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.signal_wifi_off_rounded, size: 48, color: AppColors.textMuted),
              const SizedBox(height: 12),
              Text('Could not load analytics: $e', textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
                onPressed: () => ref.invalidate(analyticsProvider(electionId)),
              ),
            ],
          ),
        ),
        data: (analytics) => _AnalyticsBody(
          analytics: analytics,
          isLive: isLive,
          isDark: isDark,
        ),
      ),
    );
  }
}

// ─── Main Body & Responsive Grid ───────────────────────────────────────────

class _AnalyticsBody extends StatelessWidget {
  final ElectionAnalytics analytics;
  final bool isLive;
  final bool isDark;

  const _AnalyticsBody({
    required this.analytics,
    required this.isLive,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 900;

            if (isWide) {
              return SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left Column (Turnout Donut & Hourly Velocity)
                    Expanded(
                      flex: 5,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _SectionHeader(icon: Icons.donut_large_rounded, title: 'Voter Turnout (मतदान सहभागिता)'),
                          const SizedBox(height: 12),
                          _TurnoutRingCard(analytics: analytics, isDark: isDark)
                              .animate()
                              .fadeIn(duration: 400.ms)
                              .scale(begin: const Offset(0.95, 0.95), duration: 400.ms, curve: Curves.easeOut),
                          const SizedBox(height: 24),
                          if (analytics.activityByHour.isNotEmpty) ...[
                            _SectionHeader(icon: Icons.bar_chart_rounded, title: 'Hourly Voting Velocity (समयगत मतदान दर)'),
                            const SizedBox(height: 12),
                            _VotingActivityCard(analytics: analytics, isDark: isDark)
                                .animate()
                                .fadeIn(duration: 500.ms, delay: 150.ms)
                                .slideY(begin: 0.1, duration: 500.ms, curve: Curves.easeOut),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 24),

                    // Right Column (Candidate Momentum Leaderboard)
                    Expanded(
                      flex: 6,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _SectionHeader(
                            icon: Icons.leaderboard_rounded,
                            title: isLive ? 'Live Candidate Momentum (अग्रता तालिका)' : 'Candidate Results Breakdown (नतिजा विवरण)',
                            badge: isLive ? 'LIVE' : null,
                          ),
                          const SizedBox(height: 12),
                          if (analytics.topCandidates.isNotEmpty)
                            ...analytics.topCandidates.asMap().entries.map(
                              (entry) => _CandidateMomentumRow(
                                candidate: entry.value,
                                rank: entry.key + 1,
                                maxScore: analytics.topCandidates.first.score,
                                isLive: isLive,
                                isDark: isDark,
                              ).animate().fadeIn(duration: 300.ms, delay: Duration(milliseconds: 150 + entry.key * 50)),
                            )
                          else
                            _EmptyState(isDark: isDark),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }

            // Stacked Mobile / Narrow Layout
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionHeader(icon: Icons.donut_large_rounded, title: 'Voter Turnout (मतदान सहभागिता)'),
                  const SizedBox(height: 12),
                  _TurnoutRingCard(analytics: analytics, isDark: isDark),
                  const SizedBox(height: 24),
                  if (analytics.activityByHour.isNotEmpty) ...[
                    _SectionHeader(icon: Icons.bar_chart_rounded, title: 'Hourly Voting Velocity (समयगत मतदान दर)'),
                    const SizedBox(height: 12),
                    _VotingActivityCard(analytics: analytics, isDark: isDark),
                    const SizedBox(height: 24),
                  ],
                  _SectionHeader(
                    icon: Icons.leaderboard_rounded,
                    title: isLive ? 'Live Candidate Momentum (अग्रता तालिका)' : 'Candidate Results Breakdown (नतिजा विवरण)',
                    badge: isLive ? 'LIVE' : null,
                  ),
                  const SizedBox(height: 12),
                  if (analytics.topCandidates.isNotEmpty)
                    ...analytics.topCandidates.asMap().entries.map(
                      (entry) => _CandidateMomentumRow(
                        candidate: entry.value,
                        rank: entry.key + 1,
                        maxScore: analytics.topCandidates.first.score,
                        isLive: isLive,
                        isDark: isDark,
                      ),
                    )
                  else
                    _EmptyState(isDark: isDark),
                  const SizedBox(height: 32),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// ─── Section 1: Turnout Donut ─────────────────────────────────────────────────

class _TurnoutRingCard extends StatelessWidget {
  final ElectionAnalytics analytics;
  final bool isDark;
  const _TurnoutRingCard({required this.analytics, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final pct = analytics.turnoutPercent.clamp(0.0, 100.0);
    final remaining = 100.0 - pct;
    final cardColor = isDark ? AppColors.surface : Colors.white;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
        ],
        border: Border.all(
          color: isDark ? AppColors.surfaceVariant : Colors.grey.shade200,
        ),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 200,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    startDegreeOffset: -90,
                    sectionsSpace: 4,
                    centerSpaceRadius: 68,
                    sections: [
                      PieChartSectionData(
                        value: pct > 0 ? pct : 0.01,
                        color: pct >= 50 ? Colors.green : AppColors.primaryLight,
                        radius: 26,
                        showTitle: false,
                      ),
                      PieChartSectionData(
                        value: remaining > 0 ? remaining : 99.99,
                        color: isDark ? AppColors.surfaceVariant : const Color(0xFFECEFF4),
                        radius: 20,
                        showTitle: false,
                      ),
                    ],
                  ),
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeInOut,
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: pct),
                      duration: const Duration(milliseconds: 800),
                      curve: Curves.easeOut,
                      builder: (_, val, _) => Text(
                        '${val.toStringAsFixed(1)}%',
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                    Text(
                      'Participation Rate',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: isDark ? AppColors.textMuted : AppColors.textSecondaryLightMode,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const Divider(height: 1),
          const SizedBox(height: 16),

          // Stat metrics
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _StatChip(
                label: 'Total Voted',
                value: '${analytics.totalVoted}',
                color: Colors.green,
                isDark: isDark,
              ),
              Container(width: 1, height: 28, color: isDark ? Colors.white12 : Colors.grey.shade300),
              _StatChip(
                label: 'Total Eligible',
                value: '${analytics.totalEligible}',
                color: AppColors.primaryLight,
                isDark: isDark,
              ),
              Container(width: 1, height: 28, color: isDark ? Colors.white12 : Colors.grey.shade300),
              _StatChip(
                label: 'Remaining',
                value: '${max(0, analytics.totalEligible - analytics.totalVoted)}',
                color: Colors.orange,
                isDark: isDark,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool isDark;
  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: isDark ? AppColors.textMuted : AppColors.textSecondaryLightMode,
          ),
        ),
      ],
    );
  }
}

// ─── Section 2: Bar Chart ─────────────────────────────────────────────────────

class _VotingActivityCard extends StatelessWidget {
  final ElectionAnalytics analytics;
  final bool isDark;
  const _VotingActivityCard({required this.analytics, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final activity = analytics.activityByHour;
    final peak = analytics.peakCount.toDouble();
    final cardColor = isDark ? AppColors.surface : Colors.white;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
        ],
        border: Border.all(
          color: isDark ? AppColors.surfaceVariant : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Activity Distribution',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isDark ? Colors.white70 : Colors.grey.shade700),
              ),
              if (analytics.peakCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('Peak: ${analytics.peakCount} votes/hr', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppColors.primaryLight)),
                ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 175,
            child: BarChart(
              BarChartData(
                maxY: max(peak * 1.3, 1),
                gridData: FlGridData(
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: isDark ? AppColors.surfaceVariant : Colors.black.withValues(alpha: 0.06),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (v, _) => Text(
                        v.toInt().toString(),
                        style: TextStyle(
                          fontSize: 9,
                          color: isDark ? AppColors.textMuted : AppColors.textSecondaryLightMode,
                        ),
                      ),
                    ),
                  ),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      getTitlesWidget: (v, _) {
                        final idx = v.toInt();
                        if (idx < 0 || idx >= activity.length) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            activity[idx].hour,
                            style: TextStyle(
                              fontSize: 9,
                              color: isDark ? AppColors.textMuted : AppColors.textSecondaryLightMode,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: activity.asMap().entries.map((entry) {
                  final isPeak = entry.value.count == analytics.peakCount && analytics.peakCount > 0;
                  return BarChartGroupData(
                    x: entry.key,
                    barRods: [
                      BarChartRodData(
                        toY: entry.value.count.toDouble(),
                        width: max(4, 320 / max(activity.length, 1) * 0.55),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: isPeak
                              ? [AppColors.primaryLight, AppColors.primaryLight.withValues(alpha: 0.6)]
                              : [
                                  AppColors.primaryLight.withValues(alpha: 0.35),
                                  AppColors.primaryLight.withValues(alpha: 0.15),
                                ],
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeInOut,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Section 3: Candidate Momentum Leaderboard ─────────────────────────────

class _CandidateMomentumRow extends StatelessWidget {
  final AnalyticsCandidateScore candidate;
  final int rank;
  final double maxScore;
  final bool isLive;
  final bool isDark;

  const _CandidateMomentumRow({
    required this.candidate,
    required this.rank,
    required this.maxScore,
    required this.isLive,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final fraction = maxScore > 0 ? (candidate.score / maxScore).clamp(0.0, 1.0) : 0.0;
    final hasVotes = candidate.score > 0;
    final isTop = hasVotes && rank == 1;
    final isWinner = candidate.isWinner && hasVotes;
    final cardColor = isDark ? AppColors.surface : Colors.white;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isWinner
              ? Colors.amber.shade600.withValues(alpha: 0.5)
              : (isLive && isTop
                  ? AppColors.primaryLight.withValues(alpha: 0.4)
                  : (isDark ? AppColors.surfaceVariant : Colors.grey.shade200)),
          width: (isWinner || (isLive && isTop)) ? 1.5 : 1,
        ),
        boxShadow: [
          if (!isDark && (isWinner || isTop))
            BoxShadow(
              color: isWinner
                  ? Colors.amber.withValues(alpha: 0.08)
                  : AppColors.primary.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Rank badge
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: isWinner
                      ? Colors.amber.withValues(alpha: 0.2)
                      : (isDark ? AppColors.surfaceVariant : const Color(0xFFECEFF4)),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  isWinner ? '🏆' : '$rank',
                  style: TextStyle(
                    fontSize: isWinner ? 13 : 11,
                    fontWeight: FontWeight.w700,
                    color: isWinner
                        ? Colors.amber.shade700
                        : (isDark ? Colors.white70 : AppColors.textSecondaryLightMode),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Candidate Information
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      candidate.name,
                      style: TextStyle(fontWeight: (isWinner || isTop) ? FontWeight.bold : FontWeight.w600, fontSize: 14),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      candidate.positionTitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? AppColors.textMuted : AppColors.textSecondaryLightMode,
                      ),
                    ),
                  ],
                ),
              ),

              // Score + Status Badges
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    candidate.score.toStringAsFixed(1),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.5),
                  ),
                  if (isWinner)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('WINNER', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.amber)),
                    )
                  else if (isLive && isTop)
                    _LiveBadge(),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Animated progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: fraction),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOut,
              builder: (_, val, _) {
                return LinearProgressIndicator(
                  value: val,
                  minHeight: 8,
                  backgroundColor: isDark ? AppColors.surfaceVariant : const Color(0xFFECEFF4),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isTop ? Colors.amber.shade700 : AppColors.primaryLight,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Small Helpers ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? badge;
  const _SectionHeader({required this.icon, required this.title, this.badge});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primaryLight, size: 20),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        if (badge != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              badge!,
              style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: Colors.green),
            ),
          ),
        ],
      ],
    );
  }
}

class _LiveBadge extends StatefulWidget {
  @override
  State<_LiveBadge> createState() => _LiveBadgeState();
}

class _LiveBadgeState extends State<_LiveBadge> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
    _opacity = Tween<double>(begin: 0.4, end: 1.0).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _opacity,
      builder: (_, _) => Opacity(
        opacity: _opacity.value,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text('🟢 LEADING', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.green)),
        ),
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.5 + _ctrl.value * 0.5),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool isDark;
  const _EmptyState({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceVariant.withValues(alpha: 0.3) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade200),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bar_chart_rounded, size: 56, color: isDark ? AppColors.textMuted : const Color(0xFFCDD5E0)),
          const SizedBox(height: 16),
          Text(
            'No analytics data available yet',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isDark ? AppColors.textMuted : AppColors.textSecondaryLightMode,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Live telemetry and momentum rankings will appear once ballot casting opens.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? AppColors.textMuted : AppColors.textSecondaryLightMode,
            ),
          ),
        ],
      ),
    );
  }
}

class _AnalyticsSkeleton extends StatelessWidget {
  const _AnalyticsSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator(color: AppColors.primaryLight));
  }
}
