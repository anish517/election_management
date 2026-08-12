import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/models.dart';
import 'create_candidate_screen.dart';
import '../../candidates/candidate_profile_sheet.dart';

class CandidatesScreen extends ConsumerWidget {
  final String electionId;
  const CandidatesScreen({super.key, required this.electionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final electionAsync = ref.watch(electionProvider(electionId));

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Election Dashboard > Candidates',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.grey),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: Card(
              color: Theme.of(context).cardColor,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Theme.of(context).dividerColor),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade300),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<int>(
                                  value: 10,
                                  items: [10, 25, 50, 100].map((v) => DropdownMenuItem(value: v, child: Text(v.toString()))).toList(),
                                  onChanged: (v) {},
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text('entries per page'),
                          ],
                        ),
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => CreateCandidateScreen(electionId: electionId),
                              ),
                            );
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('Add New Record'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    // Table Header
                    _buildTableHeader(context),
                    const Divider(),
                    // Table Body
                    Expanded(
                      child: electionAsync.when(
                        loading: () => const Center(child: CircularProgressIndicator()),
                        error: (err, _) => Center(child: Text('Error: $err')),
                        data: (election) {
                          // Extract candidates from all positions
                          final allCandidates = election.positions.expand((p) => p.candidates).toList();
                          
                          if (allCandidates.isEmpty) {
                            return const Center(child: Text('No candidates found.'));
                          }
                          return ListView.separated(
                            itemCount: allCandidates.length,
                            separatorBuilder: (context, index) => const Divider(),
                            itemBuilder: (context, index) {
                              final cand = allCandidates[index];
                              // Find position title
                              final posTitle = election.positions.firstWhere((p) => p.id == cand.positionId).title;
                              return _buildTableRow(context, cand, posTitle, election.title, index + 1);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Expanded(flex: 1, child: Text('S.N.', style: _headerStyle(context))),
          Expanded(flex: 3, child: Text('NAME', style: _headerStyle(context))),
          Expanded(flex: 4, child: Text('ELECTION', style: _headerStyle(context))),
          Expanded(flex: 2, child: Text('DESIGNATION', style: _headerStyle(context))),
          Expanded(flex: 2, child: Text('STATUS', style: _headerStyle(context))),
          Expanded(flex: 1, child: Text('ACTION', style: _headerStyle(context))),
        ],
      ),
    );
  }

  TextStyle _headerStyle(BuildContext context) {
    return Theme.of(context).textTheme.titleSmall!.copyWith(
      color: Colors.grey[600],
      fontWeight: FontWeight.bold,
      fontSize: 12,
      letterSpacing: 1.1,
    );
  }

  Widget _buildTableRow(BuildContext context, CandidateModel cand, String positionTitle, String electionTitle, int index) {
    Color statusColor = cand.status == 'approved' ? Colors.green : (cand.status == 'rejected' ? Colors.red : Colors.orange);
    String statusText = cand.status != null && cand.status!.isNotEmpty 
        ? cand.status![0].toUpperCase() + cand.status!.substring(1) 
        : 'Unknown';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Row(
        children: [
          Expanded(flex: 1, child: Text(index.toString())),
          Expanded(flex: 3, child: Text(cand.name)),
          Expanded(flex: 4, child: Text(electionTitle)),
          Expanded(flex: 2, child: Text(positionTitle)),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  statusText,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: IconButton(
              icon: const Icon(Icons.person_search_rounded),
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => CandidateProfileSheet(candidate: cand),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
