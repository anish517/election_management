import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../network/api_client.dart';
import '../network/api_constants.dart';
import '../../shared/models/models.dart';
import 'app_providers.dart';

// ─── Election Management ──────────────────────────────────────────────────

class CreateElectionNotifier extends AutoDisposeAsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  Future<void> createElection({
    required String title,
    required String description,
    required DateTime votingStartAt,
    required DateTime votingEndAt,
  }) async {
    state = const AsyncValue.loading();
    try {
      final dio = ref.read(apiClientProvider);
      final data = {
        'title': title,
        'description': description,
        'voting_start_at': votingStartAt.toIso8601String(),
        'voting_end_at': votingEndAt.toIso8601String(),
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

final createElectionProvider = AutoDisposeAsyncNotifierProvider<CreateElectionNotifier, void>(
  () => CreateElectionNotifier(),
);

class PublishElectionNotifier extends AutoDisposeAsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  Future<void> publishElection(String electionId) async {
    state = const AsyncValue.loading();
    try {
      final dio = ref.read(apiClientProvider);
      await dio.post(ApiConstants.electionPublish(electionId));
      ref.invalidate(electionProvider(electionId));
      ref.invalidate(electionsProvider);
      state = const AsyncValue.data(null);
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      rethrow;
    }
  }

  Future<void> advanceElectionState(String electionId, String targetState) async {
    state = const AsyncValue.loading();
    try {
      final dio = ref.read(apiClientProvider);
      await dio.post(ApiConstants.electionAdvanceState(electionId), data: {'state': targetState});
      ref.invalidate(electionProvider(electionId));
      ref.invalidate(electionsProvider);
      state = const AsyncValue.data(null);
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      rethrow;
    }
  }
}

final publishElectionProvider = AutoDisposeAsyncNotifierProvider<PublishElectionNotifier, void>(
  () => PublishElectionNotifier(),
);

// ─── Candidates Management ────────────────────────────────────────────────

class AddCandidateNotifier extends AutoDisposeAsyncNotifier<void> {
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

final addCandidateProvider = AutoDisposeAsyncNotifierProvider<AddCandidateNotifier, void>(
  () => AddCandidateNotifier(),
);

// ─── Members Management ───────────────────────────────────────────────────

class AddMemberNotifier extends AutoDisposeAsyncNotifier<void> {
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

final addMemberProvider = AutoDisposeAsyncNotifierProvider<AddMemberNotifier, void>(
  () => AddMemberNotifier(),
);

