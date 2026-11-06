import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/network/api_constants.dart';
import '../../../core/providers/platform_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/org_logo.dart';
import '../../../shared/widgets/responsive_layout.dart';

const _statusLabels = {
  'trial': 'Trial',
  'active': 'Active',
  'past_due': 'Past Due',
  'suspended': 'Suspended',
  'cancelled': 'Cancelled',
};

/// "1 voter", "3 voters".
String _count(int n, String noun) => '$n $noun${n == 1 ? '' : 's'}';

Color _statusColor(String status) {
  switch (status) {
    case 'active':
      return AppColors.success;
    case 'trial':
      return AppColors.info;
    case 'past_due':
      return AppColors.warning;
    default:
      return AppColors.error;
  }
}

/// Super Admin console: every organization (tenant) on the platform.
Widget _buildOrgLinks(BuildContext context, PlatformOrganizationModel org) {
  if (org.prefix.isEmpty) return const SizedBox.shrink();
  final loginUrl = ApiConstants.orgLoginUrl(org.prefix, portalToken: org.portalToken);
  final publicUrl = ApiConstants.orgPublicUrl(org.prefix);
  final shortLogin = org.portalToken.isNotEmpty
      ? '#/${org.portalToken}/${org.prefix}/login'
      : '#/login?org=${org.prefix}';

  return Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 4),
    child: Wrap(
      spacing: 10,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            Clipboard.setData(ClipboardData(text: loginUrl));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Copied Login Link for ${org.name} to clipboard'),
                duration: const Duration(seconds: 2),
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.login_rounded, size: 14, color: AppColors.primary),
                const SizedBox(width: 5),
                Text(
                  'Login: $shortLogin',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.copy_rounded, size: 13, color: AppColors.primary),
              ],
            ),
          ),
        ),
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => launchUrl(Uri.parse(publicUrl), webOnlyWindowName: '_blank'),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.public_rounded, size: 14, color: Colors.grey),
                const SizedBox(width: 5),
                Text(
                  'Public: #/o/${org.prefix}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).textTheme.bodySmall?.color,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.open_in_new_rounded, size: 12, color: Colors.grey),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
class PlatformOrganizationsScreen extends ConsumerStatefulWidget {
  const PlatformOrganizationsScreen({super.key});

  @override
  ConsumerState<PlatformOrganizationsScreen> createState() =>
      _PlatformOrganizationsScreenState();
}

class _PlatformOrganizationsScreenState
    extends ConsumerState<PlatformOrganizationsScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _createOrganization() async {
    await context.pushNamed('register');
    ref.invalidate(platformOrganizationsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final orgsAsync = ref.watch(platformOrganizationsProvider);
    final statusFilter = ref.watch(platformOrgStatusProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('All Organizations'),
        centerTitle: false,
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.canPop()
              ? context.pop()
              : context.goNamed('dashboard'),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(platformOrganizationsProvider),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createOrganization,
        icon: const Icon(Icons.add_business_rounded),
        label: const Text('New Organization'),
      ),
      body: CenteredScroll(
        maxWidth: 960,
        builder: (context, pad) => Column(
          children: [
            Padding(
              padding: pad(const EdgeInsets.fromLTRB(16, 16, 16, 8)),
              child: TextField(
                controller: _searchCtrl,
                decoration: const InputDecoration(
                  hintText: 'Search by name, prefix or email',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
                onSubmitted: (v) =>
                    ref.read(platformOrgSearchProvider.notifier).state = v.trim(),
              ),
            ),
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: pad(const EdgeInsets.symmetric(horizontal: 16)),
                children: [
                  _filterChip('All', null, statusFilter),
                  for (final e in _statusLabels.entries)
                    _filterChip(e.value, e.key, statusFilter),
                ],
              ),
            ),
            Expanded(
              child: orgsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Could not load organizations: $e'),
                  ),
                ),
                data: (orgs) {
                  if (orgs.isEmpty) {
                    return const EmptyStateWidget(
                      icon: Icons.business_rounded,
                      title: 'No organizations found',
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: () =>
                        ref.refresh(platformOrganizationsProvider.future),
                    child: ListView.separated(
                      padding: pad(const EdgeInsets.fromLTRB(16, 8, 16, 96)),
                      itemCount: orgs.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, i) => _OrgCard(org: orgs[i]),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String label, String? value, String? selected) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected == value,
        onSelected: (_) =>
            ref.read(platformOrgStatusProvider.notifier).state = value,
      ),
    );
  }
}

class _OrgCard extends ConsumerWidget {
  final PlatformOrganizationModel org;
  const _OrgCard({required this.org});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final color = _statusColor(org.status);
    final dateFmt = DateFormat('d MMM yyyy');

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.pushNamed(
          'platform-organization',
          pathParameters: {'id': org.id},
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  OrgLogo(name: org.name, logoUrl: org.logoUrl, size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      org.name,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _statusLabels[org.status] ?? org.status,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                org.adminEmails.isEmpty
                    ? 'No org admin'
                    : 'Admin: ${org.adminEmails.join(', ')}',
                style: theme.textTheme.bodySmall,
              ),
              _buildOrgLinks(context, org),
              const SizedBox(height: 10),
              Wrap(
                spacing: 16,
                runSpacing: 6,
                children: [
                  _stat(Icons.how_to_reg_rounded, _count(org.voterCount, 'voter')),
                  _stat(Icons.people_alt_rounded, _count(org.memberCount, 'member')),
                  _stat(Icons.how_to_vote_rounded, _count(org.electionCount, 'election')),
                  if (org.createdAt != null)
                    _stat(Icons.event_rounded,
                        'Created ${dateFmt.format(org.createdAt!.toLocal())}'),
                  if (org.status == 'trial' && org.trialEndsAt != null)
                    _stat(Icons.hourglass_bottom_rounded,
                        'Trial ends ${dateFmt.format(org.trialEndsAt!.toLocal())}'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stat(IconData icon, String text) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.textMuted),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(fontSize: 13)),
        ],
      );
}

String _electionStateLabel(PlatformElectionModel e) => e.stateDisplay.isNotEmpty
    ? e.stateDisplay
    : e.state.replaceAll('_', ' ');

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
    default:
      return AppColors.textMuted;
  }
}

