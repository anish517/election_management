import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../network/api_client.dart';
import '../network/api_constants.dart';

class PublicElection {
  final String title;
  final String state;
  final String stateDisplay;
  final String method;
  final DateTime? votingStartAt;
  final DateTime? votingEndAt;

  PublicElection.fromJson(Map<String, dynamic> j)
      : title = j['title'] as String? ?? '',
        state = j['state'] as String? ?? '',
        stateDisplay = j['state_display'] as String? ?? '',
        method = j['election_method'] as String? ?? '',
        votingStartAt = DateTime.tryParse(j['voting_start_at'] as String? ?? ''),
        votingEndAt = DateTime.tryParse(j['voting_end_at'] as String? ?? '');
}

class PublicOrganization {
  final String id;
  final String name;
  final String prefix;
  final String portalToken;
  final String orgType;
  final String address;
  final String phone;
  final String email;
  final String website;
  final String logoUrl;
  final String coverImageUrl;
  final String brandColor;
  final List<PublicElection> elections;

  PublicOrganization.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String? ?? '',
        name = j['name'] as String? ?? '',
        prefix = j['prefix'] as String? ?? '',
        portalToken = j['portal_token'] as String? ?? '',
        orgType = j['org_type'] as String? ?? '',
        address = j['address'] as String? ?? '',
        phone = j['phone'] as String? ?? '',
        email = j['email'] as String? ?? '',
        website = j['website'] as String? ?? '',
        logoUrl = j['logo_url'] as String? ?? '',
        coverImageUrl = j['cover_image_url'] as String? ?? '',
        brandColor = j['brand_color'] as String? ?? '',
        elections = (j['elections'] as List<dynamic>? ?? [])
            .map((e) => PublicElection.fromJson(e as Map<String, dynamic>))
            .toList();
}

Color? parseBrandColor(String? hex) {
  if (hex == null || hex.isEmpty) return null;
  final clean = hex.replaceAll('#', '').trim();
  if (clean.length == 6) {
    final val = int.tryParse('FF$clean', radix: 16);
    if (val != null) return Color(val);
  } else if (clean.length == 8) {
    final val = int.tryParse(clean, radix: 16);
    if (val != null) return Color(val);
  }
  return null;
}

final publicOrganizationProvider = FutureProvider.autoDispose
    .family<PublicOrganization, String>((ref, handle) async {
  final cleanHandle = handle.trim();
  if (cleanHandle.isEmpty) {
    throw Exception('No organization handle provided');
  }
  final dio = ref.watch(apiClientProvider);
  String path;
  if (cleanHandle.contains('/')) {
    final parts = cleanHandle.split('/');
    // e.g. "sldfe21324vfbgf/nesog"
    path = '/public/organizations/${Uri.encodeComponent(parts[0])}/${Uri.encodeComponent(parts[1])}/';
  } else if (cleanHandle.contains('?token=')) {
    final parts = cleanHandle.split('?token=');
    path = '${ApiConstants.publicOrganization(parts[0])}?token=${Uri.encodeQueryComponent(parts[1])}';
  } else {
    path = ApiConstants.publicOrganization(cleanHandle);
  }
  final response = await dio.get(path);
  return PublicOrganization.fromJson(response.data as Map<String, dynamic>);
});

