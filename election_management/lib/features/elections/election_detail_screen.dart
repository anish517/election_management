import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/admin_providers.dart';
import '../admin/elections/add_position_dialog.dart';
import '../admin/elections/add_candidate_dialog.dart';
import '../admin/elections/edit_election_dialog.dart';
import '../admin/elections/edit_position_dialog.dart';
import '../admin/elections/edit_candidate_dialog.dart';
import '../admin/elections/assign_officer_dialog.dart';
import '../admin/elections/audit_portal_screen.dart';
import '../voters/dialogs/file_voter_claim_dialog.dart';
import '../admin/elections/manage_voter_claims_dialog.dart';
import '../candidates/dialogs/file_candidate_objection_dialog.dart';
import '../admin/elections/manage_candidate_objections_dialog.dart';
import '../admin/elections/voters_screen.dart';
import '../admin/elections/notice_screen.dart';
import '../admin/elections/guidelines_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/network/api_constants.dart';
import '../../core/network/api_client.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/shimmer_loaders.dart';
import 'package:nepali_date_picker/nepali_date_picker.dart';
import '../../shared/widgets/responsive_layout.dart';
import '../candidates/candidate_profile_sheet.dart';
import '../candidates/nomination_list_screen.dart';

class ElectionDetailScreen extends ConsumerWidget {
  final String electionId;
  const ElectionDetailScreen({super.key, required this.electionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final electionAsync = ref.watch(electionProvider(electionId));
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Election Overview'),
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
                  const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit_outlined, size: 18), SizedBox(width: 10), Text('Edit Election')])),
                  const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.error), SizedBox(width: 10), Text('Delete Election', style: TextStyle(color: AppColors.error))])),
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
    final isAuditor = user?.isAuditor ?? false;
    final candidatesAsync = ref.watch(candidatesProvider(election.id));
    final myCorrectionNomination = user != null
        ? (candidatesAsync.valueOrNull ?? []).where((c) =>
            c.email?.toLowerCase() == user.email.toLowerCase() &&
            (c.latestPayment?.isCorrectionRequested == true ||
                (c.latestPayment?.correctionNotes.isNotEmpty == true))).firstOrNull
        : null;

    return ResponsivePageWrapper(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeroCard(context, election),
            const SizedBox(height: 20),
            if (myCorrectionNomination != null) ...[
              _buildPaymentCorrectionAlertCard(context, election, myCorrectionNomination),
              const SizedBox(height: 16),
            ],
            if (isAuditor) ...[
              _buildAuditorCard(context, election),
              const SizedBox(height: 20),
            ],
            _buildVoterListAndClaimsSection(context, ref, election, user),
            const SizedBox(height: 20),
            _buildActionButtons(context, ref, election, user),
            const SizedBox(height: 20),
            if (user != null && user.canManageElections) ...[
              _buildAdminControls(context, ref, election),
              const SizedBox(height: 24),
            ],
            _buildPositionsSection(context, election, user),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentCorrectionAlertCard(
    BuildContext context,
    ElectionModel election,
    CandidateModel candidate,
  ) {
    final payment = candidate.latestPayment;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF59E0B), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706), size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Payment Correction Required (भुक्तानी सच्याउनुहोस्)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF92400E)),
                    ),
                    Text(
                      'Designation: ${candidate.positionTitle ?? "Nomination"}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFB45309)),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => context.pushNamed('nominate', pathParameters: {'electionId': election.id}),
                icon: const Icon(Icons.edit_note_rounded, size: 16),
                label: const Text('Correct & Resubmit'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD97706),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
            ],
          ),
          if (payment?.correctionNotes.isNotEmpty == true) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
              ),
              child: Text(
                'Officer Note: ${payment!.correctionNotes}',
                style: const TextStyle(fontSize: 12.5, color: Color(0xFF78350F), height: 1.35),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAuditorCard(BuildContext context, ElectionModel election) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E3A8A).withValues(alpha: 0.18) : const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.verified_user_rounded, color: Color(0xFF3B82F6), size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Auditor Forensic Suite (लेखापरीक्षक)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: isDark ? const Color(0xFF93C5FD) : const Color(0xFF1E40AF))),
                const SizedBox(height: 2),
                Text('Inspect cryptographic hash chains, ballot snapshots, and system audit logs.', style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.black54)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => AuditPortalScreen(
                  electionId: election.id,
                  electionTitle: election.title,
                ),
              ),
            ),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E40AF), foregroundColor: Colors.white),
            icon: const Icon(Icons.shield_rounded, size: 16),
            label: const Text('Open Audit Portal'),
          ),
        ],
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
    
    final primaryBg = _hexToColor(election.primaryColor, isDark ? AppColors.surface : Colors.white);
    final isCustomBg = election.primaryColor.isNotEmpty && election.primaryColor != '#6C5CE7';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: isCustomBg ? primaryBg.withValues(alpha: isDark ? 0.2 : 0.05) : (isDark ? AppColors.surface : Colors.white),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isCustomBg ? primaryBg.withValues(alpha: 0.3) : (isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.shade200),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 12,
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
                  width: 58, height: 58,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF27272A) : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade300),
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
                              color: AppColors.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '#${election.prefix}',
                              style: const TextStyle(color: AppColors.primaryLight, fontSize: 11, fontWeight: FontWeight.w700),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3.5),
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
                    Text(election.title, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
          
          if (election.description.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              election.description,
              style: TextStyle(color: isDark ? Colors.white70 : Colors.grey.shade700, fontSize: 14, height: 1.4),
            ),
          ],
          const SizedBox(height: 16),

          // Election Method & Voting Delivery Specification Banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: election.isVenueElection
                  ? (isDark ? Colors.purple.withValues(alpha: 0.15) : const Color(0xFFFAF5FF))
                  : (isDark ? Colors.blue.withValues(alpha: 0.15) : const Color(0xFFEFF6FF)),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: election.isVenueElection
                    ? (isDark ? Colors.purple.withValues(alpha: 0.4) : const Color(0xFFE9D5FF))
                    : (isDark ? Colors.blue.withValues(alpha: 0.4) : const Color(0xFFBFDBFE)),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: election.isVenueElection
                        ? Colors.purple.withValues(alpha: 0.2)
                        : Colors.blue.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    election.isVenueElection ? Icons.storefront_rounded : Icons.wifi_tethering_rounded,
                    color: election.isVenueElection ? Colors.purple : Colors.blue.shade700,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            election.isVenueElection
                                ? 'Method 2: Venue / Device-Based (भौतिक बुथ)'
                                : 'Method 1: Online / Remote (अनलाइन मतदान)',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13.5,
                              color: election.isVenueElection
                                  ? (isDark ? const Color(0xFFD8B4FE) : const Color(0xFF6B21A8))
                                  : (isDark ? const Color(0xFF93C5FD) : const Color(0xFF1E40AF)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: (election.isVenueElection ? Colors.purple : Colors.blue).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              election.isVenueElection
                                  ? 'Physical Kiosk'
                                  : election.onlineType == 'mobile_app'
                                      ? 'Type 1: Mobile App'
                                      : election.onlineType == 'web_based'
                                          ? 'Type 2: Web-Based'
                                          : 'Type 3: Hybrid',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: election.isVenueElection ? Colors.purple : Colors.blue.shade800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        election.isVenueElection
                            ? 'Polling Location: ${election.venueName.isNotEmpty ? election.venueName : "Venue Polling Booth"}${election.venueAddress.isNotEmpty ? " • ${election.venueAddress}" : ""}${election.requireVenueOtp ? " • 2nd Layer OTP (${election.venueOtpChannel.toUpperCase()})" : " • Direct Check-in"}'
                            : election.onlineType == 'mobile_app'
                                ? 'Mobile App Based: Voters authenticate via Mobile App with SMS & Email OTP.'
                                : election.onlineType == 'web_based'
                                    ? 'Web Based: Voters verify email on web to receive a single-use direct ballot link.'
                                    : 'Hybrid Delivery: Smart auto-routing based on voter device (Mobile App vs Web Browser).',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white70 : Colors.black87,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 14,
            runSpacing: 10,
            children: [
              _MetaItem(
                icon: election.isVenueElection ? Icons.storefront_outlined : Icons.language_rounded,
                label: election.isVenueElection
                    ? 'Venue: ${election.venueName.isNotEmpty ? election.venueName : "In-Person Polling"}'
                    : 'Delivery: ${election.onlineType == "mobile_app" ? "Mobile App" : election.onlineType == "web_based" ? "Web Single-Use" : "Hybrid (App+Web)"}',
              ),
              _MetaItem(icon: Icons.how_to_vote_outlined,
                  label: election.isSecretBallot ? 'Secret Ballot (गोप्य मतदान)' : 'Open Ballot (खुला मतदान)'),
              _MetaItem(icon: Icons.bar_chart_rounded,
                  label: '${election.positions.length} Designation(s)'),
              if (election.contactNumber.isNotEmpty)
                _MetaItem(icon: Icons.phone_outlined, label: 'Helpline: ${election.contactNumber}'),
              if (election.isPaidCandidacy)
                const _MetaItem(icon: Icons.monetization_on_outlined, label: 'Paid Nomination (Designation Fee Applies)'),
            ],
          ),
          
          const Divider(height: 32),
          
          Wrap(
            spacing: 24,
            runSpacing: 16,
            children: [
              if (election.firstVoterListDate != null || election.finalVoterListDate != null)
                _SingleMilestoneBlock(
                  title: '1. Voter Roll Scrutiny Schedule',
                  icon: Icons.people_alt_outlined,
                  milestones: [
                    if (election.firstVoterListDate != null) 'First List: ${_formatIsoDate(election.firstVoterListDate!)}',
                    if (election.voterListClaimDate != null) 'Claims Due: ${_formatIsoDate(election.voterListClaimDate!)}',
                    if (election.finalVoterListDate != null) 'Final Certified Roll: ${_formatIsoDate(election.finalVoterListDate!)}',
                  ],
                ),
              if (election.nominationOpenAt != null || election.candidacyFinalDate != null)
                if (election.nominationOpenAt != null && election.nominationCloseAt != null)
                  _ScheduleBlock(title: '2. Candidate Nominations', start: election.nominationOpenAt!, end: election.nominationCloseAt!, icon: Icons.assignment_ind_outlined)
                else if (election.candidacyClaimDate != null || election.candidacyFinalDate != null)
                  _SingleMilestoneBlock(
                    title: '2. Candidacy Scrutiny Milestones',
                    icon: Icons.verified_user_outlined,
                    milestones: [
                      if (election.candidacyClaimDate != null) 'Objections Due: ${_formatIsoDate(election.candidacyClaimDate!)}',
                      if (election.candidacyFinalDate != null) 'Final Candidate List: ${_formatIsoDate(election.candidacyFinalDate!)}',
                    ],
                  ),
              if (election.votingStartAt != null && election.votingEndAt != null)
                _ScheduleBlock(title: '3. Official Polling Period', start: election.votingStartAt!, end: election.votingEndAt!, icon: Icons.how_to_vote_rounded),
            ],
          ),
        ],
      ),
    );
  }

  static String _formatIsoDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${NepaliDateFormat('MMM d, yyyy').format(dt.toNepaliDateTime())} (BS)';
    } catch (_) {
      return iso;
    }
  }

  Widget _buildVoterListAndClaimsSection(BuildContext context, WidgetRef ref, ElectionModel election, UserModel? user) {
    final now = DateTime.now();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isObserverOrAuditor = (user?.isObserver ?? false) || (user?.isAuditor ?? false);

    DateTime? firstListDate = election.firstVoterListDate != null ? DateTime.tryParse(election.firstVoterListDate!) : null;
    DateTime? claimDeadline = election.voterListClaimDate != null ? DateTime.tryParse(election.voterListClaimDate!) : null;
    DateTime? finalListDate = election.finalVoterListDate != null ? DateTime.tryParse(election.finalVoterListDate!) : null;

    DateTime? nomClose = election.nominationCloseAt != null ? DateTime.tryParse(election.nominationCloseAt!) : null;
    DateTime? candClaimDeadline = election.candidacyClaimDate != null ? DateTime.tryParse(election.candidacyClaimDate!) : null;

    bool isVoterClaimOpen = false;
    if (firstListDate != null && now.isAfter(firstListDate)) {
      if (claimDeadline == null || now.isBefore(claimDeadline)) {
        isVoterClaimOpen = true;
      }
    }

    bool isFinalVoterList = finalListDate != null && now.isAfter(finalListDate);

    bool isCandObjectionOpen = false;
    if (nomClose != null && now.isAfter(nomClose)) {
      if (candClaimDeadline == null || now.isBefore(candClaimDeadline)) {
        isCandObjectionOpen = true;
      }
    }

    if (election.state == 'draft') return const SizedBox.shrink();

    String voterBadgeText;
    Color voterBadgeColor;
    String voterDescription;

    if (isFinalVoterList) {
      voterBadgeText = 'Certified Final Voter Roll (अन्तिम नामावली)';
      voterBadgeColor = Colors.green;
      voterDescription = 'The voter roll has been certified and locked. All eligible members are registered to cast ballots.';
    } else if (isVoterClaimOpen) {
      voterBadgeText = 'First Voter Roll Published — Claims Open';
      voterBadgeColor = Colors.blue;
      voterDescription = claimDeadline != null
          ? 'Claims and objections are open until ${_formatIsoDate(election.voterListClaimDate!)}. Review the roll and submit omissions/corrections if needed.'
          : 'First voter list published. Review the roll and submit claims/objections if needed.';
    } else if (firstListDate != null && now.isBefore(firstListDate)) {
      voterBadgeText = 'Voter Roll Scheduled';
      voterBadgeColor = AppColors.textMuted;
      voterDescription = 'The first voter list will be officially published on ${_formatIsoDate(election.firstVoterListDate!)}.';
    } else {
      voterBadgeText = 'Claims Closed — Scrutiny in Progress';
      voterBadgeColor = Colors.orange;
      voterDescription = 'The claim window has closed. The Election Committee is verifying claims before final certified publication.';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surface : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.badge_outlined, color: AppColors.primaryLight, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text('Voter Roll & Scrutiny Status', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: voterBadgeColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: voterBadgeColor.withValues(alpha: 0.5)),
                          ),
                          child: Text(
                            voterBadgeText,
                            style: TextStyle(color: voterBadgeColor, fontSize: 11, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(voterDescription, style: TextStyle(color: isDark ? Colors.white60 : Colors.grey.shade600, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => VotersScreen(electionId: election.id),
                    ),
                  );
                },
                icon: const Icon(Icons.people_outline_rounded, size: 18),
                label: const Text('View Published Voter Roll'),
              ),
              if (isVoterClaimOpen && !isObserverOrAuditor)
                ElevatedButton.icon(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => FileVoterClaimDialog(electionId: election.id),
                    );
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
                  icon: const Icon(Icons.rate_review_rounded, size: 18),
                  label: const Text('File Claim / Objection (दाबी-विरोध)'),
                ),
            ],
          ),
          if (isCandObjectionOpen) ...[
            const Divider(height: 24),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.gavel_rounded, color: Colors.orange, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Candidate Scrutiny & Objection Window (उम्मेदवार दाबी-विरोध)',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.orange),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          candClaimDeadline != null
                              ? 'Nominations are closed. You may file eligibility objections against any candidate before ${_formatIsoDate(election.candidacyClaimDate!)}.'
                              : 'Nominations are closed. You may file formal eligibility objections against candidates.',
                          style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black87),
                        ),
                      ],
                    ),
                  ),
                  if (!isObserverOrAuditor) ...[
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () {
                        final allCandidates = election.positions.expand((p) => p.candidates).toList();
                        showDialog(
                          context: context,
                          builder: (_) => FileCandidateObjectionDialog(
                            electionId: election.id,
                            candidates: allCandidates,
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade800, foregroundColor: Colors.white),
                      icon: const Icon(Icons.gavel, size: 16),
                      label: const Text('File Objection'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context, WidgetRef ref, ElectionModel election, UserModel? user) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        if (election.state == 'nomination_open' &&
            user != null &&
            !user.canManageElections &&
            !user.isObserver &&
            !user.isAuditor)
          ElevatedButton.icon(
            onPressed: () => context.pushNamed('nominate',
                pathParameters: {'electionId': electionId}),
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: const Text('Nominate Myself'),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
          ),
        if (election.state == 'nomination_open' && user?.canManageElections == true)
          ElevatedButton.icon(
            onPressed: () => context.pushNamed('review_nominations',
                pathParameters: {'electionId': electionId}),
            icon: const Icon(Icons.rate_review_rounded),
            label: const Text('Review Nominations'),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.stateNominations, foregroundColor: Colors.white),
          ),
        if (election.isVotingActive && user != null && !user.canManageElections && !user.isObserver && !user.isAuditor) ...[
          if (election.isVenueElection)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.purple.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.purple.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.storefront_rounded, color: Colors.purple, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'In-Person Booth Voting at ${election.venueName.isNotEmpty ? election.venueName : "Venue"}',
                    style: const TextStyle(color: Colors.purple, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ],
              ),
            )
          else if (election.isWebBasedOnly)
            ElevatedButton.icon(
              onPressed: () => _showRequestWebBallotDialog(context, election, user),
              icon: const Icon(Icons.mark_email_read_rounded),
              label: const Text('Get Web Ballot Link (मतदान लिङ्क पाउनुहोस्)'),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.stateVoting, foregroundColor: Colors.white),
            )
          else
            ElevatedButton.icon(
              onPressed: () => context.pushNamed('ballot',
                  pathParameters: {'electionId': electionId}),
              icon: const Icon(Icons.how_to_vote_rounded),
              label: const Text('Vote Now (मतदान गर्नुहोस्)'),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.stateVoting, foregroundColor: Colors.white),
            )
            .animate(onPlay: (controller) => controller.repeat(reverse: true))
            .scale(begin: const Offset(1, 1), end: const Offset(1.03, 1.03), duration: 800.ms),
        ],
        if (election.hasResults ||
            election.state == 'voting_closed' ||
            (election.state == 'voting_open' && user?.canManageElections == true))
          ElevatedButton.icon(
            onPressed: () => context.pushNamed('results',
                pathParameters: {'electionId': electionId}),
            icon: const Icon(Icons.emoji_events_outlined),
            label: const Text('View Results (नतिजा)'),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.stateResults, foregroundColor: Colors.white),
          ),

        if (user?.canManageElections == true && (election.isVenueElection || election.isHybrid))
          ElevatedButton.icon(
            onPressed: () => context.pushNamed('venue-kiosk', pathParameters: {'electionId': electionId}),
            icon: const Icon(Icons.storefront_rounded),
            label: const Text('Launch Voting Kiosk Mode (मतदान बुथ सुरु)'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.purple.shade700, foregroundColor: Colors.white),
          ),

        if (election.hasResults || user?.isAuditor == true || user?.canManageElections == true)
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
          ),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => NoticeScreen(electionId: election.id),
            ),
          ),
          icon: const Icon(Icons.campaign_outlined, size: 18),
          label: const Text('Notices (सूचना)'),
        ),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => GuidelinesScreen(electionId: election.id),
            ),
          ),
          icon: const Icon(Icons.menu_book_outlined, size: 18),
          label: const Text('Guidelines (निर्देशिका)'),
        ),
      ],
    );
  }

  Future<void> _advanceStateWithConfirm(
    BuildContext context,
    WidgetRef ref,
    String electionId,
    String targetState,
    String title,
    String message,
    String successMsg, {
    Color? confirmColor,
  }) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.info_outline, color: confirmColor ?? AppColors.primary),
            const SizedBox(width: 8),
            Text(title),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: confirmColor ?? AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await ref.read(publishElectionProvider.notifier).advanceElectionState(electionId, targetState);
      ref.invalidate(electionProvider(electionId));
      ref.invalidate(resultsProvider(electionId));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(successMsg)));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Widget _buildAdminControls(BuildContext context, WidgetRef ref, ElectionModel election) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surface : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primaryLight.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryLight.withValues(alpha: isDark ? 0.15 : 0.05),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.admin_panel_settings_rounded, color: AppColors.primaryLight, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Election Operations & Governance Hub', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    Text('Advance lifecycle phases and manage candidates, claims, and officers.', style: TextStyle(color: isDark ? Colors.white60 : Colors.grey.shade600, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              if (ref.watch(publishElectionProvider).isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                      SizedBox(width: 8),
                      Text('Transitioning election state...'),
                    ],
                  ),
                )
              else ...[
                if (election.state == 'draft')
                  ElevatedButton.icon(
                    onPressed: () => _advanceStateWithConfirm(
                      context, ref, election.id, 'published',
                      'Publish Election',
                      'Are you sure you want to publish this election? Voters will be notified.',
                      'Election Published Successfully!',
                      confirmColor: AppColors.primary,
                    ),
                    icon: const Icon(Icons.campaign_rounded),
                    label: const Text('Publish Election'),
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
                  ),
                if (election.state == 'published')
                  ElevatedButton.icon(
                    onPressed: () => _advanceStateWithConfirm(
                      context, ref, election.id, 'nomination_open',
                      'Open Nominations',
                      'Are you sure you want to open candidate nominations? Eligible members can begin submitting nominations.',
                      'Nominations Opened Successfully!',
                      confirmColor: AppColors.stateNominations,
                    ),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Open Nominations'),
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.stateNominations, foregroundColor: Colors.white),
                  ),
                if (election.state == 'nomination_open')
                  ElevatedButton.icon(
                    onPressed: () => _advanceStateWithConfirm(
                      context, ref, election.id, 'nomination_closed',
                      'Close Nominations',
                      'Are you sure you want to close candidate nominations? No new nominations will be accepted.',
                      'Nominations Closed Successfully!',
                      confirmColor: AppColors.stateNominations,
                    ),
                    icon: const Icon(Icons.stop_rounded),
                    label: const Text('Close Nominations'),
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.stateNominations, foregroundColor: Colors.white),
                  ),
                if (election.state == 'nomination_closed')
                  ElevatedButton.icon(
                    onPressed: () => _advanceStateWithConfirm(
                      context, ref, election.id, 'voting_open',
                      'Start Voting',
                      'Are you sure you want to open live voting polls? Verified voters will be able to cast their ballots.',
                      'Voting Started Successfully!',
                      confirmColor: AppColors.stateVoting,
                    ),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Start Voting'),
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.stateVoting, foregroundColor: Colors.white),
                  ),
                if (election.state == 'voting_open')
                  ElevatedButton.icon(
                    onPressed: () => _advanceStateWithConfirm(
                      context, ref, election.id, 'voting_closed',
                      'Close Voting',
                      'Are you sure you want to close live voting polls? Voting will cease and ballot counts will be frozen.',
                      'Voting Closed Successfully!',
                      confirmColor: AppColors.stateClosed,
                    ),
                    icon: const Icon(Icons.stop_rounded),
                    label: const Text('Close Voting'),
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.stateClosed, foregroundColor: Colors.white),
                  ),
                if (election.state == 'voting_closed') ...[
                  ElevatedButton.icon(
                    onPressed: () => _advanceStateWithConfirm(
                      context, ref, election.id, 'results_provisional',
                      'Publish Provisional Results',
                      'Publish provisional results for initial review and verification?',
                      'Provisional Results Published!',
                      confirmColor: Colors.orange.shade700,
                    ),
                    icon: const Icon(Icons.rate_review_outlined),
                    label: const Text('Publish Provisional Results'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade700, foregroundColor: Colors.white),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _advanceStateWithConfirm(
                      context, ref, election.id, 'results_final',
                      'Publish Final Results',
                      'Are you sure you want to finalize and certify official election results?',
                      'Final Official Results Published!',
                      confirmColor: AppColors.stateResults,
                    ),
                    icon: const Icon(Icons.verified_rounded),
                    label: const Text('Publish Final Results'),
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.stateResults, foregroundColor: Colors.white),
                  ),
                ],
                if (election.state == 'results_provisional')
                  ElevatedButton.icon(
                    onPressed: () => _advanceStateWithConfirm(
                      context, ref, election.id, 'results_final',
                      'Finalize & Publish Official Results',
                      'Are you sure you want to finalize and certify official election results? This action cannot be undone.',
                      'Final Official Results Published Successfully!',
                      confirmColor: AppColors.stateResults,
                    ),
                    icon: const Icon(Icons.verified_rounded),
                    label: const Text('Finalize & Publish Official Results'),
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.stateResults, foregroundColor: Colors.white),
                  ),
                if (election.state == 'results_final')
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.success),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_rounded, color: AppColors.success, size: 18),
                        SizedBox(width: 8),
                        Text('Final Results Certified & Published', style: TextStyle(color: AppColors.success, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          Divider(color: isDark ? Colors.white12 : Colors.grey.shade200),
          const SizedBox(height: 14),
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
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) => ManageVoterClaimsDialog(electionId: election.id),
                  ),
                  icon: const Icon(Icons.rate_review_rounded, size: 18, color: AppColors.primary),
                  label: const Text('Manage Voter Claims'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) => ManageCandidateObjectionsDialog(electionId: election.id),
                  ),
                  icon: const Icon(Icons.gavel_rounded, size: 18, color: Colors.orange),
                  label: const Text('Candidate Objections'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => context.pushNamed('election-turnout',
                      pathParameters: {'electionId': election.id}),
                  icon: const Icon(Icons.people_alt_outlined, size: 18),
                  label: const Text('Live Turnout'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => context.pushNamed('review_nominations',
                      pathParameters: {'electionId': election.id}),
                  icon: const Icon(Icons.fact_check_outlined, size: 18),
                  label: const Text('Review Nominations'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
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
                  label: const Text('Export Roll (CSV)'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
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
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => context.pushNamed('analytics',
                  pathParameters: {'electionId': election.id}),
              icon: const Icon(Icons.bar_chart_rounded, size: 18),
              label: const Text('Live Analytics & Telemetry Dashboard'),
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

  Widget _buildPositionsSection(BuildContext context, ElectionModel election, UserModel? user) {
    final isAdmin = user?.canManageElections ?? false;
    final now = DateTime.now();
    final candFinalDate = election.candidacyFinalDate != null ? DateTime.tryParse(election.candidacyFinalDate!) : null;
    final isFinalCandidates = candFinalDate != null && now.isAfter(candFinalDate);
    final isVotingOrBeyond = election.state == 'voting_open' || election.state == 'voting_closed' || election.state.startsWith('results');

    final isCertifiedFinal = isFinalCandidates || isVotingOrBeyond;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        isCertifiedFinal
                            ? 'Certified Candidate Roster'
                            : 'Candidate Nominations & Roster',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      if (isCertifiedFinal)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.green.withValues(alpha: 0.5)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.verified_rounded, color: Colors.green, size: 13),
                              SizedBox(width: 4),
                              Text(
                                'Certified Final (अन्तिम नामावली)',
                                style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        )
                      else if (election.state == 'nomination_closed')
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
                          ),
                          child: const Text(
                            'Preliminary Scrutiny (दाबी-विरोध जारी)',
                            style: TextStyle(color: Colors.orange, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isCertifiedFinal
                        ? 'The certified final candidate list has been officially published. Only verified approved candidates appear on the ballot.'
                        : 'Review candidates who have filed nominations across all election designations.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (election.positions.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark ? AppColors.surface : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: const Column(
              children: [
                Icon(Icons.badge_outlined, size: 36, color: AppColors.textMuted),
                SizedBox(height: 8),
                Text('No designations added yet.', style: TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          )
        else
          ...election.positions.map(
            (pos) => _PositionCard(
              electionId: election.id,
              position: pos,
              isAdmin: isAdmin,
              isCertifiedFinal: isCertifiedFinal,
            ),
          ),
      ],
    );
  }

  Color _stateColor(String state) {
    switch (state) {
      case 'draft': return AppColors.stateDraft;
      case 'published': return AppColors.statePublished;
      case 'nomination_open': case 'nomination_closed': return AppColors.stateNominations;
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
  final bool isCertifiedFinal;
  const _PositionCard({
    required this.electionId,
    required this.position,
    required this.isAdmin,
    this.isCertifiedFinal = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final activeCandidates = position.candidates.where((c) {
      if (c.status == 'withdrawn') return false;
      if (isCertifiedFinal) return c.status == 'approved';
      return isAdmin || c.status != 'rejected';
    }).toList();

    final withdrawnCandidates = position.candidates.where((c) => c.status == 'withdrawn').toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surface : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.star_border_rounded, color: AppColors.primaryLight, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(position.title,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 15, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text('${position.seatsAvailable} seat(s) · ${position.votingMethod.toUpperCase()}',
                        style: TextStyle(color: isDark ? Colors.white60 : Colors.grey.shade600, fontSize: 12)),
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
                    const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit_outlined, size: 16), SizedBox(width: 8), Text('Edit')])),
                    const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline_rounded, size: 16, color: AppColors.error), SizedBox(width: 8), Text('Delete', style: TextStyle(color: AppColors.error))])),
                  ],
                ),
            ],
          ),
          if (activeCandidates.isNotEmpty) ...[
            const SizedBox(height: 16),
            Divider(color: isDark ? Colors.white12 : Colors.grey.shade200),
            const SizedBox(height: 8),
            ...activeCandidates.map((c) => _CandidateTile(electionId: electionId, candidate: c, isAdmin: isAdmin)),
          ],
          if (withdrawnCandidates.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.person_off_outlined, color: Colors.grey, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        'Withdrawn Candidates (उम्मेदवारी फिर्ता) (${withdrawnCandidates.length})',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...withdrawnCandidates.map((c) => _CandidateTile(electionId: electionId, candidate: c, isAdmin: isAdmin)),
                ],
              ),
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
              color: isDark ? AppColors.surfaceVariant.withValues(alpha: 0.4) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.grey.shade200,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.02),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
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
                      if (candidate.manifesto.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          candidate.manifesto,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white60 : Colors.grey.shade600,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),

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
                          const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit_outlined, size: 16), SizedBox(width: 8), Text('Edit')])),
                          const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline_rounded, size: 16, color: AppColors.error), SizedBox(width: 8), Text('Delete', style: TextStyle(color: AppColors.error))])),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark ? Colors.white70 : Colors.black87;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 15),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
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
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: AppColors.primaryLight),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isDark ? Colors.white : Colors.black87)),
            const SizedBox(height: 4),
            Text('Starts: ${_format(start)} (BS)', style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.grey.shade600)),
            Text('Ends: ${_format(end)} (BS)', style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.grey.shade600)),
          ],
        ),
      ],
    );
  }
}