/// Super Admin view of one tenant: lifecycle summary plus all its elections.
class PlatformOrganizationDetailScreen extends ConsumerWidget {
  final String orgId;
  const PlatformOrganizationDetailScreen({super.key, required this.orgId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orgAsync = ref.watch(platformOrganizationProvider(orgId));
    final electionsAsync = ref.watch(platformOrgElectionsProvider(orgId));

    Future<void> refresh() async {
      ref.invalidate(platformOrganizationProvider(orgId));
      ref.invalidate(platformOrgElectionsProvider(orgId));
      await ref.read(platformOrgElectionsProvider(orgId).future);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(orgAsync.valueOrNull?.name ?? 'Organization'),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: refresh,
          ),
        ],
      ),
      body: CenteredScroll(
        maxWidth: 960,
        builder: (context, pad) => RefreshIndicator(
          onRefresh: refresh,
          child: ListView(
            padding: pad(const EdgeInsets.fromLTRB(16, 16, 16, 40)),
            children: [
              orgAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Text('Could not load organization: $e'),
                data: (org) => _OrgSummaryCard(org: org),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Elections',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  FilledButton.icon(
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Create Election for Org'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      backgroundColor: AppColors.primary,
                    ),
                    onPressed: () {
                      context.push('/elections/new?orgId=$orgId');
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              electionsAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Text('Could not load elections: $e'),
                data: (elections) => elections.isEmpty
                    ? const EmptyStateWidget(
                        icon: Icons.how_to_vote_rounded,
                        title: 'No elections yet',
                      )
                    : Column(
                        children: [
                          for (final e in elections) ...[
                            _ElectionRow(election: e),
                            const SizedBox(height: 10),
                          ],
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrgSummaryCard extends StatelessWidget {
  final PlatformOrganizationModel org;
  const _OrgSummaryCard({required this.org});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _statusColor(org.status);
    final dateFmt = DateFormat('d MMM yyyy');

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
                OrgLogo(name: org.name, logoUrl: org.logoUrl, size: 52),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    org.name,
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _statusLabels[org.status] ?? org.status,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              org.adminEmails.isEmpty
                  ? 'No org admin'
                  : 'Admin: ${org.adminEmails.join(', ')}',
              style: theme.textTheme.bodySmall,
            ),
            _buildOrgLinks(context, org),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                _iconText(Icons.how_to_reg_rounded, _count(org.voterCount, 'voter')),
                _iconText(Icons.people_alt_rounded, _count(org.memberCount, 'member')),
                _iconText(Icons.how_to_vote_rounded, _count(org.electionCount, 'election')),
                if (org.createdAt != null)
                  _iconText(Icons.event_rounded,
                      'Created ${dateFmt.format(org.createdAt!.toLocal())}'),
                if (org.status == 'trial' && org.trialEndsAt != null)
                  _iconText(Icons.hourglass_bottom_rounded,
                      'Trial ends ${dateFmt.format(org.trialEndsAt!.toLocal())}'),
              ],
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                builder: (_) => _OrgLifecycleSheet(org: org),
              ),
              icon: const Icon(Icons.tune_rounded, size: 18),
              label: const Text('Status & Trial'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ElectionRow extends StatelessWidget {
  final PlatformElectionModel election;
  const _ElectionRow({required this.election});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = electionStateColor(election.state);
    final dateFmt = DateFormat('d MMM yyyy, h:mm a');
    final turnout = election.voterCount == 0
        ? null
        : (election.votedCount * 100 / election.voterCount).toStringAsFixed(0);

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.pushNamed(
          'platform-election',
          pathParameters: {'id': election.id},
        ),
        child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    election.title,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: color.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    _electionStateLabel(election).toUpperCase(),
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                _iconText(Icons.work_outline_rounded,
                    '${election.positionCount} positions'),
                _iconText(Icons.people_outline_rounded,
                    '${election.voterCount} voters'),
                _iconText(
                  Icons.check_circle_outline_rounded,
                  turnout == null
                      ? 'No votes'
                      : '${election.votedCount} voted ($turnout%)',
                ),
                if (election.votingStartAt != null)
                  _iconText(
                    Icons.schedule_rounded,
                    'Voting ${dateFmt.format(election.votingStartAt!.toLocal())}'
                    '${election.votingEndAt != null ? ' – ${dateFmt.format(election.votingEndAt!.toLocal())}' : ''}',
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.tune_rounded, size: 14),
                  label: const Text('Open Election Control Panel', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () => context.push('/elections/${election.id}'),
                ),
              ],
            ),
          ],
        ),
        ),
      ),
    );
  }
}

