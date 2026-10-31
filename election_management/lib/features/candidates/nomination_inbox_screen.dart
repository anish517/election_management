import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/admin_drawer.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/responsive_layout.dart';

class NominationSummaryRow {
  final String electionId;
  final String title;
  final String state;
  final String stateDisplay;
  final int pending;
  final int approved;
  final int rejected;
  final int total;

  const NominationSummaryRow({
    required this.electionId,
    required this.title,
    required this.state,
    required this.stateDisplay,
    required this.pending,
    required this.approved,
    required this.rejected,
    required this.total,
  });

  factory NominationSummaryRow.fromJson(Map<String, dynamic> json) => NominationSummaryRow(
        electionId: json['election_id'] as String,
        title: json['title'] as String? ?? '',
        state: json['state'] as String? ?? '',
        stateDisplay: json['state_display'] as String? ?? '',
        pending: json['pending'] as int? ?? 0,
        approved: json['approved'] as int? ?? 0,
        rejected: json['rejected'] as int? ?? 0,
        total: json['total'] as int? ?? 0,
      );
}

final nominationSummaryProvider =
    FutureProvider.autoDispose<List<NominationSummaryRow>>((ref) async {
  final dio = ref.watch(apiClientProvider);
  final resp = await dio.get('/nominations/summary/');
  return (resp.data as List<dynamic>)
      .map((e) => NominationSummaryRow.fromJson(e as Map<String, dynamic>))
      .toList();
});

/// Left-menu inbox: every election's nominee applications, pending first.
/// Each row opens the existing per-election review (view, approve, reject).
class NominationInboxScreen extends ConsumerWidget {
  const NominationInboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(nominationSummaryProvider);
    final isDesktop = ResponsiveLayout.isDesktop(context);

    final body = async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Could not load nominations: $e')),
      data: (rows) {
        if (rows.isEmpty) {
          return const EmptyStateWidget(
            icon: Icons.assignment_ind_outlined,
            title: 'No elections to review',
            subtitle: 'Nominee applications appear here once an election accepts nominations.',
          );
        }
        final pendingTotal = rows.fold<int>(0, (n, r) => n + r.pending);
        return RefreshIndicator(
          onRefresh: () => ref.refresh(nominationSummaryProvider.future),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
            children: [
              Text(
                pendingTotal == 0
                    ? 'No applications waiting for review.'
                    : '$pendingTotal application${pendingTotal == 1 ? '' : 's'} waiting for review.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              for (final r in rows) ...[
                _ElectionNominationCard(row: r),
                const SizedBox(height: 10),
              ],
            ],
          ),
        );
      },
    );

    // Same shell as the dashboard: persistent menu full height on desktop,
    // drawer on smaller screens.
    final content = Scaffold(
      drawer: isDesktop ? null : const AdminDrawer(),
      appBar: AppBar(
        title: const Text('Nominee Applications (उम्मेदवारी)'),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(nominationSummaryProvider),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: body,
        ),
      ),
    );

    if (!isDesktop) return content;
    return Scaffold(
      body: Row(
        children: [
          const SizedBox(width: 250, child: AdminDrawer(isPersistent: true)),
          Expanded(child: content),
        ],
      ),
    );
  }
}

class _ElectionNominationCard extends StatelessWidget {
  final NominationSummaryRow row;
  const _ElectionNominationCard({required this.row});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        onTap: () => context.pushNamed(
          'review_nominations',
          pathParameters: {'electionId': row.electionId},
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.title,
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      row.stateDisplay.isNotEmpty ? row.stateDisplay : row.state,
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _CountChip('Pending', row.pending, AppColors.warning),
                        _CountChip('Approved', row.approved, AppColors.success),
                        _CountChip('Rejected', row.rejected, AppColors.error),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _CountChip(this.label, this.count, this.color);

  @override
  Widget build(BuildContext context) {
    final active = count > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: active ? 0.14 : 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: active ? 0.4 : 0.15)),
      ),
      child: Text(
        '$label $count',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: active ? color : color.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}
