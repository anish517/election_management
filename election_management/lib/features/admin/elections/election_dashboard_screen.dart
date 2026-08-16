import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/models.dart';
import 'designations_screen.dart';
import 'candidates_screen.dart';
import 'voters_screen.dart';
import 'email_screen.dart';
import 'notice_screen.dart';
import 'guidelines_screen.dart';
import 'election_committee_screen.dart';
import '../../elections/election_detail_screen.dart';
import '../../analytics/analytics_screen.dart';

class ElectionDashboardScreen extends ConsumerStatefulWidget {
  final String electionId;
  const ElectionDashboardScreen({super.key, required this.electionId});

  @override
  ConsumerState<ElectionDashboardScreen> createState() => _ElectionDashboardScreenState();
}

class _ElectionDashboardScreenState extends ConsumerState<ElectionDashboardScreen> {
  int _selectedIndex = 0;
  bool _sidebarCollapsed = false;

  final List<Map<String, dynamic>> _navItems = [
    {
      'group': 'MANAGEMENT HUB',
      'items': [
        {
          'index': 0,
          'title': 'Overview & Setup',
          'subtitle': 'निर्वाचन विवरण',
          'icon': Icons.dashboard_rounded,
        },
        {
          'index': 8,
          'title': 'Turnout & Analytics',
          'subtitle': 'तथ्याङ्क तथा विश्लेषण',
          'icon': Icons.insights_rounded,
        },
      ],
    },
    {
      'group': 'STRUCTURE & OFFICERS',
      'items': [
        {
          'index': 1,
          'title': 'Designations & Seats',
          'subtitle': 'पद तथा सिट',
          'icon': Icons.military_tech_rounded,
        },
        {
          'index': 2,
          'title': 'Election Committee',
          'subtitle': 'निर्वाचन समिति',
          'icon': Icons.security_rounded,
        },
      ],
    },
    {
      'group': 'ELECTORAL ROLLS',
      'items': [
        {
          'index': 3,
          'title': 'Candidate Nominations',
          'subtitle': 'उम्मेदवार व्यवस्थापन',
          'icon': Icons.groups_rounded,
        },
        {
          'index': 4,
          'title': 'Voter Roll Directory',
          'subtitle': 'मतदाता नामावली',
          'icon': Icons.how_to_vote_rounded,
        },
      ],
    },
    {
      'group': 'COMMUNICATION & RULES',
      'items': [
        {
          'index': 5,
          'title': 'Broadcast Dispatcher',
          'subtitle': 'इमेल सूचना प्रसारण',
          'icon': Icons.mark_email_read_outlined,
        },
        {
          'index': 6,
          'title': 'Public Notices',
          'subtitle': 'आधिकारिक सूचनाहरू',
          'icon': Icons.notifications_active_outlined,
        },
        {
          'index': 7,
          'title': 'Guidelines & Bylaws',
          'subtitle': 'आचारसंहिता र नियम',
          'icon': Icons.menu_book_rounded,
        },
      ],
    },
  ];

  Color _getStateColor(String state) {
    switch (state.toLowerCase()) {
      case 'ongoing':
      case 'voting':
      case 'open':
        return Colors.green;
      case 'upcoming':
      case 'nomination':
      case 'published':
        return Colors.blue;
      case 'completed':
      case 'finalized':
      case 'closed':
        return Colors.purple;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.amber.shade700;
    }
  }

