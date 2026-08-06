import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/admin_providers.dart';
import '../admin/elections/add_position_dialog.dart';
import '../admin/elections/add_candidate_dialog.dart';
import '../admin/elections/assign_officer_dialog.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/network/api_constants.dart';
import '../../core/network/api_client.dart';
import '../../shared/models/models.dart';

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
      ),
      body: electionAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (election) => _buildBody(context, ref, election, user),
      ),
    );
  }

  Widget _buildBody(BuildContext context, WidgetRef ref, ElectionModel election, UserModel? user) {
    return SingleChildScrollView(
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
          _buildPositionsSection(context, election),
        ],
      ),
    );
  }

  Widget _buildHeroCard(BuildContext context, ElectionModel election) {
    final stateColor = _stateColor(election.state);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary.withValues(alpha: 0.6), AppColors.primaryDark],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: stateColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: stateColor.withValues(alpha: 0.5)),
            ),
            child: Text(
              election.state.replaceAll('_', ' ').toUpperCase(),
              style: TextStyle(color: stateColor, fontSize: 10, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 14),
          Text(election.title, style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: Colors.white)),
          if (election.description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(election.description,
                style: const TextStyle(color: Colors.white70, fontSize: 14)),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              _MetaItem(icon: Icons.how_to_vote_outlined,
                  label: election.isSecretBallot ? 'Secret Ballot' : 'Open Ballot'),
              const SizedBox(width: 16),
              _MetaItem(icon: Icons.bar_chart_rounded,
                  label: '${election.positions.length} Position(s)'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPositionsSection(BuildContext context, ElectionModel election) {
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
          ...election.positions.map((p) => _PositionCard(position: p)),
      ],
    );
  }

  Widget _buildActionButtons(BuildContext context, WidgetRef ref, ElectionModel election, UserModel? user) {
    return Column(
      children: [
        if (election.state == 'nomination_open') ...[
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => context.pushNamed('nominate',
                  pathParameters: {'electionId': electionId}),
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Nominate Myself'),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (election.isVotingActive)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => context.pushNamed('ballot',
                  pathParameters: {'electionId': electionId}),
              icon: const Icon(Icons.how_to_vote_rounded),
              label: const Text('Vote Now'),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.stateVoting),
            ),
          ),
        if (election.hasResults || election.state == 'voting_closed') ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => context.pushNamed('results',
                  pathParameters: {'electionId': electionId}),
              icon: const Icon(Icons.emoji_events_outlined),
              label: const Text('View Results'),
            ),
          ),
        ],
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
          if (election.state == 'draft')
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
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
            ),
          if (election.state == 'published')
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
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
            ),
          if (election.state == 'nomination_open')
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
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
            ),
          if (election.state == 'nomination_closed')
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
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
            ),
          if (election.state == 'voting_open')
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
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
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) => AddPositionDialog(electionId: election.id),
                  ),
                  icon: const Icon(Icons.add_box_outlined, size: 18),
                  label: const Text('Add Position'),
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
        ],
      ),
    );
  }

  Color _stateColor(String state) {
    switch (state) {
      case 'draft': return AppColors.stateDraft;
      case 'published': return AppColors.statePublished;
      case 'nominations_open': case 'nominations_closed': return AppColors.stateNominations;
      case 'voting_active': return AppColors.stateVoting;
      case 'voting_closed': return AppColors.stateClosed;
      case 'results_provisional': case 'results_final': return AppColors.stateResults;
      default: return AppColors.textMuted;
    }
  }
}

class _PositionCard extends StatelessWidget {
  final PositionModel position;
  const _PositionCard({required this.position});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.surfaceVariant),
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
            ],
          ),
          if (position.candidates.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(color: AppColors.surfaceVariant),
            const SizedBox(height: 8),
            ...position.candidates.map((c) => _CandidateTile(candidate: c)),
          ],
        ],
      ),
    );
  }
}

class _CandidateTile extends StatelessWidget {
  final CandidateModel candidate;
  const _CandidateTile({required this.candidate});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 28, // Increased from 16 to 28
            backgroundColor: AppColors.primaryDark,
            backgroundImage: candidate.photoUrl != null && candidate.photoUrl!.isNotEmpty
                ? NetworkImage(candidate.photoUrl!)
                : null,
            child: (candidate.photoUrl == null || candidate.photoUrl!.isEmpty)
                ? const Icon(Icons.person, size: 28, color: Colors.white)
                : null,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(candidate.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                if (candidate.slateName.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(candidate.slateName, style: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                if (candidate.manifesto.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      candidate.manifesto,
                      style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                    ),
                  ),
              ],
            ),
          ),
          if (candidate.status != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: _getStatusColor(candidate.status!).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _getStatusColor(candidate.status!).withOpacity(0.3)),
              ),
              child: Text(
                candidate.status!.toUpperCase(),
                style: TextStyle(color: _getStatusColor(candidate.status!), fontSize: 9, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
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
