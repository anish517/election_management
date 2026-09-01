import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/admin_providers.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/network/api_constants.dart';
import '../../../core/network/api_client.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/utils/download_helper.dart';
import '../../voters/dialogs/file_voter_claim_dialog.dart';
import '../../shared/digital_id_card_dialog.dart';
import 'add_voter_dialog.dart';
import 'edit_voter_dialog.dart';
import 'import_members_dialog.dart';
import 'voter_csv_import_wizard_screen.dart';
import 'voter_profile_sheet.dart';

class VotersScreen extends ConsumerStatefulWidget {
  final String electionId;
  const VotersScreen({super.key, required this.electionId});

  @override
  ConsumerState<VotersScreen> createState() => _VotersScreenState();
}

class _VotersScreenState extends ConsumerState<VotersScreen> {
  String _searchQuery = '';
  String _eligibilityFilter = 'all'; // 'all', 'eligible', 'ineligible'

  Future<void> _exportCsv() async {
    try {
      final dio = ref.read(apiClientProvider);
      final url = ApiConstants.exportElectionVotersCsv(widget.electionId);
      final response = await dio.get(url, options: Options(responseType: ResponseType.plain));

      final csvString = response.data.toString();
      final bytes = utf8.encode(csvString);
      final base64String = base64Encode(bytes);

      try {
        downloadFileFromBase64(base64String, 'voters_export.csv');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.download_done_rounded, color: Colors.white),
                  SizedBox(width: 10),
                  Text('Voter roll exported to CSV successfully!'),
                ],
              ),
              backgroundColor: Colors.green.shade700,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not download file: $e')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }

