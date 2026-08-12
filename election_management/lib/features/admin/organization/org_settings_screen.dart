import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/org_providers.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_constants.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/loading_button.dart';
import '../../../shared/widgets/admin_drawer.dart';
import '../../../shared/widgets/shimmer_loaders.dart';

// ---------------------------------------------------------------------------
// Type-specific metadata field descriptors (mirrored from register_screen)
// ---------------------------------------------------------------------------
const Map<String, List<Map<String, String>>> _typeMetaFields = {
  'cooperative': [
    {'key': 'sacco_license', 'label': 'SACCO License No.', 'hint': 'e.g. SB-123/078'},
    {'key': 'member_share_value', 'label': 'Member Share Value (NPR)', 'hint': 'e.g. 1000'},
  ],
  'college': [
    {'key': 'affiliation_body', 'label': 'Affiliation Body', 'hint': 'e.g. TU, KU, PU'},
    {'key': 'campus_code', 'label': 'Campus Code', 'hint': 'e.g. CAM-001'},
  ],
  'educational': [
    {'key': 'affiliation_body', 'label': 'Affiliation Body', 'hint': 'e.g. TU, KU, PU'},
    {'key': 'campus_code', 'label': 'Campus Code', 'hint': 'e.g. CAM-001'},
  ],
  'ngo': [
    {'key': 'registration_act', 'label': 'Registration Act', 'hint': 'e.g. Associations Registration Act 2034'},
    {'key': 'swc_affiliation_no', 'label': 'SWC Affiliation No.', 'hint': 'e.g. SWC-2079/001'},
  ],
  'housing_society': [
    {'key': 'locality', 'label': 'Locality / Ward', 'hint': 'e.g. Ward 14, Lalitpur'},
    {'key': 'plot_count', 'label': 'Total Plots', 'hint': 'e.g. 120'},
  ],
  'political_party': [
    {'key': 'ec_registration_no', 'label': 'Election Commission Reg. No.', 'hint': 'e.g. EC-2079/01'},
  ],
  'government': [
    {'key': 'ministry', 'label': 'Under Ministry / Department', 'hint': 'e.g. Ministry of Home Affairs'},
    {'key': 'office_code', 'label': 'Office Code', 'hint': 'e.g. OFC-301'},
  ],
};

// ---------------------------------------------------------------------------
// Reusable rectangular image picker tile
// ---------------------------------------------------------------------------
class _ImageTile extends StatefulWidget {
  final String label;
  final String? initialUrl;
  final IconData icon;
  final Future<String?> Function(Uint8List bytes, String name) onUpload;
  final void Function(String url) onUploaded;
  final double height;

  const _ImageTile({
    required this.label,
    this.initialUrl,
    required this.icon,
    required this.onUpload,
    required this.onUploaded,
    this.height = 140,
  });

  @override
  State<_ImageTile> createState() => _ImageTileState();
}

class _ImageTileState extends State<_ImageTile> {
  bool _uploading = false;
  String? _url;

  @override
  void initState() {
    super.initState();
    _url = widget.initialUrl;
  }