  @override
  Widget build(BuildContext context) {
    final electionAsync = ref.watch(electionProvider(widget.electionId));
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isDesktop = MediaQuery.of(context).size.width >= 960;

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: isDark ? AppColors.surface : Colors.white,
        foregroundColor: isDark ? Colors.white : Colors.black87,
        leadingWidth: isDesktop ? 60 : 56,
        leading: isDesktop
            ? IconButton(
                icon: Icon(_sidebarCollapsed ? Icons.menu_open_rounded : Icons.menu_rounded),
                tooltip: _sidebarCollapsed ? 'Expand Sidebar' : 'Collapse Sidebar',
                onPressed: () => setState(() => _sidebarCollapsed = !_sidebarCollapsed),
              )
            : Builder(
                builder: (ctx) => IconButton(
                  icon: const Icon(Icons.menu_rounded),
                  tooltip: 'Open Navigation',
                  onPressed: () => Scaffold.of(ctx).openDrawer(),
                ),
              ),
        title: electionAsync.when(
          data: (election) => Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      election.title,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Election Control Panel • ${election.prefix.isNotEmpty ? election.prefix : "Governance Portal"}',
                      style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _getStateColor(election.state).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _getStateColor(election.state).withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: _getStateColor(election.state),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      election.state.toUpperCase(),
                      style: TextStyle(
                        color: _getStateColor(election.state),
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          loading: () => const Text('Loading election control hub...', style: TextStyle(fontSize: 14)),
          error: (_, _) => const Text('Election Administration Hub', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        actions: [
          OutlinedButton.icon(
            onPressed: () => context.go('/dashboard'),
            icon: const Icon(Icons.arrow_back_rounded, size: 16),
            label: const Text('Admin Hub'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(width: 14),
        ],
      ),
      drawer: isDesktop ? null : Drawer(child: _buildSidebarContent(context, electionAsync, isDark, isDrawer: true)),
      body: Row(
        children: [
          // Desktop Collapsible Sidebar
          if (isDesktop)
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: _sidebarCollapsed ? 76 : 270,
              decoration: BoxDecoration(
                color: isDark ? AppColors.surface : Colors.white,
                border: Border(
                  right: BorderSide(
                    color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.shade200,
                  ),
                ),
              ),
              child: _buildSidebarContent(context, electionAsync, isDark, isCollapsed: _sidebarCollapsed),
            ),

          // Main View Body
          Expanded(
            child: Container(
              color: isDark ? AppColors.background : const Color(0xFFF8FAFC),
              child: _buildBody(),
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // SIDEBAR NAVIGATION COMPONENT
  // ════════════════════════════════════════════════════════════════════════════
  Widget _buildSidebarContent(
    BuildContext context,
    AsyncValue<ElectionModel> electionAsync,
    bool isDark, {
    bool isCollapsed = false,
    bool isDrawer = false,
  }) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      children: [
        if (isDrawer) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.how_to_vote_rounded, color: AppColors.primaryLight, size: 22),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Election Control',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(height: 1),
              ],
            ),
          ),
        ],

        ..._navItems.map((group) {
          final groupTitle = group['group'] as String;
          final items = group['items'] as List<Map<String, dynamic>>;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isCollapsed)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 16, 14, 6),
                  child: Text(
                    groupTitle,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.1,
                      color: isDark ? Colors.white38 : Colors.grey.shade500,
                    ),
                  ),
                )
              else
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Divider(height: 1),
                ),
              ...items.map((item) {
                final idx = item['index'] as int;
                final title = item['title'] as String;
                final subtitle = item['subtitle'] as String;
                final icon = item['icon'] as IconData;
                final isSelected = _selectedIndex == idx;

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Tooltip(
                    message: isCollapsed ? '$title ($subtitle)' : '',
                    child: InkWell(
                      onTap: () {
                        setState(() => _selectedIndex = idx);
                        if (isDrawer) Navigator.of(context).pop();
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: isCollapsed ? 12 : 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.primary.withValues(alpha: 0.12)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.primary.withValues(alpha: 0.3)
                                : Colors.transparent,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: isCollapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
                          children: [
                            Icon(
                              icon,
                              size: 20,
                              color: isSelected
                                  ? AppColors.primaryLight
                                  : (isDark ? Colors.white70 : Colors.grey.shade700),
                            ),
                            if (!isCollapsed) ...[
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      title,
                                      style: TextStyle(
                                        color: isSelected
                                            ? AppColors.primaryLight
                                            : (isDark ? Colors.white : Colors.black87),
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                        fontSize: 13,
                                      ),
                                    ),
                                    Text(
                                      subtitle,
                                      style: TextStyle(
                                        color: isSelected
                                            ? AppColors.primaryLight.withValues(alpha: 0.8)
                                            : (isDark ? Colors.white38 : Colors.grey.shade500),
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (isSelected)
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                    color: AppColors.primaryLight,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ],
          );
        }),
      ],
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // MAIN BODY ROUTER / STACK
  // ════════════════════════════════════════════════════════════════════════════
  Widget _buildBody() {
    Widget activeView;
    switch (_selectedIndex) {
      case 0:
        activeView = ElectionDetailScreen(electionId: widget.electionId);
        break;
      case 1:
        activeView = DesignationsScreen(electionId: widget.electionId);
        break;
      case 2:
        activeView = ElectionCommitteeScreen(electionId: widget.electionId, showAppBar: false);
        break;
      case 3:
        activeView = CandidatesScreen(electionId: widget.electionId);
        break;
      case 4:
        activeView = VotersScreen(electionId: widget.electionId);
        break;
      case 5:
        activeView = EmailScreen(electionId: widget.electionId, showAppBar: false);
        break;
      case 6:
        activeView = NoticeScreen(electionId: widget.electionId, showAppBar: false);
        break;
      case 7:
        activeView = GuidelinesScreen(electionId: widget.electionId, showAppBar: false);
        break;
      case 8:
        activeView = AnalyticsScreen(electionId: widget.electionId, showAppBar: false);
        break;
      default:
        activeView = const Center(child: Text('Coming Soon'));
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: KeyedSubtree(
        key: ValueKey<int>(_selectedIndex),
        child: activeView,
      ),
    );
  }
}
