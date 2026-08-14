import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_constants.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/models.dart';
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

  void _showViewSheet(Map<String, dynamic> c) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CommitteeDetailSheet(
        committee: c,
        electionId: widget.electionId,
        onEdited: _fetchCommittees,
        onDeleted: _fetchCommittees,
      ),
    );
  }

  Color _roleColor(String? role) {
    switch (role) {
      case 'election_officer':
        return Colors.blue;
      case 'observer':
        return Colors.orange;
      case 'auditor':
        return Colors.green;
      default:
        return Colors.blueGrey;
    }
  }

  IconData _roleIcon(String? role) {
    switch (role) {
      case 'election_officer':
        return Icons.manage_accounts_outlined;
      case 'observer':
        return Icons.visibility_outlined;
      case 'auditor':
        return Icons.verified_user_outlined;
      default:
        return Icons.group_outlined;
    }
  }

  String _roleLabel(String? role) {
    switch (role) {
      case 'election_officer':
        return 'Election Officer';
      case 'observer':
        return 'Observer';
      case 'auditor':
        return 'Auditor';
      default:
        return role ?? 'Unknown';
    }
  }

  String _displayName(Map<String, dynamic> c) {
    final fullName = c['chair_full_name']?.toString();
    if (fullName != null && fullName.trim().isNotEmpty) return fullName.trim();
    final name = c['committee_name']?.toString();
    if (name != null && name.trim().isNotEmpty) return name.trim();
    return c['chair_email']?.toString() ?? 'Committee Member';
  }

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
                        'Assign Election Officers, Observers, and Auditors to this election.',
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
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
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
                        Text('No election committee members assigned yet.',
                            style:
                                TextStyle(fontSize: 18, color: Colors.grey)),
                        SizedBox(height: 8),
                        Text(
                          'Click "New Committee" to assign election officers or observers.',
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
                      final role = c['role']?.toString();
                      final signatureUrl = c['chair_signature'] != null
                          ? ApiConstants.getFullImageUrl(
                              c['chair_signature'].toString())
                          : null;
                      final roleColor = _roleColor(role);
                      final memberCode = c['chair_member_code']?.toString() ?? '';

                      return GlassCard(
                        margin: const EdgeInsets.only(bottom: 14),
                        onTap: () => _showViewSheet(c),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Signature avatar
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: signatureUrl != null
                                  ? Image.network(signatureUrl,
                                      width: 64, height: 64, fit: BoxFit.cover)
                                  : Container(
                                      width: 64,
                                      height: 64,
                                      decoration: BoxDecoration(
                                        color: roleColor.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Icon(_roleIcon(role),
                                          size: 28, color: roleColor),
                                    ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        _displayName(c),
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16),
                                      ),
                                      if (memberCode.isNotEmpty) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.grey.withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            '#$memberCode',
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey[700],
                                                fontWeight: FontWeight.w600),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  _infoRow(Icons.email_outlined, c['chair_email'] ?? ''),
                                  const SizedBox(height: 8),
                                  // Role badge
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: roleColor.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: roleColor.withValues(alpha: 0.3)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(_roleIcon(role), size: 11, color: roleColor),
                                        const SizedBox(width: 4),
                                        Text(_roleLabel(role),
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: roleColor,
                                                fontWeight: FontWeight.w600)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // 3-dot menu
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert_rounded, size: 20),
                              onSelected: (val) {
                                if (val == 'edit') {
                                  showDialog<bool>(
                                    context: context,
                                    builder: (_) => _EditCommitteeDialog(
                                      committee: c,
                                      electionId: widget.electionId,
                                    ),
                                  ).then((ok) {
                                    if (ok == true) _fetchCommittees();
                                  });
                                } else if (val == 'delete') {
                                  _confirmDelete(c);
                                }
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem(
                                    value: 'edit',
                                    child: Row(children: [
                                      Icon(Icons.edit_outlined, size: 18),
                                      SizedBox(width: 8),
                                      Text('Edit Role / Signature'),
                                    ])),
                                const PopupMenuItem(
                                    value: 'delete',
                                    child: Row(children: [
                                      Icon(Icons.delete_outline_rounded,
                                          size: 18, color: Colors.red),
                                      SizedBox(width: 8),
                                      Text('Delete',
                                          style: TextStyle(color: Colors.red)),
                                    ])),
                              ],
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

  Future<void> _confirmDelete(Map<String, dynamic> c) async {
    final name = _displayName(c);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Committee Member?'),
        content: Text('Remove "$name" from this election committee?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      final dio = ref.read(apiClientProvider);
      await dio.delete(ApiConstants.electionDeleteCommittee(
          widget.electionId, c['id'].toString()));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Committee member removed.')));
        _fetchCommittees();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to delete committee member.')));
      }
    }
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
// Committee Detail Bottom Sheet
// ─────────────────────────────────────────────────────────────────────────────
class _CommitteeDetailSheet extends ConsumerWidget {
  final Map<String, dynamic> committee;
  final String electionId;
  final VoidCallback onEdited;
  final VoidCallback onDeleted;

