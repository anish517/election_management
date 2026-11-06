import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/network/api_constants.dart';
import '../../../core/providers/platform_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/models.dart';
import 'platform_organizations_screen.dart' show electionStateColor;
import '../../../shared/widgets/responsive_layout.dart';

final _dateFmt = DateFormat('d MMM yyyy, h:mm a');

/// Super Admin, read-only view of any tenant's election. Vote tallies are not
/// shown here; they stay behind the results publication flow.
class PlatformElectionDetailScreen extends ConsumerWidget {
  final String electionId;
  const PlatformElectionDetailScreen({super.key, required this.electionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(platformElectionDetailProvider(electionId));

    return Scaffold(
      appBar: AppBar(
        title: Text(async.valueOrNull?.title ?? 'Election'),
        centerTitle: false,
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            final orgId = async.valueOrNull?.organizationId;
            if (context.canPop()) {
              context.pop();
            } else if (orgId != null && orgId.isNotEmpty) {
              context.goNamed('platform-organization', pathParameters: {'id': orgId});
            } else {
              context.goNamed('platform-organizations');
            }
          },
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(platformElectionDetailProvider(electionId)),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Could not load election: $e'),
          ),
        ),
        data: (e) => CenteredScroll(
          maxWidth: 960,
          builder: (context, pad) => RefreshIndicator(
            onRefresh: () => ref.refresh(platformElectionDetailProvider(electionId).future),
            child: ListView(
              padding: pad(const EdgeInsets.fromLTRB(16, 16, 16, 40)),
              children: [
                _Header(e: e),
                const SizedBox(height: 16),
                _VoterStats(e: e),
                const SizedBox(height: 16),
                _Section(
                  title: 'Settings',
                  icon: Icons.tune_rounded,
                  child: _Settings(e: e),
                ),
                if (e.schedule.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _Section(
                    title: 'Schedule',
                    icon: Icons.event_note_rounded,
                    child: Column(
                      children: [
                        for (final (label, at) in e.schedule)
                          _KeyValue(label, _dateFmt.format(at.toLocal())),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                _Section(
                  title: 'Positions & Candidates',
                  icon: Icons.work_outline_rounded,
                  child: e.positions.isEmpty
                      ? const Text('No positions yet')
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final p in e.positions) _PositionBlock(p: p),
                          ],
                        ),
                ),
                if (e.history.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _Section(
                    title: 'State History',
                    icon: Icons.history_rounded,
                    child: Column(
                      children: [
                        for (final (from, to, at) in e.history)
                          _KeyValue('$from → $to', _dateFmt.format(at.toLocal())),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final PlatformElectionDetailModel e;
  const _Header({required this.e});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = electionStateColor(e.state);
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        e.title,
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      InkWell(
                        onTap: e.organizationId.isEmpty
                            ? null
                            : () => context.goNamed(
                                  'platform-organization',
                                  pathParameters: {'id': e.organizationId},
                                ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.domain_rounded,
                                size: 16, color: AppColors.textMuted),
                            const SizedBox(width: 6),
                            Text(e.organizationName,
                                style: theme.textTheme.bodySmall),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: color.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    (e.stateDisplay.isNotEmpty ? e.stateDisplay : e.state)
                        .toUpperCase(),
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            if (e.description.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(e.description, style: theme.textTheme.bodyMedium),
            ],
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.admin_panel_settings_rounded, size: 16),
                  label: const Text('Open in Election Control Panel'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                  onPressed: () => context.push('/elections/${e.id}/overview'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _VoterStats extends StatelessWidget {
  final PlatformElectionDetailModel e;
  const _VoterStats({required this.e});

  @override
  Widget build(BuildContext context) {
    final turnout = e.votersEligible == 0
        ? '—'
        : '${(e.votersVoted * 100 / e.votersEligible).toStringAsFixed(1)}%';
    final candidates =
        e.positions.fold<int>(0, (n, p) => n + p.candidates.length);
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 640 ? 4 : 2;
        final w = (c.maxWidth - (cols - 1) * 12) / cols;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final (label, value, icon, color) in [
              ('Voters', '${e.votersTotal}', Icons.people_alt_rounded, AppColors.info),
              ('Eligible', '${e.votersEligible}', Icons.verified_user_rounded, AppColors.primaryLight),
              ('Voted', '${e.votersVoted} · $turnout', Icons.check_circle_rounded, AppColors.success),
              ('Candidates', '$candidates', Icons.person_pin_rounded, AppColors.accent),
            ])
              SizedBox(
                width: w,
                child: Card(
                  margin: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(icon, size: 18, color: color),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(value,
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800)),
                              Text(label,
                                  style: Theme.of(context).textTheme.bodySmall),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Settings extends StatelessWidget {
  final PlatformElectionDetailModel e;
  const _Settings({required this.e});

  @override
  Widget build(BuildContext context) {
    final venue = [e.venueName, e.venueAddress].where((s) => s.isNotEmpty).join(', ');
    return Column(
      children: [
        if (e.prefix.isNotEmpty) _KeyValue('Prefix', e.prefix),
        _KeyValue('Election type', e.electionType),
        _KeyValue(
          'Method',
          [e.electionMethod, if (e.onlineType.isNotEmpty) e.onlineType].join(' · '),
        ),
        if (venue.isNotEmpty) _KeyValue('Venue', venue),
        _KeyValue('Secret ballot', e.isSecretBallot ? 'Yes' : 'No'),
        _KeyValue(
          'Candidacy fee',
          e.isPaidCandidacy ? 'Paid (Rs. ${e.nomineeCharge})' : 'Free',
        ),
        _KeyValue('Results visibility', e.resultsVisibility),
      ],
    );
  }
}

class _PositionBlock extends StatelessWidget {
  final PlatformPositionSummary p;
  const _PositionBlock({required this.p});

  Color _statusColor(String status) {
    switch (status) {
      case 'approved':
        return AppColors.success;
      case 'rejected':
      case 'withdrawn':
        return AppColors.error;
      case 'submitted':
      case 'under_review':
        return AppColors.warning;
      default:
        return AppColors.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            p.title,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          Text(
            [
              '${p.seats} seat${p.seats == 1 ? '' : 's'}',
              p.votingMethod,
              if (p.quotaName.isNotEmpty) p.quotaName,
            ].join(' · '),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          if (p.candidates.isEmpty)
            Text('No candidates', style: theme.textTheme.bodySmall)
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in p.candidates)
                  Container(
                    padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: theme.dividerColor),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 13,
                          backgroundColor:
                              AppColors.primaryLight.withValues(alpha: 0.2),
                          backgroundImage: c.imageUrl.isNotEmpty
                              ? NetworkImage(
                                  ApiConstants.getFullImageUrl(c.imageUrl)!)
                              : null,
                          child: c.imageUrl.isEmpty
                              ? Text(
                                  c.fullName.isNotEmpty
                                      ? c.fullName[0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold),
                                )
                              : null,
                        ),
                        const SizedBox(width: 8),
                        Text(c.fullName, style: const TextStyle(fontSize: 13)),
                        const SizedBox(width: 8),
                        Text(
                          c.statusDisplay,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _statusColor(c.status),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  const _Section({required this.title, required this.icon, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: AppColors.primaryLight),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _KeyValue extends StatelessWidget {
  final String label;
  final String value;
  const _KeyValue(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 170,
            child: Text(label, style: theme.textTheme.bodySmall),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
