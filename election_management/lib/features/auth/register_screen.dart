import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/loading_button.dart';

// ---------------------------------------------------------------------------
// Org-type specific metadata field descriptors
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
// Reusable rectangular image picker tile (Logo / Cover / QR)
// ---------------------------------------------------------------------------
class _ImagePickerTile extends StatefulWidget {
  final String label;
  final String? currentUrl;
  final Future<String?> Function(Uint8List bytes, String name) onUpload;
  final void Function(String url) onUploaded;
  final bool isSquare;

  const _ImagePickerTile({
    required this.label,
    required this.currentUrl,
    required this.onUpload,
    required this.onUploaded,
    this.isSquare = false,
  });

  @override
  State<_ImagePickerTile> createState() => _ImagePickerTileState();
}

class _ImagePickerTileState extends State<_ImagePickerTile> {
  bool _uploading = false;
  String? _url;

  @override
  void initState() {
    super.initState();
    _url = widget.currentUrl;
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
    final hasImage = _url != null && _url!.isNotEmpty;
    final h = widget.isSquare ? 100.0 : 140.0;
    final w = widget.isSquare ? 100.0 : double.infinity;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _uploading ? null : _pick,
          child: Container(
            height: h,
            width: w,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF27272A) : const Color(0xFFF4F4F5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? const Color(0xFF3F3F46) : const Color(0xFFE4E4E7),
                width: 1.5,
              ),
              image: hasImage ? DecorationImage(image: NetworkImage(ApiConstants.getFullImageUrl(_url)!), fit: BoxFit.cover) : null,
            ),
            child: _uploading
                ? const Center(child: CircularProgressIndicator())
                : hasImage
                    ? Align(
                        alignment: Alignment.bottomRight,
                        child: Container(
                          margin: const EdgeInsets.all(8),
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                          child: const Icon(Icons.edit, color: Colors.white, size: 14),
                        ),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.cloud_upload_outlined, color: AppColors.textMuted, size: 32),
                          const SizedBox(height: 8),
                          Text('Tap to upload', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                          const SizedBox(height: 4),
                          Text('Max 2MB · jpeg, png, jpg, gif, svg',
                              style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                        ],
                      ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Section header
// ---------------------------------------------------------------------------
Widget _sectionHeader(BuildContext context, String title, IconData icon) {
  return Row(
    children: [
      Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: AppColors.primaryLight, size: 18),
      ),
      const SizedBox(width: 10),
      Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
    ],
  );
}

