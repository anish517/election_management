import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/glass_card.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Main screen
// ─────────────────────────────────────────────────────────────────────────────
class ElectionCommitteeScreen extends ConsumerStatefulWidget {
  final String electionId;
  const ElectionCommitteeScreen({super.key, required this.electionId});

  @override
  ConsumerState<ElectionCommitteeScreen> createState() =>
      _ElectionCommitteeScreenState();
}

class _ElectionCommitteeScreenState
    extends ConsumerState<ElectionCommitteeScreen> {
  bool _isLoading = true;
  List<dynamic> _committees = [];

  @override
  void initState() {
    super.initState();
    _fetchCommittees();
  }

  Future<void> _fetchCommittees() async {
    setState(() => _isLoading = true);
    try {
      final dio = ref.read(apiClientProvider);
      final resp =
          await dio.get(ApiConstants.electionCommittees(widget.electionId));
      if (mounted) {
        final data = resp.data;
        setState(() {
          _committees = (data is Map && data.containsKey('results'))
              ? data['results']
              : (data is List ? data : []);
          _isLoading = false;
        });
      }
    } on DioException catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showCreateDialog() {
    showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _CreateCommitteeDialog(electionId: widget.electionId),
    ).then((created) {
      if (created == true) _fetchCommittees();
    });
  }

  IconData _roleIcon(String type) =>
      type == 'new' ? Icons.group_add_outlined : Icons.group_outlined;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──────────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Election Committee',
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      Text(
                        'Create and manage election committees for this election.',
                        style: TextStyle(
                            color: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.color,
                            fontSize: 15),
                      ),
                    ],
                  ),
                  ElevatedButton.icon(
                    onPressed: _showCreateDialog,
                    icon: const Icon(Icons.add),
                    label: const Text('New Committee'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 16),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),

              // ── Body ────────────────────────────────────────────────────
              if (_isLoading)
                const Expanded(
                    child: Center(child: CircularProgressIndicator()))
              else if (_committees.isEmpty)
                const Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.group_outlined, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text('No committees yet.',
                            style:
                                TextStyle(fontSize: 18, color: Colors.grey)),
                        SizedBox(height: 8),
                        Text(
                          'Click "New Committee" to create the first committee.',
                          style: TextStyle(color: Colors.grey),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.builder(
                    itemCount: _committees.length,
                    itemBuilder: (context, i) {
                      final c = _committees[i];
                      final type = c['committee_type']?.toString() ?? 'new';
                      final signatureUrl = c['chair_signature'] != null
                          ? ApiConstants.getFullImageUrl(
                              c['chair_signature'].toString())
                          : null;
                      return GlassCard(
                        margin: const EdgeInsets.only(bottom: 14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Signature avatar
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: signatureUrl != null
                                  ? Image.network(signatureUrl,
                                      width: 72, height: 72, fit: BoxFit.cover)
                                  : Container(
                                      width: 72,
                                      height: 72,
                                      decoration: BoxDecoration(
                                        color: AppColors.primary
                                            .withValues(alpha: 0.12),
                                        borderRadius:
                                            BorderRadius.circular(8),
                                      ),
                                      child: Icon(_roleIcon(type),
                                          size: 32, color: AppColors.primary),
                                    ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(c['committee_name'] ?? '',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16)),
                                  const SizedBox(height: 4),
                                  if ((c['chair_designation'] ?? '')
                                      .isNotEmpty)
                                    Text(
                                      c['chair_designation'],
                                      style: TextStyle(
                                          color: AppColors.textMuted,
                                          fontSize: 13),
                                    ),
                                  const SizedBox(height: 4),
                                  _infoRow(Icons.email_outlined,
                                      c['chair_email'] ?? ''),
                                  if ((c['chair_contact'] ?? '').isNotEmpty)
                                    _infoRow(Icons.phone_outlined,
                                        c['chair_contact']),
                                ],
                              ),
                            ),
                            // Type badge
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: (type == 'new'
                                        ? AppColors.primary
                                        : Colors.teal)
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                type == 'new' ? 'New' : 'Existing',
                                style: TextStyle(
                                  color: type == 'new'
                                      ? AppColors.primary
                                      : Colors.teal,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
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

  Widget _infoRow(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Row(
          children: [
            Icon(icon, size: 13, color: AppColors.textMuted),
            const SizedBox(width: 4),
            Flexible(
                child: Text(text,
                    style: const TextStyle(fontSize: 13),
                    overflow: TextOverflow.ellipsis)),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Create Committee Dialog
// ─────────────────────────────────────────────────────────────────────────────
class _CreateCommitteeDialog extends ConsumerStatefulWidget {
  final String electionId;
  const _CreateCommitteeDialog({required this.electionId});

  @override
  ConsumerState<_CreateCommitteeDialog> createState() =>
      _CreateCommitteeDialogState();
}

class _CreateCommitteeDialogState
    extends ConsumerState<_CreateCommitteeDialog> {
  final _formKey = GlobalKey<FormState>();
  String _committeeType = 'new';
  String _selectedRole = 'election_officer'; // default
  bool _isSaving = false;
  String? _error;

  // Signature pick
  Uint8List? _signatureBytes;
  String? _signatureFileName;
  static const int _maxSignatureBytes = 2 * 1024 * 1024; // 2 MB
  static const List<String> _allowedExts = [
    'jpeg', 'jpg', 'png', 'gif', 'svg'
  ];

  final _nameCtrl = TextEditingController();
  final _chairDesignationCtrl = TextEditingController();
  final _chairContactCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _chairDesignationCtrl.dispose();
    _chairContactCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickSignature() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _allowedExts,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if ((file.size) > _maxSignatureBytes) {
      setState(() => _error = 'Signature file must be ≤ 2 MB.');
      return;
    }
    setState(() {
      _signatureBytes = file.bytes;
      _signatureFileName = file.name;
      _error = null;
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_committeeType == 'new' &&
        _passwordCtrl.text != _confirmCtrl.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      final dio = ref.read(apiClientProvider);
      final formData = FormData.fromMap({
        'committee_type': _committeeType,
        'committee_name': _nameCtrl.text.trim(),
        'chair_designation': _chairDesignationCtrl.text.trim(),
        'chair_contact': _chairContactCtrl.text.trim(),
        'chair_email': _emailCtrl.text.trim(),
        'role': _selectedRole,
        if (_committeeType == 'new') 'password': _passwordCtrl.text,
        if (_signatureBytes != null)
          'chair_signature': MultipartFile.fromBytes(
            _signatureBytes!,
            filename: _signatureFileName ?? 'signature.png',
          ),
      });

      await dio.post(
        ApiConstants.electionCreateCommittee(widget.electionId),
        data: formData,
        options: Options(contentType: 'multipart/form-data'),
      );

      if (mounted) Navigator.of(context).pop(true);
    } on DioException catch (e) {
      String msg = 'Failed to create committee.';
      if (e.response?.data is Map) {
        final err = e.response!.data['error'];
        if (err is String) msg = err;
      }
      if (mounted) setState(() => _error = msg);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Title bar ────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.group_add_outlined,
                      color: Colors.white, size: 22),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text('Create New Election Committee',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 17)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
            ),

            // ── Form body ────────────────────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Error banner
                      if (_error != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.1),
                            border: Border.all(
                                color: Colors.red.withValues(alpha: 0.3)),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline,
                                  color: Colors.red, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: Text(_error!,
                                      style: const TextStyle(
                                          color: Colors.red, fontSize: 13))),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Committee Type
                      _sectionLabel('Committee Type'),
                      Row(
                        children: [
                          _typeCard('new', 'Create New',
                              Icons.person_add_outlined),
                          const SizedBox(width: 12),
                          _typeCard('existing', 'Select Existing',
                              Icons.person_search_outlined),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Committee Name
                      _sectionLabel('Committee Name *'),
                      _field(
                        controller: _nameCtrl,
                        hint: 'Enter full committee name',
                        icon: Icons.groups_outlined,
                        validator: (v) =>
                            (v == null || v.trim().isEmpty)
                                ? 'Required'
                                : null,
                      ),
                      const SizedBox(height: 16),

                      // Role assignment
                      _sectionLabel('Assign Role *'),
                      DropdownButtonFormField<String>(
                        value: _selectedRole,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10)),
                          prefixIcon: const Icon(Icons.admin_panel_settings_outlined),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 14),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'election_officer',
                            child: Row(
                              children: [
                                Icon(Icons.manage_accounts_outlined, size: 18, color: Colors.blue),
                                SizedBox(width: 8),
                                Text('Election Officer — manages this election'),
                              ],
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'observer',
                            child: Row(
                              children: [
                                Icon(Icons.visibility_outlined, size: 18, color: Colors.orange),
                                SizedBox(width: 8),
                                Text('Observer — read-only view'),
                              ],
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'auditor',
                            child: Row(
                              children: [
                                Icon(Icons.verified_user_outlined, size: 18, color: Colors.green),
                                SizedBox(width: 8),
                                Text('Auditor — read-only + audit log'),
                              ],
                            ),
                          ),
                        ],
                        onChanged: (v) =>
                            setState(() => _selectedRole = v ?? 'election_officer'),
                      ),
                      const SizedBox(height: 16),

                      // Chair Designation
                      _sectionLabel('Chair Designation *'),
                      _field(
                        controller: _chairDesignationCtrl,
                        hint: 'Enter chair designation',
                        icon: Icons.badge_outlined,
                        validator: (v) =>
                            (v == null || v.trim().isEmpty)
                                ? 'Required'
                                : null,
                      ),
                      const SizedBox(height: 16),

                      // Chair Contact
                      _sectionLabel('Chair Contact *'),
                      _field(
                        controller: _chairContactCtrl,
                        hint: 'Enter chair contact (phone)',
                        icon: Icons.phone_outlined,
                        keyboardType: TextInputType.phone,
                        validator: (v) =>
                            (v == null || v.trim().isEmpty)
                                ? 'Required'
                                : null,
                      ),
                      const SizedBox(height: 16),

                      // Email
                      _sectionLabel('Email Address *'),
                      _field(
                        controller: _emailCtrl,
                        hint: 'Enter email address',
                        icon: Icons.email_outlined,
                        keyboardType: TextInputType.emailAddress,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Required';
                          }
                          if (!RegExp(r'^[^@]+@[^@]+\.[^@]+')
                              .hasMatch(v.trim())) {
                            return 'Enter a valid email';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Password fields (only for 'new')
                      if (_committeeType == 'new') ...[
                        _sectionLabel('Password *'),
                        _passwordField(
                          controller: _passwordCtrl,
                          hint: 'Enter password',
                          obscure: _obscurePassword,
                          onToggle: () => setState(
                              () => _obscurePassword = !_obscurePassword),
                          validator: (v) {
                            if (v == null || v.isEmpty) return 'Required';
                            if (v.length < 8) {
                              return 'Minimum 8 characters';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        _sectionLabel('Confirm Password *'),
                        _passwordField(
                          controller: _confirmCtrl,
                          hint: 'Confirm password',
                          obscure: _obscureConfirm,
                          onToggle: () => setState(
                              () => _obscureConfirm = !_obscureConfirm),
                          validator: (v) =>
                              (v == null || v.isEmpty) ? 'Required' : null,
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Chair Signature upload
                      _sectionLabel('Chair Signature'),
                      _signatureUploadBox(),
                    ],
                  ),
                ),
              ),
            ),

            // ── Action buttons ───────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSaving
                          ? null
                          : () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ))
                          : const Text('Create Committee'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: const TextStyle(
                fontWeight: FontWeight.w600, fontSize: 13)),
      );

  Widget _field({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) =>
      TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: Icon(icon, size: 18),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        ),
        validator: validator,
      );

  Widget _passwordField({
    required TextEditingController controller,
    required String hint,
    required bool obscure,
    required VoidCallback onToggle,
    String? Function(String?)? validator,
  }) =>
      TextFormField(
        controller: controller,
        obscureText: obscure,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: const Icon(Icons.lock_outline, size: 18),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          suffixIcon: IconButton(
            icon: Icon(
                obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                size: 18),
            onPressed: onToggle,
          ),
        ),
        validator: validator,
      );

  Widget _typeCard(String value, String label, IconData icon) {
    final selected = _committeeType == value;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _committeeType = value),
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding:
              const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected
                  ? AppColors.primary
                  : Theme.of(context).dividerColor,
              width: selected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(10),
            color: selected
                ? AppColors.primary.withValues(alpha: 0.08)
                : Colors.transparent,
          ),
          child: Column(
            children: [
              Icon(icon,
                  color: selected ? AppColors.primary : Colors.grey,
                  size: 26),
              const SizedBox(height: 6),
              Text(label,
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: selected ? AppColors.primary : Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _signatureUploadBox() {
    return InkWell(
      onTap: _pickSignature,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          border: Border.all(
              color: Theme.of(context).dividerColor,
              style: BorderStyle.solid),
          borderRadius: BorderRadius.circular(10),
        ),
        child: _signatureBytes != null
            ? Column(
                children: [
                  Image.memory(_signatureBytes!,
                      height: 100, fit: BoxFit.contain),
                  const SizedBox(height: 8),
                  Text(_signatureFileName ?? 'signature',
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  TextButton(
                      onPressed: () =>
                          setState(() {
                            _signatureBytes = null;
                            _signatureFileName = null;
                          }),
                      child: const Text('Remove')),
                ],
              )
            : Column(
                children: [
                  Icon(Icons.upload_file_outlined,
                      size: 36, color: Colors.grey.shade400),
                  const SizedBox(height: 8),
                  const Text('Click to upload signature',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text(
                    'Max size: 2MB. Formats: jpeg, png, jpg, gif, svg',
                    style: TextStyle(
                        color: Colors.grey.shade500, fontSize: 11),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
      ),
    );
  }
}
