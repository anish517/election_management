import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../network/api_client.dart';
import '../network/api_constants.dart';
import '../../shared/models/models.dart';
import 'app_providers.dart';

// ─── Election Management ──────────────────────────────────────────────────

class CreateElectionNotifier extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  Future<void> createElection({
    required String title,
    required String description,
  }) async {
    if (state.isLoading) return;
    state = const AsyncValue.loading();
    try {
      final dio = ref.read(apiClientProvider);
      final data = {
        'title': title,
        'description': description,
        'state': 'draft',
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
}

final publishElectionProvider = AsyncNotifierProvider<PublishElectionNotifier, void>(
  () => PublishElectionNotifier(),
);

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
}

final addMemberProvider = AsyncNotifierProvider<AddMemberNotifier, void>(
  () => AddMemberNotifier(),
);

