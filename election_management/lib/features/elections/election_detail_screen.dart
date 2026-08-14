import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/admin_providers.dart';
import '../admin/elections/add_position_dialog.dart';
import '../admin/elections/add_candidate_dialog.dart';
import '../admin/elections/edit_election_dialog.dart';
import '../admin/elections/edit_position_dialog.dart';
import '../admin/elections/edit_candidate_dialog.dart';
import '../admin/elections/assign_officer_dialog.dart';
import '../admin/elections/audit_portal_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/network/api_constants.dart';
import '../../core/network/api_client.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/shimmer_loaders.dart';
import 'package:nepali_date_picker/nepali_date_picker.dart';
import '../../shared/widgets/responsive_layout.dart';
import '../candidates/candidate_profile_sheet.dart';

class ElectionDetailScreen extends ConsumerWidget {
  final String electionId;
  const ElectionDetailScreen({super.key, required this.electionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final electionAsync = ref.watch(electionProvider(electionId));
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Election Details'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => context.pop(),
        ),
        actions: [
          if (user != null && user.canManageElections)
            electionAsync.when(
              data: (election) => PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded),
                onSelected: (value) async {
                  if (value == 'edit') {
                    showDialog(
                      context: context,
                      builder: (ctx) => EditElectionDialog(election: election),
                    );
                  } else if (value == 'delete') {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Delete Election?'),
                        content: const Text('Are you sure you want to delete this election? This action cannot be undone.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            style: TextButton.styleFrom(foregroundColor: AppColors.error),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true && context.mounted) {
                      try {
                        await ref.read(publishElectionProvider.notifier).deleteElection(election.id);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Election deleted.')));
                          context.go('/dashboard');
                        }
                      } catch (e) {
                        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
                      }
                    }
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'edit', child: Text('Edit Election')),
                  const PopupMenuItem(value: 'delete', child: Text('Delete Election', style: TextStyle(color: AppColors.error))),
                ],
              ),
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const SizedBox.shrink(),
            ),
        ],
      ),
      body: electionAsync.when(
        loading: () => const CardListSkeleton(count: 3),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (election) => _buildBody(context, ref, election, user),
      ),
    );
  }

  Widget _buildBody(BuildContext context, WidgetRef ref, ElectionModel election, UserModel? user) {
    return ResponsivePageWrapper(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeroCard(context, election),
          const SizedBox(height: 20),
          _buildActionButtons(context, ref, election, user),
          const SizedBox(height: 20),
          if (user != null && user.canManageElections) ...[
            _buildAdminControls(context, ref, election),
            const SizedBox(height: 20),
          ],
          _buildPositionsSection(context, election, user),
        ],
      ),
    ),
    );
  }

  Color _hexToColor(String hex, Color fallback) {
    try {
      final h = hex.replaceAll('#', '');
      return Color(int.parse('FF$h', radix: 16));
    } catch (_) {
      return fallback;
    }
  }

  Widget _buildHeroCard(BuildContext context, ElectionModel election) {
    final stateColor = _stateColor(election.state);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // Determine colors
    final primaryBg = _hexToColor(election.primaryColor, isDark ? AppColors.surface : Colors.white);
    final isCustomBg = election.primaryColor.isNotEmpty && election.primaryColor != '#6C5CE7';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isCustomBg ? primaryBg.withValues(alpha: isDark ? 0.2 : 0.05) : (isDark ? AppColors.surface : Colors.white),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCustomBg ? primaryBg.withValues(alpha: 0.3) : (isDark ? AppColors.surfaceVariant : Colors.black.withValues(alpha: 0.05))
        ),
        boxShadow: [
          if (!isDark && !isCustomBg)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (election.logoUrl.isNotEmpty) ...[
                Container(
                  width: 54, height: 54,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF27272A) : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Theme.of(context).dividerColor),
                    image: DecorationImage(
                      image: NetworkImage(election.logoUrl),
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (election.prefix.isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              election.prefix,
                              style: const TextStyle(color: AppColors.primaryLight, fontSize: 11, fontWeight: FontWeight.w700),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: stateColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: stateColor.withValues(alpha: 0.5)),
                          ),
                          child: Text(
                            election.state.replaceAll('_', ' ').toUpperCase(),
                            style: TextStyle(color: stateColor, fontSize: 10, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(election.title, style: Theme.of(context).textTheme.headlineMedium),
                  ],
                ),
              ),
            ],
          ),
          
          if (election.description.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(election.description,
                style: TextStyle(color: isDark ? Colors.white70 : AppColors.textSecondaryLightMode, fontSize: 14)),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 16,
            runSpacing: 10,
            children: [
              _MetaItem(icon: Icons.how_to_vote_outlined,
                  label: election.isSecretBallot ? 'Secret Ballot' : 'Open Ballot'),
              _MetaItem(icon: Icons.bar_chart_rounded,
                  label: '${election.positions.length} Position(s)'),
              if (election.contactNumber.isNotEmpty)
                _MetaItem(icon: Icons.phone_outlined, label: election.contactNumber),
              if (election.isPaidCandidacy)
                _MetaItem(icon: Icons.monetization_on_outlined, label: 'Paid Candidacy: Rs. ${election.nomineeCharge.toStringAsFixed(0)}'),
            ],
          ),
          
          const Divider(height: 32),
          
          // Displaying schedules if available
          Wrap(
            spacing: 24,
            runSpacing: 16,
            children: [
              if (election.votingStartAt != null && election.votingEndAt != null)
                _ScheduleBlock(title: 'Voting Period', start: election.votingStartAt!, end: election.votingEndAt!, icon: Icons.schedule_rounded),
              if (election.nominationOpenAt != null && election.nominationCloseAt != null)
                _ScheduleBlock(title: 'Nomination Phase', start: election.nominationOpenAt!, end: election.nominationCloseAt!, icon: Icons.assignment_ind_outlined),
            ],
          ),
        ],
      ),
    );
  }


  Widget _buildPositionsSection(BuildContext context, ElectionModel election, UserModel? user) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.work_outline_rounded, color: AppColors.primaryLight, size: 18),
            const SizedBox(width: 8),
            Text('Positions', style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: 12),
        if (election.positions.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text('No positions added yet', style: TextStyle(color: AppColors.textMuted)),
            ),
          )
        else
          ...election.positions.map((p) => _PositionCard(electionId: election.id, position: p, isAdmin: user?.canManageElections ?? false)),
      ],
    );
  }

  Widget _buildActionButtons(BuildContext context, WidgetRef ref, ElectionModel election, UserModel? user) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        if (election.state == 'nomination_open')
          ElevatedButton.icon(
            onPressed: () => context.pushNamed('nominate',
                pathParameters: {'electionId': electionId}),
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: const Text('Nominate Myself'),
          ),
        if (election.isVotingActive)
          ElevatedButton.icon(
            onPressed: () => context.pushNamed('ballot',
                pathParameters: {'electionId': electionId}),
            icon: const Icon(Icons.how_to_vote_rounded),
            label: const Text('Vote Now'),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.stateVoting),
          ),
        if (election.hasResults || election.state == 'voting_closed' || (election.state == 'voting_open' && user?.canManageElections == true))
          OutlinedButton.icon(
            onPressed: () => context.pushNamed('results',
                pathParameters: {'electionId': electionId}),
            icon: const Icon(Icons.emoji_events_outlined),
            label: const Text('View Results'),
          ),
        if (election.hasResults)
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => AuditPortalScreen(
                  electionId: election.id,
                  electionTitle: election.title,
                ),
              ),
            ),
            icon: const Icon(Icons.verified_user_rounded),
            label: const Text('Auditor Verification Portal'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).brightness == Brightness.dark ? AppColors.textMuted : AppColors.textSecondaryLightMode,
              side: BorderSide(color: Theme.of(context).brightness == Brightness.dark ? AppColors.surfaceVariant : Colors.black.withValues(alpha: 0.1)),
            ),
          ),
      ],
    );
  }

  Widget _buildAdminControls(BuildContext context, WidgetRef ref, ElectionModel election) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primaryLight.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primaryLight.withValues(alpha: 0.3)),
        boxShadow: [
          if (Theme.of(context).brightness == Brightness.light)
            BoxShadow(
              color: AppColors.primaryLight.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.admin_panel_settings_rounded, color: AppColors.primaryLight),
              const SizedBox(width: 8),
              Text('Admin Controls', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.primaryLight)),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              if (election.state == 'draft')
                ElevatedButton.icon(
                  onPressed: () async {
                    try {
                      await ref.read(publishElectionProvider.notifier).publishElection(election.id);
                      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Election Published!')));
                    } catch (e) {
                      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
                    }
                  },
                  icon: const Icon(Icons.campaign_rounded),
                  label: const Text('Publish Election'),
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                ),
              if (election.state == 'published')
                ElevatedButton.icon(
                  onPressed: () async {
                    try {
                      await ref.read(publishElectionProvider.notifier).advanceElectionState(election.id, 'nomination_open');
                      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nominations Opened!')));
                    } catch (e) {
                      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
                    }
                  },
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Open Nominations'),
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.stateNominations),
                ),
              if (election.state == 'nomination_open')
                ElevatedButton.icon(
                  onPressed: () async {
                    try {
                      await ref.read(publishElectionProvider.notifier).advanceElectionState(election.id, 'nomination_closed');
                      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nominations Closed!')));
                    } catch (e) {
                      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
                    }
                  },
                  icon: const Icon(Icons.stop_rounded),
                  label: const Text('Close Nominations'),
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.stateNominations),
                ),
              if (election.state == 'nomination_closed')
                ElevatedButton.icon(
                  onPressed: () async {
                    try {
                      await ref.read(publishElectionProvider.notifier).advanceElectionState(election.id, 'voting_open');
                      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Voting Started!')));
                    } catch (e) {
                      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
                    }
                  },
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Start Voting'),
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.stateVoting),
                ),
              if (election.state == 'voting_open')
                ElevatedButton.icon(
                  onPressed: () async {
                    try {
                      await ref.read(publishElectionProvider.notifier).advanceElectionState(election.id, 'voting_closed');
                      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Voting Closed!')));
                    } catch (e) {
                      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
                    }
                  },
                  icon: const Icon(Icons.stop_rounded),
                  label: const Text('Close Voting'),
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.stateClosed),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) => AddPositionDialog(electionId: election.id),
                  ),
                  icon: const Icon(Icons.add_box_outlined, size: 18),
                  label: const Text('Add Designation'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) => AddCandidateDialog(election: election),
                  ),
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                  label: const Text('Add Candidate'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => context.pushNamed('election-turnout',
                  pathParameters: {'electionId': election.id}),
              icon: const Icon(Icons.people_alt_outlined, size: 18),
              label: const Text('View Voter Turnout'),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => context.pushNamed('review_nominations',
                  pathParameters: {'electionId': election.id}),
              icon: const Icon(Icons.fact_check_outlined, size: 18),
              label: const Text('Review Nominations'),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                final token = await JwtInterceptor.getAccessToken();
                final url = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.elections}${election.id}/export_voter_roll/?token=$token');
                if (await canLaunchUrl(url)) {
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                } else {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not launch export URL')));
                  }
                }
              },
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('Export Voter Roll (CSV)'),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => showDialog(
                context: context,
                builder: (_) => AssignOfficerDialog(electionId: election.id),
              ),
              icon: const Icon(Icons.admin_panel_settings_outlined, size: 18),
              label: const Text('Assign Roles'),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => context.pushNamed('analytics',
                  pathParameters: {'electionId': election.id}),
              icon: const Icon(Icons.bar_chart_rounded, size: 18),
              label: const Text('Live Analytics Dashboard'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primaryLight,
                side: BorderSide(color: AppColors.primaryLight.withValues(alpha: 0.5)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _stateColor(String state) {
    switch (state) {
      case 'draft': return AppColors.stateDraft;
      case 'published': return AppColors.statePublished;
      case 'nominations_open': case 'nominations_closed': return AppColors.stateNominations;
      case 'voting_open': return AppColors.stateVoting;
      case 'voting_closed': return AppColors.stateClosed;
      case 'results_provisional': case 'results_final': return AppColors.stateResults;
      default: return AppColors.textMuted;
    }
  }
}

class _PositionCard extends ConsumerWidget {
  final String electionId;
  final PositionModel position;
  final bool isAdmin;
  const _PositionCard({required this.electionId, required this.position, required this.isAdmin});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surface : Colors.white,
        borderRadius: BorderRadius.circular(16),
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
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.star_border_rounded, color: AppColors.primaryLight, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(position.title,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 15)),
                    const SizedBox(height: 2),
                    Text('${position.seatsAvailable} seat(s) · ${position.votingMethod.toUpperCase()}',
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                  ],
                ),
              ),
              if (isAdmin)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded, color: AppColors.textMuted),
                  onSelected: (val) async {
                    if (val == 'edit') {
                      showDialog(context: context, builder: (_) => EditPositionDialog(electionId: electionId, position: position));
                    } else if (val == 'delete') {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Delete Position?'),
                          content: const Text('Are you sure you want to delete this position?'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                            TextButton(onPressed: () => Navigator.pop(ctx, true), style: TextButton.styleFrom(foregroundColor: AppColors.error), child: const Text('Delete')),
                          ],
                        ),
                      );
                      if (confirm == true && context.mounted) {
                        try {
                          await ref.read(addCandidateProvider.notifier).deletePosition(electionId: electionId, positionId: position.id);
                          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Position deleted')));
                        } catch (e) {
                          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
                        }
                      }
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 'edit', child: Text('Edit')),
                    const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: AppColors.error))),
                  ],
                ),
            ],
          ),
          if (position.candidates.isNotEmpty) ...[
            Builder(
              builder: (context) {
                final visibleCandidates = position.candidates.where((c) => isAdmin || c.status == 'approved').toList();
                if (visibleCandidates.isEmpty) return const SizedBox.shrink();
                
                return Column(
                  children: [
                    const SizedBox(height: 16),
                    Divider(color: isDark ? AppColors.surfaceVariant : Colors.black.withValues(alpha: 0.05)),
                    const SizedBox(height: 8),
                    ...visibleCandidates.map((c) => _CandidateTile(electionId: electionId, candidate: c, isAdmin: isAdmin)),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _CandidateTile extends ConsumerWidget {
  final String electionId;
  final CandidateModel candidate;
  final bool isAdmin;
  const _CandidateTile({required this.electionId, required this.candidate, required this.isAdmin});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasPhoto = candidate.photoUrl != null && candidate.photoUrl!.isNotEmpty;
    final statusColor = _getStatusColor(candidate.status ?? '');

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => showCandidateProfile(context, candidate),
          borderRadius: BorderRadius.circular(16),
          splashColor: AppColors.primaryLight.withValues(alpha: 0.08),
          highlightColor: AppColors.primaryLight.withValues(alpha: 0.04),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark ? AppColors.background : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark
                    ? AppColors.surfaceVariant
                    : Colors.black.withValues(alpha: 0.06),
              ),
              boxShadow: [
                if (!isDark)
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
              ],
            ),
            child: Row(
              children: [
                // ── Avatar with gradient ring ──
                Hero(
                  tag: 'candidate_avatar_${candidate.id}',
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          AppColors.primaryLight.withValues(alpha: 0.8),
                          AppColors.primary.withValues(alpha: 0.3),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    padding: const EdgeInsets.all(2.5),
                    child: CircleAvatar(
                      radius: 26,
                      backgroundColor: isDark ? AppColors.surface : const Color(0xFFF0F3F8),
                      backgroundImage: hasPhoto ? NetworkImage(candidate.photoUrl!) : null,
                      child: !hasPhoto
                          ? Text(
                              _initials(candidate.name),
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: AppColors.primaryLight,
                              ),
                            )
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // ── Name + position + manifesto snippet ──
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              candidate.name,
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // Status badge
                          if (candidate.status != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                              ),
                              child: Text(
                                candidate.status!.replaceAll('_', ' ').toUpperCase(),
                                style: TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w800,
                                    color: statusColor),
                              ),
                            ),
                        ],
                      ),
                      if (candidate.manifesto.isNotEmpty) ...[const SizedBox(height: 4),
                        Text(
                          candidate.manifesto,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? AppColors.textMuted : AppColors.textSecondaryLightMode,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // ── Tap indicator + admin menu ──
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (isAdmin)
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert_rounded, size: 20, color: AppColors.textMuted),
                        onSelected: (val) async {
                          if (val == 'edit') {
                            showDialog(context: context, builder: (_) => EditCandidateDialog(electionId: electionId, candidate: candidate));
                          } else if (val == 'delete') {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Delete Candidate?'),
                                content: const Text('Are you sure you want to delete this candidate?'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                  TextButton(onPressed: () => Navigator.pop(ctx, true), style: TextButton.styleFrom(foregroundColor: AppColors.error), child: const Text('Delete')),
                                ],
                              ),
                            );
                            if (confirm == true && context.mounted) {
                              try {
                                await ref.read(addCandidateProvider.notifier).deleteCandidate(electionId: electionId, candidateId: candidate.id);
                                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Candidate deleted')));
                              } catch (e) {
                                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
                              }
                            }
                          } else if (val == 'view_profile') {
                            showCandidateProfile(context, candidate);
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(value: 'view_profile', child: Row(children: [Icon(Icons.person_rounded, size: 16), SizedBox(width: 8), Text('View Profile')])),
                          const PopupMenuItem(value: 'edit', child: Text('Edit')),
                          const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: AppColors.error))),
                        ],
                      )
                    else
                      const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted, size: 20),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'approved': return Colors.green;
      case 'rejected': return Colors.red;
      case 'submitted': return Colors.blue;
      case 'under_review': return Colors.orange;
      case 'withdrawn': return Colors.grey;
      default: return AppColors.textMuted;
    }
  }
}

class _MetaItem extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MetaItem({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white60, size: 15),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(color: Colors.white60, fontSize: 12)),
      ],
    );
  }
}

class _ScheduleBlock extends StatelessWidget {
  final String title;
  final String start;
  final String end;
  final IconData icon;

  const _ScheduleBlock({
    required this.title,
    required this.start,
    required this.end,
    required this.icon,
  });

  String _format(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return NepaliDateFormat('MMM d, yyyy - h:mm a').format(dt.toNepaliDateTime());
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: isDark ? Colors.white70 : Colors.black54),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isDark ? Colors.white : Colors.black87)),
            const SizedBox(height: 4),
            Text('Starts: ${_format(start)}', style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.black54)),
            Text('Ends: ${_format(end)}', style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.black54)),
          ],
        ),
      ],
    );
  }
}
