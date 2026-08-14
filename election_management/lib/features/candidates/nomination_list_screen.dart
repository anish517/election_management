import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/models.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_constants.dart';
import '../../shared/widgets/shimmer_loaders.dart';
import '../../shared/widgets/empty_state.dart';
import 'candidate_profile_sheet.dart';

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
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final c = pending[i];
              final isDark = Theme.of(context).brightness == Brightness.dark;
              return Container(
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
                              radius: 28,
                              backgroundImage: NetworkImage(c.photoUrl!),
                            )
                          else
                            CircleAvatar(
                              radius: 28,
                              backgroundColor: AppColors.primaryLight.withValues(alpha: 0.2),
                              child: Text(
                                c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
                                style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryLight, fontSize: 20),
                              ),
                            ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (c.positionTitle != null)
                                  Text('Position: ${c.positionTitle}', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 13)),
                                const SizedBox(height: 2),
                                Text(c.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                                const SizedBox(height: 8),
                                Text(
                                  'Manifesto: ${c.manifesto}', 
                                  maxLines: 2, 
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: isDark ? Colors.white70 : AppColors.textSecondaryLightMode, fontSize: 13),
                                ),
                                const SizedBox(height: 8),
                                const SizedBox(height: 8),
                                if (c.endorsements.isNotEmpty) ...[
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 4,
                                    children: c.endorsements.map((e) {
                                      final isProp = e.endorsementType.toLowerCase() == 'proposer';
                                      final col = isProp ? const Color(0xFF2563EB) : const Color(0xFF059669);
                                      final label = isProp ? 'Proposer' : 'Supporter';
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
                                    }).toList(),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton.icon(
                            onPressed: () {
                              print('Viewing candidate: ${c.name} with ${c.endorsements.length} endorsements');
                              for (var e in c.endorsements) {
                                print('Endorsement: ${e.name} (${e.endorsementType})');
                              }
                              showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                backgroundColor: Colors.transparent,
                                builder: (_) => CandidateProfileSheet(candidate: c),
                              );
                            },
                            icon: const Icon(Icons.person_search_rounded, size: 18),
                            label: const Text('View Profile'),
                            style: TextButton.styleFrom(foregroundColor: AppColors.primaryLight),
                          ),
                          Row(
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
