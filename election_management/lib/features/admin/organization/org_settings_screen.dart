import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/org_providers.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/loading_button.dart';
import '../../../shared/widgets/admin_drawer.dart';
import '../../../shared/widgets/shimmer_loaders.dart';
import '../../../shared/widgets/image_upload_widget.dart';
import '../../../shared/widgets/glass_card.dart';

class OrgSettingsScreen extends ConsumerStatefulWidget {
  const OrgSettingsScreen({super.key});

  @override
  ConsumerState<OrgSettingsScreen> createState() => _OrgSettingsScreenState();
}

class _OrgSettingsScreenState extends ConsumerState<OrgSettingsScreen> {
  final _formKey = GlobalKey<FormState>();

  // Identity
  late TextEditingController _nameController;
  late TextEditingController _addressController;
  late TextEditingController _logoController;
  String _selectedOrgType = 'other';

  // Election Defaults
  late TextEditingController _grievanceWindowController;
  late TextEditingController _voterRollOffsetController;
  late TextEditingController _defaultNominationController;
  late TextEditingController _defaultVotingController;
  late TextEditingController _defaultSilentController;
  String _selectedVisibility = 'admin_only';
  bool _officersCanPublish = false;

  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _addressController = TextEditingController();
    _logoController = TextEditingController();

