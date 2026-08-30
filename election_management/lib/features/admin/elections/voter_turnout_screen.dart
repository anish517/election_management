import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/providers/app_providers.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/shimmer_loaders.dart';

class VoterTurnoutScreen extends ConsumerStatefulWidget {
  final String electionId;

  const VoterTurnoutScreen({super.key, required this.electionId});

  @override
  ConsumerState<VoterTurnoutScreen> createState() => _VoterTurnoutScreenState();
}

class _VoterTurnoutScreenState extends ConsumerState<VoterTurnoutScreen> {
  String _searchQuery = '';
  String _statusFilter = 'all'; // 'all', 'voted', 'pending'

  @override
  Widget build(BuildContext context) {
    final turnoutAsync = ref.watch(electionTurnoutProvider(widget.electionId));
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Voter Turnout & Telemetry', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Text('प्रत्यक्ष मतदान सहभागिता तथा विवरण', style: TextStyle(fontSize: 11, color: Theme.of(context).appBarTheme.foregroundColor?.withValues(alpha: 0.65) ?? Colors.white70)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Live Turnout',
            onPressed: () => ref.invalidate(electionTurnoutProvider(widget.electionId)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: turnoutAsync.when(
        loading: () => const ListSkeleton(count: 10),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 48),
              const SizedBox(height: 16),
              Text('Failed to load turnout telemetry:\n$e', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                icon: const Icon(Icons.refresh_rounded),
                onPressed: () => ref.invalidate(electionTurnoutProvider(widget.electionId)),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (data) {
          final int totalEligible = data['total_eligible'] ?? 0;
          final int totalVoted = data['total_voted'] ?? 0;
          final int remainingPending = (totalEligible - totalVoted) > 0 ? (totalEligible - totalVoted) : 0;
          final double turnoutRatio = totalEligible > 0 ? (totalVoted / totalEligible) : 0.0;
          final double turnoutPercent = turnoutRatio * 100;
          final List<dynamic> rawList = data['turnout_list'] ?? [];

          if (rawList.isEmpty) {
            return const EmptyStateWidget(
              icon: Icons.group_off_outlined,
              title: 'No Eligible Voters Found',
              subtitle: 'There are currently no voters on the electoral roll for this election.',
            );
          }

          // Filter voters list by search and status
          final filteredList = rawList.where((item) {
            final map = item as Map<String, dynamic>;
            final name = (map['full_name'] ?? '').toString().toLowerCase();
            final email = (map['email'] ?? '').toString().toLowerCase();
            final voterId = (map['voter_id'] ?? '').toString().toLowerCase();
            final ip = (map['voted_ip_address'] ?? '').toString().toLowerCase();
            final hasVoted = map['has_voted'] == true;

            // Status filter
            if (_statusFilter == 'voted' && !hasVoted) return false;
            if (_statusFilter == 'pending' && hasVoted) return false;

            // Search filter
            if (_searchQuery.isNotEmpty) {
              final q = _searchQuery.toLowerCase();
              return name.contains(q) || email.contains(q) || voterId.contains(q) || ip.contains(q);
            }
            return true;
          }).toList();

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  // Top Hero Banner & Metrics
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Turnout Progress Meter Hero Card
                          Material(
                            color: isDark ? AppColors.surfaceVariant.withValues(alpha: 0.5) : Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                              side: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade200),
                            ),
                            elevation: isDark ? 0 : 2,
                            shadowColor: Colors.black.withValues(alpha: 0.05),
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            width: 10,
                                            height: 10,
                                            decoration: const BoxDecoration(
                                              color: Colors.green,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'LIVE TURNOUT PROGRESS (प्रत्यक्ष सहभागिता)',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: 0.5,
                                              color: isDark ? Colors.white70 : Colors.grey.shade700,
                                            ),
                                          ),
                                        ],
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: (turnoutPercent >= 50 ? Colors.green : Colors.orange).withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        child: Text(
                                          '${turnoutPercent.toStringAsFixed(1)}% Turnout',
                                          style: TextStyle(
                                            color: turnoutPercent >= 50 ? Colors.green : Colors.orange.shade800,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: LinearProgressIndicator(
                                      value: turnoutRatio.clamp(0.0, 1.0),
                                      minHeight: 14,
                                      backgroundColor: isDark ? Colors.white10 : Colors.grey.shade200,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        turnoutPercent >= 60 ? Colors.green : AppColors.primaryLight,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    '$totalVoted out of $totalEligible qualified electors have cast their electronic ballot.',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: isDark ? Colors.white60 : Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),

                          // 4 Quick Metric Stat Cards
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final isNarrow = constraints.maxWidth < 700;
                              return Wrap(
                                spacing: 14,
                                runSpacing: 14,
                                children: [
                                  SizedBox(
                                    width: isNarrow ? (constraints.maxWidth - 14) / 2 : (constraints.maxWidth - 42) / 4,
                                    child: _StatCard(
                                      title: 'Total Eligible',
                                      nepaliLabel: 'कुल योग्य मतदाता',
                                      value: totalEligible.toString(),
                                      icon: Icons.people_alt_outlined,
                                      color: AppColors.primaryLight,
                                    ),
                                  ),
                                  SizedBox(
                                    width: isNarrow ? (constraints.maxWidth - 14) / 2 : (constraints.maxWidth - 42) / 4,
                                    child: _StatCard(
                                      title: 'Total Voted',
                                      nepaliLabel: 'मतदान गरेका',
                                      value: totalVoted.toString(),
                                      icon: Icons.how_to_vote_outlined,
                                      color: Colors.green,
                                    ),
                                  ),
                                  SizedBox(
                                    width: isNarrow ? (constraints.maxWidth - 14) / 2 : (constraints.maxWidth - 42) / 4,
                                    child: _StatCard(
                                      title: 'Remaining Pending',
                                      nepaliLabel: 'मतदान बाँकी',
                                      value: remainingPending.toString(),
                                      icon: Icons.schedule_outlined,
                                      color: Colors.orange,
                                    ),
                                  ),
                                  SizedBox(
                                    width: isNarrow ? (constraints.maxWidth - 14) / 2 : (constraints.maxWidth - 42) / 4,
                                    child: _StatCard(
                                      title: 'Turnout Rate',
                                      nepaliLabel: 'सहभागिता प्रतिशत',
                                      value: '${turnoutPercent.toStringAsFixed(1)}%',
                                      icon: Icons.pie_chart_outline_rounded,
                                      color: Colors.purple,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 24),

                          // Search & Status Filter Toolbar
                          Material(
                            color: isDark ? AppColors.surfaceVariant.withValues(alpha: 0.3) : const Color(0xFFF8FAFC),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade200),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              child: Row(
                                children: [
                                  // Search Field
                                  Expanded(
                                    child: TextField(
                                      decoration: InputDecoration(
                                        hintText: 'Search voter by name, email, ID, or IP address...',
                                        hintStyle: const TextStyle(fontSize: 13),
                                        prefixIcon: const Icon(Icons.search_rounded, size: 20),
                                        isDense: true,
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                        filled: true,
                                        fillColor: isDark ? AppColors.surfaceVariant : Colors.white,
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(10),
                                          borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade300),
                                        ),
                                      ),
                                      onChanged: (v) => setState(() => _searchQuery = v),
                                    ),
                                  ),
                                  const SizedBox(width: 16),

                                  // Status Filter Chips
                                  Wrap(
                                    spacing: 8,
                                    children: [
                                      ChoiceChip(
                                        label: Text('All (${rawList.length})', style: const TextStyle(fontSize: 12)),
                                        selected: _statusFilter == 'all',
                                        onSelected: (val) => setState(() => _statusFilter = 'all'),
                                      ),
                                      ChoiceChip(
                                        label: Text('Voted ($totalVoted)', style: const TextStyle(fontSize: 12)),
                                        selected: _statusFilter == 'voted',
                                        selectedColor: Colors.green.withValues(alpha: 0.2),
                                        onSelected: (val) => setState(() => _statusFilter = 'voted'),
                                      ),
                                      ChoiceChip(
                                        label: Text('Pending ($remainingPending)', style: const TextStyle(fontSize: 12)),
                                        selected: _statusFilter == 'pending',
                                        selectedColor: Colors.orange.withValues(alpha: 0.2),
                                        onSelected: (val) => setState(() => _statusFilter = 'pending'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Elector Turnout List
                  if (filteredList.isEmpty)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: EmptyStateWidget(
                          icon: Icons.search_off_rounded,
                          title: 'No matching voters',
                          subtitle: 'Try adjusting your search criteria or status filter.',
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate((context, index) {
                          final item = filteredList[index] as Map<String, dynamic>;
                          final hasVoted = item['has_voted'] == true;
                          final fullName = item['full_name'] ?? 'Unknown Member';
                          final email = item['email'] ?? '';
                          final voterId = item['voter_id']?.toString() ?? '';
                          final ipAddress = item['voted_ip_address']?.toString() ?? '';
                          final macAddress = item['voted_mac_address']?.toString() ?? '';

                          String votedTimeFormatted = '';
                          if (hasVoted && item['voted_at'] != null) {
                            try {
                              final dt = DateTime.parse(item['voted_at']).toLocal();
                              votedTimeFormatted = DateFormat('MMM d, y • hh:mm a').format(dt);
                            } catch (_) {}
                          }

                          return Card(
                            elevation: 0,
                            margin: const EdgeInsets.only(bottom: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: BorderSide(
                                color: hasVoted
                                    ? Colors.green.withValues(alpha: isDark ? 0.3 : 0.2)
                                    : (isDark ? Colors.white12 : Colors.grey.shade200),
                              ),
                            ),
                            color: isDark ? AppColors.surfaceVariant.withValues(alpha: 0.4) : Colors.white,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  // Avatar
                                  CircleAvatar(
                                    radius: 20,
                                    backgroundColor: hasVoted
                                        ? Colors.green.withValues(alpha: 0.15)
                                        : Colors.orange.withValues(alpha: 0.15),
                                    child: Icon(
                                      hasVoted ? Icons.check_circle_rounded : Icons.schedule_rounded,
                                      color: hasVoted ? Colors.green : Colors.orange,
                                      size: 22,
                                    ),
                                  ),
                                  const SizedBox(width: 14),

                                  // Member identity & telemetry
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              fullName,
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                            ),
                                            if (voterId.isNotEmpty) ...[
                                              const SizedBox(width: 8),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                                decoration: BoxDecoration(
                                                  color: AppColors.primary.withValues(alpha: 0.1),
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  voterId,
                                                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.primaryLight),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          email.isNotEmpty ? email : 'No email registered',
                                          style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.grey.shade600),
                                        ),
                                        if (hasVoted) ...[
                                          const SizedBox(height: 6),
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 4,
                                            children: [
                                              if (votedTimeFormatted.isNotEmpty)
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: Colors.green.withValues(alpha: 0.08),
                                                    borderRadius: BorderRadius.circular(4),
                                                    border: Border.all(color: Colors.green.withValues(alpha: 0.2)),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      const Icon(Icons.access_time_rounded, size: 11, color: Colors.green),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        votedTimeFormatted,
                                                        style: const TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.w600),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              if (ipAddress.isNotEmpty)
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: Colors.blue.withValues(alpha: 0.08),
                                                    borderRadius: BorderRadius.circular(4),
                                                    border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      const Icon(Icons.language_rounded, size: 11, color: Colors.blue),
                                                      const SizedBox(width: 4),
                                                      Text('IP: $ipAddress', style: const TextStyle(fontSize: 11, color: Colors.blue, fontWeight: FontWeight.w600)),
                                                    ],
                                                  ),
                                                ),
                                              if (macAddress.isNotEmpty)
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: Colors.purple.withValues(alpha: 0.08),
                                                    borderRadius: BorderRadius.circular(4),
                                                    border: Border.all(color: Colors.purple.withValues(alpha: 0.2)),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      const Icon(Icons.devices_rounded, size: 11, color: Colors.purple),
                                                      const SizedBox(width: 4),
                                                      Text('Device: $macAddress', style: const TextStyle(fontSize: 11, color: Colors.purple, fontWeight: FontWeight.w600)),
                                                    ],
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),

                                  // Status Badge
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: hasVoted ? Colors.green.withValues(alpha: 0.12) : Colors.orange.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: hasVoted ? Colors.green.withValues(alpha: 0.3) : Colors.orange.withValues(alpha: 0.3)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(hasVoted ? Icons.check_circle_rounded : Icons.pending_outlined, size: 14, color: hasVoted ? Colors.green : Colors.orange),
                                        const SizedBox(width: 6),
                                        Text(
                                          hasVoted ? 'Voted (मतदान सम्पन्न)' : 'Pending (मतदान बाँकी)',
                                          style: TextStyle(
                                            color: hasVoted ? Colors.green : Colors.orange.shade800,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }, childCount: filteredList.length),
                      ),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 40)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String nepaliLabel;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.title,
    required this.nepaliLabel,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceVariant.withValues(alpha: 0.5) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(height: 2),
          Text(
            nepaliLabel,
            style: TextStyle(
              fontSize: 11,
              color: isDark ? Colors.white54 : Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }
}
