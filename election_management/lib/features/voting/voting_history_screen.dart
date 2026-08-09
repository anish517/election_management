import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_constants.dart';
import '../../core/theme/app_theme.dart';
import 'package:intl/intl.dart';
import '../../shared/widgets/shimmer_loaders.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/responsive_layout.dart';

final votingHistoryProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final dio = ref.watch(apiClientProvider);
  final resp = await dio.get(ApiConstants.votingHistory);
  final data = resp.data as List;
  return data.cast<Map<String, dynamic>>();
});

class VotingHistoryScreen extends ConsumerWidget {
  const VotingHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(votingHistoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Voting History'),
      ),
      body: ResponsivePageWrapper(
        child: historyAsync.when(
        loading: () => const ListSkeleton(count: 5),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (history) {
          if (history.isEmpty) {
            return const EmptyStateWidget(
              icon: Icons.history_edu_rounded,
              title: 'No Votes Cast Yet',
              subtitle: 'Your voting history will appear here once you participate in an election.',
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: history.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final item = history[i];
              final votedAt = DateTime.parse(item['voted_at']).toLocal();
              
              final isDark = Theme.of(context).brightness == Brightness.dark;
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.surface : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isDark ? AppColors.surfaceVariant : Colors.black.withValues(alpha: 0.05)),
                  boxShadow: [
                    if (!isDark)
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                  leading: const CircleAvatar(
                    backgroundColor: AppColors.stateVoting,
                    child: Icon(Icons.how_to_vote_rounded, color: Colors.white),
                  ),
                  title: Text(
                    item['title'] ?? 'Election',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      'Voted on: ${DateFormat.yMMMd().add_jm().format(votedAt)}',
                      style: const TextStyle(color: AppColors.textMuted),
                    ),
                  ),
                  trailing: OutlinedButton.icon(
                    onPressed: () => context.pushNamed('results', pathParameters: {'electionId': item['election_id']}),
                    icon: const Icon(Icons.bar_chart_rounded, size: 16),
                    label: const Text('Results'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                  ),
                  onTap: () {
                    context.pushNamed('election-detail', pathParameters: {'electionId': item['election_id']});
                  },
                  ),
                ),
              );
            },
          );
        },
        ),
      ),
    );
  }
}
