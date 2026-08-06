import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/models/models.dart';
import '../network/api_client.dart';
import '../network/api_constants.dart';

final orgProfileProvider = FutureProvider.autoDispose<OrganizationModel>((
  ref,
) async {
  final dio = ref.watch(apiClientProvider);
  final response = await dio.get(ApiConstants.organizationProfile);
  return OrganizationModel.fromJson(response.data);
});

final orgStatsProvider = FutureProvider.autoDispose<OrganizationStatsModel>((
  ref,
) async {
  final dio = ref.watch(apiClientProvider);
  final response = await dio.get(ApiConstants.organizationStats);
  return OrganizationStatsModel.fromJson(response.data);
});

class UpdateOrgSettingsNotifier extends AutoDisposeAsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  Future<void> updateSettings(Map<String, dynamic> data) async {
    state = const AsyncValue.loading();
    try {
      final dio = ref.read(apiClientProvider);
      await dio.patch(ApiConstants.organizationProfile, data: data);
      ref.invalidate(orgProfileProvider);
      state = const AsyncValue.data(null);
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      rethrow;
    }
  }
}

final updateOrgSettingsProvider =
    AutoDisposeAsyncNotifierProvider<UpdateOrgSettingsNotifier, void>(
      () => UpdateOrgSettingsNotifier(),
    );
