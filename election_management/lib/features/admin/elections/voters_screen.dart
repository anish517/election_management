import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/admin_providers.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/network/api_constants.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/download_helper.dart';
import '../../voters/dialogs/file_voter_claim_dialog.dart';
import 'add_voter_dialog.dart';
import 'edit_voter_dialog.dart';
import 'import_members_dialog.dart';
import 'voter_csv_import_wizard_screen.dart';
import 'voter_profile_sheet.dart';

class VotersScreen extends ConsumerWidget {
  final String electionId;
  const VotersScreen({super.key, required this.electionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final votersAsync = ref.watch(votersProvider(electionId));
    final user = ref.watch(currentUserProvider);
    final isAdmin = user?.canManageElections ?? false;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.background : const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('Voter Roll (मतदाता नामावली)'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Published Voter Roll',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isAdmin
                          ? 'Official registered voter roll with management controls'
                          : 'Public voter list for verification and scrutiny (दाबी-विरोध)',
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (!isAdmin) ...[
                      ElevatedButton.icon(
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (_) => FileVoterClaimDialog(electionId: electionId),
                          );
                        },
                        icon: const Icon(Icons.rate_review_rounded, size: 18),
                        label: const Text('File Claim / Objection (दाबी-विरोध)'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                      ),
                    ] else ...[
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
                      ElevatedButton.icon(
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (context) => ImportMembersDialog(electionId: electionId),
                          );
                        },
                        icon: const Icon(Icons.people_alt_outlined, size: 18),
                        label: const Text('Import Members'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                      ),
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
                      OutlinedButton.icon(
                        onPressed: () => _exportCsv(context, ref),
                        icon: const Icon(Icons.download_rounded, size: 18),
                        label: const Text('Export CSV'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),

            Expanded(
              child: Card(
                elevation: 0,
                color: isDark ? AppColors.surface : Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: isDark ? AppColors.surfaceVariant : Colors.grey.shade200),
                ),
                child: Column(
                  children: [
                    _buildTableHeader(isAdmin),
                    const Divider(height: 1),
                    Expanded(
                      child: votersAsync.when(
                        loading: () => const Center(child: CircularProgressIndicator()),
                        error: (err, stack) => Center(child: Text('Error loading voters: $err')),
                        data: (voters) {
                          if (voters.isEmpty) {
                            return const Center(
                              child: Text('No voters found on the roll.'),
                            );
                          }
                          return ListView.separated(
                            itemCount: voters.length,
                            separatorBuilder: (context, index) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final voter = voters[index] as Map<String, dynamic>;
                              return _buildTableRow(context, ref, voter, index + 1, isAdmin);
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

  Widget _buildTableHeader(bool isAdmin) {
    if (!isAdmin) {
      // Clean, privacy-first view for regular Voters and Candidates
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
        child: Row(
          children: [
            SizedBox(
              width: 50,
              child: Text('S.N.', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            Expanded(
              flex: 2,
              child: Text(
                'Voter ID',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(
              flex: 4,
              child: Text(
                'Full Name',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                'Status',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            SizedBox(
              width: 140,
              child: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.right),
            ),
          ],
        ),
      );
    }

    // Admin view with full contact details
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
      child: Row(
        children: [
          SizedBox(
            width: 50,
            child: Text('S.N.', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'Voter ID',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              'Name',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              'Email',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text('Phone', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          Expanded(
            flex: 2,
            child: Text('Council No.', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          Expanded(
            flex: 2,
            child: Text('Citizenship No.', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          SizedBox(
            width: 150,
            child: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }

  Widget _buildTableRow(BuildContext context, WidgetRef ref, Map<String, dynamic> voter, int sn, bool isAdmin) {
    final fullName = (voter['full_name'] as String?)?.trim() ?? '';
    final initial = fullName.isNotEmpty ? fullName[0].toUpperCase() : 'V';
    final isEligible = voter['is_eligible'] == true;

    if (!isAdmin) {
      // Read-Only Privacy Row for Voters & Candidates
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Row(
          children: [
            SizedBox(width: 50, child: Text(sn.toString())),
            Expanded(
              flex: 2,
              child: Text(
                voter['voter_id']?.toString().isNotEmpty == true ? voter['voter_id'] : '-',
                style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary),
              ),
            ),
            Expanded(
              flex: 4,
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                    child: Text(initial, style: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      fullName.isNotEmpty ? fullName : '-',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (isEligible ? Colors.green : Colors.red).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isEligible ? 'Eligible Voter' : 'Ineligible',
                  style: TextStyle(
                    color: isEligible ? Colors.green : Colors.red,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 140,
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
                    icon: const Icon(Icons.rate_review_outlined, size: 18, color: Colors.orange),
                    tooltip: 'File Claim / Correction on this Voter',
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (_) => FileVoterClaimDialog(
                          electionId: electionId,
                          initialVoterName: fullName,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Admin Row with full controls (Edit / Delete)
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Row(
        children: [
          SizedBox(width: 50, child: Text(sn.toString())),
          Expanded(flex: 2, child: Text(voter['voter_id']?.toString().isNotEmpty == true ? voter['voter_id'] : '-')),
          Expanded(
            flex: 3,
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
          Expanded(flex: 3, child: Text(voter['email']?.toString().isNotEmpty == true ? voter['email'] : '-', overflow: TextOverflow.ellipsis)),
          Expanded(flex: 2, child: Text(voter['phone']?.toString().isNotEmpty == true ? voter['phone'] : '-')),
          Expanded(flex: 2, child: Text(voter['council_number']?.toString().isNotEmpty == true ? voter['council_number'] : '-')),
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
