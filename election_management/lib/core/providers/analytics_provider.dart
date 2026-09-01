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
  final String photoUrl;
  final double score;
  final bool isWinner;
  final String positionTitle;
  const AnalyticsCandidateScore({
    required this.candidateId,
    required this.name,
    this.photoUrl = '',
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

      // 3. Candidate & Party scores from results endpoint
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
            final photo = (candMap['photo_url'] as String?) ??
                (candMap['candidate_image'] as String?) ??
                (candMap['photo'] as String?) ??
                '';
            topCandidates.add(AnalyticsCandidateScore(
              candidateId: candMap['candidate_id'] as String? ?? '',
              name: candMap['name'] as String? ?? '',
              photoUrl: photo,
              score: (candMap['score'] as num?)?.toDouble() ?? 0.0,
              isWinner: winners.contains(candMap['candidate_id']) && ((candMap['score'] as num?)?.toDouble() ?? 0.0) > 0,
              positionTitle: posTitle,
            ));
          }
        }

        // Also check for Samānupātik party scores
        final prScores = (resultsData['party_results'] as List<dynamic>?) ??
            ((resultsData['samanupatik_results'] as Map<String, dynamic>?)?['party_scores'] as List<dynamic>? ?? []);
        for (final party in prScores) {
          final pMap = party as Map<String, dynamic>;
          final partyName = pMap['party_name'] as String? ?? '';
          final photo = (pMap['symbol_image'] as String?) ?? '';
          final seatsWon = (pMap['seats_allocated'] as num?)?.toInt() ??
              (pMap['allocated_seats'] as num?)?.toInt() ??
              0;
          final votes = (pMap['votes'] as num?)?.toDouble() ??
              (pMap['valid_votes'] as num?)?.toDouble() ??
              (pMap['score'] as num?)?.toDouble() ??
              0.0;
          final isWinner = (pMap['is_winner'] == true || seatsWon > 0 || pMap['is_qualified'] == true) && votes > 0;
          final posTitle = seatsWon > 0
              ? 'Samānupātik PR ($seatsWon seats won / $seatsWon सिट विजयी)'
              : 'Samānupātik Party Slate (समानुपातिक दल)';

          topCandidates.add(AnalyticsCandidateScore(
            candidateId: partyName,
            name: partyName,
            photoUrl: photo,
            score: votes,
            isWinner: isWinner,
            positionTitle: posTitle,
          ));
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
