import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../network/api_client.dart';
import '../network/api_constants.dart';
import 'app_providers.dart';

// ─── Election Management ──────────────────────────────────────────────────

class CreateElectionNotifier extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  Future<void> createElection({
    required String title,
    required String description,
    // Branding
    String? prefix,
    String? logoUrl,
    String? contactNumber,
    String? primaryColor,
    String? secondaryColor,
    // Election schedule
    DateTime? votingStartAt,
    DateTime? votingEndAt,
    // Voter list schedule
    DateTime? firstVoterListDate,
    DateTime? voterListClaimDate,
    DateTime? finalVoterListDate,
    // Candidacy schedule
    DateTime? nominationOpenAt,
    DateTime? nominationCloseAt,
    DateTime? candidacyClaimDate,
    DateTime? candidacyFinalDate,
    // Payment
    bool isPaidCandidacy = false,
    double nomineeCharge = 0,
  }) async {
    if (state.isLoading) return;
    state = const AsyncValue.loading();
    try {
      final dio = ref.read(apiClientProvider);
      final data = {
        'title': title,
        'description': description,
        'state': 'draft',
        if (prefix != null && prefix.isNotEmpty) 'prefix': prefix,
        if (logoUrl != null && logoUrl.isNotEmpty) 'logo_url': logoUrl,
        if (contactNumber != null && contactNumber.isNotEmpty) 'contact_number': contactNumber,
        'primary_color': primaryColor,
        'secondary_color': secondaryColor,
        if (votingStartAt != null) 'voting_start_at': votingStartAt.toUtc().toIso8601String(),
        if (votingEndAt != null) 'voting_end_at': votingEndAt.toUtc().toIso8601String(),
        if (firstVoterListDate != null) 'first_voter_list_date': firstVoterListDate.toUtc().toIso8601String(),
        if (voterListClaimDate != null) 'voter_list_claim_date': voterListClaimDate.toUtc().toIso8601String(),
        if (finalVoterListDate != null) 'final_voter_list_date': finalVoterListDate.toUtc().toIso8601String(),
        if (nominationOpenAt != null) 'nomination_open_at': nominationOpenAt.toUtc().toIso8601String(),
        if (nominationCloseAt != null) 'nomination_close_at': nominationCloseAt.toUtc().toIso8601String(),
        if (candidacyClaimDate != null) 'candidacy_claim_date': candidacyClaimDate.toUtc().toIso8601String(),
        if (candidacyFinalDate != null) 'candidacy_final_date': candidacyFinalDate.toUtc().toIso8601String(),
        'is_paid_candidacy': isPaidCandidacy,
        'nominee_charge': nomineeCharge,
      };
      await dio.post(ApiConstants.elections, data: data);
      
      // Invalidate elections list so it refreshes
      ref.invalidate(electionsProvider);
      state = const AsyncValue.data(null);
    } on DioException catch (e) {
      final err = e.response?.data is Map ? (e.response?.data['detail'] ?? e.response?.data.toString()) : e.message;
      state = AsyncValue.error(err ?? 'Failed to create election', StackTrace.current);
      rethrow;
    }
  }

}

final createElectionProvider = AsyncNotifierProvider<CreateElectionNotifier, void>(
  () => CreateElectionNotifier(),
);

class PublishElectionNotifier extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  Future<void> publishElection(String electionId) async {
    if (state.isLoading) return;
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final dio = ref.read(apiClientProvider);
      await dio.post(ApiConstants.electionPublish(electionId));
      ref.invalidate(electionProvider(electionId));
      ref.invalidate(electionsProvider);
    });
    if (state.hasError) {
      throw state.error!;
    }
  }

  Future<void> advanceElectionState(String electionId, String targetState) async {
    if (state.isLoading) return;
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final dio = ref.read(apiClientProvider);
      await dio.post(ApiConstants.electionAdvanceState(electionId), data: {'state': targetState});
      ref.invalidate(electionProvider(electionId));
      ref.invalidate(electionsProvider);
    });
    if (state.hasError) {
      throw state.error!;
    }
  }

  Future<void> deleteElection(String electionId) async {
    if (state.isLoading) return;
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final dio = ref.read(apiClientProvider);
      await dio.delete(ApiConstants.electionDetail(electionId));
      ref.invalidate(electionsProvider);
    });
    if (state.hasError) {
      throw state.error!;
    }
  }

  Future<void> addPosition(Map<String, dynamic> data) async {
    if (state.isLoading) return;
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final dio = ref.read(apiClientProvider);
      await dio.post(ApiConstants.electionPositions(data['election'] as String), data: data);
      ref.invalidate(electionProvider(data['election'] as String));
    });
    if (state.hasError) {
      throw state.error!;
    }
  }

  Future<void> addCandidate(Map<String, dynamic> data) async {
    if (state.isLoading) return;
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final dio = ref.read(apiClientProvider);
      await dio.post(ApiConstants.electionCandidates(data['election'] as String), data: data);
      ref.invalidate(electionProvider(data['election'] as String));
    });
    if (state.hasError) {
      throw state.error!;
    }
  }

  Future<void> addVoter(Map<String, dynamic> data) async {
    if (state.isLoading) return;
    state = const AsyncValue.loading();
    try {
      final dio = ref.read(apiClientProvider);
      await dio.post(ApiConstants.electionVoters(data['election'] as String), data: data);
      ref.invalidate(votersProvider(data['election'] as String));
      state = const AsyncValue.data(null);
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      rethrow;
    }
  }

  Future<void> editVoter(String electionId, String voterId, Map<String, dynamic> data) async {
    if (state.isLoading) return;
    state = const AsyncValue.loading();
    try {
      final dio = ref.read(apiClientProvider);
      await dio.put('${ApiConstants.electionVoters(electionId)}$voterId/', data: data);
      ref.invalidate(votersProvider(electionId));
      state = const AsyncValue.data(null);
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      rethrow;
    }
  }

  Future<void> deleteVoter(String electionId, String voterId) async {
    if (state.isLoading) return;
    state = const AsyncValue.loading();
    try {
      final dio = ref.read(apiClientProvider);
      await dio.delete('${ApiConstants.electionVoters(electionId)}$voterId/');
      ref.invalidate(votersProvider(electionId));
      state = const AsyncValue.data(null);
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      rethrow;
    }
  }
}

