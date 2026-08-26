import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/models/models.dart';
import '../network/api_client.dart';
import '../network/api_constants.dart';

class PaymentFilterState {
  final String status;
  final String electionId;
  final String searchQuery;

  const PaymentFilterState({
    this.status = 'all',
    this.electionId = '',
    this.searchQuery = '',
  });

  PaymentFilterState copyWith({
    String? status,
    String? electionId,
    String? searchQuery,
  }) {
    return PaymentFilterState(
      status: status ?? this.status,
      electionId: electionId ?? this.electionId,
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }
}

final paymentFilterProvider = StateProvider.autoDispose<PaymentFilterState>(
  (ref) => const PaymentFilterState(),
);

final paymentsListProvider = FutureProvider.autoDispose<List<PaymentModel>>((ref) async {
  final dio = ref.watch(apiClientProvider);
  final filter = ref.watch(paymentFilterProvider);

  final queryParams = <String, dynamic>{};
  if (filter.status.isNotEmpty && filter.status.toLowerCase() != 'all') {
    queryParams['status'] = filter.status.toLowerCase();
  }
  if (filter.electionId.isNotEmpty) {
    queryParams['election'] = filter.electionId;
  }
  if (filter.searchQuery.trim().isNotEmpty) {
    queryParams['q'] = filter.searchQuery.trim();
  }

  final response = await dio.get(
    ApiConstants.payments,
    queryParameters: queryParams.isNotEmpty ? queryParams : null,
  );

  final data = response.data;
  List<dynamic> list;
  if (data is List) {
    list = data;
  } else if (data is Map && data.containsKey('results')) {
    list = data['results'] as List<dynamic>;
  } else {
    list = [];
  }

  return list.map((json) => PaymentModel.fromJson(json as Map<String, dynamic>)).toList();
});

class PaymentStatsData {
  final double totalCollected;
  final int pendingCount;
  final double pendingAmount;
  final int verifiedCount;
  final double verifiedAmount;
  final int rejectedCount;
  final int totalTransactions;

  const PaymentStatsData({
    this.totalCollected = 0.0,
    this.pendingCount = 0,
    this.pendingAmount = 0.0,
    this.verifiedCount = 0,
    this.verifiedAmount = 0.0,
    this.rejectedCount = 0,
    this.totalTransactions = 0,
  });

  factory PaymentStatsData.fromJson(Map<String, dynamic> json) => PaymentStatsData(
        totalCollected: double.tryParse(json['total_collected']?.toString() ?? '0.0') ?? 0.0,
        pendingCount: json['pending_count'] as int? ?? 0,
        pendingAmount: double.tryParse(json['pending_amount']?.toString() ?? '0.0') ?? 0.0,
        verifiedCount: json['verified_count'] as int? ?? 0,
        verifiedAmount: double.tryParse(json['verified_amount']?.toString() ?? '0.0') ?? 0.0,
        rejectedCount: json['rejected_count'] as int? ?? 0,
        totalTransactions: json['total_transactions'] as int? ?? 0,
      );
}

final paymentStatsProvider = FutureProvider.autoDispose<PaymentStatsData>((ref) async {
  final dio = ref.watch(apiClientProvider);
  final filter = ref.watch(paymentFilterProvider);

  final queryParams = <String, dynamic>{};
  if (filter.electionId.isNotEmpty) {
    queryParams['election'] = filter.electionId;
  }

  final response = await dio.get(
    ApiConstants.paymentStats,
    queryParameters: queryParams.isNotEmpty ? queryParams : null,
  );

  return PaymentStatsData.fromJson(response.data as Map<String, dynamic>);
});

class PaymentActionsNotifier extends AutoDisposeAsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  Future<void> verifyPayment(String paymentId, {String notes = ''}) async {
    state = const AsyncValue.loading();
    try {
      final dio = ref.read(apiClientProvider);
      await dio.post(ApiConstants.verifyPayment(paymentId), data: {'notes': notes});
      ref.invalidate(paymentsListProvider);
      ref.invalidate(paymentStatsProvider);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  Future<void> rejectPayment(String paymentId, {required String reason}) async {
    state = const AsyncValue.loading();
    try {
      final dio = ref.read(apiClientProvider);
      await dio.post(ApiConstants.rejectPayment(paymentId), data: {'reason': reason});
      ref.invalidate(paymentsListProvider);
      ref.invalidate(paymentStatsProvider);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  Future<void> resubmitPayment(
    String paymentId, {
    required String transactionReference,
    String? receiptImageUrl,
    String? paymentNotes,
  }) async {
    state = const AsyncValue.loading();
    try {
      final dio = ref.read(apiClientProvider);
      final payload = <String, dynamic>{
        'transaction_reference': transactionReference,
      };
      if (receiptImageUrl != null && receiptImageUrl.isNotEmpty) {
        payload['receipt_image_url'] = receiptImageUrl;
      }
      if (paymentNotes != null && paymentNotes.isNotEmpty) {
        payload['payment_notes'] = paymentNotes;
      }
      await dio.post(ApiConstants.resubmitPayment(paymentId), data: payload);
      ref.invalidate(paymentsListProvider);
      ref.invalidate(paymentStatsProvider);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }
}

final paymentActionsProvider =
    AutoDisposeAsyncNotifierProvider<PaymentActionsNotifier, void>(
  () => PaymentActionsNotifier(),
);
