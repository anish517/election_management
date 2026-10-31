import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../network/api_client.dart';
import '../network/api_constants.dart';

/// Opens a printable ID card page. The page opens in a new tab without the
/// login token, so the server first issues a short-lived signed link.
///
/// [kind] is 'candidate' or 'voter'; [id] is the candidate / voter-roll id,
/// or 'bulk' for the whole printable sheet.
Future<void> openIdCard(
  BuildContext context, {
  required String electionId,
  required String kind,
  required String id,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final dio = ProviderScope.containerOf(context, listen: false).read(apiClientProvider);

  final Uri uri;
  try {
    final resp = await dio.post(
      ApiConstants.idCardLink(electionId),
      data: {'kind': kind, 'id': id},
    );
    final base = ApiConstants.baseUrl.replaceAll('/v1', '');
    uri = Uri.parse('$base${resp.data['url']}');
  } on DioException catch (e) {
    final data = e.response?.data;
    final detail = data is Map && data['detail'] != null
        ? data['detail'].toString()
        : (data is Map && data['error'] is Map ? data['error']['message']?.toString() : null);
    messenger.showSnackBar(SnackBar(
      content: Text(detail ?? 'Could not open the ID card.'),
      backgroundColor: Colors.red,
    ));
    return;
  }

  var opened = false;
  try {
    opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    opened = false;
  }
  if (!opened) {
    // Pop-up blocked after the network round trip: let a fresh tap open it.
    messenger.showSnackBar(SnackBar(
      content: const Text('ID card is ready (link valid for 10 minutes).'),
      duration: const Duration(seconds: 12),
      action: SnackBarAction(
        label: 'Open',
        onPressed: () => launchUrl(uri, mode: LaunchMode.externalApplication),
      ),
    ));
  }
}
