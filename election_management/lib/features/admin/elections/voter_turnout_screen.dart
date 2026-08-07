import 'package:election_management/shared/widgets/empty_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/providers/app_providers.dart';
import '../../../shared/widgets/shimmer_loaders.dart';

class VoterTurnoutScreen extends ConsumerWidget {
  final String electionId;

  const VoterTurnoutScreen({super.key, required this.electionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final turnoutAsync = ref.watch(electionTurnoutProvider(electionId));

    return Scaffold(
      appBar: AppBar(title: const Text('Voter Turnout')),
      body: turnoutAsync.when(
        loading: () => const ListSkeleton(count: 10),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: AppColors.error,
                size: 48,
              ),
              const SizedBox(height: 16),
              Text('Failed to load turnout\n$e', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () =>
                    ref.invalidate(electionTurnoutProvider(electionId)),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (data) {
          final int totalEligible = data['total_eligible'] ?? 0;
          final int totalVoted = data['total_voted'] ?? 0;
          final List<dynamic> rawList = data['turnout_list'] ?? [];

          if (rawList.isEmpty) {
            return const EmptyStateWidget(
              icon: Icons.group_off_outlined,
              title: 'No Eligible Voters',
              subtitle: 'There are no active members in this organization.',
            );
          }

          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          title: 'Total Eligible',
                          value: totalEligible.toString(),
                          icon: Icons.people_alt_outlined,
                          color: AppColors.primaryLight,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _StatCard(
                          title: 'Total Voted',
                          value: totalVoted.toString(),
                          icon: Icons.how_to_vote_outlined,
                          color: Colors.green,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _StatCard(
                          title: 'Turnout %',
                          value: totalEligible > 0
                              ? '${((totalVoted / totalEligible) * 100).toStringAsFixed(1)}%'
                              : '0%',
                          icon: Icons.percent_outlined,
                          color: Colors.orange,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final item = rawList[index] as Map<String, dynamic>;
                    final hasVoted = item['has_voted'] == true;

                    String subtitleText = item['email'] ?? '';
                    if (hasVoted && item['voted_at'] != null) {
                      try {
                        final dt = DateTime.parse(item['voted_at']).toLocal();
                        subtitleText +=
                            ' • Voted at: ${DateFormat('MMM d, y HH:mm').format(dt)}';
                      } catch (e) {
                        // ignore
                      }
                    }

                    return Card(
                      elevation: 0,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey.withOpacity(0.2)),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 8,
                        ),
                        leading: CircleAvatar(
                          backgroundColor: hasVoted
                              ? Colors.green.withOpacity(0.1)
                              : Colors.grey.withOpacity(0.1),
                          child: Icon(
                            hasVoted
                                ? Icons.check_circle_rounded
                                : Icons.pending_outlined,
                            color: hasVoted ? Colors.green : Colors.grey,
                          ),
                        ),
                        title: Text(
                          item['full_name'] ?? 'Unknown',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(subtitleText),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: hasVoted
                                ? Colors.green.withOpacity(0.1)
                                : Colors.orange.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            hasVoted ? 'Voted' : 'Not Voted',
                            style: TextStyle(
                              color: hasVoted ? Colors.green : Colors.orange,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    );
                  }, childCount: rawList.length),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 40)),
            ],
          );
        },
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
