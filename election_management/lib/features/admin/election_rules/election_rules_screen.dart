import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/org_providers.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/loading_button.dart';
import '../../../shared/widgets/admin_drawer.dart';
import '../../../shared/widgets/shimmer_loaders.dart';
import '../../../shared/widgets/responsive_layout.dart';

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

  // Nomination Endorsements & Ballot Duration Config
  late TextEditingController _minProposersCtrl;
  late TextEditingController _maxProposersCtrl;
  late TextEditingController _minSupportersCtrl;
  late TextEditingController _maxSupportersCtrl;
  late TextEditingController _votingTimeLimitCtrl;
  bool _showVotingDuration = false;
  bool _enableVotingCountdown = false;

  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _defaultNominationCtrl = TextEditingController();
    _defaultVotingCtrl = TextEditingController();
    _voterRollOffsetCtrl = TextEditingController();
    _defaultSilentCtrl = TextEditingController();
    _grievanceWindowCtrl = TextEditingController();
    _minProposersCtrl = TextEditingController();
    _maxProposersCtrl = TextEditingController();
    _minSupportersCtrl = TextEditingController();
    _maxSupportersCtrl = TextEditingController();
    _votingTimeLimitCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _defaultNominationCtrl.dispose();
    _defaultVotingCtrl.dispose();
    _voterRollOffsetCtrl.dispose();
    _defaultSilentCtrl.dispose();
    _grievanceWindowCtrl.dispose();
    _minProposersCtrl.dispose();
    _maxProposersCtrl.dispose();
    _minSupportersCtrl.dispose();
    _maxSupportersCtrl.dispose();
    _votingTimeLimitCtrl.dispose();
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

    _minProposersCtrl.text = (org.paymentSettings['min_proposers'] ?? 1).toString();
    _maxProposersCtrl.text = (org.paymentSettings['max_proposers'] ?? 5).toString();
    _minSupportersCtrl.text = (org.paymentSettings['min_supporters'] ?? 1).toString();
    _maxSupportersCtrl.text = (org.paymentSettings['max_supporters'] ?? 5).toString();
    _showVotingDuration = (org.paymentSettings['show_voting_duration'] as bool?) ?? false;
    _enableVotingCountdown = (org.paymentSettings['enable_voting_countdown'] as bool?) ?? false;
    _votingTimeLimitCtrl.text = (org.paymentSettings['voting_time_limit_minutes'] ?? 5).toString();

    _initialized = true;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    try {
      final org = ref.read(orgProfileProvider).valueOrNull;
      final updatedPaymentSettings = Map<String, dynamic>.from(org?.paymentSettings ?? {});
      updatedPaymentSettings['min_proposers'] = int.tryParse(_minProposersCtrl.text.trim()) ?? 1;
      updatedPaymentSettings['max_proposers'] = int.tryParse(_maxProposersCtrl.text.trim()) ?? 5;
      updatedPaymentSettings['min_supporters'] = int.tryParse(_minSupportersCtrl.text.trim()) ?? 1;
      updatedPaymentSettings['max_supporters'] = int.tryParse(_maxSupportersCtrl.text.trim()) ?? 5;
      updatedPaymentSettings['show_voting_duration'] = _showVotingDuration;
      updatedPaymentSettings['enable_voting_countdown'] = _enableVotingCountdown;
      updatedPaymentSettings['voting_time_limit_minutes'] = int.tryParse(_votingTimeLimitCtrl.text.trim()) ?? 5;

      await ref.read(updateOrgSettingsProvider.notifier).updateSettings({
        'default_nomination_window_days': int.tryParse(_defaultNominationCtrl.text.trim()) ?? 7,
        'default_voting_window_days': int.tryParse(_defaultVotingCtrl.text.trim()) ?? 1,
        'voter_roll_freeze_offset_days': int.tryParse(_voterRollOffsetCtrl.text.trim()) ?? 0,
        'default_silent_period_hours': int.tryParse(_defaultSilentCtrl.text.trim()) ?? 24,
        'grievance_window_days': int.tryParse(_grievanceWindowCtrl.text.trim()) ?? 3,
        'default_result_visibility': _selectedVisibility,
        'election_officers_can_publish': _officersCanPublish,
        'payment_settings': updatedPaymentSettings,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 12),
              Text('Election governance rules saved successfully!', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          backgroundColor: Colors.green.shade700,
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
          backgroundColor: Colors.red.shade700,
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

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
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
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                ),
                child: Icon(icon, color: AppColors.primaryLight, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    Text(subtitle, style: TextStyle(color: isDark ? Colors.white60 : Colors.grey.shade600, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Material(
            color: isDark ? AppColors.surface : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.shade200,
              ),
            ),
            elevation: isDark ? 0 : 1,
            shadowColor: Colors.black.withValues(alpha: 0.04),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
            ),
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
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final orgAsync = ref.watch(orgProfileProvider);
    final isSaving = ref.watch(updateOrgSettingsProvider).isLoading;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      drawer: const AdminDrawer(),
      appBar: AppBar(
        title: const Text('Election Rules & Policies'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          tooltip: 'Back',
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/dashboard');
            }
          },
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16, top: 8, bottom: 8),
            child: LoadingButton(
              onPressed: _submit,
              isLoading: isSaving,
              label: 'Save Rules',
              icon: Icons.save_rounded,
              fullWidth: false,
            ),
          ),
        ],
      ),
      body: ResponsivePageWrapper(
        child: orgAsync.when(
          loading: () => const ListSkeleton(count: 4),
          error: (err, _) => Center(child: Text('Error loading rules: $err')),
          data: (org) {
            _populateForm(org);
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 860),
                child: Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
                    children: [
                      // Header Banner
                      Container(
                        margin: const EdgeInsets.only(bottom: 24),
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF1D4ED8).withValues(alpha: 0.3),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.gavel_rounded, color: Colors.white, size: 28),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Institutional Electoral Bylaws (निर्वाचन कार्यविधि)',
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Configure statutory default phase windows, silence periods, and publication authority for all new elections in this organization.',
                                    style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      )
                      .animate()
                      .fade(duration: 300.ms)
                      .slideY(begin: -0.05, end: 0),

                      _section(
                        title: 'Default Timeline Windows',
                        subtitle: 'Baseline calendar defaults pre-filled during new election creation',
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
                              const SizedBox(width: 14),
                              Expanded(
                                child: TextFormField(
                                  controller: _defaultVotingCtrl,
                                  decoration: _dec('Voting Polling Phase (Days)', prefix: const Icon(Icons.how_to_vote_outlined)),
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
                              const SizedBox(width: 14),
                              Expanded(
                                child: TextFormField(
                                  controller: _defaultSilentCtrl,
                                  decoration: _dec('Silence Period (Hours)', prefix: const Icon(Icons.volume_off_outlined)),
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
                        title: 'Transparency & Governance Authority',
                        subtitle: 'Control default visibility of tallies and election officer publishing permissions',
                        icon: Icons.verified_user_outlined,
                        children: [
                          DropdownButtonFormField<String>(
                            initialValue: _selectedVisibility,
                            decoration: _dec('Default Result Visibility', prefix: const Icon(Icons.remove_red_eye_outlined)),
                            items: const [
                              DropdownMenuItem(value: 'admin_only', child: Text('Admin Only (आन्तरिक मात्र)')),
                              DropdownMenuItem(value: 'org_members', child: Text('Organization Members (प्रमाणीकृत सदस्य)')),
                              DropdownMenuItem(value: 'public', child: Text('Public / Open Ballot (सार्वजनिक)')),
                            ],
                            onChanged: (val) => setState(() => _selectedVisibility = val ?? 'admin_only'),
                          ),
                          const SizedBox(height: 20),
                          Material(
                            color: isDark ? AppColors.surfaceVariant : const Color(0xFFF4F4F5),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: BorderSide(
                                color: isDark ? Colors.white12 : Colors.grey.shade300,
                              ),
                            ),
                            child: SwitchListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              title: const Text('Election Officers Can Publish Results', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              subtitle: const Text(
                                'Grant assigned Election Officers authority to publish provisional & certified final results directly without requiring Org Admin approval.',
                                style: TextStyle(fontSize: 12),
                              ),
                              value: _officersCanPublish,
                              activeThumbColor: AppColors.primary,
                              onChanged: (val) => setState(() => _officersCanPublish = val),
                            ),
                          ),
                        ],
                      ),

                      // Section C: Nomination Endorsements Rules
                      _section(
                        title: 'Nomination Endorsement Rules (प्रस्तावक तथा समर्थक)',
                        subtitle: 'Define minimum and maximum number of proposers and supporters required per candidacy nomination',
                        icon: Icons.how_to_reg_outlined,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _minProposersCtrl,
                                  decoration: _dec('Min Proposers (न्यूनतम प्रस्तावक)', prefix: const Icon(Icons.person_outline)),
                                  keyboardType: TextInputType.number,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: TextFormField(
                                  controller: _maxProposersCtrl,
                                  decoration: _dec('Max Proposers (अधिकतम प्रस्तावक)', prefix: const Icon(Icons.people_alt_outlined)),
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
                                  controller: _minSupportersCtrl,
                                  decoration: _dec('Min Supporters (न्यूनतम समर्थक)', prefix: const Icon(Icons.verified_outlined)),
                                  keyboardType: TextInputType.number,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: TextFormField(
                                  controller: _maxSupportersCtrl,
                                  decoration: _dec('Max Supporters (अधिकतम समर्थक)', prefix: const Icon(Icons.verified_user_outlined)),
                                  keyboardType: TextInputType.number,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),

                      // Section D: Ballot Time Limit, Countdown & Duration
                      _section(
                        title: 'Ballot Time Limit & Countdown (मतदान समय सीमा तथा काउन्टडाउन)',
                        subtitle: 'Enforce maximum voting time limit per ballot session or display duration timer',
                        icon: Icons.timer_outlined,
                        children: [
                          Material(
                            color: isDark ? AppColors.surfaceVariant : const Color(0xFFF4F4F5),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: BorderSide(
                                color: isDark ? Colors.white12 : Colors.grey.shade300,
                              ),
                            ),
                            child: Column(
                              children: [
                                SwitchListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  title: const Text('Enforce Voting Time Limit Countdown (समय सीमा काउन्टडाउन)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                  subtitle: const Text(
                                    'When enabled, voters must cast and submit their ballot within the defined time limit before the session expires.',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                  value: _enableVotingCountdown,
                                  activeThumbColor: const Color(0xFFE11D48),
                                  onChanged: (val) => setState(() => _enableVotingCountdown = val),
                                ),
                                if (_enableVotingCountdown) ...[
                                  const Divider(height: 1),
                                  Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const Text('Voting Time Limit (Minutes)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                              const SizedBox(height: 2),
                                              Text(
                                                'Allocated voting duration per session (e.g. 5 minutes)',
                                                style: TextStyle(fontSize: 11.5, color: isDark ? Colors.white60 : Colors.grey.shade600),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        SizedBox(
                                          width: 120,
                                          child: TextFormField(
                                            controller: _votingTimeLimitCtrl,
                                            decoration: _dec('Minutes', prefix: const Icon(Icons.hourglass_top_rounded, size: 18)),
                                            keyboardType: TextInputType.number,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          Material(
                            color: isDark ? AppColors.surfaceVariant : const Color(0xFFF4F4F5),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: BorderSide(
                                color: isDark ? Colors.white12 : Colors.grey.shade300,
                              ),
                            ),
                            child: SwitchListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              title: const Text('Show Stopwatch Timer on Ballot', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              subtitle: const Text(
                                'Displays an elapsed stopwatch timer at the top of the secret electronic ballot.',
                                style: TextStyle(fontSize: 12),
                              ),
                              value: _showVotingDuration,
                              activeThumbColor: AppColors.primary,
                              onChanged: (val) => setState(() => _showVotingDuration = val),
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
      ),
    );
  }
}