  void _showInitializeStationDialog() {
    final nameCtrl = TextEditingController(text: 'Main Polling Station');
    final codeCtrl = TextEditingController(text: 'BOOTH-01');
    bool regenAll = false;
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.how_to_vote_rounded, color: Color(0xFF059669)),
                SizedBox(width: 10),
                Text('Initialize Polling Station', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ],
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Initializing the station generates a guaranteed unique, collision-free PIN for every voter in the roll to unlock touch-screen voting booths.',
                    style: TextStyle(fontSize: 13, color: Color(0xFF64748B), height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Station / Venue Name',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: codeCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Station Code',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    value: regenAll,
                    onChanged: (val) => setModalState(() => regenAll = val ?? false),
                    title: const Text('Regenerate All PINs', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    subtitle: const Text('Generates fresh unique PINs for all voters', style: TextStyle(fontSize: 11)),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                onPressed: isSubmitting ? null : () async {
                  final messenger = ScaffoldMessenger.of(context);
                  setModalState(() => isSubmitting = true);
                  try {
                    final dio = ref.read(apiClientProvider);
                    final res = await dio.post(
                      ApiConstants.initializePollingStation(widget.electionId),
                      data: {
                        'station_name': nameCtrl.text.trim(),
                        'station_code': codeCtrl.text.trim(),
                        'regenerate_all': regenAll,
                      },
                    );
                    if (ctx.mounted) Navigator.pop(ctx);
                    ref.invalidate(votersProvider(widget.electionId));
                    if (mounted) {
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(res.data['message'] ?? 'Polling station initialized successfully.'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } catch (e) {
                    setModalState(() => isSubmitting = false);
                    if (mounted) {
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text('Failed to initialize: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
                icon: isSubmitting
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.check_circle_rounded, size: 18),
                label: const Text('Initialize & Generate PINs'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF059669),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final votersAsync = ref.watch(votersProvider(widget.electionId));
    final user = ref.watch(currentUserProvider);
    final isAdmin = user?.canManageElections ?? false;
    final isObserverOrAuditor = (user?.isObserver ?? false) || (user?.isAuditor ?? false);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.background : const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Voter Roll (मतदाता नामावली)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Text('Electoral roll directory & franchise administration', style: TextStyle(fontSize: 11, color: isDark ? Colors.white70 : AppColors.textSecondaryLightMode)),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Voter Roll',
            onPressed: () => ref.invalidate(votersProvider(widget.electionId)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Observer / Auditor Notice
            if (isObserverOrAuditor)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.visibility_rounded, color: Colors.blue, size: 22),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Observer / Auditor Mode: You have read-only independent monitoring access to the published voter roll.',
                        style: TextStyle(color: Colors.blue, fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),

            // Top Header & Action Suite
            LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 960;
                final titleCol = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Published Voter Roll (मतदाता सूची)',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isAdmin
                          ? 'Official registered voter roll with management controls and verification'
                          : isObserverOrAuditor
                              ? 'Read-only voter roll for independent audit and monitoring'
                              : 'Public voter list for verification and statutory scrutiny (दाबी-विरोध)',
                      style: TextStyle(color: isDark ? Colors.white60 : AppColors.textMuted, fontSize: 13),
                    ),
                  ],
                );

                final actionBtns = Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    if (!isAdmin && !isObserverOrAuditor) ...[
                      ElevatedButton.icon(
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (_) => FileVoterClaimDialog(electionId: widget.electionId),
                          );
                        },
                        icon: const Icon(Icons.rate_review_rounded, size: 18),
                        label: const Text('File Claim / Objection (दाबी-विरोध)'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ] else if (isAdmin) ...[
                      FilledButton.icon(
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (context) => AddVoterDialog(electionId: widget.electionId),
                          );
                        },
                        icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                        label: const Text('Add New Voter'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF4F46E5),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (context) => ImportMembersDialog(electionId: widget.electionId),
                          );
                        },
                        icon: const Icon(Icons.people_alt_outlined, size: 18),
                        label: const Text('Import Members'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF7C3AED),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => VoterCsvImportWizardScreen(electionId: widget.electionId),
                            ),
                          );
                        },
                        icon: const Icon(Icons.upload_file_rounded, size: 18),
                        label: const Text('Import CSV'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _exportCsv,
                        icon: const Icon(Icons.download_rounded, size: 18),
                        label: const Text('Export CSV'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () {
                          final baseUrl = ApiConstants.baseUrl.replaceAll('/v1', '');
                          final url = '$baseUrl/v1/elections/${widget.electionId}/voters/id_cards_bulk/';
                          launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                        },
                        icon: const Icon(Icons.badge_rounded, size: 18, color: Color(0xFF10B981)),
                        label: const Text('Batch ID Cards (PDF)'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF10B981),
                          side: const BorderSide(color: Color(0xFF10B981)),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: _showInitializeStationDialog,
                        icon: const Icon(Icons.how_to_vote_rounded, size: 18),
                        label: const Text('Initialize Station & PINs'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF059669),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () {
                          final baseUrl = ApiConstants.baseUrl.replaceAll('/v1', '');
                          final url = '$baseUrl/v1/elections/${widget.electionId}/voter-pins/print-slips/';
                          launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                        },
                        icon: const Icon(Icons.pin_rounded, size: 18, color: Color(0xFFD97706)),
                        label: const Text('Print PIN Slips (पर्ची प्रिन्ट)'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFD97706),
                          side: const BorderSide(color: Color(0xFFD97706)),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ],
                  ],
                );

                if (isNarrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      titleCol,
                      const SizedBox(height: 12),
                      actionBtns,
                    ],
                  );
                }

                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: titleCol),
                    const SizedBox(width: 16),
                    Flexible(child: actionBtns),
                  ],
                );
              },
            ),
            const SizedBox(height: 18),

            // Live Search & Franchise Filter Toolbar
            votersAsync.maybeWhen(
              data: (voters) {
                final totalVoters = voters.length;
                final eligibleCount = voters.where((v) => v['is_eligible'] == true).length;
                final ineligibleCount = totalVoters - eligibleCount;

                return Material(
                  color: isDark ? AppColors.surfaceVariant.withValues(alpha: 0.3) : Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade200),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        // Search Field
                        Expanded(
                          child: TextField(
                            decoration: InputDecoration(
                              hintText: 'Search by voter name, email, Voter ID, council or citizenship no...',
                              hintStyle: const TextStyle(fontSize: 13),
                              prefixIcon: const Icon(Icons.search_rounded, size: 20),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              filled: true,
                              fillColor: isDark ? AppColors.surfaceVariant : const Color(0xFFF9FAFB),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade300),
                              ),
                            ),
                            onChanged: (v) => setState(() => _searchQuery = v),
                          ),
                        ),
                        const SizedBox(width: 16),

                        // Franchise Filter Choice Chips
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            ChoiceChip(
                              label: Text('All ($totalVoters)', style: const TextStyle(fontSize: 12)),
                              selected: _eligibilityFilter == 'all',
                              onSelected: (val) => setState(() => _eligibilityFilter = 'all'),
                            ),
                            ChoiceChip(
                              label: Text('Eligible ($eligibleCount)', style: const TextStyle(fontSize: 12)),
                              selected: _eligibilityFilter == 'eligible',
                              selectedColor: Colors.green.withValues(alpha: 0.2),
                              onSelected: (val) => setState(() => _eligibilityFilter = 'eligible'),
                            ),
                            ChoiceChip(
                              label: const Text('📱 App', style: TextStyle(fontSize: 12)),
                              selected: _eligibilityFilter == 'mobile_app',
                              selectedColor: Colors.indigo.withValues(alpha: 0.2),
                              onSelected: (val) => setState(() => _eligibilityFilter = 'mobile_app'),
                            ),
                            ChoiceChip(
                              label: const Text('🌐 Web', style: TextStyle(fontSize: 12)),
                              selected: _eligibilityFilter == 'web_email',
                              selectedColor: Colors.blue.withValues(alpha: 0.2),
                              onSelected: (val) => setState(() => _eligibilityFilter = 'web_email'),
                            ),
                            ChoiceChip(
                              label: const Text('🏛️ Venue', style: TextStyle(fontSize: 12)),
                              selected: _eligibilityFilter == 'venue_kiosk',
                              selectedColor: Colors.purple.withValues(alpha: 0.2),
                              onSelected: (val) => setState(() => _eligibilityFilter = 'venue_kiosk'),
                            ),
                            if (ineligibleCount > 0)
                              ChoiceChip(
                                label: Text('Ineligible ($ineligibleCount)', style: const TextStyle(fontSize: 12)),
                                selected: _eligibilityFilter == 'ineligible',
                                selectedColor: Colors.red.withValues(alpha: 0.2),
                                onSelected: (val) => setState(() => _eligibilityFilter = 'ineligible'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
              orElse: () => const SizedBox.shrink(),
            ),
            const SizedBox(height: 16),

            // Elector Directory Table Card
            Expanded(
              child: Card(
                elevation: 0,
                color: isDark ? AppColors.surface : Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: isDark ? AppColors.surfaceVariant : Colors.grey.shade200),
                ),
                child: Column(
                  children: [
                    _buildTableHeader(isAdmin, isDark),
                    const Divider(height: 1),
                    Expanded(
                      child: votersAsync.when(
                        loading: () => const Center(child: CircularProgressIndicator()),
                        error: (err, stack) => Center(child: Text('Error loading voters: $err', style: const TextStyle(color: Colors.red))),
                        data: (voters) {
                          if (voters.isEmpty) {
                            return const Center(
                              child: Text('No voters registered on the electoral roll.', style: TextStyle(fontSize: 13, color: Colors.grey)),
                            );
                          }

                          // Filter voters
                          final filtered = voters.where((item) {
                            final map = item as Map<String, dynamic>;
                            final fullName = (map['full_name'] ?? '${map['first_name']} ${map['last_name']}').toString().toLowerCase();
                            final email = (map['email'] ?? '').toString().toLowerCase();
                            final voterId = (map['voter_id'] ?? '').toString().toLowerCase();
                            final councilNo = (map['council_number'] ?? '').toString().toLowerCase();
                            final citizenNo = (map['citizenship_number'] ?? '').toString().toLowerCase();
                            final isEligible = map['is_eligible'] == true;
                            final channel = (map['verification_channel'] ?? 'unverified').toString();

                            if (_eligibilityFilter == 'eligible' && !isEligible) return false;
                            if (_eligibilityFilter == 'ineligible' && isEligible) return false;
                            if (_eligibilityFilter == 'mobile_app' && channel != 'mobile_app') return false;
                            if (_eligibilityFilter == 'web_email' && channel != 'web_email') return false;
                            if (_eligibilityFilter == 'venue_kiosk' && channel != 'venue_kiosk') return false;

                            if (_searchQuery.isNotEmpty) {
                              final q = _searchQuery.toLowerCase();
                              return fullName.contains(q) ||
                                  email.contains(q) ||
                                  voterId.contains(q) ||
                                  councilNo.contains(q) ||
                                  citizenNo.contains(q);
                            }
                            return true;
                          }).toList();

                          if (filtered.isEmpty) {
                            return const Center(
                              child: Text('No voters matching search or filter criteria.', style: TextStyle(fontSize: 13, color: Colors.grey)),
                            );
                          }

                          return ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (context, index) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final voter = filtered[index] as Map<String, dynamic>;
                              return _buildTableRow(context, ref, voter, index + 1, isAdmin, isObserverOrAuditor, isDark);
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

  Widget _buildTableHeader(bool isAdmin, bool isDark) {
    final style = TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: 12.5,
      color: isDark ? Colors.white70 : Colors.grey.shade800,
    );

    if (!isAdmin) {
      // Privacy-first view for regular Voters and Observers
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 14.0),
        child: Row(
          children: [
            SizedBox(width: 48, child: Text('S.N.', style: style)),
            Expanded(flex: 2, child: Text('Voter Roll ID', style: style)),
            Expanded(flex: 4, child: Text('Full Legal Name', style: style)),
            Expanded(flex: 2, child: Text('Franchise Status', style: style)),
            SizedBox(width: 140, child: Text('Actions', style: style, textAlign: TextAlign.right)),
          ],
        ),
      );
    }

    // Admin view with verification credentials
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 14.0),
      child: Row(
        children: [
          SizedBox(width: 48, child: Text('S.N.', style: style)),
          Expanded(flex: 2, child: Text('Voter ID', style: style)),
          Expanded(flex: 3, child: Text('Elector Name', style: style)),
          Expanded(flex: 3, child: Text('Email Address', style: style)),
          Expanded(flex: 2, child: Text('Contact Phone', style: style)),
          Expanded(flex: 2, child: Text('Verification', style: style)),
          Expanded(flex: 2, child: Text('Council / Reg', style: style)),
          SizedBox(width: 180, child: Text('Actions', style: style, textAlign: TextAlign.right)),
        ],
      ),
    );
  }

  Widget _buildTableRow(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> voter,
    int sn,
    bool isAdmin,
    bool isObserverOrAuditor,
    bool isDark,
  ) {
    final fullName = (voter['full_name'] as String?)?.trim() ?? '${voter['first_name'] ?? ''} ${voter['last_name'] ?? ''}'.trim();
    final initial = fullName.isNotEmpty ? fullName[0].toUpperCase() : 'V';
    final isEligible = voter['is_eligible'] == true;
    final voterId = voter['voter_id']?.toString() ?? '-';

    if (!isAdmin) {
      // Read-Only Privacy Row for Voters & Candidates
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 12.0),
        child: Row(
          children: [
            SizedBox(width: 48, child: Text(sn.toString(), style: const TextStyle(fontSize: 13))),
            Expanded(
              flex: 2,
              child: Text(
                voterId.isNotEmpty ? voterId : '-',
                style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryLight, fontSize: 13),
              ),
            ),
            Expanded(
              flex: 4,
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                    child: Text(initial, style: const TextStyle(color: AppColors.primaryLight, fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      fullName.isNotEmpty ? fullName : '-',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
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
                  isEligible ? 'Franchise Active' : 'Ineligible',
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
                    tooltip: 'View Profile Dossier',
                    onPressed: () {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => VoterProfileSheet(voter: voter),
                      );
                    },
                  ),
                  if (!isObserverOrAuditor)
                    IconButton(
                      icon: const Icon(Icons.rate_review_outlined, size: 18, color: Colors.orange),
                      tooltip: 'File Claim / Correction on this Voter',
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (_) => FileVoterClaimDialog(
                            electionId: widget.electionId,
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

    final voterPin = voter['voter_pin']?.toString() ?? '';

    // Admin Row with full controls (Edit / Delete / Profile)
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 10.0),
      child: Row(
        children: [
          SizedBox(width: 48, child: Text(sn.toString(), style: const TextStyle(fontSize: 13))),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    voterId.isNotEmpty ? voterId : '-',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.primaryLight),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (voterPin.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.pin_rounded, size: 11, color: Color(0xFFD97706)),
                      const SizedBox(width: 2),
                      Text(
                        voterPin,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                          color: Color(0xFFD97706),
                          fontFamily: 'monospace',
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 15,
                  backgroundColor: const Color(0xFF4F46E5).withValues(alpha: 0.12),
                  child: Text(initial, style: const TextStyle(color: Color(0xFF4F46E5), fontSize: 12, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    fullName.isNotEmpty ? fullName : '-',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              voter['email']?.toString().isNotEmpty == true ? voter['email'] : '-',
              style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.grey.shade700),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              voter['phone']?.toString().isNotEmpty == true ? voter['phone'] : '-',
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 2,
            child: _buildVerificationChannelBadge(voter['verification_channel']?.toString()),
          ),
          Expanded(
            flex: 2,
            child: Text(
              voter['council_number']?.toString().isNotEmpty == true ? voter['council_number'] : (voter['citizenship_number']?.toString().isNotEmpty == true ? voter['citizenship_number'] : '-'),
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: 180,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.badge_outlined, size: 18, color: Color(0xFF10B981)),
                  tooltip: 'View / Print Voter ID Card',
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(),
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => DigitalIdCardDialog(
                        cardType: 'voter',
                        fullName: fullName,
                        idNumber: voterId.isNotEmpty ? voterId : (voter['id']?.toString() ?? ''),
                        councilNumber: voter['council_number']?.toString(),
                        phone: voter['phone']?.toString(),
                        electionTitle: 'Official Voter Roll',
                        electionId: widget.electionId,
                        entityId: voter['id']?.toString() ?? '',
                      ),
                    );
                  },
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.person_search_rounded, size: 18, color: AppColors.primaryLight),
                  tooltip: 'View Profile Dossier',
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(),
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => VoterProfileSheet(voter: voter),
                    );
                  },
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18, color: Colors.indigo),
                  tooltip: 'Edit Voter',
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(),
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => EditVoterDialog(electionId: widget.electionId, voter: voter),
                    );
                  },
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red),
                  tooltip: 'Delete Voter',
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(),
                  visualDensity: VisualDensity.compact,
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        title: const Text('Delete Voter from Roll'),
                        content: Text('Are you sure you want to delete "$fullName" from this election roll?'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                          FilledButton(
                            style: FilledButton.styleFrom(backgroundColor: Colors.red),
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Delete Voter'),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      ref.read(publishElectionProvider.notifier).deleteVoter(widget.electionId, voter['id'].toString());
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

  Widget _buildVerificationChannelBadge(String? channel) {
    switch (channel) {
      case 'mobile_app':
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.indigo.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.indigo.withValues(alpha: 0.3)),
          ),
          child: const Text('📱 App', style: TextStyle(color: Colors.indigo, fontSize: 10.5, fontWeight: FontWeight.bold)),
        );
      case 'web_email':
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
          ),
          child: const Text('🌐 Web', style: TextStyle(color: Colors.blue, fontSize: 10.5, fontWeight: FontWeight.bold)),
        );
      case 'venue_kiosk':
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.purple.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.purple.withValues(alpha: 0.3)),
          ),
          child: const Text('🏛️ Venue', style: TextStyle(color: Colors.purple, fontSize: 10.5, fontWeight: FontWeight.bold)),
        );
      default:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.grey.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text('⏳ Pending', style: TextStyle(color: Colors.grey, fontSize: 10.5, fontWeight: FontWeight.w600)),
        );
    }
  }
}

