import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/admin_providers.dart';
import '../../../shared/models/claim_models.dart';

class ManageCandidateObjectionsDialog extends ConsumerStatefulWidget {
  final String electionId;

  const ManageCandidateObjectionsDialog({super.key, required this.electionId});

  @override
  ConsumerState<ManageCandidateObjectionsDialog> createState() => _ManageCandidateObjectionsDialogState();
}

class _ManageCandidateObjectionsDialogState extends ConsumerState<ManageCandidateObjectionsDialog>
    with SingleTickerProviderStateMixin {
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

  Future<void> _resolveObjection(CandidateObjectionModel objection, String status) async {
    final noteController = TextEditingController();
    final isUphold = status == 'upheld';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              isUphold ? Icons.cancel_outlined : Icons.check_circle_outline,
              color: isUphold ? Colors.red : Colors.green,
            ),
            const SizedBox(width: 8),
            Text(isUphold ? 'Uphold Objection (Disqualify)' : 'Dismiss Objection (Clear Candidate)'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isUphold
                  ? 'Upholding this objection will disqualify "${objection.candidateName}" and change their nomination status to REJECTED.'
                  : 'Dismissing this objection clears "${objection.candidateName}" to remain an approved candidate.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteController,
              decoration: InputDecoration(
                labelText: 'Election Committee Ruling / Notes',
                hintText: isUphold ? 'e.g. Ineligible as per Section 4' : 'e.g. Objections lack substantiated proof',
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
              backgroundColor: isUphold ? Colors.red : Colors.green,
              foregroundColor: Colors.white,
            ),
            child: Text(isUphold ? 'Uphold & Disqualify' : 'Dismiss Objection'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await ref.read(claimsActionProvider.notifier).resolveCandidateObjection(
            widget.electionId,
            objection.id,
            status,
            noteController.text.trim(),
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Objection ${isUphold ? 'upheld (Candidate Disqualified)' : 'dismissed'}.'),
            backgroundColor: isUphold ? Colors.red : Colors.green,
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
    final objectionsAsync = ref.watch(candidateObjectionsProvider(widget.electionId));
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
                      color: Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.gavel_rounded, color: Colors.orange, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Review Candidate Objections',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Candidacy Scrutiny & Objections (उम्मेदवार दाबी-विरोध सुनुवाई)',
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
                indicatorColor: Colors.orange,
                labelColor: Colors.orange,
                unselectedLabelColor: AppColors.textMuted,
                tabs: const [
                  Tab(text: 'All Objections'),
                  Tab(text: 'Pending Review'),
                  Tab(text: 'Upheld (Disqualified)'),
                  Tab(text: 'Dismissed'),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: objectionsAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (err, _) => Center(child: Text('Error: $err')),
                  data: (objections) {
                    if (objections.isEmpty) {
                      return const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.gavel_outlined, size: 48, color: AppColors.textMuted),
                            SizedBox(height: 12),
                            Text('No candidate objections filed.', style: TextStyle(color: AppColors.textMuted)),
                          ],
                        ),
                      );
                    }

                    final pending = objections.where((o) => o.status == 'pending').toList();
                    final upheld = objections.where((o) => o.status == 'upheld').toList();
                    final dismissed = objections.where((o) => o.status == 'dismissed').toList();

                    return TabBarView(
                      controller: _tabController,
                      children: [
                        _buildObjectionsList(objections),
                        _buildObjectionsList(pending),
                        _buildObjectionsList(upheld),
                        _buildObjectionsList(dismissed),
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

  Widget _buildObjectionsList(List<CandidateObjectionModel> list) {
    if (list.isEmpty) {
      return const Center(
        child: Text('No objections in this category.', style: TextStyle(color: AppColors.textMuted)),
      );
    }

    return ListView.separated(
      itemCount: list.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (ctx, i) {
        final obj = list[i];
        final isPending = obj.status == 'pending';

        Color badgeColor = Colors.orange;
        if (obj.status == 'upheld') badgeColor = Colors.red;
        if (obj.status == 'dismissed') badgeColor = Colors.green;

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
                            color: Colors.orange.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Objected: ${obj.candidateName}',
                            style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 12),
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
                            obj.statusDisplay,
                            style: TextStyle(color: badgeColor, fontWeight: FontWeight.bold, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                    if (obj.createdAt != null)
                      Text(
                        obj.createdAt!.toLocal().toString().split('.')[0],
                        style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Target Candidate: ${obj.candidateName} (${obj.positionTitle})',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  'Filed By: ${obj.claimantName} (${obj.claimantEmail}) ${obj.claimantPhone.isNotEmpty ? '• ${obj.claimantPhone}' : ''}',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(obj.objectionReason, style: const TextStyle(fontSize: 13)),
                ),
                if (obj.resolutionNotes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Ruling: ${obj.resolutionNotes} ${obj.resolvedByEmail != null ? '(${obj.resolvedByEmail})' : ''}',
                    style: TextStyle(color: badgeColor, fontStyle: FontStyle.italic, fontSize: 12),
                  ),
                ],
                if (isPending) ...[
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _resolveObjection(obj, 'dismissed'),
                        icon: const Icon(Icons.check, size: 16, color: Colors.green),
                        label: const Text('Dismiss Objection', style: TextStyle(color: Colors.green)),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: () => _resolveObjection(obj, 'upheld'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                        icon: const Icon(Icons.cancel, size: 16),
                        label: const Text('Uphold (Disqualify)'),
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