final publishElectionProvider = AsyncNotifierProvider<PublishElectionNotifier, void>(
  () => PublishElectionNotifier(),
);

// ─── Voters Provider ────────────────────────────────────────────────────────

final votersProvider = FutureProvider.family<List<dynamic>, String>((ref, electionId) async {
  final dio = ref.watch(apiClientProvider);
  final response = await dio.get(ApiConstants.electionVoters(electionId));
  if (response.data is Map<String, dynamic>) {
    return response.data['results'] as List<dynamic>;
  }
  return response.data as List<dynamic>;
});

// ─── Candidates Management ────────────────────────────────────────────────

class AddCandidateNotifier extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  Future<void> addCandidate({
    required String electionId,
    required String positionId,
    required String memberId,
    required String manifesto,
    required String slateName,
    required String status,
  }) async {
    if (state.isLoading) return;
    state = const AsyncValue.loading();
    try {
      final dio = ref.read(apiClientProvider);
      await dio.post(ApiConstants.electionCandidates(electionId), data: {
        'position': positionId,
        'member': memberId,
        'manifesto': manifesto,
        'slate_name': slateName,
        'status': status,
      });
      ref.invalidate(electionProvider(electionId));
      state = const AsyncValue.data(null);
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      rethrow;
    }
  }

  Future<void> deletePosition({
    required String electionId,
    required String positionId,
  }) async {
    if (state.isLoading) return;
    state = const AsyncValue.loading();
    try {
      final dio = ref.read(apiClientProvider);
      await dio.delete('${ApiConstants.electionPositions(electionId)}$positionId/');
      ref.invalidate(electionProvider(electionId));
      state = const AsyncValue.data(null);
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      rethrow;
    }
  }

  Future<void> deleteCandidate({
    required String electionId,
    required String candidateId,
  }) async {
    if (state.isLoading) return;
    state = const AsyncValue.loading();
    try {
      final dio = ref.read(apiClientProvider);
      await dio.delete('${ApiConstants.electionCandidates(electionId)}$candidateId/');
      ref.invalidate(electionProvider(electionId));
      state = const AsyncValue.data(null);
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      rethrow;
    }
  }
}

final addCandidateProvider = AsyncNotifierProvider<AddCandidateNotifier, void>(
  () => AddCandidateNotifier(),
);

// ─── Members Management ───────────────────────────────────────────────────

class AddMemberNotifier extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  Future<void> addMember({
    required String fullName,
    required String email,
    required String memberCode,
    required String phone,
    required String photoUrl,
    required String gender,
    required String department,
    required String region,
    required String positionTitle,
    required String membershipStatus,
    String? membershipExpiryDate,
    required double votingWeight,
  }) async {
    if (state.isLoading) return;
    state = const AsyncValue.loading();
    try {
      final dio = ref.read(apiClientProvider);
      await dio.post(ApiConstants.members, data: {
        'full_name': fullName,
        'email': email,
        'member_code': memberCode,
        'phone': phone,
        'photo_url': photoUrl,
        'gender': gender,
        'department': department,
        'region': region,
        'position_title': positionTitle,
        'membership_status': membershipStatus,
        if (membershipExpiryDate != null && membershipExpiryDate.isNotEmpty)
          'membership_expiry_date': membershipExpiryDate,
        'voting_weight': votingWeight.toString(),
      });
      ref.invalidate(membersProvider);
      state = const AsyncValue.data(null);
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      rethrow;
    }
  }

  Future<void> deleteMember(String memberId) async {
    if (state.isLoading) return;
    state = const AsyncValue.loading();
    try {
      final dio = ref.read(apiClientProvider);
      await dio.delete('${ApiConstants.members}$memberId/');
      ref.invalidate(membersProvider);
      state = const AsyncValue.data(null);
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      rethrow;
    }
  }
}

final addMemberProvider = AsyncNotifierProvider<AddMemberNotifier, void>(
  () => AddMemberNotifier(),
);