    _grievanceWindowController = TextEditingController();
    _voterRollOffsetController = TextEditingController();
    _defaultNominationController = TextEditingController();
    _defaultVotingController = TextEditingController();
    _defaultSilentController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _logoController.dispose();
    _grievanceWindowController.dispose();
    _voterRollOffsetController.dispose();
    _defaultNominationController.dispose();
    _defaultVotingController.dispose();
    _defaultSilentController.dispose();
    super.dispose();
  }

  void _populateForm(OrganizationModel org) {
    if (_initialized) return;
    _nameController.text = org.name;
    _addressController.text = org.address;
    _logoController.text = org.logoUrl;

    _selectedOrgType = org.orgType.isNotEmpty ? org.orgType : 'other';

    _grievanceWindowController.text = org.grievanceWindowDays.toString();
    _voterRollOffsetController.text = org.voterRollFreezeOffsetDays.toString();
    _defaultNominationController.text = org.defaultNominationWindowDays
        .toString();
    _defaultVotingController.text = org.defaultVotingWindowDays.toString();
    _defaultSilentController.text = org.defaultSilentPeriodHours.toString();

    _selectedVisibility = org.defaultResultVisibility;
    _officersCanPublish = org.electionOfficersCanPublish;

    _initialized = true;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    try {
      await ref.read(updateOrgSettingsProvider.notifier).updateSettings({
        'name': _nameController.text.trim(),
        'org_type': _selectedOrgType,
        'address': _addressController.text.trim(),
        'logo_url': _logoController.text.trim(),
        'grievance_window_days':
            int.tryParse(_grievanceWindowController.text.trim()) ?? 0,
        'voter_roll_freeze_offset_days':
            int.tryParse(_voterRollOffsetController.text.trim()) ?? 0,
        'default_nomination_window_days':
            int.tryParse(_defaultNominationController.text.trim()) ?? 0,
        'default_voting_window_days':
            int.tryParse(_defaultVotingController.text.trim()) ?? 0,
        'default_silent_period_hours':
            int.tryParse(_defaultSilentController.text.trim()) ?? 0,
        'default_result_visibility': _selectedVisibility,
        'election_officers_can_publish': _officersCanPublish,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Text(
                  'Organization settings saved!',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            backgroundColor: Colors.green.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.all(24),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(child: Text('Error: $e')),
              ],
            ),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.all(24),
          ),
        );
      }
    }
  }

  Widget _buildPreviewHeader() {
    return AnimatedBuilder(
      animation: Listenable.merge([_nameController, _logoController]),
      builder: (context, _) {
        final previewName = _nameController.text;
        final previewLogo = _logoController.text;

        return Container(
          padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.primary, AppColors.primaryDark],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.2),
                ),
                child: SizedBox(
                  width: 100,
                  height: 100,
                  child: ImageUploadWidget(
                    initialImageUrl: previewLogo,
                    placeholderText: 'LOGO',
                    radius: 50,
                    onImageUploaded: (url) {
                      _logoController.text = url;
                    },
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                previewName.isEmpty ? 'Your Organization' : previewName,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.remove_red_eye,
                      color: Colors.white,
                      size: 14,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'LIVE PREVIEW',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSection({
    required String title,
    required String subtitle,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primary.withValues(alpha: 0.15),
                      AppColors.primary.withValues(alpha: 0.05),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.2),
                  ),
                ),
                child: Icon(icon, color: AppColors.primary, size: 22),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          Card(
            elevation: 0,
            margin: EdgeInsets.zero,
            color: Theme.of(context).brightness == Brightness.dark
                ? AppColors.surfaceVariant.withValues(alpha: 0.5)
                : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.black.withValues(alpha: 0.05),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final orgAsync = ref.watch(orgProfileProvider);
    final isSaving = ref.watch(updateOrgSettingsProvider).isLoading;

    return Scaffold(
      drawer: const AdminDrawer(),
      appBar: AppBar(
        title: const Text('Organization Profile'),
        elevation: 0,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0, top: 8, bottom: 8),
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
        error: (err, stack) => Center(child: Text('Error: $err')),
        data: (org) {
          _populateForm(org);

          return SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 800),
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildPreviewHeader(),
                      const SizedBox(height: 40),

                      _buildSection(
                        title: 'Basic Information',
                        subtitle: 'Your organization identity and type.',
                        icon: Icons.business_rounded,
                        children: [
                          TextFormField(
                            controller: _nameController,
                            decoration: const InputDecoration(
                              labelText: 'Organization Name',
                              prefixIcon: Icon(Icons.badge_outlined),
                            ),
                            validator: (val) =>
                                val == null || val.isEmpty ? 'Required' : null,
                          ),
                          const SizedBox(height: 20),
                          DropdownButtonFormField<String>(
                            value: _selectedOrgType,
                            decoration: const InputDecoration(
                              labelText: 'Organization Type',
                              prefixIcon: Icon(Icons.category_outlined),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'cooperative',
                                child: Text('Cooperative / SACCO'),
                              ),
                              DropdownMenuItem(
                                value: 'college',
                                child: Text('College / University'),
                              ),
                              DropdownMenuItem(
                                value: 'association',
                                child: Text('Professional Association'),
                              ),
                              DropdownMenuItem(
                                value: 'corporate',
                                child: Text('Corporate'),
                              ),
                              DropdownMenuItem(
                                value: 'other',
                                child: Text('Other'),
                              ),
                            ],
                            onChanged: (val) =>
                                setState(() => _selectedOrgType = val!),
                          ),
                          const SizedBox(height: 20),
                          TextFormField(
                            controller: _addressController,
                            decoration: const InputDecoration(
                              labelText: 'Address',
                              prefixIcon: Icon(Icons.location_on_outlined),
                            ),
                            maxLines: 2,
                          ),
                          const SizedBox(height: 20),
                          TextFormField(
                            controller: _logoController,
                            decoration: const InputDecoration(
                              labelText: 'Logo URL',
                              prefixIcon: Icon(Icons.image_outlined),
                            ),
                          ),
                        ],
                      ),

                      _buildSection(
                        title: 'Election Rules',
                        subtitle: 'Default timeframes for all your elections.',
                        icon: Icons.gavel_rounded,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _defaultNominationController,
                                  decoration: const InputDecoration(
                                    labelText: 'Nomination Phase (Days)',
                                    prefixIcon: Icon(
                                      Icons.assignment_ind_outlined,
                                    ),
                                  ),
                                  keyboardType: TextInputType.number,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: TextFormField(
                                  controller: _defaultVotingController,
                                  decoration: const InputDecoration(
                                    labelText: 'Voting Phase (Days)',
                                    prefixIcon: Icon(
                                      Icons.how_to_vote_outlined,
                                    ),
                                  ),
                                  keyboardType: TextInputType.number,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _voterRollOffsetController,
                                  decoration: const InputDecoration(
                                    labelText: 'Roll Freeze Offset (Days)',
                                    prefixIcon: Icon(Icons.people_outline),
                                  ),
                                  keyboardType: TextInputType.number,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: TextFormField(
                                  controller: _defaultSilentController,
                                  decoration: const InputDecoration(
                                    labelText: 'Silent Period (Hours)',
                                    prefixIcon: Icon(Icons.volume_off_outlined),
                                  ),
                                  keyboardType: TextInputType.number,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          TextFormField(
                            controller: _grievanceWindowController,
                            decoration: const InputDecoration(
                              labelText:
                                  'Post-Election Grievance Window (Days)',
                              prefixIcon: Icon(Icons.report_problem_outlined),
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ],
                      ),

                      _buildSection(
                        title: 'Transparency Settings',
                        subtitle: 'Control who sees election results.',
                        icon: Icons.visibility_outlined,
                        children: [
                          DropdownButtonFormField<String>(
                            value: _selectedVisibility,
                            decoration: const InputDecoration(
                              labelText: 'Default Result Visibility',
                              prefixIcon: Icon(Icons.remove_red_eye_outlined),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'admin_only',
                                child: Text('Admin Only'),
                              ),
                              DropdownMenuItem(
                                value: 'voters',
                                child: Text('Voters Only'),
                              ),
                              DropdownMenuItem(
                                value: 'public',
                                child: Text('Public'),
                              ),
                            ],
                            onChanged: (val) =>
                                setState(() => _selectedVisibility = val!),
                          ),
                          const SizedBox(height: 24),
                          Material(
                            color: AppColors.primary.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: AppColors.primary.withValues(
                                    alpha: 0.1,
                                  ),
                                ),
                              ),
                              child: SwitchListTile(
                                contentPadding: const EdgeInsets.all(16),
                                title: const Text(
                                  'Officers Can Publish Results',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                subtitle: const Text(
                                  'Allow Election Officers to publish official results without Org Admin approval.',
                                  style: TextStyle(fontSize: 12),
                                ),
                                value: _officersCanPublish,
                                activeColor: AppColors.primary,
                                onChanged: (val) =>
                                    setState(() => _officersCanPublish = val),
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 32),
                      SizedBox(
                        height: 56,
                        child: LoadingButton(
                          onPressed: _submit,
                          isLoading: isSaving,
                          label: 'Save Organization Settings',
                          icon: Icons.save_rounded,
                        ),
                      ),

                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
