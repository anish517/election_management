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

// ─── Ballot Provider ─────────────────────────────────────────────────────────

final ballotProvider = FutureProvider.autoDispose.family<List<PositionModel>, String>((ref, electionId) async {
  final dio = ref.watch(apiClientProvider);
  final resp = await dio.get(ApiConstants.ballot(electionId));
  final data = resp.data;
  List<dynamic> list;
  if (data is Map && data.containsKey('ballot')) {
    list = data['ballot'] as List<dynamic>;
  } else if (data is List) {
    list = data;
  } else {
    list = [];
  }
  return list
      .map((p) => PositionModel.fromJson(p as Map<String, dynamic>))
      .toList();
});

// ─── Results Provider ────────────────────────────────────────────────────────

final resultsProvider = FutureProvider.autoDispose.family<TallyResult, String>((ref, electionId) async {
  final dio = ref.watch(apiClientProvider);
  final resp = await dio.get(ApiConstants.results(electionId));
  return TallyResult.fromJson(resp.data as Map<String, dynamic>);
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
  }) {
    final current = Map<String, List<String>>.from(state);
    final positionSelections = List<String>.from(current[positionId] ?? []);

    if (positionSelections.contains(candidateId)) {
      positionSelections.remove(candidateId);
    } else {
      if (positionSelections.length < maxSeats) {
        positionSelections.add(candidateId);
      }
      // If maxSeats == 1 (FPTP), replace selection
      if (maxSeats == 1) {
        positionSelections
          ..clear()
          ..add(candidateId);
      }
    }
    current[positionId] = positionSelections;
    state = current;
  }

  bool isSelected(String positionId, String candidateId) {
    return state[positionId]?.contains(candidateId) ?? false;
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
  }) async {
    final resp = await _dio.post(ApiConstants.castVote(electionId), data: {
      'session_token': sessionToken,
      'ballot_data': ballotData,
    });
    return resp.data['receipt_hash'] as String;
  }
}

final votingServiceProvider = Provider<VotingService>((ref) {
  return VotingService(ref.watch(apiClientProvider));
});
