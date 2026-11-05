import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/network/api_constants.dart';
import '../../core/providers/platform_providers.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/org_logo.dart';

/// Super Admin dashboard: platform totals as stat cards.
class PlatformStatCards extends ConsumerWidget {
  const PlatformStatCards({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(platformOverviewProvider);
    final o = overview.valueOrNull;
    final cards = [
      _StatCard(
        icon: Icons.account_balance_rounded,
        label: 'Institutions',
        caption: 'Registered organizations',
        value: o?.organizationCount,
        color: AppColors.primary,
      ),
      _StatCard(
        icon: Icons.how_to_vote_rounded,
        label: 'Total Elections',
        caption: 'Across all institutions',
        value: o?.electionCount,
        color: AppColors.statePublished,
      ),
      _StatCard(
        icon: Icons.bolt_rounded,
        label: 'Active Elections',
        caption: 'Announced, not yet final',
        value: o?.activeElectionCount,
        color: AppColors.stateVoting,
      ),
    ];
    if (overview.hasError && o == null) {
      return _ErrorCard(onRetry: () => ref.invalidate(platformOverviewProvider));
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 640) {
          return Column(
            children: [
              for (final c in cards) Padding(padding: const EdgeInsets.only(bottom: 12), child: c),
            ],
          );
        }
        return Row(
          children: [
            for (var i = 0; i < cards.length; i++) ...[
              if (i > 0) const SizedBox(width: 16),
              Expanded(child: cards[i]),
            ],
          ],
        );
      },
    );
  }
}

/// Super Admin dashboard: running and past elections, and the newest organizations.
class PlatformLists extends ConsumerWidget {
  const PlatformLists({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(platformOverviewProvider);
    final o = overview.valueOrNull;
    if (o == null) {
      return overview.hasError
          ? const SizedBox.shrink()
          : const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CircularProgressIndicator()),
            );
    }
    final running = _ListCard(
      title: 'Running Elections',
      icon: Icons.play_circle_fill_rounded,
      color: AppColors.stateVoting,
      emptyText: 'No elections are running right now.',
      tiles: [for (final e in o.runningElections) _ElectionTile(election: e)],
    );
    final past = _ListCard(
      title: 'Past Elections',
      icon: Icons.history_rounded,
      color: AppColors.stateResults,
      emptyText: 'No completed elections yet.',
      tiles: [for (final e in o.pastElections) _ElectionTile(election: e)],
    );
    final orgs = _ListCard(
      title: 'Organizations',
      icon: Icons.account_balance_rounded,
      color: AppColors.primary,
      emptyText: 'No organizations yet.',
      onSeeAll: () => context.pushNamed('platform-organizations'),
      tiles: [for (final org in o.organizations) _OrgTile(org: org)],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 980;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: running),
                  const SizedBox(width: 16),
                  Expanded(child: past),
                ],
              )
            else ...[
              running,
              const SizedBox(height: 16),
              past,
            ],
            const SizedBox(height: 16),
            orgs,
          ],
        );
      },
    );
  }
}

BoxDecoration _cardDecoration(bool isDark) => BoxDecoration(
      color: isDark ? AppColors.surface : Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.shade200),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ],
    );

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String caption;
  final int? value;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.caption,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? Colors.white60 : Colors.grey.shade600;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(isDark),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [color, color.withValues(alpha: 0.7)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4)),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value?.toString() ?? '—',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        height: 1.1,
                      ),
                ),
                const SizedBox(height: 2),
                Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                Text(caption, style: TextStyle(color: muted, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ListCard extends StatefulWidget {
  final String title;
  final IconData icon;
  final Color color;
  final String emptyText;
  final List<Widget> tiles;
  final VoidCallback? onSeeAll;

  const _ListCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.emptyText,
    required this.tiles,
    this.onSeeAll,
  });

  @override
  State<_ListCard> createState() => _ListCardState();
}

class _ListCardState extends State<_ListCard> {
  static const _collapsedCount = 6;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final divider = isDark ? Colors.white.withValues(alpha: 0.06) : Colors.grey.shade100;
    final shown = _expanded ? widget.tiles : widget.tiles.take(_collapsedCount).toList();
    final hidden = widget.tiles.length - shown.length;

