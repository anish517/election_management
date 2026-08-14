import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_theme.dart';
import 'designations_screen.dart';
import 'candidates_screen.dart';
import 'voters_screen.dart';
import 'email_screen.dart';
import 'notice_screen.dart';
import 'guidelines_screen.dart';
import 'election_committee_screen.dart';
import '../../elections/election_detail_screen.dart';

class ElectionDashboardScreen extends ConsumerStatefulWidget {
  final String electionId;
  const ElectionDashboardScreen({super.key, required this.electionId});

  @override
  ConsumerState<ElectionDashboardScreen> createState() =>
      _ElectionDashboardScreenState();
}

class _ElectionDashboardScreenState
    extends ConsumerState<ElectionDashboardScreen> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final electionAsync = ref.watch(electionProvider(widget.electionId));

    return Scaffold(
      appBar: AppBar(
        title: electionAsync.when(
          data: (election) => Text(election.title),
          loading: () => const Text('Loading...'),
          error: (_, _) => const Text('Election Dashboard'),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => context.go('/dashboard'),
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            label: const Text(
              'Back to Super Admin Panel',
              style: TextStyle(color: Colors.white),
            ),
            style: TextButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Row(
        children: [
          // Sidebar
          Container(
            width: 250,
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              border: Border(
                right: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            child: ListView(
              children: [
                _buildNavItem(0, Icons.dashboard_outlined, 'Dashboard'),
                _buildNavItem(1, Icons.badge_outlined, 'Designations'),
                _buildNavItem(2, Icons.groups_outlined, 'Election Committee'),
                _buildNavItem(3, Icons.people_outline, 'Candidate'),
                _buildNavItem(4, Icons.how_to_vote_outlined, 'Voter'),
                _buildNavItem(5, Icons.email_outlined, 'Email'),
                _buildNavItem(6, Icons.notifications_outlined, 'Notice'),
                _buildNavItem(
                  7,
                  Icons.menu_book_outlined,
                  'Election Guidelines',
                ),
                _buildNavItem(
                  8,
                  Icons.bar_chart_outlined,
                  'Election Statistics',
                ),
              ],
            ),
          ),
          // Main Body
          Expanded(
            child: Container(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: _buildBody(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String title) {
    final isSelected = _selectedIndex == index;
    final color = isSelected
        ? Colors.white
        : (Theme.of(context).brightness == Brightness.dark
              ? Colors.white70
              : Colors.black87);
    final bgColor = isSelected ? AppColors.primary : Colors.transparent;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: InkWell(
        onTap: () => setState(() => _selectedIndex = index),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 12),
              Text(
                title,
                style: TextStyle(
                  color: color,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_selectedIndex) {
      case 0:
        return ElectionDetailScreen(electionId: widget.electionId);
      case 1:
        return DesignationsScreen(electionId: widget.electionId);
      case 2:
        return ElectionCommitteeScreen(electionId: widget.electionId);
      case 3:
        return CandidatesScreen(electionId: widget.electionId);
      case 4:
        return VotersScreen(electionId: widget.electionId);
      case 5:
        return EmailScreen(electionId: widget.electionId);
      case 6:
        return NoticeScreen(electionId: widget.electionId);
      case 7:
        return GuidelinesScreen(electionId: widget.electionId);
      default:
        return const Center(child: Text('Coming Soon'));
    }
  }
}
