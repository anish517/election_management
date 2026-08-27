import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../network/api_client.dart';
import '../network/api_constants.dart';
import '../../shared/models/models.dart';

// ─── Elections Provider ──────────────────────────────────────────────────────

final electionsProvider = FutureProvider.autoDispose<List<ElectionModel>>((ref) async {
  final dio = ref.watch(apiClientProvider);
  final resp = await dio.get(ApiConstants.elections);
  final data = resp.data;
  List<dynamic> list;
  if (data is List) {
    list = data;
  } else if (data is Map && data.containsKey('results')) {
    list = data['results'] as List<dynamic>;
  } else {
    list = [];
  }
  return list
      .map((e) => ElectionModel.fromJson(e as Map<String, dynamic>))
      .toList();
});

// ─── Single Election Provider ─────────────────────────────────────────────────

final electionProvider = FutureProvider.autoDispose.family<ElectionModel, String>((ref, id) async {
  final dio = ref.watch(apiClientProvider);
  final resp = await dio.get(ApiConstants.electionDetail(id));
  return ElectionModel.fromJson(resp.data as Map<String, dynamic>);
});

// ─── Ballot Data Model ───────────────────────────────────────────────────────

class BallotData {
  final List<PositionModel> positions;
  final bool hasVoted;
  final bool notEligible;
  final String notEligibleReason;
  final Map<String, dynamic>? voterInfo;
  final bool allowBoycott;
  const BallotData({
    required this.positions,
    required this.hasVoted,
    required this.notEligible,
    required this.notEligibleReason,
    this.voterInfo,
    required this.allowBoycott,
  });
}

// ─── Ballot Provider ─────────────────────────────────────────────────────────

final ballotDataProvider = FutureProvider.autoDispose.family<BallotData, String>((ref, electionId) async {
  final dio = ref.watch(apiClientProvider);
  final resp = await dio.get(ApiConstants.ballot(electionId));
  final data = resp.data;
  List<dynamic> list;
  bool hasVoted = false;
  bool notEligible = false;
  String notEligibleReason = '';
  Map<String, dynamic>? voterInfo;
  bool allowBoycott = true;
  if (data is Map) {
    list = (data['ballot'] as List<dynamic>?) ?? [];
    hasVoted = data['has_voted'] as bool? ?? false;
    notEligible = data['not_eligible'] as bool? ?? false;
    notEligibleReason = data['not_eligible_reason'] as String? ?? '';
    voterInfo = data['voter_info'] as Map<String, dynamic>?;
    allowBoycott = data['allow_boycott'] as bool? ?? true;
  } else if (data is List) {
    list = data;
  } else {
    list = [];
  }
  final positions = list
      .map((p) => PositionModel.fromJson(p as Map<String, dynamic>))
      .toList();
  return BallotData(
    positions: positions,
    hasVoted: hasVoted,
    notEligible: notEligible,
    notEligibleReason: notEligibleReason,
    voterInfo: voterInfo,
    allowBoycott: allowBoycott,
  );
});

// Backwards-compatible provider for screens that only need positions
final ballotProvider = FutureProvider.autoDispose.family<List<PositionModel>, String>((ref, electionId) async {
  final data = await ref.watch(ballotDataProvider(electionId).future);
  return data.positions;
});

// ─── Results Provider ────────────────────────────────────────────────────────

final resultsProvider = FutureProvider.autoDispose.family<TallyResult, String>((ref, electionId) async {
  final dio = ref.watch(apiClientProvider);
  final resp = await dio.get(ApiConstants.results(electionId));
  return TallyResult.fromJson(resp.data as Map<String, dynamic>);
});

// ─── Turnout Provider ────────────────────────────────────────────────────────

final electionTurnoutProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, electionId) async {
  final dio = ref.watch(apiClientProvider);
  final resp = await dio.get(ApiConstants.electionTurnout(electionId));
  return resp.data as Map<String, dynamic>;
});

// ─── Members Provider ────────────────────────────────────────────────────────

final membersProvider = FutureProvider.autoDispose<List<MemberModel>>((ref) async {
  final dio = ref.watch(apiClientProvider);
  final resp = await dio.get(ApiConstants.members);
  final data = resp.data;
  List<dynamic> list;
  if (data is Map && data.containsKey('results')) {
    list = data['results'] as List<dynamic>;
  } else if (data is List) {
    list = data;
  } else {
    list = [];
  }
  return list
      .map((m) => MemberModel.fromJson(m as Map<String, dynamic>))
      .toList();
});

