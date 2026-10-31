import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/providers/platform_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/empty_state.dart';

const _statusLabels = {
  'trial': 'Trial',
  'active': 'Active',
  'past_due': 'Past Due',
  'suspended': 'Suspended',
  'cancelled': 'Cancelled',
};

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
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(
                    hintText: 'Search by name, slug or email',
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
                  padding: const EdgeInsets.symmetric(horizontal: 16),
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
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
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
        onTap: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          builder: (_) => _OrgLifecycleSheet(org: org),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
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
              const SizedBox(height: 10),
              Wrap(
                spacing: 16,
                runSpacing: 6,
                children: [
                  _stat(Icons.people_alt_rounded, '${org.memberCount} members'),
                  _stat(Icons.how_to_vote_rounded,
                      '${org.electionCount} elections'),
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
