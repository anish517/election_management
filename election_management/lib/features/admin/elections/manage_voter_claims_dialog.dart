import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/admin_providers.dart';
import '../../../shared/models/claim_models.dart';

class ManageVoterClaimsDialog extends ConsumerStatefulWidget {
  final String electionId;

  const ManageVoterClaimsDialog({super.key, required this.electionId});

  @override
  ConsumerState<ManageVoterClaimsDialog> createState() => _ManageVoterClaimsDialogState();
}

class _ManageVoterClaimsDialogState extends ConsumerState<ManageVoterClaimsDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _resolveClaim(VoterClaimModel claim, String status) async {
    final noteController = TextEditingController();
    final isApprove = status == 'approved';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              isApprove ? Icons.check_circle_outline : Icons.highlight_off,
              color: isApprove ? Colors.green : Colors.red,
            ),
            const SizedBox(width: 8),
            Text(isApprove ? 'Approve Claim' : 'Reject Claim'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isApprove
                  ? 'Confirm approval of this claim. You can manually apply any necessary corrections to the Voter Roll from the Voter Management screen.'
                  : 'Please state the grounds or notes for rejecting this claim:',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteController,
              decoration: InputDecoration(
                labelText: 'Resolution Notes',
                hintText: isApprove ? 'e.g. Verified citizenship copy' : 'e.g. Ineligible as per constitution bylaws',
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
              backgroundColor: isApprove ? Colors.green : Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text(isApprove ? 'Approve' : 'Reject'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await ref.read(claimsActionProvider.notifier).resolveVoterClaim(
            widget.electionId,
            claim.id,
            status,
            noteController.text.trim(),
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Claim ${isApprove ? 'approved' : 'rejected'} successfully.'),
            backgroundColor: isApprove ? Colors.green : Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final claimsAsync = ref.watch(voterClaimsProvider(widget.electionId));
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: isDark ? AppColors.surface : Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.rate_review_rounded, color: AppColors.primary, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Manage Voter Roll Claims & Objections',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Review and resolve voter list omissions, corrections, and objections',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TabBar(
                controller: _tabController,
                indicatorColor: AppColors.primary,
                labelColor: AppColors.primary,
                unselectedLabelColor: AppColors.textMuted,
                tabs: const [
                  Tab(text: 'All Claims'),
                  Tab(text: 'Pending Review'),
                  Tab(text: 'Approved'),
                  Tab(text: 'Rejected'),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: claimsAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (err, _) => Center(child: Text('Error loading claims: $err')),
                  data: (claims) {
                    if (claims.isEmpty) {
                      return const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.inbox_outlined, size: 48, color: AppColors.textMuted),
                            SizedBox(height: 12),
                            Text('No voter claims or objections filed yet.', style: TextStyle(color: AppColors.textMuted)),
                          ],
                        ),
                      );
                    }

                    final pendingClaims = claims.where((c) => c.status == 'pending').toList();
                    final approvedClaims = claims.where((c) => c.status == 'approved').toList();
                    final rejectedClaims = claims.where((c) => c.status == 'rejected').toList();

                    return TabBarView(
                      controller: _tabController,
                      children: [
                        _buildClaimsList(claims),
                        _buildClaimsList(pendingClaims),
                        _buildClaimsList(approvedClaims),
                        _buildClaimsList(rejectedClaims),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildClaimsList(List<VoterClaimModel> list) {
    if (list.isEmpty) {
      return const Center(
        child: Text('No claims in this category.', style: TextStyle(color: AppColors.textMuted)),
      );
    }

    return ListView.separated(
      itemCount: list.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (ctx, i) {
        final claim = list[i];
        final isPending = claim.status == 'pending';

        Color badgeColor = Colors.orange;
        if (claim.status == 'approved') badgeColor = Colors.green;
        if (claim.status == 'rejected') badgeColor = Colors.red;

        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            claim.claimTypeDisplay,
                            style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: badgeColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            claim.statusDisplay,
                            style: TextStyle(color: badgeColor, fontWeight: FontWeight.bold, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                    if (claim.createdAt != null)
                      Text(
                        claim.createdAt!.toLocal().toString().split('.')[0],
                        style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Claimant: ${claim.claimantName} (${claim.claimantEmail}) ${claim.claimantPhone.isNotEmpty ? '• ${claim.claimantPhone}' : ''}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                if (claim.targetVoterName.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('Target Voter: ${claim.targetVoterName}', style: const TextStyle(color: Colors.blueAccent, fontSize: 13)),
                ],
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(claim.description, style: const TextStyle(fontSize: 13)),
                ),
                if (claim.resolutionNotes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Resolution Note: ${claim.resolutionNotes} ${claim.resolvedByEmail != null ? '(${claim.resolvedByEmail})' : ''}',
                    style: TextStyle(color: badgeColor, fontStyle: FontStyle.italic, fontSize: 12),
                  ),
                ],
                if (isPending) ...[
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _resolveClaim(claim, 'rejected'),
                        icon: const Icon(Icons.close, size: 16, color: Colors.red),
                        label: const Text('Reject', style: TextStyle(color: Colors.red)),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: () => _resolveClaim(claim, 'approved'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                        icon: const Icon(Icons.check, size: 16),
                        label: const Text('Approve & Update Roll'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