  const _CommitteeDetailSheet({
    required this.committee,
    required this.electionId,
    required this.onEdited,
    required this.onDeleted,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = committee;
    final signatureUrl = c['chair_signature'] != null
        ? ApiConstants.getFullImageUrl(c['chair_signature'].toString())
        : null;
    final role = c['role']?.toString();

    Color roleColor(String? r) {
      switch (r) {
        case 'election_officer':
          return Colors.blue;
        case 'observer':
          return Colors.orange;
        case 'auditor':
          return Colors.green;
        default:
          return Colors.blueGrey;
      }
    }

    String roleLabel(String? r) {
      switch (r) {
        case 'election_officer':
          return 'Election Officer';
        case 'observer':
          return 'Observer';
        case 'auditor':
          return 'Auditor';
        default:
          return r ?? 'Unknown';
      }
    }

    String displayName() {
      final fullName = c['chair_full_name']?.toString();
      if (fullName != null && fullName.trim().isNotEmpty) return fullName.trim();
      final name = c['committee_name']?.toString();
      if (name != null && name.trim().isNotEmpty) return name.trim();
      return c['chair_email']?.toString() ?? 'Committee Member';
    }

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (_, ctrl) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 16, 0),
              child: Row(
                children: [
                  const Text('Committee Member Details',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  TextButton.icon(
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Edit'),
                    onPressed: () {
                      Navigator.pop(context);
                      showDialog<bool>(
                        context: context,
                        builder: (_) => _EditCommitteeDialog(
                            committee: c, electionId: electionId),
                      ).then((ok) {
                        if (ok == true) onEdited();
                      });
                    },
                  ),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: ListView(
                controller: ctrl,
                padding: const EdgeInsets.all(24),
                children: [
                  // Signature image
                  if (signatureUrl != null) ...[
                    Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(signatureUrl,
                            height: 100, fit: BoxFit.contain),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Role badge
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: roleColor(role).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: roleColor(role).withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        roleLabel(role),
                        style: TextStyle(
                            color: roleColor(role),
                            fontWeight: FontWeight.bold,
                            fontSize: 12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  _tile(Icons.person_outline, 'Name', displayName()),
                  _tile(Icons.email_outlined, 'Email', c['chair_email'] ?? '-'),
                  if ((c['chair_member_code'] ?? '').isNotEmpty)
                    _tile(Icons.badge_outlined, 'Member Code', '#${c['chair_member_code']}'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.textMuted),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style:
                        const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                Text(value,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w500)),
              ],
            ),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Edit Committee Dialog
// ─────────────────────────────────────────────────────────────────────────────
class _EditCommitteeDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic> committee;
  final String electionId;
  const _EditCommitteeDialog(
      {required this.committee, required this.electionId});

  @override
  ConsumerState<_EditCommitteeDialog> createState() =>
      _EditCommitteeDialogState();
}

class _EditCommitteeDialogState extends ConsumerState<_EditCommitteeDialog> {
  final _formKey = GlobalKey<FormState>();
  late String _selectedRole;
  bool _isSaving = false;
  String? _error;

  Uint8List? _newSignatureBytes;
  String? _newSignatureFileName;
  static const int _maxSignatureBytes = 2 * 1024 * 1024;

  @override
  void initState() {
    super.initState();
    final c = widget.committee;
    _selectedRole = c['role']?.toString() ?? 'election_officer';
    if (!['election_officer', 'observer', 'auditor'].contains(_selectedRole)) {
      _selectedRole = 'election_officer';
    }
  }

  Future<void> _pickSignature() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpeg', 'jpg', 'png', 'gif', 'svg'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.size > _maxSignatureBytes) {
      setState(() => _error = 'Signature file must be ≤ 2 MB.');
      return;
    }
    setState(() {
      _newSignatureBytes = file.bytes;
      _newSignatureFileName = file.name;
      _error = null;
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      final dio = ref.read(apiClientProvider);

      if (_newSignatureBytes != null) {
        final formData = FormData.fromMap({
          'role': _selectedRole,
          'chair_signature': MultipartFile.fromBytes(
            _newSignatureBytes!,
            filename: _newSignatureFileName ?? 'signature.png',
          ),
        });
        await dio.patch(
          ApiConstants.electionUpdateCommittee(
              widget.electionId, widget.committee['id'].toString()),
          data: formData,
          options: Options(contentType: 'multipart/form-data'),
        );
      } else {
        await dio.patch(
          ApiConstants.electionUpdateCommittee(
              widget.electionId, widget.committee['id'].toString()),
          data: {'role': _selectedRole},
        );
      }

      if (mounted) Navigator.of(context).pop(true);
    } on DioException catch (e) {
      String msg = 'Failed to update committee.';
      if (e.response?.data is Map) {
        final data = e.response!.data as Map;
        if (data['error'] is Map && data['error']['message'] != null) {
          msg = data['error']['message'].toString();
        } else if (data['error'] is String) {
          msg = data['error'];
        } else if (data['detail'] is String) {
          msg = data['detail'];
        } else {
          msg = data.values.join(', ');
        }
      }
      if (mounted) setState(() => _error = msg);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.committee;
    final fullName = c['chair_full_name']?.toString() ?? c['chair_email']?.toString() ?? '';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title
                Row(
                  children: [
                    const Icon(Icons.edit_outlined, size: 22, color: AppColors.primary),
                    const SizedBox(width: 10),
                    const Text('Edit Committee Role & Signature',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop(false)),
                  ],
                ),
                const SizedBox(height: 16),

                // Member Info summary card
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: AppColors.primaryLight.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        child: Text(fullName.isNotEmpty ? fullName[0].toUpperCase() : '?'),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(fullName, style: const TextStyle(fontWeight: FontWeight.bold)),
                            Text(c['chair_email'] ?? '', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                if (_error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(_error!,
                        style:
                            const TextStyle(color: Colors.red, fontSize: 13)),
                  ),
                  const SizedBox(height: 12),
                ],

                // Role Selector
                const Text('Assigned Role *',
                    style:
                        TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: _selectedRole,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.admin_panel_settings_outlined),
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                        value: 'election_officer',
                        child: Text('Election Officer — manages election')),
                    DropdownMenuItem(
                        value: 'observer', child: Text('Observer — read-only view')),
                    DropdownMenuItem(
                        value: 'auditor', child: Text('Auditor — audit log access')),
                  ],
                  onChanged: (v) =>
                      setState(() => _selectedRole = v ?? 'election_officer'),
                ),
                const SizedBox(height: 16),

                // Signature Upload
                const Text('Update Signature (Optional)',
                    style:
                        TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  onPressed: _pickSignature,
                  icon: const Icon(Icons.upload_file_outlined),
                  label: Text(_newSignatureFileName != null
                      ? 'Selected: $_newSignatureFileName'
                      : 'Choose New Signature Image'),
                ),
                const SizedBox(height: 24),

                // Actions
                Row(
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
                            padding: const EdgeInsets.symmetric(vertical: 14)),
                        child: _isSaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Text('Save Changes'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Create Committee Dialog (Search & Select Existing Member)
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

  String _mode = 'existing'; // 'existing' | 'new'
  MemberModel? _selectedMember;
  String _searchQuery = '';

  String _selectedRole = 'election_officer'; // default
  bool _isSaving = false;
  String? _error;

  // Signature pick
  Uint8List? _signatureBytes;
  String? _signatureFileName;
  static const int _maxSignatureBytes = 2 * 1024 * 1024; // 2 MB

  // Manual new user controllers
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickSignature() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpeg', 'jpg', 'png', 'gif', 'svg'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.size > _maxSignatureBytes) {
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
    if (_mode == 'existing' && _selectedMember == null) {
      setState(() => _error = 'Please search and select an existing member.');
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    if (_mode == 'new' && _passwordCtrl.text != _confirmCtrl.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }

    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      final dio = ref.read(apiClientProvider);

      final Map<String, dynamic> mapData = {
        'role': _selectedRole,
      };

      if (_mode == 'existing' && _selectedMember != null) {
        mapData['committee_type'] = 'existing';
        mapData['member_id'] = _selectedMember!.id;
        mapData['chair_email'] = _selectedMember!.email;
        mapData['committee_name'] = _selectedMember!.fullName;
      } else {
        mapData['committee_type'] = 'new';
        mapData['chair_email'] = _emailCtrl.text.trim();
        mapData['password'] = _passwordCtrl.text;
      }

      if (_signatureBytes != null) {
        mapData['chair_signature'] = MultipartFile.fromBytes(
          _signatureBytes!,
          filename: _signatureFileName ?? 'signature.png',
        );
      }

      final formData = FormData.fromMap(mapData);

      await dio.post(
        ApiConstants.electionCreateCommittee(widget.electionId),
        data: formData,
        options: Options(contentType: 'multipart/form-data'),
      );

      if (mounted) Navigator.of(context).pop(true);
    } on DioException catch (e) {
      String msg = 'Failed to create committee member.';
      if (e.response?.data is Map) {
        final data = e.response!.data as Map;
        if (data['error'] is Map && data['error']['message'] != null) {
          msg = data['error']['message'].toString();
        } else if (data['error'] is String) {
          msg = data['error'];
        } else if (data['detail'] is String) {
          msg = data['detail'];
        } else {
          msg = data.values.join(', ');
        }
      }
      if (mounted) setState(() => _error = msg);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final membersAsync = ref.watch(membersProvider);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Title bar ────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.group_add_outlined,
                      color: Colors.white, size: 22),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text('Add Election Committee Member',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
            ),

            // ── Mode Switch Tabs ─────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              color: Theme.of(context).cardColor,
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => setState(() {
                        _mode = 'existing';
                        _error = null;
                      }),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _mode == 'existing'
                              ? AppColors.primary.withValues(alpha: 0.1)
                              : Colors.transparent,
                          border: Border.all(
                            color: _mode == 'existing'
                                ? AppColors.primary
                                : Colors.grey.withValues(alpha: 0.3),
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.person_search_outlined,
                                size: 18,
                                color: _mode == 'existing'
                                    ? AppColors.primary
                                    : Colors.grey[700]),
                            const SizedBox(width: 6),
                            Text(
                              'Select Existing Member',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: _mode == 'existing'
                                    ? AppColors.primary
                                    : Colors.grey[700],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: InkWell(
                      onTap: () => setState(() {
                        _mode = 'new';
                        _error = null;
                      }),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _mode == 'new'
                              ? AppColors.primary.withValues(alpha: 0.1)
                              : Colors.transparent,
                          border: Border.all(
                            color: _mode == 'new'
                                ? AppColors.primary
                                : Colors.grey.withValues(alpha: 0.3),
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.person_add_outlined,
                                size: 18,
                                color: _mode == 'new'
                                    ? AppColors.primary
                                    : Colors.grey[700]),
                            const SizedBox(width: 6),
                            Text(
                              'Create New User',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: _mode == 'new'
                                    ? AppColors.primary
                                    : Colors.grey[700],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // ── Form body ────────────────────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Error banner
                      if (_error != null) ...[
                        Container(
                          padding: const EdgeInsets.all(10),
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
                        const SizedBox(height: 14),
                      ],

                      // MODE 1: SELECT EXISTING MEMBER
                      if (_mode == 'existing') ...[
                        const Text('Search Organization Member *',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(height: 6),

                        if (_selectedMember != null) ...[
                          // Selected Member Card
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: Colors.green.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              children: [
                                const CircleAvatar(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                  child: Icon(Icons.check, size: 20),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _selectedMember!.fullName,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${_selectedMember!.email} • #${_selectedMember!.memberCode}',
                                        style: TextStyle(
                                            color: Colors.grey[700],
                                            fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                                TextButton(
                                  onPressed: () =>
                                      setState(() => _selectedMember = null),
                                  child: const Text('Change'),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ] else ...[
                          // Search Box & Results
                          membersAsync.when(
                            loading: () => const Center(
                                child: Padding(
                              padding: EdgeInsets.all(16.0),
                              child: CircularProgressIndicator(),
                            )),
                            error: (err, _) => Text(
                              'Error loading members: $err',
                              style: const TextStyle(color: Colors.red),
                            ),
                            data: (members) {
                              final filtered = members.where((m) {
                                if (_searchQuery.trim().isEmpty) return true;
                                final q = _searchQuery.toLowerCase();
                                return m.fullName.toLowerCase().contains(q) ||
                                    m.email.toLowerCase().contains(q) ||
                                    m.memberCode.toLowerCase().contains(q);
                              }).toList();

                              return Column(
                                children: [
                                  TextFormField(
                                    decoration: InputDecoration(
                                      hintText:
                                          'Type name, email, or member code...',
                                      prefixIcon:
                                          const Icon(Icons.search_rounded),
                                      border: const OutlineInputBorder(),
                                      suffixIcon: _searchQuery.isNotEmpty
                                          ? IconButton(
                                              icon: const Icon(Icons.clear),
                                              onPressed: () => setState(
                                                  () => _searchQuery = ''),
                                            )
                                          : null,
                                    ),
                                    onChanged: (val) =>
                                        setState(() => _searchQuery = val),
                                  ),
                                  const SizedBox(height: 8),
                                  Container(
                                    height: 160,
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                          color: Colors.grey.withValues(alpha: 0.3)),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: filtered.isEmpty
                                        ? const Center(
                                            child: Text('No members found.',
                                                style: TextStyle(
                                                    color: Colors.grey)))
                                        : ListView.separated(
                                            itemCount: filtered.length,
                                            separatorBuilder: (_, _) =>
                                                const Divider(height: 1),
                                            itemBuilder: (context, index) {
                                              final m = filtered[index];
                                              return ListTile(
                                                dense: true,
                                                leading: CircleAvatar(
                                                  radius: 14,
                                                  backgroundColor:
                                                      AppColors.primary,
                                                  foregroundColor: Colors.white,
                                                  child: Text(
                                                    m.fullName.isNotEmpty
                                                        ? m.fullName[0]
                                                            .toUpperCase()
                                                        : '?',
                                                    style: const TextStyle(
                                                        fontSize: 12),
                                                  ),
                                                ),
                                                title: Text(m.fullName,
                                                    style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 13)),
                                                subtitle: Text(
                                                    '${m.email} • #${m.memberCode}',
                                                    style: const TextStyle(
                                                        fontSize: 11)),
                                                trailing: const Icon(
                                                    Icons.chevron_right_rounded,
                                                    size: 18),
                                                onTap: () {
                                                  setState(() {
                                                    _selectedMember = m;
                                                    _error = null;
                                                  });
                                                },
                                              );
                                            },
                                          ),
                                  ),
                                  const SizedBox(height: 16),
                                ],
                              );
                            },
                          ),
                        ],
                      ] else ...[
                        // MODE 2: CREATE NEW USER
                        const Text('Email Address *',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _emailCtrl,
                          decoration: const InputDecoration(
                            hintText: 'Enter official email address',
                            prefixIcon: Icon(Icons.email_outlined),
                            border: OutlineInputBorder(),
                          ),
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
                        const SizedBox(height: 14),

                        const Text('Password *',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _passwordCtrl,
                          obscureText: _obscurePassword,
                          decoration: InputDecoration(
                            hintText: 'Minimum 8 characters',
                            prefixIcon: const Icon(Icons.lock_outline),
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: Icon(_obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined),
                              onPressed: () => setState(() =>
                                  _obscurePassword = !_obscurePassword),
                            ),
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty) return 'Required';
                            if (v.length < 8) return 'Minimum 8 characters';
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),

                        const Text('Confirm Password *',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _confirmCtrl,
                          obscureText: _obscureConfirm,
                          decoration: InputDecoration(
                            hintText: 'Re-enter password',
                            prefixIcon: const Icon(Icons.lock_outline),
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: Icon(_obscureConfirm
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined),
                              onPressed: () => setState(() =>
                                  _obscureConfirm = !_obscureConfirm),
                            ),
                          ),
                          validator: (v) =>
                              (v == null || v.isEmpty) ? 'Required' : null,
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Role assignment
                      const Text('Assign Role *',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        initialValue: _selectedRole,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.admin_panel_settings_outlined),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'election_officer',
                            child: Row(
                              children: [
                                Icon(Icons.manage_accounts_outlined,
                                    size: 18, color: Colors.blue),
                                SizedBox(width: 8),
                                Text('Election Officer — manages election'),
                              ],
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'observer',
                            child: Row(
                              children: [
                                Icon(Icons.visibility_outlined,
                                    size: 18, color: Colors.orange),
                                SizedBox(width: 8),
                                Text('Observer — read-only view'),
                              ],
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'auditor',
                            child: Row(
                              children: [
                                Icon(Icons.verified_user_outlined,
                                    size: 18, color: Colors.green),
                                SizedBox(width: 8),
                                Text('Auditor — audit log access'),
                              ],
                            ),
                          ),
                        ],
                        onChanged: (v) => setState(
                            () => _selectedRole = v ?? 'election_officer'),
                      ),
                      const SizedBox(height: 16),

                      // Chair Signature upload
                      const Text('Signature Image (Optional)',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 6),
                      OutlinedButton.icon(
                        onPressed: _pickSignature,
                        icon: const Icon(Icons.upload_file_outlined),
                        label: Text(_signatureFileName != null
                            ? 'Selected: $_signatureFileName'
                            : 'Upload Signature Image (PNG/JPG)'),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── Action buttons ───────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
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
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ))
                          : const Text('Assign to Committee'),
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
}
