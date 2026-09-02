import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/org_providers.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_constants.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/loading_button.dart';
import '../../../shared/widgets/admin_drawer.dart';
import '../../../shared/widgets/shimmer_loaders.dart';
import '../../../shared/widgets/responsive_layout.dart';

// ---------------------------------------------------------------------------
// Type-specific metadata field descriptors
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
      setState(() {
        _uploading = false;
        if (url != null) _url = url;
      });
      if (url != null) widget.onUploaded(url);
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
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDark ? Colors.white12 : Colors.grey.shade300,
                width: 1.5,
              ),
              image: hasImg ? DecorationImage(image: NetworkImage(_url!), fit: BoxFit.cover) : null,
            ),
            child: _uploading
                ? const Center(child: CircularProgressIndicator())
                : hasImg
                    ? Align(
                        alignment: Alignment.bottomRight,
                        child: Container(
                          margin: const EdgeInsets.all(10),
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
                            ],
                          ),
                          child: const Icon(Icons.edit, color: Colors.white, size: 14),
                        ),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(widget.icon, color: AppColors.textMuted, size: 30),
                          const SizedBox(height: 8),
                          const Text('Tap to upload', style: TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          const Text('Max 2MB · jpeg, png, jpg, gif, svg', style: TextStyle(color: AppColors.textMuted, fontSize: 10)),
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

class _OrgSettingsScreenState extends ConsumerState<OrgSettingsScreen> {
  final _formKey = GlobalKey<FormState>();

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

  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _prefixCtrl = TextEditingController();
    _councilCtrl = TextEditingController();
    _orgEmailCtrl = TextEditingController();
    _orgPhoneCtrl = TextEditingController();
    _websiteCtrl = TextEditingController();
    _addressCtrl = TextEditingController();
  }

  @override
  void dispose() {
    for (final c in [
      _nameCtrl,
      _prefixCtrl,
      _councilCtrl,
      _orgEmailCtrl,
      _orgPhoneCtrl,
      _websiteCtrl,
      _addressCtrl,
    ]) {
      c.dispose();
    }
    for (final c in _metaCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _populateForm(OrganizationModel org) {
    if (_initialized) return;
    _nameCtrl.text = org.name;
    _prefixCtrl.text = org.prefix;
    _councilCtrl.text = org.councilNumber;
    _orgEmailCtrl.text = org.email;
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
    for (final c in _metaCtrls.values) {
      c.dispose();
    }
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
      if (entry.value.text.isNotEmpty) {
        meta[entry.key] = entry.value.text.trim();
      }
    }
    try {
      await ref.read(updateOrgSettingsProvider.notifier).updateSettings({
        'name': _nameCtrl.text.trim(),
        'prefix': _prefixCtrl.text.trim(),
        'org_type': _selectedOrgType,
        'council_number': _councilCtrl.text.trim(),
        'email': _orgEmailCtrl.text.trim(),
        'org_email': _orgEmailCtrl.text.trim(),
        'phone': _orgPhoneCtrl.text.trim(),
        'website': _websiteCtrl.text.trim(),
        'address': _addressCtrl.text.trim(),
        'logo_url': _logoUrl,
        'cover_image_url': _coverUrl,
        'type_metadata': meta,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Row(children: [
            Icon(Icons.check_circle, color: Colors.white),
            SizedBox(width: 12),
            Text('Organization settings saved successfully!', style: TextStyle(fontWeight: FontWeight.bold)),
          ]),
          backgroundColor: Colors.green.shade700,
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
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(24),
        ));
      }
    }
  }

  // --- Shared section card builder ---
  Widget _section({required String title, required String subtitle, required IconData icon, required List<Widget> children}) {
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  Text(subtitle, style: TextStyle(color: isDark ? Colors.white60 : Colors.grey.shade600, fontSize: 12)),
                ],
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

  InputDecoration _dec(String label, {String? hint, Widget? prefix}) => InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: prefix,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      );

  Widget _buildProfileTab() {
    final metaFields = _typeMetaFields[_selectedOrgType] ?? [];

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
      children: [
        // Live Preview banner
        _buildPreviewBanner()
            .animate()
            .fade(duration: 300.ms)
            .slideY(begin: -0.05, end: 0),
        const SizedBox(height: 24),

        // Basic Info
        _section(
          title: 'Organization Identity',
          subtitle: 'Core brand metadata and registered tenant details',
          icon: Icons.business_rounded,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: _nameCtrl,
                    decoration: _dec('Organization Name *', hint: 'Enter organization name', prefix: const Icon(Icons.badge_outlined)),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _prefixCtrl,
                    decoration: _dec('Prefix Tag', hint: 'e.g. SOC'),
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
              decoration: _dec('Organization Type *', prefix: const Icon(Icons.category_outlined)),
              items: const [
                DropdownMenuItem(value: 'cooperative', child: Text('Cooperative / SACCO (सहकारी)')),
                DropdownMenuItem(value: 'college', child: Text('College / University (क्याम्पस)')),
                DropdownMenuItem(value: 'educational', child: Text('Educational Institution (शैक्षिक संस्था)')),
                DropdownMenuItem(value: 'association', child: Text('Professional Association (संघ / महासंघ)')),
                DropdownMenuItem(value: 'club', child: Text('Club / Community (क्लब / समाज)')),
                DropdownMenuItem(value: 'housing_society', child: Text('Housing Society (आवास समाज)')),
                DropdownMenuItem(value: 'union', child: Text('Trade Union (ट्रेड युनियन)')),
                DropdownMenuItem(value: 'ngo', child: Text('NGO / INGO (गैर सरकारी संस्था)')),
                DropdownMenuItem(value: 'corporate', child: Text('Corporate / Private Ltd.')),
                DropdownMenuItem(value: 'religious', child: Text('Religious / Trust Organization')),
                DropdownMenuItem(value: 'political_party', child: Text('Political Party (राजनीतिक दल)')),
                DropdownMenuItem(value: 'government', child: Text('Government / Public Body (सरकारी निकाय)')),
                DropdownMenuItem(value: 'other', child: Text('Other Enterprise')),
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
                    decoration: _dec('Official Email', hint: 'contact@org.org.np', prefix: const Icon(Icons.email_outlined)),
                    keyboardType: TextInputType.emailAddress,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _orgPhoneCtrl,
                    decoration: _dec('Helpline Phone', hint: '+977-9800000000', prefix: const Icon(Icons.phone_outlined)),
                    keyboardType: TextInputType.phone,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _websiteCtrl,
              decoration: _dec('Official Website', hint: 'https://example.org.np', prefix: const Icon(Icons.language_outlined)),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _addressCtrl,
              decoration: _dec('Headquarters Address', hint: 'Street, Ward, City, District', prefix: const Icon(Icons.location_on_outlined)),
              maxLines: 2,
            ),
          ],
        ),

        // Branding
        _section(
          title: 'Branding & Assets',
          subtitle: 'Official emblem and cover banner displayed on election portal',
          icon: Icons.palette_rounded,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _ImageTile(
                    label: 'Emblem / Logo',
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
                    label: 'Cover Banner',
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
            title: '${_orgTypeLabel(_selectedOrgType)} Compliance',
            subtitle: 'Statutory parameters specific to your organizational charter',
            icon: Icons.tune_rounded,
            children: metaFields
                .map((f) => Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: TextFormField(
                        controller: _metaCtrls[f['key']!],
                        decoration: _dec(f['label']!, hint: f['hint']),
                      ),
                    ))
                .toList(),
          ),

        // Election Rules Shortcut Card
        Container(
          margin: const EdgeInsets.only(bottom: 24),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.gavel_rounded, color: AppColors.primary, size: 24),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Election Rules & Governance Policies', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    SizedBox(height: 2),
                    Text('Manage default nomination/voting phases, silence periods, and ballot publication controls.', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                onPressed: () => context.pushNamed('election-rules'),
                icon: const Icon(Icons.tune_rounded, size: 16),
                label: const Text('Manage Rules'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewBanner() {
    return AnimatedBuilder(
      animation: Listenable.merge([_nameCtrl, _prefixCtrl]),
      builder: (context, _) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
          decoration: BoxDecoration(
            gradient: _coverUrl.isEmpty
                ? const LinearGradient(
                    colors: [AppColors.primary, AppColors.primaryDark],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            image: _coverUrl.isNotEmpty
                ? DecorationImage(
                    image: NetworkImage(ApiConstants.getFullImageUrl(_coverUrl)!),
                    fit: BoxFit.cover,
                    colorFilter: ColorFilter.mode(Colors.black.withValues(alpha: 0.6), BlendMode.darken),
                  )
                : null,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.2),
                  border: Border.all(color: Colors.white30, width: 2),
                  image: _logoUrl.isNotEmpty
                      ? DecorationImage(
                          image: NetworkImage(ApiConstants.getFullImageUrl(_logoUrl)!),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: _logoUrl.isEmpty
                    ? const Icon(Icons.business_rounded, color: Colors.white, size: 36)
                    : null,
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (_prefixCtrl.text.isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              _prefixCtrl.text,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _orgTypeLabel(_selectedOrgType),
                            style: const TextStyle(color: Colors.white, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _nameCtrl.text.isEmpty ? 'Your Organization Name' : _nameCtrl.text,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
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

  String _orgTypeLabel(String type) {
    const labels = {
      'cooperative': 'Cooperative',
      'college': 'College / University',
      'educational': 'Educational Institute',
      'association': 'Professional Association',
      'club': 'Club / Community',
      'housing_society': 'Housing Society',
      'union': 'Trade Union',
      'ngo': 'NGO / INGO',
      'corporate': 'Corporate Enterprise',
      'religious': 'Religious Organization',
      'political_party': 'Political Party',
      'government': 'Government / Public Body',
      'other': 'Organization',
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
              label: 'Save Changes',
              icon: Icons.save_rounded,
              fullWidth: false,
            ),
          ),
        ],
      ),
      body: ResponsivePageWrapper(
        child: orgAsync.when(
          loading: () => const ListSkeleton(count: 5),
          error: (err, _) => Center(child: Text('Error: $err')),
          data: (org) {
            _populateForm(org);
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 860),
                child: Form(
                  key: _formKey,
                  child: _buildProfileTab(),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

