import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/models/models.dart';
import '../network/api_client.dart';
import '../network/api_constants.dart';

/// Search text and status filter for the Super Admin organizations console.
final platformOrgSearchProvider = StateProvider.autoDispose<String>((ref) => '');
final platformOrgStatusProvider = StateProvider.autoDispose<String?>((ref) => null);

final platformOrganizationsProvider =
    FutureProvider.autoDispose<List<PlatformOrganizationModel>>((ref) async {
  final dio = ref.watch(apiClientProvider);
  final search = ref.watch(platformOrgSearchProvider);
  final status = ref.watch(platformOrgStatusProvider);
  final response = await dio.get(
    ApiConstants.platformOrganizations,
    queryParameters: {
      if (search.isNotEmpty) 'search': search,
      'status': ?status,
    },
  );
  return (response.data as List<dynamic>)
      .map((e) => PlatformOrganizationModel.fromJson(e as Map<String, dynamic>))
      .toList();
});

/// PATCH status / trial_ends_at for one tenant, then refresh the list.
Future<void> updatePlatformOrganization(
  WidgetRef ref,
  String orgId,
  Map<String, dynamic> data,
) async {
  final dio = ref.read(apiClientProvider);
  await dio.patch(ApiConstants.platformOrganizationDetail(orgId), data: data);
  ref.invalidate(platformOrganizationsProvider);
}
