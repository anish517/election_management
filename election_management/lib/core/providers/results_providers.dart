import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../network/api_client.dart';
import '../network/api_constants.dart';

class CandidateResult {
  final String candidateId;
  final String name;
  final double score;

  CandidateResult({
    required this.candidateId,
    required this.name,
    required this.score,
  });

  factory CandidateResult.fromJson(Map<String, dynamic> json) {
    return CandidateResult(
      candidateId: json['candidate_id'],
      name: json['name'],
      score: (json['score'] as num).toDouble(),
    );
  }
}

class PositionResult {
  final String positionId;
  final String title;
  final int totalValidBallots;
  final List<String> winners;
  final List<CandidateResult> breakdown;

  PositionResult({
    required this.positionId,
    required this.title,
    required this.totalValidBallots,
    required this.winners,
    required this.breakdown,
  });

  factory PositionResult.fromJson(Map<String, dynamic> json) {
    return PositionResult(
      positionId: json['position_id'],
      title: json['title'],
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