class _SingleMilestoneBlock extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<String> milestones;

  const _SingleMilestoneBlock({
    required this.title,
    required this.icon,
    required this.milestones,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: AppColors.primaryLight),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isDark ? Colors.white : Colors.black87)),
            const SizedBox(height: 4),
            ...milestones.map((m) => Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(m, style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.grey.shade600)),
            )),
          ],
        ),
      ],
    );
  }
}

void _showRequestWebBallotDialog(BuildContext context, ElectionModel election, UserModel? user) {
  showDialog(
    context: context,
    builder: (ctx) => _WebBallotRequestDialog(election: election, initialEmail: user?.email ?? ''),
  );
}

class _WebBallotRequestDialog extends ConsumerStatefulWidget {
  final ElectionModel election;
  final String initialEmail;
  const _WebBallotRequestDialog({required this.election, required this.initialEmail});

  @override
  ConsumerState<_WebBallotRequestDialog> createState() => _WebBallotRequestDialogState();
}

class _WebBallotRequestDialogState extends ConsumerState<_WebBallotRequestDialog> {
  late TextEditingController _identifierController;
  final TextEditingController _otpController = TextEditingController();
  bool _otpSent = false;
  bool _isLoading = false;
  String? _maskedEmail;
  String? _directToken;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _identifierController = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _identifierController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _requestOtp() async {
    final identifier = _identifierController.text.trim();
    if (identifier.isEmpty) {
      setState(() => _errorMessage = 'Please enter your registered email or Voter ID');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final dio = ref.read(apiClientProvider);
      final resp = await dio.post(
        ApiConstants.requestWebOtp,
        data: {
          'election_id': widget.election.id,
          'identifier': identifier,
        },
      );

      setState(() {
        _otpSent = true;
        _maskedEmail = resp.data['masked_email'] as String? ?? identifier;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  Future<void> _verifyOtp() async {
    final otp = _otpController.text.trim();
    if (otp.length != 6) {
      setState(() => _errorMessage = 'Please enter the 6-digit verification code');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final dio = ref.read(apiClientProvider);
      final resp = await dio.post(
        ApiConstants.verifyWebOtp,
        data: {
          'election_id': widget.election.id,
          'identifier': _identifierController.text.trim(),
          'otp': otp,
        },
      );

      setState(() {
        _directToken = resp.data['direct_token'] as String?;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: isDark ? AppColors.surface : Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.mark_email_read_rounded, color: AppColors.primary, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Web Ballot Verification',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        Text(
                          'Method 1 Type 2 • Single-Use Direct Ballot Link',
                          style: TextStyle(color: isDark ? Colors.white60 : Colors.grey.shade600, fontSize: 11.5),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),

              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 12.5)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],

              if (_directToken != null) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.check_circle_rounded, color: Colors.green, size: 36),
                      const SizedBox(height: 10),
                      const Text(
                        'Ballot Link Generated & Emailed!',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.green),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Your single-use direct ballot link has been sent to $_maskedEmail. You can also open the ballot immediately below.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      context.push('/vote/direct/$_directToken');
                    },
                    icon: const Icon(Icons.how_to_vote_rounded, size: 18),
                    label: const Text('Open Ballot Paper Now (मतदान गर्नुहोस्)'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ] else if (!_otpSent) ...[
                Text(
                  'Enter your registered email address or Voter ID to receive a 6-digit verification code.',
                  style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.grey.shade700),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _identifierController,
                  decoration: InputDecoration(
                    labelText: 'Email Address / Voter ID *',
                    hintText: 'e.g. voter@example.com or VOTER-001',
                    prefixIcon: const Icon(Icons.email_outlined),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _requestOtp,
                    icon: _isLoading
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.send_rounded, size: 18),
                    label: const Text('Send Verification Code'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ] else ...[
                Text(
                  'A 6-digit code has been dispatched to $_maskedEmail. Please enter it below:',
                  style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.grey.shade700),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _otpController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 8),
                  decoration: InputDecoration(
                    hintText: '------',
                    counterText: '',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    TextButton(
                      onPressed: _isLoading ? null : () => setState(() => _otpSent = false),
                      child: const Text('Change Email'),
                    ),
                    const Spacer(),
                    ElevatedButton.icon(
                      onPressed: _isLoading ? null : _verifyOtp,
                      icon: _isLoading
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.verified_rounded, size: 18),
                      label: const Text('Verify & Get Ballot Link'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

