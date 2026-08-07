import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/models.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_constants.dart';
import '../../shared/widgets/shimmer_loaders.dart';
import '../../shared/widgets/empty_state.dart';

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

class NominationListScreen extends ConsumerWidget {
  final String electionId;
  const NominationListScreen({super.key, required this.electionId});

  Future<void> _processNomination(BuildContext context, WidgetRef ref, CandidateModel candidate, bool approve) async {
    final dio = ref.read(apiClientProvider);
    final endpoint = approve 
      ? ApiConstants.approveCandidate(electionId, candidate.id)
      : ApiConstants.rejectCandidate(electionId, candidate.id);
      
    try {
      await dio.post(endpoint, data: {'notes': approve ? 'Approved by officer' : 'Rejected by officer'});
      ref.invalidate(candidatesProvider(electionId));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Candidate ${approve ? 'approved' : 'rejected'}.'))
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to process: $e'))
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final candidatesAsync = ref.watch(candidatesProvider(electionId));

    return Scaffold(
      appBar: AppBar(title: const Text('Review Nominations')),
      body: candidatesAsync.when(
        loading: () => const ListSkeleton(count: 5),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (candidates) {
          final pending = candidates.where((c) => c.status == 'submitted').toList();
          
          if (pending.isEmpty) {
            return const EmptyStateWidget(
              icon: Icons.how_to_vote_outlined,
              title: 'No Pending Nominations',
              subtitle: 'All nominations have been reviewed or none have been submitted yet.',
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: pending.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final c = pending[i];
              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: AppColors.surfaceVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (c.positionTitle != null)
                        Text('Position: ${c.positionTitle}', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(c.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text('Manifesto: ${c.manifesto}', style: const TextStyle(color: Colors.white70)),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => _processNomination(context, ref, c, false),
                            child: const Text('Reject', style: TextStyle(color: AppColors.error)),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () => _processNomination(context, ref, c, true),
                            child: const Text('Approve'),
                          ),
                        ],
                      )
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
