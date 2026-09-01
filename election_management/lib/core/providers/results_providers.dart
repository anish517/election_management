import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../network/api_client.dart';
import '../network/api_constants.dart';
import '../../shared/models/models.dart';

class CandidateResult {
  final String candidateId;
  final String name;
  final String photoUrl;
  final String partyName;
  final String panelName;
  final String symbolName;
  final String symbolImage;
  final int prRank;
  final double score;
  final int rank;
  final bool isElected;
  final bool isUncontested;
  final bool isTie;

  CandidateResult({
    required this.candidateId,
    required this.name,
    this.photoUrl = '',
    this.partyName = '',
    this.panelName = '',
    this.symbolName = '',
    this.symbolImage = '',
    this.prRank = 1,
    required this.score,
    this.rank = 0,
    this.isElected = false,
    this.isUncontested = false,
    this.isTie = false,
  });

  factory CandidateResult.fromJson(Map<String, dynamic> json) {
    return CandidateResult(
      candidateId: json['candidate_id'] ?? '',
      name: json['name'] ?? '',
      photoUrl: json['photo_url'] ?? '',
      partyName: json['party_name'] ?? '',
      panelName: json['panel_name'] ?? '',
      symbolName: json['symbol_name'] ?? '',
      symbolImage: json['symbol_image'] ?? '',
      prRank: json['pr_rank'] as int? ?? 1,
      score: (json['score'] as num?)?.toDouble() ?? 0.0,
      rank: json['rank'] as int? ?? 0,
      isElected: json['is_elected'] as bool? ?? false,
      isUncontested: json['is_uncontested'] as bool? ?? false,
      isTie: json['is_tie'] as bool? ?? false,
    );
  }
}

class PositionResult {
  final String positionId;
  final String title;
  final int seatsAvailable;
  final bool hasTie;
  final bool isUncontested;
  final int totalValidBallots;
  final List<String> winners;
  final List<CandidateResult> breakdown;

  PositionResult({
    required this.positionId,
    required this.title,
    this.seatsAvailable = 1,
    this.hasTie = false,
    this.isUncontested = false,
    required this.totalValidBallots,
    required this.winners,
    required this.breakdown,
  });

  factory PositionResult.fromJson(Map<String, dynamic> json) {
    return PositionResult(
      positionId: json['position_id'] ?? '',
      title: json['title'] ?? '',
      seatsAvailable: json['seats_available'] as int? ?? 1,
      hasTie: json['has_tie'] as bool? ?? false,
      isUncontested: json['is_uncontested'] as bool? ?? false,
      totalValidBallots: (json['total_valid_ballots'] as num?)?.toInt() ?? 0,
      winners: List<String>.from(json['winners'] ?? []),
      breakdown: (json['breakdown'] as List? ?? [])
          .map((e) => CandidateResult.fromJson(e))
          .toList(),
    );
  }
}

class ElectionResults {
  final String electionId;
  final String electionTitle;
  final String electionType;
  final int totalVoters;
  final int ballotsCast;
  final double turnoutPercentage;
  final List<PositionResult> results;
  final int totalPrSeats;
  final double prThresholdPercent;
  final String prAllocationMethod;
  final double totalValidPartyVotes;
  final double boycottScore;
  final List<PartyPRScore> partyResults;
  final List<dynamic> seatAllocationTable;

  ElectionResults({
    required this.electionId,
    required this.electionTitle,
    this.electionType = 'fptp',
    this.totalVoters = 0,
    this.ballotsCast = 0,
    this.turnoutPercentage = 0.0,
    this.results = const [],
    this.totalPrSeats = 10,
    this.prThresholdPercent = 0.0,
    this.prAllocationMethod = 'sainte_lague',
    this.totalValidPartyVotes = 0.0,
    this.boycottScore = 0.0,
    this.partyResults = const [],
    this.seatAllocationTable = const [],
  });

  bool get isSamanupatik => electionType == 'samanupatik';
  bool get isMixed => electionType == 'mixed';
  bool get isFptp => electionType == 'fptp';
  bool get hasPrSystem => isSamanupatik || isMixed;
  bool get hasFptpSystem => isFptp || isMixed;

  factory ElectionResults.fromJson(Map<String, dynamic> json) {
    final prJson = (json['samanupatik_results'] as Map<String, dynamic>?) ?? json;

    return ElectionResults(
      electionId: json['election_id'] ?? '',
      electionTitle: json['election_title'] ?? '',
      electionType: json['election_type'] as String? ?? 'fptp',
      totalVoters: (json['total_voters'] as num?)?.toInt() ?? 0,
      ballotsCast: (json['ballots_cast'] as num?)?.toInt() ?? 0,
      turnoutPercentage: (json['turnout_percentage'] as num?)?.toDouble() ?? 0.0,
      results: (json['results'] as List? ?? [])
          .map((e) => PositionResult.fromJson(e))
          .toList(),
      totalPrSeats: (prJson['total_pr_seats'] as num?)?.toInt() ?? 10,
      prThresholdPercent: (prJson['pr_threshold_percent'] as num?)?.toDouble() ?? 0.0,
      prAllocationMethod: prJson['pr_allocation_method'] as String? ?? 'modified_sainte_lague',
      totalValidPartyVotes: (prJson['total_valid_party_votes'] as num?)?.toDouble() ?? 0.0,
      boycottScore: (prJson['boycott_score'] as num?)?.toDouble() ?? 0.0,
      partyResults: (prJson['party_results'] as List? ?? [])
          .map((p) => PartyPRScore.fromJson(p as Map<String, dynamic>))
          .toList(),
      seatAllocationTable: (prJson['seat_allocation_table'] as List? ?? []),
    );
  }
}

final electionResultsProvider = FutureProvider.family<ElectionResults, String>((ref, electionId) async {
  final dio = ref.watch(apiClientProvider);
  final response = await dio.get(ApiConstants.results(electionId));
  return ElectionResults.fromJson(response.data);
});
