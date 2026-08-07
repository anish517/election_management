import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/org_providers.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/loading_button.dart';
import '../../../shared/widgets/admin_drawer.dart';
import '../../../shared/widgets/shimmer_loaders.dart';
import '../../../shared/widgets/image_upload_widget.dart';

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
  late TextEditingController _colorController;
  late TextEditingController _logoController;
  String _selectedOrgType = 'other';

  // Localization
  String _selectedLanguage = 'en';
  String _selectedTimezone = 'UTC';

  // Election Defaults
  late TextEditingController _grievanceWindowController;
  late TextEditingController _voterRollOffsetController;
  late TextEditingController _defaultNominationController;
  late TextEditingController _defaultVotingController;
  late TextEditingController _defaultSilentController;
  String _selectedVisibility = 'admin_only';
  bool _officersCanPublish = false;

  bool _initialized = false;
  
  // Real-time preview values
  String _previewName = 'Organization Name';
  Color _previewColor = AppColors.primary;
  String _previewLogo = '';

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController()..addListener(() {
      setState(() => _previewName = _nameController.text);
    });
    _addressController = TextEditingController();
    _colorController = TextEditingController()..addListener(() {
      setState(() => _previewColor = _parseColor(_colorController.text));
    });
    _logoController = TextEditingController()..addListener(() {
      setState(() => _previewLogo = _logoController.text);
    });

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
    _colorController.dispose();
    _logoController.dispose();
    _grievanceWindowController.dispose();
    _voterRollOffsetController.dispose();
    _defaultNominationController.dispose();
    _defaultVotingController.dispose();
    _defaultSilentController.dispose();
    super.dispose();
  }
  
  Color _parseColor(String hex) {
    if (hex.isEmpty) return AppColors.primary;
    hex = hex.replaceAll('#', '');
    if (hex.length == 6) {
      hex = 'FF$hex';
    }
    try {
      return Color(int.parse(hex, radix: 16));
    } catch (e) {
      return AppColors.primary;
    }
  }

  void _populateForm(OrganizationModel org) {
    if (_initialized) return;
    _nameController.text = org.name;
    _addressController.text = org.address;
    _colorController.text = org.brandColor;
    _logoController.text = org.logoUrl;

    _selectedOrgType = org.orgType.isNotEmpty ? org.orgType : 'other';
    _selectedLanguage = org.defaultLanguage.isNotEmpty ? org.defaultLanguage : 'en';
    _selectedTimezone = org.timezone.isNotEmpty ? org.timezone : 'UTC';

    _grievanceWindowController.text = org.grievanceWindowDays.toString();
    _voterRollOffsetController.text = org.voterRollFreezeOffsetDays.toString();
    _defaultNominationController.text = org.defaultNominationWindowDays.toString();
    _defaultVotingController.text = org.defaultVotingWindowDays.toString();
    _defaultSilentController.text = org.defaultSilentPeriodHours.toString();

    _selectedVisibility = org.defaultResultVisibility;
    _officersCanPublish = org.electionOfficersCanPublish;

    _previewName = org.name;
    _previewColor = _parseColor(org.brandColor);
    _previewLogo = org.logoUrl;

    _initialized = true;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    try {
      await ref.read(updateOrgSettingsProvider.notifier).updateSettings({
        'name': _nameController.text.trim(),
        'org_type': _selectedOrgType,
        'address': _addressController.text.trim(),
        'brand_color': _colorController.text.trim(),
        'logo_url': _logoController.text.trim(),
        'default_language': _selectedLanguage,
        'timezone': _selectedTimezone,
        'grievance_window_days': int.parse(_grievanceWindowController.text.trim()),
        'voter_roll_freeze_offset_days': int.parse(_voterRollOffsetController.text.trim()),
        'default_nomination_window_days': int.parse(_defaultNominationController.text.trim()),
        'default_voting_window_days': int.parse(_defaultVotingController.text.trim()),
        'default_silent_period_hours': int.parse(_defaultSilentController.text.trim()),
        'default_result_visibility': _selectedVisibility,
        'election_officers_can_publish': _officersCanPublish,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Organization settings updated successfully!'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating settings: $e'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
  
  Widget _buildPreviewHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      decoration: BoxDecoration(
        color: _previewColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _previewColor.withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          )
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ImageUploadWidget(
            initialImageUrl: _previewLogo,
            placeholderText: 'LOGO',
            radius: 50,
            onImageUploaded: (url) {
              setState(() {
                _logoController.text = url;
                _previewLogo = url;
              });
            },
          ),
          const SizedBox(height: 16),
          Text(
            _previewName.isEmpty ? 'Your Organization' : _previewName,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'LIVE PREVIEW',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1),
            ),
          )
        ],
      ),
    );
  }
  
  Widget _buildSectionCard({required String title, required IconData icon, required List<Widget> children}) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: AppColors.primary),
                ),
                const SizedBox(width: 12),
                Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 24),
            ...children,
          ],
        ),
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
        title: const Text('Organization Settings'),
        elevation: 0,
      ),
      body: orgAsync.when(
        loading: () => const ListSkeleton(count: 4),
        error: (err, stack) => Center(child: Text('Error: $err')),
        data: (org) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            setState(() => _populateForm(org));
          });

          if (!_initialized) return const Padding(
            padding: EdgeInsets.all(24),
            child: ListSkeleton(count: 6),
          );

          return SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 800),
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildPreviewHeader(),
                      const SizedBox(height: 32),
                      
                      _buildSectionCard(
                        title: 'Profile & Branding',
                        icon: Icons.palette_rounded,
                        children: [
                          TextFormField(
                            controller: _nameController,
                            decoration: const InputDecoration(labelText: 'Organization Name', prefixIcon: Icon(Icons.business)),
                            validator: (val) => val == null || val.isEmpty ? 'Required' : null,
                          ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            value: _selectedOrgType,
                            decoration: const InputDecoration(labelText: 'Organization Type', prefixIcon: Icon(Icons.category)),
                            items: const [
                              DropdownMenuItem(value: 'cooperative', child: Text('Cooperative / SACCO')),
                              DropdownMenuItem(value: 'college', child: Text('College / University')),
                              DropdownMenuItem(value: 'association', child: Text('Professional Association')),
                              DropdownMenuItem(value: 'corporate', child: Text('Corporate')),
                              DropdownMenuItem(value: 'other', child: Text('Other')),
                            ],
                            onChanged: (val) => setState(() => _selectedOrgType = val!),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _addressController,
                            decoration: const InputDecoration(labelText: 'Address', prefixIcon: Icon(Icons.location_on)),
                            maxLines: 2,
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _colorController,
                                  decoration: const InputDecoration(labelText: 'Brand Color (Hex)', prefixIcon: Icon(Icons.color_lens)),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: TextFormField(
                                  controller: _logoController,
                                  decoration: const InputDecoration(
                                    labelText: 'Logo URL',
                                    prefixIcon: Icon(Icons.image),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      
                      _buildSectionCard(
                        title: 'Localization',
                        icon: Icons.language_rounded,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  value: _selectedLanguage,
                                  decoration: const InputDecoration(labelText: 'Default Language', prefixIcon: Icon(Icons.translate)),
                                  items: const [
                                    DropdownMenuItem(value: 'en', child: Text('English')),
                                    DropdownMenuItem(value: 'ne', child: Text('Nepali')),
                                  ],
                                  onChanged: (val) => setState(() => _selectedLanguage = val!),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  value: _selectedTimezone,
                                  decoration: const InputDecoration(labelText: 'Timezone', prefixIcon: Icon(Icons.access_time)),
                                  items: const [
                                    DropdownMenuItem(value: 'UTC', child: Text('UTC')),
                                    DropdownMenuItem(value: 'Asia/Kathmandu', child: Text('Asia/Kathmandu (NPT)')),
                                    DropdownMenuItem(value: 'America/New_York', child: Text('America/New_York (EST)')),
                                  ],
                                  onChanged: (val) => setState(() => _selectedTimezone = val!),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      
                      _buildSectionCard(
                        title: 'Election Defaults',
                        icon: Icons.how_to_vote_rounded,
                        children: [
                          Row(
                            children: [
                              Expanded(child: TextFormField(controller: _grievanceWindowController, decoration: const InputDecoration(labelText: 'Grievance Window (Days)', prefixIcon: Icon(Icons.report_problem)), keyboardType: TextInputType.number)),
                              const SizedBox(width: 16),
                              Expanded(child: TextFormField(controller: _voterRollOffsetController, decoration: const InputDecoration(labelText: 'Voter Roll Freeze Offset', prefixIcon: Icon(Icons.ac_unit)), keyboardType: TextInputType.number)),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(child: TextFormField(controller: _defaultNominationController, decoration: const InputDecoration(labelText: 'Nomination Window (Days)'), keyboardType: TextInputType.number)),
                              const SizedBox(width: 16),
                              Expanded(child: TextFormField(controller: _defaultVotingController, decoration: const InputDecoration(labelText: 'Voting Window (Days)'), keyboardType: TextInputType.number)),
                              const SizedBox(width: 16),
                              Expanded(child: TextFormField(controller: _defaultSilentController, decoration: const InputDecoration(labelText: 'Silent Period (Hours)'), keyboardType: TextInputType.number)),
                            ],
                          ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            value: _selectedVisibility,
                            decoration: const InputDecoration(labelText: 'Default Result Visibility', prefixIcon: Icon(Icons.visibility)),
                            items: const [
                              DropdownMenuItem(value: 'admin_only', child: Text('Admin Only')),
                              DropdownMenuItem(value: 'org_members', child: Text('Org Members')),
                              DropdownMenuItem(value: 'public', child: Text('Public')),
                            ],
                            onChanged: (val) => setState(() => _selectedVisibility = val!),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                            ),
                            child: SwitchListTile(
                              title: const Text('Election Officers Can Publish'),
                              subtitle: const Text('If enabled, election officers can self-publish results without Org Admin approval.'),
                              value: _officersCanPublish,
                              onChanged: (val) => setState(() => _officersCanPublish = val),
                              activeColor: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                      
                      _buildSectionCard(
                        title: 'Compliance & Legal (Read-Only)',
                        icon: Icons.gavel_rounded,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.info_outline, color: Colors.orange),
                                SizedBox(width: 12),
                                Expanded(child: Text('These settings are enforced at the platform level and cannot be modified by organization admins.')),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  initialValue: org.dataRetentionYears.toString(),
                                  decoration: const InputDecoration(labelText: 'Data Retention (Years)', prefixIcon: Icon(Icons.save)),
                                  readOnly: true,
                                  enabled: false,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: TextFormField(
                                  initialValue: org.legalHold ? 'Active' : 'Inactive',
                                  decoration: const InputDecoration(labelText: 'Legal Hold Status', prefixIcon: Icon(Icons.shield)),
                                  readOnly: true,
                                  enabled: false,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 55,
                        child: LoadingButton(
                          isLoading: isSaving,
                          onPressed: _submit,
                          label: 'Save All Settings',
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