    return Container(
      decoration: _cardDecoration(isDark),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 10, 14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(widget.icon, color: widget.color, size: 18),
                ),
                const SizedBox(width: 10),
                Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${widget.tiles.length}',
                    style: TextStyle(color: widget.color, fontWeight: FontWeight.w700, fontSize: 12),
                  ),
                ),
                const Spacer(),
                if (widget.onSeeAll != null)
                  TextButton.icon(
                    onPressed: widget.onSeeAll,
                    icon: const Icon(Icons.arrow_forward_rounded, size: 14),
                    label: const Text('See All'),
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: divider),
          if (widget.tiles.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 18),
              child: Text(
                widget.emptyText,
                textAlign: TextAlign.center,
                style: TextStyle(color: isDark ? Colors.white54 : Colors.grey.shade500),
              ),
            )
          else
            for (var i = 0; i < shown.length; i++) ...[
              if (i > 0) Divider(height: 1, indent: 72, color: divider),
              shown[i],
            ],
          if (hidden > 0 || _expanded && widget.tiles.length > _collapsedCount) ...[
            Divider(height: 1, color: divider),
            TextButton(
              onPressed: () => setState(() => _expanded = !_expanded),
              child: Text(_expanded ? 'Show less' : 'Show $hidden more'),
            ),
          ],
        ],
      ),
    );
  }
}

class _ElectionTile extends StatelessWidget {
  final PlatformOverviewElection election;
  const _ElectionTile({required this.election});

  String get _dates {
    final fmt = DateFormat('d MMM yyyy');
    final start = election.votingStartAt;
    final end = election.votingEndAt;
    if (start == null && end == null) return 'Voting date not set';
    if (start != null && end != null) {
      final s = fmt.format(start.toLocal());
      final e = fmt.format(end.toLocal());
      return s == e ? 'Voting $s' : 'Voting $s – $e';
    }
    return 'Voting ${fmt.format((start ?? end)!.toLocal())}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? Colors.white60 : Colors.grey.shade600;
    final color = electionStateColor(election.state);
    return InkWell(
      onTap: () => context.pushNamed('platform-election', pathParameters: {'id': election.id}),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        child: Row(
          children: [
            OrgLogo(name: election.organization.name, logoUrl: election.organization.logoUrl, size: 40),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    election.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${election.organization.name}  ·  $_dates',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            _Chip(label: election.stateDisplay, color: color),
          ],
        ),
      ),
    );
  }
}

class _OrgTile extends StatelessWidget {
  final PlatformOrganizationModel org;
  const _OrgTile({required this.org});

  static const _statusColors = {
    'trial': AppColors.statePublished,
    'active': AppColors.stateVoting,
    'past_due': AppColors.stateClosed,
    'suspended': AppColors.error,
    'cancelled': AppColors.stateDraft,
  };

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? Colors.white60 : Colors.grey.shade600;
    final address = org.prefix.isEmpty
        ? 'No prefix set'
        : '#/o/$($org.prefix)';
    final status = org.status.replaceAll('_', ' ');
    return InkWell(
      onTap: () => context.pushNamed('platform-organization', pathParameters: {'id': org.id}),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        child: Row(
          children: [
            OrgLogo(name: org.name, logoUrl: org.logoUrl, size: 40),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    org.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$address  ·  ${org.electionCount} elections  ·  ${org.voterCount} voters',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            _Chip(
              label: status.isEmpty ? '' : status[0].toUpperCase() + status.substring(1),
              color: _statusColors[org.status] ?? AppColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 11.5)),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorCard({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(isDark),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, color: AppColors.error),
          const SizedBox(width: 12),
          const Expanded(child: Text('Could not load the platform overview.')),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

/// Colour for an election state badge.
Color electionStateColor(String state) {
  switch (state) {
    case 'draft':
      return AppColors.stateDraft;
    case 'published':
      return AppColors.statePublished;
    case 'nomination_open':
    case 'nomination_closed':
      return AppColors.stateNominations;
    case 'voting_open':
      return AppColors.stateVoting;
    case 'voting_closed':
      return AppColors.stateClosed;
    case 'results_provisional':
    case 'results_final':
      return AppColors.stateResults;
    case 'cancelled':
      return AppColors.error;
    default:
      return AppColors.textMuted;
  }
}
