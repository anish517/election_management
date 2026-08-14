import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/org_providers.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/loading_button.dart';
import '../../../shared/widgets/admin_drawer.dart';
import '../../../shared/widgets/shimmer_loaders.dart';

class ElectionRulesScreen extends ConsumerStatefulWidget {
  const ElectionRulesScreen({super.key});

  @override
  ConsumerState<ElectionRulesScreen> createState() => _ElectionRulesScreenState();
}

class _ElectionRulesScreenState extends ConsumerState<ElectionRulesScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _defaultNominationCtrl;
  late TextEditingController _defaultVotingCtrl;
  late TextEditingController _voterRollOffsetCtrl;
  late TextEditingController _defaultSilentCtrl;
  late TextEditingController _grievanceWindowCtrl;
  String _selectedVisibility = 'admin_only';
  bool _officersCanPublish = false;

  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _defaultNominationCtrl = TextEditingController();
    _defaultVotingCtrl = TextEditingController();
    _voterRollOffsetCtrl = TextEditingController();
    _defaultSilentCtrl = TextEditingController();
    _grievanceWindowCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _defaultNominationCtrl.dispose();
    _defaultVotingCtrl.dispose();
    _voterRollOffsetCtrl.dispose();
    _defaultSilentCtrl.dispose();
    _grievanceWindowCtrl.dispose();
    super.dispose();
  }

  void _populateForm(OrganizationModel org) {
    if (_initialized) return;
    _defaultNominationCtrl.text = org.defaultNominationWindowDays.toString();
    _defaultVotingCtrl.text = org.defaultVotingWindowDays.toString();
    _voterRollOffsetCtrl.text = org.voterRollFreezeOffsetDays.toString();
    _defaultSilentCtrl.text = org.defaultSilentPeriodHours.toString();
    _grievanceWindowCtrl.text = org.grievanceWindowDays.toString();
    _selectedVisibility = org.defaultResultVisibility.isNotEmpty
        ? org.defaultResultVisibility
        : 'admin_only';
    _officersCanPublish = org.electionOfficersCanPublish;
    _initialized = true;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    try {
      await ref.read(updateOrgSettingsProvider.notifier).updateSettings({
        'default_nomination_window_days': int.tryParse(_defaultNominationCtrl.text.trim()) ?? 7,
        'default_voting_window_days': int.tryParse(_defaultVotingCtrl.text.trim()) ?? 1,
        'voter_roll_freeze_offset_days': int.tryParse(_voterRollOffsetCtrl.text.trim()) ?? 0,
        'default_silent_period_hours': int.tryParse(_defaultSilentCtrl.text.trim()) ?? 24,
        'grievance_window_days': int.tryParse(_grievanceWindowCtrl.text.trim()) ?? 3,
        'default_result_visibility': _selectedVisibility,
        'election_officers_can_publish': _officersCanPublish,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 12),
              Text('Election rules saved successfully!', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          backgroundColor: Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(24),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(child: Text('Error: $e')),
            ],
          ),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(24),
        ));
      }
    }
  }

  Widget _section({
    required String title,
    required String subtitle,
    required IconData icon,
    required List<Widget> children,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E24) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.06),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: AppColors.primary, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? AppColors.textSecondary : AppColors.textSecondaryLightMode,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.06),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
          ),
        ],
      ),
    );
  }

  InputDecoration _dec(String label, {String? hint, Widget? prefix}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: prefix,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final orgAsync = ref.watch(orgProfileProvider);
    final isSaving = ref.watch(updateOrgSettingsProvider).isLoading;

    return Scaffold(
      drawer: const AdminDrawer(),
      appBar: AppBar(
        title: const Text('Election Rules & Policies'),
        elevation: 0,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16, top: 8, bottom: 8),
            child: LoadingButton(
              onPressed: _submit,
              isLoading: isSaving,
              label: 'Save Changes',
              icon: Icons.save_rounded,
              fullWidth: false,
            ),
          ),
        ],
      ),
      body: orgAsync.when(
        loading: () => const ListSkeleton(count: 4),
        error: (err, _) => Center(child: Text('Error loading rules: $err')),
        data: (org) {
          _populateForm(org);
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 100),
                  children: [
                    _section(
                      title: 'Default Timeframes',
                      subtitle: 'Applied automatically as initial defaults when creating new elections',
                      icon: Icons.schedule_rounded,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _defaultNominationCtrl,
                                decoration: _dec('Nomination Phase (Days)', prefix: const Icon(Icons.assignment_ind_outlined)),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: _defaultVotingCtrl,
                                decoration: _dec('Voting Phase (Days)', prefix: const Icon(Icons.how_to_vote_outlined)),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _voterRollOffsetCtrl,
                                decoration: _dec('Roll Freeze Offset (Days)', prefix: const Icon(Icons.people_outline)),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: _defaultSilentCtrl,
                                decoration: _dec('Silent Period (Hours)', prefix: const Icon(Icons.volume_off_outlined)),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _grievanceWindowCtrl,
                          decoration: _dec('Post-Election Grievance Window (Days)', prefix: const Icon(Icons.report_problem_outlined)),
                          keyboardType: TextInputType.number,
                        ),
                      ],
                    ),
                    _section(
                      title: 'Transparency & Default Permissions',
                      subtitle: 'Control default visibility of tallies and election officer publishing permissions',
                      icon: Icons.visibility_outlined,
                      children: [
                        DropdownButtonFormField<String>(
                          initialValue: _selectedVisibility,
                          decoration: _dec('Default Result Visibility', prefix: const Icon(Icons.remove_red_eye_outlined)),
                          items: const [
                            DropdownMenuItem(value: 'admin_only', child: Text('Admin Only')),
                            DropdownMenuItem(value: 'org_members', child: Text('Organization Members')),
                            DropdownMenuItem(value: 'public', child: Text('Public (Anyone)')),
                          ],
                          onChanged: (val) => setState(() => _selectedVisibility = val ?? 'admin_only'),
                        ),
                        const SizedBox(height: 20),
                        Material(
                          color: AppColors.primary.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.primary.withValues(alpha: 0.1)),
                            ),
                            child: SwitchListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              title: const Text('Officers Can Publish Results', style: TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: const Text(
                                'Allow Election Officers to publish provisional & final results without Org Admin approval.',
                                style: TextStyle(fontSize: 12),
                              ),
                              value: _officersCanPublish,
                              activeThumbColor: AppColors.primary,
                              onChanged: (val) => setState(() => _officersCanPublish = val),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