// ---------------------------------------------------------------------------
// Main Register Screen
// ---------------------------------------------------------------------------
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _scrollController = ScrollController();

  // --- Organisation ---
  final _orgNameCtrl = TextEditingController();
  final _prefixCtrl = TextEditingController();
  final _councilCtrl = TextEditingController();
  final _orgEmailCtrl = TextEditingController();
  final _orgPhoneCtrl = TextEditingController();
  final _websiteCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  String _orgType = 'other';
  String _logoUrl = '';
  String _coverUrl = '';

  // --- Bank ---
  final _bankNameCtrl = TextEditingController();
  final _bankBranchCtrl = TextEditingController();
  final _bankAccountNumCtrl = TextEditingController();
  final _bankAccountNameCtrl = TextEditingController();
  final _bankSwiftCtrl = TextEditingController();
  String _bankQrUrl = '';

  // --- Type metadata ---
  final Map<String, TextEditingController> _metaCtrls = {};

  // --- Admin ---
  final _adminNameCtrl = TextEditingController();
  final _adminEmailCtrl = TextEditingController();
  final _adminPhoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();

  bool _passwordVisible = false;
  bool _confirmVisible = false;
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [
      _orgNameCtrl, _prefixCtrl, _councilCtrl, _orgEmailCtrl, _orgPhoneCtrl,
      _websiteCtrl, _addressCtrl, _bankNameCtrl, _bankBranchCtrl,
      _bankAccountNumCtrl, _bankAccountNameCtrl, _bankSwiftCtrl,
      _adminNameCtrl, _adminEmailCtrl, _adminPhoneCtrl,
      _passwordCtrl, _confirmPasswordCtrl,
    ]) {
      c.dispose();
    }
    for (final c in _metaCtrls.values) { c.dispose(); }
    _scrollController.dispose();
    super.dispose();
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
    setState(() => _orgType = val);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final meta = <String, dynamic>{};
    for (final entry in _metaCtrls.entries) {
      if (entry.value.text.isNotEmpty) meta[entry.key] = entry.value.text.trim();
    }

    setState(() { _isLoading = true; _error = null; });

    final error = await ref.read(authProvider.notifier).register(
      email: _adminEmailCtrl.text.trim(),
      password: _passwordCtrl.text,
      orgName: _orgNameCtrl.text.trim(),
      orgType: _orgType,
      adminName: _adminNameCtrl.text.trim(),
      phone: _adminPhoneCtrl.text.trim(),
      prefix: _prefixCtrl.text.trim(),
      councilNumber: _councilCtrl.text.trim(),
      orgEmail: _orgEmailCtrl.text.trim(),
      orgPhone: _orgPhoneCtrl.text.trim(),
      website: _websiteCtrl.text.trim(),
      address: _addressCtrl.text.trim(),
      logoUrl: _logoUrl,
      coverImageUrl: _coverUrl,
      bankName: _bankNameCtrl.text.trim(),
      bankBranch: _bankBranchCtrl.text.trim(),
      bankAccountNumber: _bankAccountNumCtrl.text.trim(),
      bankAccountName: _bankAccountNameCtrl.text.trim(),
      bankSwiftCode: _bankSwiftCtrl.text.trim(),
      bankQrUrl: _bankQrUrl,
      typeMetadata: meta,
    );

    if (mounted) setState(() { _isLoading = false; _error = error; });
  }

  // ---- ORG TYPE choices ----
  static const _orgTypeItems = [
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
  ];

  InputDecoration _field(String label, {String? hint, Widget? prefix, bool required = true}) {
    return InputDecoration(
      labelText: required ? '$label *' : label,
      hintText: hint,
      prefixIcon: prefix,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
    );
  }

  @override
  Widget build(BuildContext context) {

    final metaFields = _typeMetaFields[_orgType] ?? [];

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Create New Organization'),
        centerTitle: false,
        elevation: 0,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Form(
            key: _formKey,
            child: ListView(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 120),
              children: [

                // ── Error banner ─────────────────────────────────────────
                if (_error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: AppColors.error),
                        const SizedBox(width: 10),
                        Expanded(child: Text(_error!, style: const TextStyle(color: AppColors.error))),
                      ],
                    ),
                  ),
                ],

                // ══════════════════════════════════════════════════════════
                // 1. ORGANIZATION INFORMATION
                // ══════════════════════════════════════════════════════════
                _sectionHeader(context, 'Organization Information', Icons.business_rounded),
                const SizedBox(height: 20),

                // Row: Name + Prefix
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _orgNameCtrl,
                        decoration: _field('Organization Name', hint: 'Enter organization name'),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _prefixCtrl,
                        decoration: _field('Prefix', hint: 'e.g. SOC', required: false),
                        textCapitalization: TextCapitalization.characters,
                        maxLength: 10,
                        buildCounter: (_, {required currentLength, required isFocused, required maxLength}) => null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Org type
                DropdownButtonFormField<String>(
                  initialValue: _orgType,
                  decoration: _field('Organization Type'),
                  items: _orgTypeItems,
                  onChanged: _onTypeChanged,
                ),
                const SizedBox(height: 14),

                // Council number
                TextFormField(
                  controller: _councilCtrl,
                  decoration: _field('Council / Registration No.', hint: 'e.g. 1234/2078', required: false),
                ),
                const SizedBox(height: 14),

                // Row: Email + Phone
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _orgEmailCtrl,
                        decoration: _field('Organization Email', hint: 'organization@example.com'),
                        keyboardType: TextInputType.emailAddress,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Required';
                          if (!v.contains('@')) return 'Invalid email';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _orgPhoneCtrl,
                        decoration: _field('Phone', hint: '9876543210'),
                        keyboardType: TextInputType.phone,
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Website
                TextFormField(
                  controller: _websiteCtrl,
                  decoration: _field('Website', hint: 'https://example.com', required: false),
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 14),

                // Address
                TextFormField(
                  controller: _addressCtrl,
                  decoration: _field('Address', hint: 'Enter full address').copyWith(
                    alignLabelWithHint: true,
                  ),
                  maxLines: 3,
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 20),

                // Logo + Cover
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _ImagePickerTile(
                        label: 'Logo *',
                        currentUrl: _logoUrl.isEmpty ? null : _logoUrl,
                        onUpload: _upload,
                        onUploaded: (url) => setState(() => _logoUrl = url),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _ImagePickerTile(
                        label: 'Cover Image',
                        currentUrl: _coverUrl.isEmpty ? null : _coverUrl,
                        onUpload: _upload,
                        onUploaded: (url) => setState(() => _coverUrl = url),
                      ),
                    ),
                  ],
                ),

                // ── Type-specific metadata ──────────────────────────────
                if (metaFields.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.primaryLight.withValues(alpha: 0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.tune_rounded, size: 16, color: AppColors.primaryLight),
                            const SizedBox(width: 6),
                            Text('${_orgTypeLabel(_orgType)} Details',
                                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                    color: AppColors.primaryLight, fontWeight: FontWeight.w700)),
                          ],
                        ),
                        const SizedBox(height: 14),
                        ...metaFields.map((f) => Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: TextFormField(
                            controller: _metaCtrls[f['key']!],
                            decoration: _field(f['label']!, hint: f['hint'], required: false),
                          ),
                        )),
                      ],
                    ),
                  ),
                ],

                // ══════════════════════════════════════════════════════════
                // 2. BANK DETAILS
                // ══════════════════════════════════════════════════════════
                const SizedBox(height: 32),
                _sectionHeader(context, 'Bank Details (Optional)', Icons.account_balance_rounded),
                const SizedBox(height: 20),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _bankNameCtrl,
                        decoration: _field('Bank Name', hint: 'Enter bank name', required: false),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _bankBranchCtrl,
                        decoration: _field('Branch Name', hint: 'Enter branch name', required: false),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _bankAccountNumCtrl,
                        decoration: _field('Account Number', hint: 'Enter account number', required: false),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _bankAccountNameCtrl,
                        decoration: _field('Account Name', hint: 'Enter account name', required: false),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _bankSwiftCtrl,
                        decoration: _field('SWIFT Code', hint: 'Enter SWIFT code', required: false),
                        textCapitalization: TextCapitalization.characters,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ImagePickerTile(
                        label: 'QR Code',
                        currentUrl: _bankQrUrl.isEmpty ? null : _bankQrUrl,
                        onUpload: _upload,
                        onUploaded: (url) => setState(() => _bankQrUrl = url),
                        isSquare: true,
                      ),
                    ),
                  ],
                ),

                // ══════════════════════════════════════════════════════════
                // 3. ORGANIZATION ADMIN
                // ══════════════════════════════════════════════════════════
                const SizedBox(height: 32),
                _sectionHeader(context, 'Organization Admin', Icons.admin_panel_settings_rounded),
                const SizedBox(height: 20),

                TextFormField(
                  controller: _adminNameCtrl,
                  decoration: _field('Admin Name', hint: 'Enter admin name'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 14),

                TextFormField(
                  controller: _adminEmailCtrl,
                  decoration: _field('Admin Email', hint: 'admin@example.com'),
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Required';
                    if (!v.contains('@')) return 'Invalid email';
                    return null;
                  },
                ),
                const SizedBox(height: 14),

                TextFormField(
                  controller: _adminPhoneCtrl,
                  decoration: _field('Admin Phone', hint: '9876543210', required: false),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 14),

                TextFormField(
                  controller: _passwordCtrl,
                  obscureText: !_passwordVisible,
                  decoration: _field('Admin Password', hint: 'Enter admin password').copyWith(
                    suffixIcon: IconButton(
                      icon: Icon(_passwordVisible ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _passwordVisible = !_passwordVisible),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Required';
                    if (v.length < 8) return 'Minimum 8 characters';
                    return null;
                  },
                ),
                const SizedBox(height: 14),

                TextFormField(
                  controller: _confirmPasswordCtrl,
                  obscureText: !_confirmVisible,
                  decoration: _field('Confirm Password', hint: 'Re-enter password').copyWith(
                    suffixIcon: IconButton(
                      icon: Icon(_confirmVisible ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _confirmVisible = !_confirmVisible),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Required';
                    if (v != _passwordCtrl.text) return 'Passwords do not match';
                    return null;
                  },
                ),

                // ── Submit ─────────────────────────────────────────────
                const SizedBox(height: 36),
                SizedBox(
                  height: 52,
                  child: LoadingButton(
                    isLoading: _isLoading,
                    label: 'Create Organization',
                    onPressed: _submit,
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: TextButton(
                    onPressed: () {
                      if (context.canPop()) { context.pop(); }
                      else { context.go('/'); }
                    },
                    child: const Text('Already have an account? Sign in'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
}
