import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../network/api_client.dart';
import '../network/api_constants.dart';

// ─── Data Models ─────────────────────────────────────────────────────────────

class HourlyActivity {
  final String hour;
  final int count;
  const HourlyActivity({required this.hour, required this.count});
}

class AnalyticsCandidateScore {
  final String candidateId;
  final String name;
  final double score;
  final bool isWinner;
  final String positionTitle;
  const AnalyticsCandidateScore({
    required this.candidateId,
    required this.name,
    required this.score,
    required this.isWinner,
    required this.positionTitle,
  });
}

class ElectionAnalytics {
  final int totalEligible;
  final int totalVoted;
  final double turnoutPercent;
  final List<HourlyActivity> activityByHour;
  final List<AnalyticsCandidateScore> topCandidates;
  final int peakCount;

  const ElectionAnalytics({
    required this.totalEligible,
    required this.totalVoted,
    required this.turnoutPercent,
    required this.activityByHour,
    required this.topCandidates,
    required this.peakCount,
  });

  factory ElectionAnalytics.empty() => const ElectionAnalytics(
        totalEligible: 0,
        totalVoted: 0,
        turnoutPercent: 0,
        activityByHour: [],
        topCandidates: [],
        peakCount: 0,
      );
}

// ─── Provider ─────────────────────────────────────────────────────────────────

final analyticsProvider =
    StreamProvider.autoDispose.family<ElectionAnalytics, String>((ref, electionId) async* {
  final dio = ref.watch(apiClientProvider);

  while (true) {
    try {
      // 1. Turnout data
      final turnoutResp = await dio.get(ApiConstants.electionTurnout(electionId));
      final turnoutData = turnoutResp.data as Map<String, dynamic>;
      final totalEligible = (turnoutData['total_eligible'] as num?)?.toInt() ?? 0;
      final totalVoted = (turnoutData['total_voted'] as num?)?.toInt() ?? 0;
      final turnoutPercent =
          totalEligible > 0 ? (totalVoted / totalEligible) * 100 : 0.0;

      // 2. Voting activity (hourly) — admin-only, silently skip for members
      List<HourlyActivity> activityByHour = [];
      try {
        final activityResp =
            await dio.get(ApiConstants.electionVotingActivity(electionId));
        final activityData = activityResp.data as Map<String, dynamic>;
        final raw = activityData['activity_by_hour'] as List<dynamic>? ?? [];
        activityByHour = raw
            .map((e) => HourlyActivity(
                  hour: e['hour'] as String? ?? '',
                  count: (e['count'] as num?)?.toInt() ?? 0,
                ))
            .toList();
      } catch (_) {
        // Non-admin — silently skip
      }

      // 3. Candidate scores from results endpoint
      List<AnalyticsCandidateScore> topCandidates = [];
      try {
        final resultsResp = await dio.get(ApiConstants.results(electionId));
        final resultsData = resultsResp.data as Map<String, dynamic>;
        final positions = resultsData['results'] as List<dynamic>? ?? [];
        for (final pos in positions) {
          final posMap = pos as Map<String, dynamic>;
          final posTitle = posMap['title'] as String? ?? '';
          final winners = List<String>.from(posMap['winners'] ?? []);
          final breakdown = posMap['breakdown'] as List<dynamic>? ?? [];
          for (final cand in breakdown) {
            final candMap = cand as Map<String, dynamic>;
            topCandidates.add(AnalyticsCandidateScore(
              candidateId: candMap['candidate_id'] as String? ?? '',
              name: candMap['name'] as String? ?? '',
              score: (candMap['score'] as num?)?.toDouble() ?? 0.0,
              isWinner: winners.contains(candMap['candidate_id']),
              positionTitle: posTitle,
            ));
          }
        }
        topCandidates.sort((a, b) => b.score.compareTo(a.score));
      } catch (_) {
        // Results not available yet — fine
      }

      final peakCount = activityByHour.isEmpty
          ? 0
          : activityByHour.map((e) => e.count).reduce((a, b) => a > b ? a : b);

      yield ElectionAnalytics(
        totalEligible: totalEligible,
        totalVoted: totalVoted,
        turnoutPercent: turnoutPercent,
        activityByHour: activityByHour,
        topCandidates: topCandidates,
        peakCount: peakCount,
      );
    } catch (_) {
      yield ElectionAnalytics.empty();
    }

    await Future.delayed(const Duration(seconds: 8));
  }
});
