import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/admin_providers.dart';
import '../../../core/network/api_constants.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/download_helper.dart';
import 'add_voter_dialog.dart';
import 'edit_voter_dialog.dart';
import 'voter_csv_import_wizard_screen.dart';
import 'voter_profile_sheet.dart';

class VotersScreen extends ConsumerWidget {
  final String electionId;
  const VotersScreen({super.key, required this.electionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {

    final votersAsync = ref.watch(votersProvider(electionId));

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Voters List',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => AddVoterDialog(electionId: electionId),
                    );
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add New Voter'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF563D7C),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => VoterCsvImportWizardScreen(electionId: electionId),
                      ),
                    );
                  },
                  icon: const Icon(Icons.upload_file, size: 18),
                  label: const Text('Import CSV'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _exportCsv(context, ref),
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: const Text('Export CSV'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            Expanded(
              child: Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.shade200),
                ),
                child: Column(
                  children: [
                    _buildTableHeader(),
                    const Divider(height: 1),
                    Expanded(
                      child: votersAsync.when(
                        loading: () =>
                            const Center(child: CircularProgressIndicator()),
                        error: (err, stack) =>
                            Center(child: Text('Error: $err')),
                        data: (voters) {
                          if (voters.isEmpty) {
                            return const Center(
                              child: Text('No voters found.'),
                            );
                          }
                          return ListView.separated(
                            itemCount: voters.length,
                            separatorBuilder: (context, index) =>
                                const Divider(),
                            itemBuilder: (context, index) {
                              final voter =
                                  voters[index] as Map<String, dynamic>;
                              return _buildTableRow(context, ref, voter, index + 1);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTableHeader() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          const SizedBox(
            width: 50,
            child: Text('S.N.', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          Expanded(
            flex: 2,
            child: const Text(
              'Voter ID',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            flex: 2,
            child: const Text(
              'Name',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            flex: 2,
            child: const Text(
              'Email',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            flex: 2,
            child: const Text('Phone', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          Expanded(
            flex: 1,
            child: const Text('Council No.', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          Expanded(
            flex: 2,
            child: const Text('Citizenship No.', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          const SizedBox(
            width: 150,
            child: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }

  Widget _buildTableRow(BuildContext context, WidgetRef ref, Map<String, dynamic> voter, int sn) {
    final fullName = (voter['full_name'] as String?)?.trim() ?? '';
    final initial = fullName.isNotEmpty ? fullName[0].toUpperCase() : 'U';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Row(
        children: [
          SizedBox(width: 50, child: Text(sn.toString())),
          Expanded(flex: 2, child: Text(voter['voter_id']?.toString().isNotEmpty == true ? voter['voter_id'] : '-')),
          Expanded(
            flex: 2,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: const Color(0xFF563D7C).withValues(alpha: 0.1),
                  child: Text(initial, style: const TextStyle(color: Color(0xFF563D7C), fontSize: 12)),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(fullName.isNotEmpty ? fullName : '-', style: const TextStyle(fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
          Expanded(flex: 2, child: Text(voter['email']?.toString().isNotEmpty == true ? voter['email'] : '-', overflow: TextOverflow.ellipsis)),
          Expanded(flex: 2, child: Text(voter['phone']?.toString().isNotEmpty == true ? voter['phone'] : '-')),
          Expanded(flex: 1, child: Text(voter['council_number']?.toString().isNotEmpty == true ? voter['council_number'] : '-')),
          Expanded(flex: 2, child: Text(voter['citizenship_number']?.toString().isNotEmpty == true ? voter['citizenship_number'] : '-')),
          SizedBox(
            width: 150,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.person_search_rounded, size: 18, color: AppColors.primaryLight),
                  tooltip: 'View Profile',
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => VoterProfileSheet(voter: voter),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18, color: AppColors.primary),
                  tooltip: 'Edit',
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => EditVoterDialog(electionId: electionId, voter: voter),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red),
                  tooltip: 'Delete',
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Delete Voter'),
                        content: Text('Are you sure you want to delete $fullName?'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                          FilledButton(
                            style: FilledButton.styleFrom(backgroundColor: Colors.red),
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      // We don't have BuildContext context in ConsumerWidget, but we can pass ref
                      // Actually we do have context from _buildTableRow, but we can't easily show snappack without a GlobalKey or just ignoring mounted.
                      // We will just call the provider.
                      ref.read(publishElectionProvider.notifier).deleteVoter(electionId, voter['id'].toString());
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportCsv(BuildContext context, WidgetRef ref) async {
    try {
      final dio = ref.read(apiClientProvider);
      final url = ApiConstants.exportElectionVotersCsv(electionId);
      final response = await dio.get(url, options: Options(responseType: ResponseType.plain));
      
      final csvString = response.data.toString();
      final bytes = utf8.encode(csvString);
      final base64String = base64Encode(bytes);
      
      try {
        downloadFileFromBase64(base64String, 'voters_export.csv');
      } catch (e) {
        if (context.mounted) {
           ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not download file: $e')));
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }
}