// ─── Ballot Selections (local state — NEVER persisted to disk) ───────────────

/// Maps position_id → list of chosen candidate_ids
class BallotSelectionsNotifier extends StateNotifier<Map<String, List<String>>> {
  BallotSelectionsNotifier() : super({});

  void toggleCandidate({
    required String positionId,
    required String candidateId,
    required int maxSeats,
    bool isApproval = false,
    bool isRankedChoice = false,
  }) {
    final current = Map<String, List<String>>.from(state);
    final positionSelections = List<String>.from(current[positionId] ?? []);

    // If No Vote / Boycott was selected, remove it
    positionSelections.remove('__BOYCOTT__');
    positionSelections.remove('__NO_VOTE__');
    positionSelections.remove('NOTA');

    if (positionSelections.contains(candidateId)) {
      positionSelections.remove(candidateId);
    } else {
      if (isApproval || isRankedChoice || positionSelections.length < maxSeats) {
        positionSelections.add(candidateId);
      }
      // If maxSeats == 1 (FPTP) and it's not approval/ranked, replace selection
      if (!isApproval && !isRankedChoice && maxSeats == 1) {
        positionSelections
          ..clear()
          ..add(candidateId);
      }
    }
    current[positionId] = positionSelections;
    state = current;
  }

  void toggleNoVote(String positionId) {
    final current = Map<String, List<String>>.from(state);
    final positionSelections = List<String>.from(current[positionId] ?? []);
    final isAlreadyNoVote = positionSelections.contains('__NO_VOTE__') ||
        positionSelections.contains('__BOYCOTT__') ||
        positionSelections.contains('NOTA');

    if (isAlreadyNoVote) {
      positionSelections.clear();
    } else {
      positionSelections
        ..clear()
        ..add('__NO_VOTE__');
    }
    current[positionId] = positionSelections;
    state = current;
  }

  void toggleBoycott(String positionId) {
    toggleNoVote(positionId);
  }

  void boycottEntireElection(List<PositionModel> positions) {
    final current = <String, List<String>>{};
    for (final p in positions) {
      current[p.id] = ['__NO_VOTE__'];
    }
    state = current;
  }

  bool isNoVote(String positionId) {
    final list = state[positionId];
    if (list == null || list.isEmpty) return false;
    return list.contains('__NO_VOTE__') || list.contains('__BOYCOTT__') || list.contains('NOTA');
  }

  bool isBoycotted(String positionId) {
    return isNoVote(positionId);
  }

  bool isSelected(String positionId, String candidateId) {
    return state[positionId]?.contains(candidateId) ?? false;
  }

  bool hasContestDecision(String positionId) {
    final list = state[positionId];
    return list != null && list.isNotEmpty;
  }

  int completedContestsCount(List<PositionModel> positions) {
    int count = 0;
    for (final p in positions) {
      if (hasContestDecision(p.id)) count++;
    }
    return count;
  }

  int? getRank(String positionId, String candidateId) {
    final list = state[positionId];
    if (list == null) return null;
    final index = list.indexOf(candidateId);
    if (index == -1) return null;
    return index + 1;
  }

  void clear() => state = {};

  bool get hasAnySelection => state.values.any((list) => list.isNotEmpty);
}

final ballotSelectionsProvider =
    StateNotifierProvider.autoDispose<BallotSelectionsNotifier, Map<String, List<String>>>(
  (ref) => BallotSelectionsNotifier(),
);

// ─── Voting Service ──────────────────────────────────────────────────────────

class VotingService {
  final Dio _dio;
  VotingService(this._dio);

  Future<String> startSession(String electionId) async {
    final resp = await _dio.post(ApiConstants.votingSession(electionId));
    return resp.data['session_token'] as String;
  }

  Future<String> castVote({
    required String electionId,
    required String sessionToken,
    required Map<String, List<String>> ballotData,
    String? deviceIdentifier,
  }) async {
    final data = <String, dynamic>{
      'session_token': sessionToken,
      'ballot_data': ballotData,
    };
    if (deviceIdentifier != null) {
      data['device_identifier'] = deviceIdentifier;
    }
    final resp = await _dio.post(ApiConstants.castVote(electionId), data: data);
    return resp.data['receipt_hash'] as String;
  }
}

final votingServiceProvider = Provider<VotingService>((ref) {
  return VotingService(ref.watch(apiClientProvider));
});