  Future<void> _pick() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'gif', 'svg'],
      withData: true,
    );
    if (result == null || result.files.isEmpty || result.files.first.bytes == null) return;
    setState(() => _uploading = true);
    final url = await widget.onUpload(result.files.first.bytes!, result.files.first.name);
    if (mounted) {
      setState(() { _uploading = false; if (url != null) { _url = url; } });
      if (url != null) { widget.onUploaded(url); }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasImg = _url != null && _url!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _uploading ? null : _pick,
          child: Container(
            height: widget.height,
            width: double.infinity,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF27272A) : const Color(0xFFF4F4F5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isDark ? const Color(0xFF3F3F46) : const Color(0xFFE4E4E7), width: 1.5),
              image: hasImg ? DecorationImage(image: NetworkImage(_url!), fit: BoxFit.cover) : null,
            ),
            child: _uploading
                ? const Center(child: CircularProgressIndicator())
                : hasImg
                    ? Align(
                        alignment: Alignment.bottomRight,
                        child: Container(
                          margin: const EdgeInsets.all(8),
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                          child: const Icon(Icons.edit, color: Colors.white, size: 14),
                        ),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(widget.icon, color: AppColors.textMuted, size: 30),
                          const SizedBox(height: 8),
                          Text('Tap to upload', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                          const SizedBox(height: 2),
                          Text('Max 2MB · jpeg, png, jpg, gif, svg', style: TextStyle(color: AppColors.textMuted, fontSize: 10)),
                        ],
                      ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Main OrgSettingsScreen
// ---------------------------------------------------------------------------
class OrgSettingsScreen extends ConsumerStatefulWidget {
  const OrgSettingsScreen({super.key});

  @override
  ConsumerState<OrgSettingsScreen> createState() => _OrgSettingsScreenState();
}

class _OrgSettingsScreenState extends ConsumerState<OrgSettingsScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  late TabController _tabController;

  // --- Organization Identity ---
  late TextEditingController _nameCtrl;
  late TextEditingController _prefixCtrl;
  late TextEditingController _councilCtrl;
  late TextEditingController _orgEmailCtrl;
  late TextEditingController _orgPhoneCtrl;
  late TextEditingController _websiteCtrl;
  late TextEditingController _addressCtrl;
  String _selectedOrgType = 'other';
  String _logoUrl = '';
  String _coverUrl = '';

  // --- Type metadata ---
  final Map<String, TextEditingController> _metaCtrls = {};

  // --- Bank ---
  late TextEditingController _bankNameCtrl;
  late TextEditingController _bankBranchCtrl;
  late TextEditingController _bankAccountNumCtrl;
  late TextEditingController _bankAccountNameCtrl;
  late TextEditingController _bankSwiftCtrl;
  String _bankQrUrl = '';

  // --- Election defaults ---
  late TextEditingController _grievanceWindowCtrl;
  late TextEditingController _voterRollOffsetCtrl;
  late TextEditingController _defaultNominationCtrl;
  late TextEditingController _defaultVotingCtrl;
  late TextEditingController _defaultSilentCtrl;
  String _selectedVisibility = 'admin_only';
  bool _officersCanPublish = false;

  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _nameCtrl = TextEditingController();
    _prefixCtrl = TextEditingController();
    _councilCtrl = TextEditingController();
    _orgEmailCtrl = TextEditingController();
    _orgPhoneCtrl = TextEditingController();
    _websiteCtrl = TextEditingController();
    _addressCtrl = TextEditingController();
    _bankNameCtrl = TextEditingController();
    _bankBranchCtrl = TextEditingController();
    _bankAccountNumCtrl = TextEditingController();
    _bankAccountNameCtrl = TextEditingController();
    _bankSwiftCtrl = TextEditingController();
    _grievanceWindowCtrl = TextEditingController();
    _voterRollOffsetCtrl = TextEditingController();
    _defaultNominationCtrl = TextEditingController();
    _defaultVotingCtrl = TextEditingController();
    _defaultSilentCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (final c in [
      _nameCtrl, _prefixCtrl, _councilCtrl, _orgEmailCtrl, _orgPhoneCtrl,
      _websiteCtrl, _addressCtrl, _bankNameCtrl, _bankBranchCtrl,
      _bankAccountNumCtrl, _bankAccountNameCtrl, _bankSwiftCtrl,
      _grievanceWindowCtrl, _voterRollOffsetCtrl, _defaultNominationCtrl,
      _defaultVotingCtrl, _defaultSilentCtrl,
    ]) {
      c.dispose();
    }
    for (final c in _metaCtrls.values) { c.dispose(); }
    super.dispose();
  }

  void _populateForm(OrganizationModel org) {
    if (_initialized) return;
    _nameCtrl.text = org.name;
    _prefixCtrl.text = org.prefix;
    _councilCtrl.text = org.councilNumber;
    _orgPhoneCtrl.text = org.phone;
    _websiteCtrl.text = org.website;
    _addressCtrl.text = org.address;
    _logoUrl = org.logoUrl;
    _coverUrl = org.coverImageUrl;
    _selectedOrgType = org.orgType.isNotEmpty ? org.orgType : 'other';

    // Populate meta fields for this org type
    final metaFields = _typeMetaFields[_selectedOrgType] ?? [];
    for (final f in metaFields) {
      _metaCtrls[f['key']!] = TextEditingController(
        text: org.typeMetadata[f['key']] as String? ?? '',
      );
    }

    _bankNameCtrl.text = org.bankName;
    _bankBranchCtrl.text = org.bankBranch;
    _bankAccountNumCtrl.text = org.bankAccountNumber;
    _bankAccountNameCtrl.text = org.bankAccountName;
    _bankSwiftCtrl.text = org.bankSwiftCode;
    _bankQrUrl = org.bankQrUrl;

    _grievanceWindowCtrl.text = org.grievanceWindowDays.toString();
    _voterRollOffsetCtrl.text = org.voterRollFreezeOffsetDays.toString();
    _defaultNominationCtrl.text = org.defaultNominationWindowDays.toString();
    _defaultVotingCtrl.text = org.defaultVotingWindowDays.toString();
    _defaultSilentCtrl.text = org.defaultSilentPeriodHours.toString();
    _selectedVisibility = org.defaultResultVisibility;
    _officersCanPublish = org.electionOfficersCanPublish;

    _initialized = true;
  }

  // --- Upload helper ---
  Future<String?> _upload(Uint8List bytes, String name) async {
    try {
      final dio = ref.read(apiClientProvider);
      final resp = await dio.post(
        ApiConstants.fileUpload,
        data: FormData.fromMap({'file': MultipartFile.fromBytes(bytes, filename: name)}),
      );
      return resp.data['url'] as String?;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Upload failed. Please try again.')),
        );
      }
      return null;
    }
  }

  void _onTypeChanged(String? val) {
    if (val == null) return;
    for (final c in _metaCtrls.values) { c.dispose(); }
    _metaCtrls.clear();
    final fields = _typeMetaFields[val] ?? [];
    for (final f in fields) {
      _metaCtrls[f['key']!] = TextEditingController();
    }
    setState(() => _selectedOrgType = val);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final meta = <String, dynamic>{};
    for (final entry in _metaCtrls.entries) {
      if (entry.value.text.isNotEmpty) { meta[entry.key] = entry.value.text.trim(); }
    }
    try {
      await ref.read(updateOrgSettingsProvider.notifier).updateSettings({
        'name': _nameCtrl.text.trim(),
        'prefix': _prefixCtrl.text.trim(),
        'org_type': _selectedOrgType,
        'council_number': _councilCtrl.text.trim(),
        'org_email': _orgEmailCtrl.text.trim(),
        'phone': _orgPhoneCtrl.text.trim(),
        'website': _websiteCtrl.text.trim(),
        'address': _addressCtrl.text.trim(),
        'logo_url': _logoUrl,
        'cover_image_url': _coverUrl,
        'type_metadata': meta,
        'bank_name': _bankNameCtrl.text.trim(),
        'bank_branch': _bankBranchCtrl.text.trim(),
        'bank_account_number': _bankAccountNumCtrl.text.trim(),
        'bank_account_name': _bankAccountNameCtrl.text.trim(),
        'bank_swift_code': _bankSwiftCtrl.text.trim(),
        'bank_qr_url': _bankQrUrl,
        'grievance_window_days': int.tryParse(_grievanceWindowCtrl.text.trim()) ?? 3,
        'voter_roll_freeze_offset_days': int.tryParse(_voterRollOffsetCtrl.text.trim()) ?? 0,
        'default_nomination_window_days': int.tryParse(_defaultNominationCtrl.text.trim()) ?? 7,
        'default_voting_window_days': int.tryParse(_defaultVotingCtrl.text.trim()) ?? 1,
        'default_silent_period_hours': int.tryParse(_defaultSilentCtrl.text.trim()) ?? 24,
        'default_result_visibility': _selectedVisibility,
        'election_officers_can_publish': _officersCanPublish,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Row(children: [
            Icon(Icons.check_circle, color: Colors.white),
            SizedBox(width: 12),
            Text('Settings saved!', style: TextStyle(fontWeight: FontWeight.bold)),
          ]),
          backgroundColor: Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(24),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text('Error: $e')),
          ]),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(24),
        ));
      }
    }
  }

  // --- Shared section card builder ---
  Widget _section({required String title, required String subtitle, required IconData icon, required List<Widget> children}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                ),
                child: Icon(icon, color: AppColors.primaryLight, size: 20),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 0,
            margin: EdgeInsets.zero,
            color: Theme.of(context).brightness == Brightness.dark
                ? AppColors.surfaceVariant.withValues(alpha: 0.5)
                : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.05),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _dec(String label, {String? hint, Widget? prefix}) => InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: prefix,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      );

  // ===========================================================================
  // TAB 1 — Organization Profile
  // ===========================================================================
  Widget _buildProfileTab() {
    final metaFields = _typeMetaFields[_selectedOrgType] ?? [];

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 100),
      children: [
        // Preview banner
        _buildPreviewBanner(),
        const SizedBox(height: 28),

        // Basic Info
        _section(
          title: 'Basic Information',
          subtitle: 'Your organization identity and contact details',
          icon: Icons.business_rounded,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: _nameCtrl,
                    decoration: _dec('Organization Name', hint: 'Enter organization name', prefix: const Icon(Icons.badge_outlined)),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _prefixCtrl,
                    decoration: _dec('Prefix', hint: 'e.g. SOC'),
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 10,
                    buildCounter: (_, {required currentLength, required isFocused, required maxLength}) => null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _selectedOrgType,
              decoration: _dec('Organization Type', prefix: const Icon(Icons.category_outlined)),
              items: const [
                DropdownMenuItem(value: 'cooperative', child: Text('Cooperative / SACCO')),
                DropdownMenuItem(value: 'college', child: Text('College / University')),
                DropdownMenuItem(value: 'educational', child: Text('Educational Institution')),
                DropdownMenuItem(value: 'association', child: Text('Professional Association')),
                DropdownMenuItem(value: 'club', child: Text('Club / Community')),
                DropdownMenuItem(value: 'housing_society', child: Text('Housing Society')),
                DropdownMenuItem(value: 'union', child: Text('Trade Union')),
                DropdownMenuItem(value: 'ngo', child: Text('NGO / INGO')),
                DropdownMenuItem(value: 'corporate', child: Text('Corporate')),
                DropdownMenuItem(value: 'religious', child: Text('Religious Organization')),
                DropdownMenuItem(value: 'political_party', child: Text('Political Party (Internal)')),
                DropdownMenuItem(value: 'government', child: Text('Government / Public Body')),
                DropdownMenuItem(value: 'other', child: Text('Other')),
              ],
              onChanged: _onTypeChanged,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _councilCtrl,
              decoration: _dec('Council / Registration No.', hint: 'e.g. 1234/2078', prefix: const Icon(Icons.numbers_outlined)),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _orgEmailCtrl,
                    decoration: _dec('Organization Email', hint: 'org@example.com', prefix: const Icon(Icons.email_outlined)),
                    keyboardType: TextInputType.emailAddress,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _orgPhoneCtrl,
                    decoration: _dec('Phone', hint: '9876543210', prefix: const Icon(Icons.phone_outlined)),
                    keyboardType: TextInputType.phone,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _websiteCtrl,
              decoration: _dec('Website', hint: 'https://example.com', prefix: const Icon(Icons.language_outlined)),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _addressCtrl,
              decoration: _dec('Address', hint: 'Enter full address', prefix: const Icon(Icons.location_on_outlined)),
              maxLines: 3,
            ),
          ],
        ),

        // Branding
        _section(
          title: 'Branding',
          subtitle: 'Logo and cover image for your organization',
          icon: Icons.palette_rounded,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _ImageTile(
                    label: 'Logo',
                    initialUrl: _logoUrl.isEmpty ? null : _logoUrl,
                    icon: Icons.image_outlined,
                    height: 130,
                    onUpload: _upload,
                    onUploaded: (url) => setState(() => _logoUrl = url),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _ImageTile(
                    label: 'Cover Image',
                    initialUrl: _coverUrl.isEmpty ? null : _coverUrl,
                    icon: Icons.wallpaper_outlined,
                    height: 130,
                    onUpload: _upload,
                    onUploaded: (url) => setState(() => _coverUrl = url),
                  ),
                ),
              ],
            ),
          ],
        ),

        // Type-specific metadata
        if (metaFields.isNotEmpty)
          _section(
            title: '${_orgTypeLabel(_selectedOrgType)} Details',
            subtitle: 'Additional details specific to your organization type',
            icon: Icons.tune_rounded,
            children: metaFields.map((f) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: TextFormField(
                controller: _metaCtrls[f['key']!],
                decoration: _dec(f['label']!, hint: f['hint']),
              ),
            )).toList(),
          ),
      ],
    );
  }

  // ===========================================================================
  // TAB 2 — Bank Details
  // ===========================================================================
  Widget _buildBankTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 100),
      children: [
        _section(
          title: 'Bank Account',
          subtitle: 'For receipts, payment tracking and QR payments',
          icon: Icons.account_balance_rounded,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: TextFormField(controller: _bankNameCtrl, decoration: _dec('Bank Name', hint: 'e.g. Nepal Bank Limited', prefix: const Icon(Icons.account_balance_outlined)))),
                const SizedBox(width: 12),
                Expanded(child: TextFormField(controller: _bankBranchCtrl, decoration: _dec('Branch Name', hint: 'e.g. Putalisadak', prefix: const Icon(Icons.location_city_outlined)))),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: TextFormField(controller: _bankAccountNumCtrl, decoration: _dec('Account Number', prefix: const Icon(Icons.pin_outlined)), keyboardType: TextInputType.number)),
                const SizedBox(width: 12),
                Expanded(child: TextFormField(controller: _bankAccountNameCtrl, decoration: _dec('Account Name', prefix: const Icon(Icons.person_outline)))),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _bankSwiftCtrl,
              decoration: _dec('SWIFT / BIC Code', hint: 'e.g. NIBLNPKT', prefix: const Icon(Icons.code_outlined)),
              textCapitalization: TextCapitalization.characters,
            ),
          ],
        ),

        _section(
          title: 'Payment QR Code',
          subtitle: 'Upload a QR image for member payments (eSewa, FonePay, etc.)',
          icon: Icons.qr_code_2_rounded,
          children: [
            _ImageTile(
              label: 'QR Code Image',
              initialUrl: _bankQrUrl.isEmpty ? null : _bankQrUrl,
              icon: Icons.qr_code_outlined,
              height: 200,
              onUpload: _upload,
              onUploaded: (url) => setState(() => _bankQrUrl = url),
            ),
          ],
        ),
      ],
    );
  }

  // ===========================================================================
  // TAB 3 — Election Rules
  // ===========================================================================
  Widget _buildElectionTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 100),
      children: [
        _section(
          title: 'Default Timeframes',
          subtitle: 'Applied automatically when creating new elections',
          icon: Icons.schedule_rounded,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: TextFormField(controller: _defaultNominationCtrl, decoration: _dec('Nomination Phase (Days)', prefix: const Icon(Icons.assignment_ind_outlined)), keyboardType: TextInputType.number)),
                const SizedBox(width: 12),
                Expanded(child: TextFormField(controller: _defaultVotingCtrl, decoration: _dec('Voting Phase (Days)', prefix: const Icon(Icons.how_to_vote_outlined)), keyboardType: TextInputType.number)),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: TextFormField(controller: _voterRollOffsetCtrl, decoration: _dec('Roll Freeze Offset (Days)', prefix: const Icon(Icons.people_outline)), keyboardType: TextInputType.number)),
                const SizedBox(width: 12),
                Expanded(child: TextFormField(controller: _defaultSilentCtrl, decoration: _dec('Silent Period (Hours)', prefix: const Icon(Icons.volume_off_outlined)), keyboardType: TextInputType.number)),
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
          title: 'Transparency & Permissions',
          subtitle: 'Control who sees results and what officers can do',
          icon: Icons.visibility_outlined,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _selectedVisibility,
              decoration: _dec('Default Result Visibility', prefix: const Icon(Icons.remove_red_eye_outlined)),
              items: const [
                DropdownMenuItem(value: 'admin_only', child: Text('Admin Only')),
                DropdownMenuItem(value: 'org_members', child: Text('Org Members')),
                DropdownMenuItem(value: 'public', child: Text('Public')),
              ],
              onChanged: (val) => setState(() => _selectedVisibility = val!),
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
                  subtitle: const Text('Allow Election Officers to publish results without Org Admin approval.', style: TextStyle(fontSize: 12)),
                  value: _officersCanPublish,
                  activeThumbColor: AppColors.primary,
                  onChanged: (val) => setState(() => _officersCanPublish = val),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPreviewBanner() {
    return AnimatedBuilder(
      animation: _nameCtrl,
      builder: (context, _) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
          decoration: BoxDecoration(
            gradient: _coverUrl.isEmpty ? LinearGradient(colors: [AppColors.primary, AppColors.primaryDark], begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
            image: _coverUrl.isNotEmpty ? DecorationImage(image: NetworkImage(ApiConstants.getFullImageUrl(_coverUrl)!), fit: BoxFit.cover, colorFilter: ColorFilter.mode(Colors.black.withValues(alpha: 0.6), BlendMode.darken)) : null,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 8))],
          ),
          child: Row(
            children: [
              Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.2),
                  image: _logoUrl.isNotEmpty ? DecorationImage(image: NetworkImage(ApiConstants.getFullImageUrl(_logoUrl)!), fit: BoxFit.cover) : null,
                ),
                child: _logoUrl.isEmpty
                    ? const Icon(Icons.business, color: Colors.white, size: 36)
                    : null,
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _nameCtrl.text.isEmpty ? 'Your Organization' : _nameCtrl.text,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                    ),
                    if (_prefixCtrl.text.isNotEmpty || _selectedOrgType.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20)),
                        child: Text(
                          _prefixCtrl.text.isNotEmpty ? '[${_prefixCtrl.text}] · ${_orgTypeLabel(_selectedOrgType)}' : _orgTypeLabel(_selectedOrgType),
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withValues(alpha: 0.2))),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.remove_red_eye, color: Colors.white, size: 12),
                    const SizedBox(width: 6),
                    Text('LIVE PREVIEW', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _orgTypeLabel(String type) {
    const labels = {
      'cooperative': 'Cooperative / SACCO',
      'college': 'College / University',
      'educational': 'Educational Institution',
      'association': 'Professional Association',
      'club': 'Club / Community',
      'housing_society': 'Housing Society',
      'union': 'Trade Union',
      'ngo': 'NGO / INGO',
      'corporate': 'Corporate',
      'religious': 'Religious Organization',
      'political_party': 'Political Party',
      'government': 'Government / Public Body',
      'other': 'Other',
    };
    return labels[type] ?? type;
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
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.business_rounded), text: 'Profile'),
            Tab(icon: Icon(Icons.account_balance_rounded), text: 'Bank'),
            Tab(icon: Icon(Icons.gavel_rounded), text: 'Election Rules'),
          ],
          indicatorColor: AppColors.primaryLight,
          labelColor: AppColors.primaryLight,
          unselectedLabelColor: AppColors.textSecondary,
        ),
      ),
      body: orgAsync.when(
        loading: () => const ListSkeleton(count: 5),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (org) {
          _populateForm(org);
          return Form(
            key: _formKey,
            child: TabBarView(
              controller: _tabController,
              children: [
                Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 800), child: _buildProfileTab())),
                Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 800), child: _buildBankTab())),
                Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 800), child: _buildElectionTab())),
              ],
            ),
          );
        },
      ),
    );
  }
}
