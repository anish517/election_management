import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/models.dart';
import 'create_designation_screen.dart';

class DesignationsScreen extends ConsumerWidget {
  final String electionId;
  const DesignationsScreen({super.key, required this.electionId});

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
                'Election Dashboard > Designations',
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
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => CreateDesignationScreen(electionId: electionId),
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
                          if (election.positions.isEmpty) {
                            return const Center(child: Text('No designations found.'));
                          }
                          return ListView.separated(
                            itemCount: election.positions.length,
                            separatorBuilder: (context, index) => const Divider(),
                            itemBuilder: (context, index) {
                              final pos = election.positions[index];
                              return _buildTableRow(context, pos, index + 1);
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
          Expanded(flex: 3, child: Text('DESIGNATION', style: _headerStyle(context))),
          Expanded(flex: 1, child: Text('SEATS', style: _headerStyle(context))),
          Expanded(flex: 2, child: Text('QUOTA', style: _headerStyle(context))),
          Expanded(flex: 2, child: Text('NOMINEE CHARGE', style: _headerStyle(context))),
          Expanded(flex: 2, child: Text('RESULT ORDER', style: _headerStyle(context))),
          Expanded(flex: 2, child: Text('BACKGROUND', style: _headerStyle(context))),
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

  Widget _buildTableRow(BuildContext context, PositionModel pos, int index) {
    Color parseColor(String hex) {
      try {
        final h = hex.replaceAll('#', '');
        return Color(int.parse('FF$h', radix: 16));
      } catch (_) {
        return Colors.grey;
      }
    }

    final bgColor = parseColor(pos.bgColor);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Row(
        children: [
          Expanded(flex: 1, child: Text(index.toString())),
          Expanded(flex: 3, child: Text(pos.title)),
          Expanded(flex: 1, child: Text(pos.seatsAvailable.toString())),
          Expanded(flex: 2, child: Text(pos.quotaName.isEmpty ? '-' : pos.quotaName)),
          Expanded(flex: 2, child: Text('Rs. ${pos.nomineeCharge}')),
          Expanded(flex: 2, child: Text(pos.resultOrder.toString())),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  pos.bgColor,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: IconButton(
              icon: const Icon(Icons.more_vert),
              onPressed: () {
                // Action menu logic here
              },
            ),
          ),
        ],
      ),
    );
  }
}
