import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/models.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_constants.dart';
import '../../shared/widgets/shimmer_loaders.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/responsive_layout.dart';
import 'candidate_profile_sheet.dart';
import 'package:flutter_animate/flutter_animate.dart';

final candidatesProvider = FutureProvider.autoDispose.family<List<CandidateModel>, String>((ref, electionId) async {
  final dio = ref.watch(apiClientProvider);
  final resp = await dio.get(ApiConstants.electionCandidates(electionId));
  final data = resp.data;
  List<dynamic> list;
  if (data is List) {
    list = data;
  } else if (data is Map && data.containsKey('results')) {
    list = data['results'] as List<dynamic>;
  } else {
    list = [];
  }
  return list.map((c) => CandidateModel.fromJson(c as Map<String, dynamic>)).toList();
});

class NominationListScreen extends ConsumerStatefulWidget {
  final String electionId;
  const NominationListScreen({super.key, required this.electionId});

  @override
  ConsumerState<NominationListScreen> createState() => _NominationListScreenState();
}

class _NominationListScreenState extends ConsumerState<NominationListScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _processNomination(BuildContext context, CandidateModel candidate, bool approve) async {
    final noteCtrl = TextEditingController(text: approve ? 'Verified and approved by Election Officer' : '');
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              approve ? Icons.check_circle_rounded : Icons.cancel_rounded,
              color: approve ? Colors.green : AppColors.error,
            ),
            const SizedBox(width: 10),
            Text(approve ? 'Approve Nomination?' : 'Reject Nomination?'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              approve
                  ? 'Confirm approval of candidate ${candidate.name} for the position of "${candidate.positionTitle ?? 'Nominee'}"?'
                  : 'Are you sure you want to reject candidate ${candidate.name}?',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: noteCtrl,
              decoration: InputDecoration(
                labelText: 'Officer Scrutiny Notes / Reason',
                hintText: approve ? 'Approval notes...' : 'Reason for rejection...',
                border: const OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: approve ? Colors.green : AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: Text(approve ? 'Approve' : 'Reject'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final dio = ref.read(apiClientProvider);
    final endpoint = approve
        ? ApiConstants.approveCandidate(widget.electionId, candidate.id)
        : ApiConstants.rejectCandidate(widget.electionId, candidate.id);

    try {
      await dio.post(endpoint, data: {
        'notes': noteCtrl.text.trim().isNotEmpty
            ? noteCtrl.text.trim()
            : (approve ? 'Approved by officer' : 'Rejected by officer')
      });
      ref.invalidate(candidatesProvider(widget.electionId));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Candidate "${candidate.name}" has been ${approve ? 'approved' : 'rejected'}.'),
            backgroundColor: approve ? Colors.green : AppColors.error,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to process: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final candidatesAsync = ref.watch(candidatesProvider(widget.electionId));
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Review Nominations (उम्मेदवारी समीक्षा)'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(candidatesProvider(widget.electionId)),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primary,
          indicatorWeight: 3,
          labelColor: AppColors.primary,
          unselectedLabelColor: isDark ? Colors.white70 : Colors.grey.shade700,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: const [
            Tab(icon: Icon(Icons.pending_actions_rounded, size: 18), text: 'Pending (बाँकी)'),
            Tab(icon: Icon(Icons.verified_rounded, size: 18), text: 'Approved (स्वीकृत)'),
            Tab(icon: Icon(Icons.rule_folder_rounded, size: 18), text: 'All / Others (सबै)'),
          ],
        ),
      ),
      body: ResponsivePageWrapper(
        child: candidatesAsync.when(
          loading: () => const ListSkeleton(count: 5),
          error: (e, _) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 40),
                const SizedBox(height: 12),
                Text('Failed to load candidate nominations', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: () => ref.invalidate(candidatesProvider(widget.electionId)),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
          data: (candidates) {
            final pending = candidates.where((c) => c.status == 'submitted').toList();
            final approved = candidates.where((c) => c.status == 'approved').toList();
            final others = candidates.where((c) => c.status != 'submitted' && c.status != 'approved').toList();

            return TabBarView(
              controller: _tabController,
              children: [
                _buildCandidateList(pending, 'No Pending Nominations', 'All submitted candidate nominations have been reviewed.', true),
                _buildCandidateList(approved, 'No Approved Candidates', 'Approved candidates will appear here once certified.', false),
                _buildCandidateList(others.isNotEmpty ? others : candidates, 'No Other Nominations', 'Rejected or withdrawn candidates will appear here.', false),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildCandidateList(List<CandidateModel> list, String emptyTitle, String emptySubtitle, bool allowActions) {
    if (list.isEmpty) {
      return EmptyStateWidget(
        icon: Icons.how_to_vote_outlined,
        title: emptyTitle,
        subtitle: emptySubtitle,
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      separatorBuilder: (_, _) => const SizedBox(height: 14),
      itemBuilder: (context, i) {
        final c = list[i];
        final statusColor = _statusColor(c.status);

        return Container(
          decoration: BoxDecoration(
            color: isDark ? AppColors.surface : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.shade200,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.02),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (c.photoUrl != null && c.photoUrl!.isNotEmpty)
                      CircleAvatar(
                        radius: 30,
                        backgroundImage: NetworkImage(c.photoUrl!),
                      )
                    else
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: AppColors.primaryLight.withValues(alpha: 0.15),
                        child: Text(
                          c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary, fontSize: 22),
                        ),
                      ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (c.positionTitle != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    c.positionTitle!,
                                    style: const TextStyle(
                                      color: AppColors.primaryLight,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                                ),
                                child: Text(
                                  (c.status ?? 'PENDING').toUpperCase(),
                                  style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.w800),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(c.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                          if (c.manifesto.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              'Manifesto: ${c.manifesto}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isDark ? Colors.white70 : Colors.grey.shade700,
                                fontSize: 13,
                              ),
                            ),
                          ],
                          if (c.endorsements.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: () {
                                int pIdx = 0;
                                int sIdx = 0;
                                return c.endorsements.map((e) {
                                  final isProp = e.endorsementType.toLowerCase() == 'proposer';
                                  final idx = isProp ? ++pIdx : ++sIdx;
                                  final col = isProp ? const Color(0xFF2563EB) : const Color(0xFF059669);
                                  final label = isProp ? 'Proposer #$idx' : 'Supporter #$idx';
                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: col.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: col.withValues(alpha: 0.3)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(isProp ? Icons.how_to_reg_rounded : Icons.verified_user_rounded, size: 12, color: col),
                                        const SizedBox(width: 4),
                                        Text(
                                          '$label: ${e.name}${e.membershipId.isNotEmpty ? " (#${e.membershipId})" : ""}',
                                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: col),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList();
                              }(),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Divider(height: 1),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton.icon(
                      onPressed: () {
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (_) => CandidateProfileSheet(candidate: c),
                        );
                      },
                      icon: const Icon(Icons.person_search_rounded, size: 18),
                      label: const Text('View Full Dossier'),
                      style: TextButton.styleFrom(foregroundColor: AppColors.primaryLight),
                    ),
                    if (allowActions || c.status == 'submitted')
                      Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => _processNomination(context, c, false),
                            icon: const Icon(Icons.close_rounded, size: 16, color: AppColors.error),
                            label: const Text('Reject', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.bold)),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: AppColors.error.withValues(alpha: 0.4)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: () => _processNomination(context, c, true),
                            icon: const Icon(Icons.check_rounded, size: 16),
                            label: const Text('Approve', style: TextStyle(fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green.shade700,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
        )
        .animate()
        .fade(delay: Duration(milliseconds: 30 * i))
        .slideY(begin: 0.05, end: 0);
      },
    );
  }

  Color _statusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'approved':
        return Colors.green;
      case 'rejected':
        return AppColors.error;
      case 'withdrawn':
        return Colors.orange;
      case 'submitted':
      default:
        return const Color(0xFF2563EB);
    }
  }
}