Widget _iconText(IconData icon, String text) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AppColors.textMuted),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(fontSize: 13)),
      ],
    );

/// Change a tenant's status or extend its trial.
class _OrgLifecycleSheet extends ConsumerStatefulWidget {
  final PlatformOrganizationModel org;
  const _OrgLifecycleSheet({required this.org});

  @override
  ConsumerState<_OrgLifecycleSheet> createState() => _OrgLifecycleSheetState();
}

class _OrgLifecycleSheetState extends ConsumerState<_OrgLifecycleSheet> {
  late String _status = widget.org.status;
  bool _saving = false;

  Future<void> _save(Map<String, dynamic> data, String message) async {
    setState(() => _saving = true);
    try {
      await updatePlatformOrganization(ref, widget.org.id, data);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Update failed: ${e.response?.data ?? e.message}'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _extendTrial(int days) {
    final now = DateTime.now();
    final current = widget.org.trialEndsAt;
    final base = current != null && current.isAfter(now) ? current : now;
    _save(
      {
        'trial_ends_at':
            base.add(Duration(days: days)).toUtc().toIso8601String(),
      },
      'Trial for ${widget.org.name} extended by $days days',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.org.name,
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
            Text(widget.org.slug, style: theme.textTheme.bodySmall),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              initialValue: _status,
              decoration: const InputDecoration(labelText: 'Status'),
              items: [
                for (final e in _statusLabels.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: _saving
                  ? null
                  : (v) => setState(() => _status = v ?? _status),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _saving || _status == widget.org.status
                  ? null
                  : () => _save(
                        {'status': _status},
                        '${widget.org.name} is now ${_statusLabels[_status]}',
                      ),
              child: const Text('Save Status'),
            ),
            const SizedBox(height: 20),
            Text('Extend trial', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final days in const [14, 30, 90]) ...[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving ? null : () => _extendTrial(days),
                      child: Text('+$days days'),
                    ),
                  ),
                  if (days != 90) const SizedBox(width: 8),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
