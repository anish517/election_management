import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_constants.dart';
import '../../core/theme/app_theme.dart';
import 'package:intl/intl.dart';

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
      body: historyAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (history) {
          if (history.isEmpty) {
            return const Center(
              child: Text(
                'You have not voted in any elections yet.',
                style: TextStyle(color: AppColors.textMuted),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: history.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final item = history[i];
              final votedAt = DateTime.parse(item['voted_at']).toLocal();
              
              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: AppColors.surfaceVariant),
                ),
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
              );
            },
          );
        },
      ),
    );
  }
}
