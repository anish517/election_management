import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../network/api_client.dart';
import '../network/api_constants.dart';

class CandidateResult {
  final String candidateId;
  final String name;
  final double score;
  final int rank;
  final bool isElected;
  final bool isTie;

  CandidateResult({
    required this.candidateId,
    required this.name,
    required this.score,
    this.rank = 0,
    this.isElected = false,
    this.isTie = false,
  });

  factory CandidateResult.fromJson(Map<String, dynamic> json) {
    return CandidateResult(
      candidateId: json['candidate_id'],
      name: json['name'],
      score: (json['score'] as num).toDouble(),
      rank: json['rank'] as int? ?? 0,
      isElected: json['is_elected'] as bool? ?? false,
      isTie: json['is_tie'] as bool? ?? false,
    );
  }
}

class PositionResult {
  final String positionId;
  final String title;
  final int seatsAvailable;
  final bool hasTie;
  final int totalValidBallots;
  final List<String> winners;
  final List<CandidateResult> breakdown;

  PositionResult({
    required this.positionId,
    required this.title,
    this.seatsAvailable = 1,
    this.hasTie = false,
    required this.totalValidBallots,
    required this.winners,
    required this.breakdown,
  });

  factory PositionResult.fromJson(Map<String, dynamic> json) {
    return PositionResult(
      positionId: json['position_id'],
      title: json['title'],
      seatsAvailable: json['seats_available'] as int? ?? 1,
      hasTie: json['has_tie'] as bool? ?? false,
      totalValidBallots: json['total_valid_ballots'] as int,
      winners: List<String>.from(json['winners'] ?? []),
      breakdown: (json['breakdown'] as List)
          .map((e) => CandidateResult.fromJson(e))
          .toList(),
    );
  }
}

class ElectionResults {
  final String electionId;
  final String electionTitle;
  final List<PositionResult> results;

  ElectionResults({
    required this.electionId,
    required this.electionTitle,
    required this.results,
  });

  factory ElectionResults.fromJson(Map<String, dynamic> json) {
    return ElectionResults(
      electionId: json['election_id'],
      electionTitle: json['election_title'],
      results: (json['results'] as List)
          .map((e) => PositionResult.fromJson(e))
          .toList(),
    );
  }
}

final electionResultsProvider = FutureProvider.family<ElectionResults, String>((ref, electionId) async {
  final dio = ref.watch(apiClientProvider);
  final response = await dio.get(ApiConstants.results(electionId));
  return ElectionResults.fromJson(response.data);
});
