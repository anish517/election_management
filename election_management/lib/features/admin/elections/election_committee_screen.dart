import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_constants.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/loading_button.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Main Election Committee Screen
// ─────────────────────────────────────────────────────────────────────────────
class ElectionCommitteeScreen extends ConsumerStatefulWidget {
  final String electionId;
  final bool? showAppBar;

  const ElectionCommitteeScreen({
    super.key,
    required this.electionId,
    this.showAppBar,
  });

  @override
  ConsumerState<ElectionCommitteeScreen> createState() => _ElectionCommitteeScreenState();
}

class _ElectionCommitteeScreenState extends ConsumerState<ElectionCommitteeScreen> {
  bool _isLoading = true;
  List<dynamic> _committees = [];
  String _searchQuery = '';
  String _roleFilter = 'all'; // 'all', 'election_officer', 'observer', 'auditor'

  @override
  void initState() {
    super.initState();
    _fetchCommittees();
  }

  Future<void> _fetchCommittees() async {
    setState(() => _isLoading = true);
    try {
      final dio = ref.read(apiClientProvider);
      final resp = await dio.get(ApiConstants.electionCommittees(widget.electionId));
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
      builder: (_) => _CreateCommitteeDialog(electionId: widget.electionId),
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
        return const Color(0xFF4F46E5); // Indigo
      case 'observer':
        return Colors.orange.shade700;
      case 'auditor':
        return const Color(0xFF10B981); // Emerald
      default:
        return Colors.blueGrey;
    }
  }

  IconData _roleIcon(String? role) {
    switch (role) {
      case 'election_officer':
        return Icons.admin_panel_settings_rounded;
      case 'observer':
        return Icons.visibility_rounded;
      case 'auditor':
        return Icons.verified_user_rounded;
      default:
        return Icons.group_rounded;
    }
  }

  String _roleLabel(String? role) {
    switch (role) {
      case 'election_officer':
        return 'Election Officer (अधिकृत)';
      case 'observer':
        return 'Independent Observer (पर्यवेक्षक)';
      case 'auditor':
        return 'Auditor (लेखापरीक्षक)';
      default:
        return role ?? 'Committee Member';
    }
  }

  String _displayName(Map<String, dynamic> c) {
    final fullName = c['chair_full_name']?.toString();
    if (fullName != null && fullName.trim().isNotEmpty) return fullName.trim();
    final name = c['committee_name']?.toString();
    if (name != null && name.trim().isNotEmpty) return name.trim();
    return c['chair_email']?.toString() ?? 'Committee Member';
  }

  Future<void> _confirmDelete(Map<String, dynamic> c) async {
    final name = _displayName(c);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.delete_outline_rounded, color: Colors.red),
            SizedBox(width: 10),
            Text('Remove Committee Member?'),
          ],
        ),
        content: Text('Are you sure you want to remove "$name" from this election committee?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Remove Member'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      final dio = ref.read(apiClientProvider);
      await dio.delete(ApiConstants.electionDeleteCommittee(widget.electionId, c['id'].toString()));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.white),
                SizedBox(width: 10),
                Text('Committee member removed successfully.'),
              ],
            ),
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
        _fetchCommittees();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to delete committee member.'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final canPop = Navigator.of(context).canPop();
    final shouldShowAppBar = widget.showAppBar ?? canPop;

    // Filter by role and search
    final filtered = _committees.where((item) {
      final map = item as Map<String, dynamic>;
      final role = (map['role'] ?? '').toString();
      final name = _displayName(map).toLowerCase();
      final email = (map['chair_email'] ?? '').toString().toLowerCase();
      final memberCode = (map['chair_member_code'] ?? '').toString().toLowerCase();

      if (_roleFilter != 'all' && role != _roleFilter) return false;

      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        return name.contains(q) || email.contains(q) || memberCode.contains(q);
      }
      return true;
    }).toList();

    Widget bodyWidget = _isLoading
        ? const Center(child: CircularProgressIndicator())
        : SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header & Action Bar
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Election Committee (निर्वाचन समिति)',
                                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Assign Election Officers, Observers, and Auditors to administer this election.',
                                style: TextStyle(color: isDark ? Colors.white60 : AppColors.textMuted, fontSize: 13),
                              ),
                            ],
                          ),
                          FilledButton.icon(
                            onPressed: _showCreateDialog,
                            icon: const Icon(Icons.person_add_rounded, size: 18),
                            label: const Text('Add Member'),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF4F46E5),
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),

                      // Search & Role Filter Bar
                      Material(
                        color: isDark ? AppColors.surfaceVariant.withValues(alpha: 0.3) : Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade200),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  decoration: InputDecoration(
                                    hintText: 'Search by name, email, or member code...',
                                    hintStyle: const TextStyle(fontSize: 13),
                                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    filled: true,
                                    fillColor: isDark ? AppColors.surfaceVariant : const Color(0xFFF9FAFB),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade300),
                                    ),
                                  ),
                                  onChanged: (v) => setState(() => _searchQuery = v),
                                ),
                              ),
                              const SizedBox(width: 16),
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Wrap(
                                  spacing: 8,
                                  children: [
                                    ChoiceChip(
                                      label: Text('All (${_committees.length})', style: const TextStyle(fontSize: 12)),
                                      selected: _roleFilter == 'all',
                                      onSelected: (val) => setState(() => _roleFilter = 'all'),
                                    ),
                                    ChoiceChip(
                                      label: Text('Officers (${_committees.where((c) => c['role'] == 'election_officer').length})', style: const TextStyle(fontSize: 12)),
                                      selected: _roleFilter == 'election_officer',
                                      selectedColor: const Color(0xFF4F46E5).withValues(alpha: 0.18),
                                      onSelected: (val) => setState(() => _roleFilter = 'election_officer'),
                                    ),
                                    ChoiceChip(
                                      label: Text('Observers (${_committees.where((c) => c['role'] == 'observer').length})', style: const TextStyle(fontSize: 12)),
                                      selected: _roleFilter == 'observer',
                                      selectedColor: Colors.orange.withValues(alpha: 0.18),
                                      onSelected: (val) => setState(() => _roleFilter = 'observer'),
                                    ),
                                    ChoiceChip(
                                      label: Text('Auditors (${_committees.where((c) => c['role'] == 'auditor').length})', style: const TextStyle(fontSize: 12)),
                                      selected: _roleFilter == 'auditor',
                                      selectedColor: Colors.green.withValues(alpha: 0.18),
                                      onSelected: (val) => setState(() => _roleFilter = 'auditor'),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.refresh_rounded),
                                tooltip: 'Refresh List',
                                onPressed: _fetchCommittees,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Member Cards List
                      Expanded(
                        child: filtered.isEmpty
                            ? Center(
                                child: Container(
                                  padding: const EdgeInsets.all(36),
                                  decoration: BoxDecoration(
                                    color: isDark ? AppColors.surface : Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade200),
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          color: AppColors.primary.withValues(alpha: 0.1),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(Icons.group_outlined, size: 48, color: AppColors.primaryLight),
                                      ),
                                      const SizedBox(height: 16),
                                      const Text('No Committee Members Found', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Assign election officers, independent observers, or auditors to manage and monitor this election.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(fontSize: 13, color: isDark ? Colors.white60 : Colors.grey.shade600),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : ListView.builder(
                                itemCount: filtered.length,
                                itemBuilder: (context, i) {
                                  final c = filtered[i];
                                  final role = c['role']?.toString();
                                  final signatureUrl = c['chair_signature'] != null
                                      ? ApiConstants.getFullImageUrl(c['chair_signature'].toString())
                                      : null;
                                  final roleColor = _roleColor(role);
                                  final memberCode = c['chair_member_code']?.toString() ?? '';
                                  final name = _displayName(c);
                                  final email = c['chair_email']?.toString() ?? '';

                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 14),
                                    decoration: BoxDecoration(
                                      color: isDark ? AppColors.surface : Colors.white,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: isDark ? AppColors.surfaceVariant : Colors.grey.shade200),
                                      boxShadow: [
                                        if (!isDark)
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.03),
                                            blurRadius: 10,
                                            offset: const Offset(0, 3),
                                          ),
                                      ],
                                    ),
                                    child: InkWell(
                                      onTap: () => _showViewSheet(c),
                                      borderRadius: BorderRadius.circular(16),
                                      child: Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.center,
                                          children: [
                                            // Avatar / Signature Icon
                                            Container(
                                              width: 54,
                                              height: 54,
                                              decoration: BoxDecoration(
                                                color: roleColor.withValues(alpha: 0.12),
                                                borderRadius: BorderRadius.circular(12),
                                                border: Border.all(color: roleColor.withValues(alpha: 0.25)),
                                              ),
                                              child: ClipRRect(
                                                borderRadius: BorderRadius.circular(11),
                                                child: signatureUrl != null
                                                    ? Image.network(
                                                        signatureUrl,
                                                        fit: BoxFit.cover,
                                                        errorBuilder: (ctx, err, stack) => Icon(_roleIcon(role), size: 26, color: roleColor),
                                                      )
                                                    : Icon(_roleIcon(role), size: 26, color: roleColor),
                                              ),
                                            ),
                                            const SizedBox(width: 16),

                                            // Details
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Text(
                                                        name,
                                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                                      ),
                                                      if (memberCode.isNotEmpty) ...[
                                                        const SizedBox(width: 8),
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                                          decoration: BoxDecoration(
                                                            color: isDark ? Colors.white10 : const Color(0xFFF1F5F9),
                                                            borderRadius: BorderRadius.circular(6),
                                                          ),
                                                          child: Text(
                                                            '#$memberCode',
                                                            style: TextStyle(
                                                              fontSize: 11,
                                                              fontWeight: FontWeight.bold,
                                                              color: isDark ? Colors.white70 : Colors.blueGrey.shade800,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                  const SizedBox(height: 3),
                                                  Row(
                                                    children: [
                                                      Icon(Icons.email_outlined, size: 13, color: isDark ? Colors.white54 : AppColors.textMuted),
                                                      const SizedBox(width: 5),
                                                      Text(
                                                        email,
                                                        style: TextStyle(fontSize: 12.5, color: isDark ? Colors.white60 : Colors.grey.shade600),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 6),
                                                  // Designation & Role Badges
                                                  Wrap(
                                                    spacing: 8,
                                                    runSpacing: 4,
                                                    children: [
                                                      // Designation Badge
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                        decoration: BoxDecoration(
                                                          color: const Color(0xFF0284C7).withValues(alpha: 0.12),
                                                          borderRadius: BorderRadius.circular(6),
                                                          border: Border.all(color: const Color(0xFF0284C7).withValues(alpha: 0.3)),
                                                        ),
                                                        child: Row(
                                                          mainAxisSize: MainAxisSize.min,
                                                          children: [
                                                            const Icon(Icons.workspace_premium_rounded, size: 12, color: Color(0xFF0284C7)),
                                                            const SizedBox(width: 5),
                                                            Text(
                                                              (c['chair_designation']?.toString().isNotEmpty == true)
                                                                  ? c['chair_designation'].toString()
                                                                  : 'Committee Member',
                                                              style: const TextStyle(fontSize: 11, color: Color(0xFF0284C7), fontWeight: FontWeight.bold),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                      // System Role Badge Pill
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                        decoration: BoxDecoration(
                                                          color: roleColor.withValues(alpha: 0.12),
                                                          borderRadius: BorderRadius.circular(6),
                                                          border: Border.all(color: roleColor.withValues(alpha: 0.3)),
                                                        ),
                                                        child: Row(
                                                          mainAxisSize: MainAxisSize.min,
                                                          children: [
                                                            Icon(_roleIcon(role), size: 12, color: roleColor),
                                                            const SizedBox(width: 5),
                                                            Text(
                                                              _roleLabel(role),
                                                              style: TextStyle(fontSize: 11, color: roleColor, fontWeight: FontWeight.bold),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),

                                            // Action Popup Menu
                                            PopupMenuButton<String>(
                                              icon: const Icon(Icons.more_vert_rounded, size: 20),
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                              onSelected: (val) {
                                                if (val == 'view') {
                                                  _showViewSheet(c);
                                                } else if (val == 'edit') {
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
                                                  value: 'view',
                                                  child: Row(
                                                    children: [
                                                      Icon(Icons.badge_outlined, size: 18),
                                                      SizedBox(width: 10),
                                                      Text('View Member Dossier'),
                                                    ],
                                                  ),
                                                ),
                                                const PopupMenuItem(
                                                  value: 'edit',
                                                  child: Row(
                                                    children: [
                                                      Icon(Icons.edit_outlined, size: 18, color: Colors.indigo),
                                                      SizedBox(width: 10),
                                                      Text('Edit Role / Signature'),
                                                    ],
                                                  ),
                                                ),
                                                const PopupMenuItem(
                                                  value: 'delete',
                                                  child: Row(
                                                    children: [
                                                      Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red),
                                                      SizedBox(width: 10),
                                                      Text('Remove Member', style: TextStyle(color: Colors.red)),
                                                    ],
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
                    ],
                  ),
                ),
              ),
            ),
          );

    if (shouldShowAppBar) {
      return Scaffold(
        backgroundColor: isDark ? AppColors.background : const Color(0xFFF8FAFC),
        appBar: AppBar(
          title: const Text('Election Committee (निर्वाचन समिति)'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            tooltip: 'Back',
            onPressed: () {
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              } else {
                context.go('/dashboard');
              }
            },
          ),
        ),
        body: bodyWidget,
      );
    }

    return Container(
      color: isDark ? AppColors.background : const Color(0xFFF8FAFC),
      child: bodyWidget,
    );
  }
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = committee;
    final signatureUrl = c['chair_signature'] != null
        ? ApiConstants.getFullImageUrl(c['chair_signature'].toString())
        : null;
    final role = c['role']?.toString();

    Color roleColor(String? r) {
      switch (r) {
        case 'election_officer':
          return const Color(0xFF4F46E5);
        case 'observer':
          return Colors.orange.shade700;
        case 'auditor':
          return const Color(0xFF10B981);
        default:
          return Colors.blueGrey;
      }
    }

    String roleLabel(String? r) {
      switch (r) {
        case 'election_officer':
          return 'Election Officer (अधिकृत)';
        case 'observer':
          return 'Independent Observer (पर्यवेक्षक)';
        case 'auditor':
          return 'Auditor (लेखापरीक्षक)';
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
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (_, ctrl) => Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.surface : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Handle Bar
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Row(
                children: [
                  const Text('Committee Member Dossier', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Edit Role'),
                    onPressed: () {
                      Navigator.pop(context);
                      showDialog<bool>(
                        context: context,
                        builder: (_) => _EditCommitteeDialog(committee: c, electionId: electionId),
                      ).then((ok) {
                        if (ok == true) onEdited();
                      });
                    },
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            Expanded(
              child: ListView(
                controller: ctrl,
                padding: const EdgeInsets.all(24),
                children: [
                  // Designation & Role Badges
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0284C7).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF0284C7).withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.workspace_premium_rounded, size: 14, color: Color(0xFF0284C7)),
                            const SizedBox(width: 6),
                            Text(
                              (c['chair_designation']?.toString().isNotEmpty == true)
                                  ? c['chair_designation'].toString()
                                  : 'Committee Member',
                              style: const TextStyle(color: Color(0xFF0284C7), fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: roleColor(role).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: roleColor(role).withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          roleLabel(role),
                          style: TextStyle(color: roleColor(role), fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  _infoTile(context, Icons.workspace_premium_rounded, 'Committee Designation (समिति पद)', (c['chair_designation']?.toString().isNotEmpty == true) ? c['chair_designation'].toString() : 'Committee Member'),
                  _infoTile(context, Icons.person_outline_rounded, 'Full Legal Name', displayName()),
                  _infoTile(context, Icons.email_outlined, 'Official Email', c['chair_email'] ?? '-'),
                  if ((c['chair_contact']?.toString() ?? '').isNotEmpty)
                    _infoTile(context, Icons.phone_outlined, 'Contact Phone Number', c['chair_contact'].toString()),
                  if ((c['chair_member_code'] ?? '').isNotEmpty)
                    _infoTile(context, Icons.badge_outlined, 'Organization Member Code', '#${c['chair_member_code']}'),

                  const SizedBox(height: 16),
                  const Text('Official Signature Record', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    height: 120,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade300),
                    ),
                    child: signatureUrl != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(
                              signatureUrl,
                              fit: BoxFit.contain,
                              errorBuilder: (ctx, err, stack) => const Center(child: Text('Signature Image Unavailable')),
                            ),
                          )
                        : const Center(
                            child: Text('No digital signature uploaded on file.', style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
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

  Widget _infoTile(BuildContext context, IconData icon, String label, String value) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceVariant.withValues(alpha: 0.3) : const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.primaryLight),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : AppColors.textMuted)),
              const SizedBox(height: 2),
              Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Edit Committee Dialog
// ─────────────────────────────────────────────────────────────────────────────
class _EditCommitteeDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic> committee;
  final String electionId;
  const _EditCommitteeDialog({required this.committee, required this.electionId});

  @override
  ConsumerState<_EditCommitteeDialog> createState() => _EditCommitteeDialogState();
}

class _EditCommitteeDialogState extends ConsumerState<_EditCommitteeDialog> {
  final _formKey = GlobalKey<FormState>();
  late String _selectedRole;
  late TextEditingController _designationCtrl;
  late TextEditingController _contactCtrl;
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
    _designationCtrl = TextEditingController(
      text: (c['chair_designation']?.toString().isNotEmpty == true)
          ? c['chair_designation'].toString()
          : 'Committee Member',
    );
    _contactCtrl = TextEditingController(
      text: c['chair_contact']?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _designationCtrl.dispose();
    _contactCtrl.dispose();
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
      final patchData = <String, dynamic>{
        'role': _selectedRole,
        'chair_designation': _designationCtrl.text.trim(),
        'chair_contact': _contactCtrl.text.trim(),
      };

      if (_newSignatureBytes != null) {
        final formData = FormData.fromMap({
          ...patchData,
          'chair_signature': MultipartFile.fromBytes(
            _newSignatureBytes!,
            filename: _newSignatureFileName ?? 'signature.png',
          ),
        });
        await dio.patch(
          ApiConstants.electionUpdateCommittee(widget.electionId, widget.committee['id'].toString()),
          data: formData,
          options: Options(contentType: 'multipart/form-data'),
        );
      } else {
        await dio.patch(
          ApiConstants.electionUpdateCommittee(widget.electionId, widget.committee['id'].toString()),
          data: patchData,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = widget.committee;
    final fullName = c['chair_full_name']?.toString() ?? c['chair_email']?.toString() ?? '';

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Row(
        children: [
          Icon(Icons.edit_outlined, size: 22, color: AppColors.primaryLight),
          SizedBox(width: 10),
          Text('Edit Committee Assignment', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Member Info summary card
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
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
                            Text(fullName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            Text(c['chair_email'] ?? '', style: TextStyle(color: isDark ? Colors.white60 : Colors.grey.shade600, fontSize: 12)),
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
                      border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                    ),
                    child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12.5, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 14),
                ],

                // Committee Designation Field
                const Text('Committee Designation / पद *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _designationCtrl,
                  decoration: InputDecoration(
                    hintText: 'e.g. Chairperson, Secretary, Member',
                    prefixIcon: const Icon(Icons.workspace_premium_outlined),
                    filled: true,
                    fillColor: isDark ? AppColors.surfaceVariant : const Color(0xFFF9FAFB),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Designation is required' : null,
                ),
                const SizedBox(height: 8),

                // Quick Suggestion Chips for Designation
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _quickChip('Chairperson (अध्यक्ष)', isDark),
                      const SizedBox(width: 6),
                      _quickChip('Secretary (सदस्य सचिव)', isDark),
                      const SizedBox(width: 6),
                      _quickChip('Senior Officer (वरिष्ठ अधिकृत)', isDark),
                      const SizedBox(width: 6),
                      _quickChip('Member (सदस्य)', isDark),
                      const SizedBox(width: 6),
                      _quickChip('Legal Advisor (कानुनी सल्लाहकार)', isDark),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Contact Phone Field
                const Text('Contact Phone (Optional)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _contactCtrl,
                  decoration: InputDecoration(
                    hintText: 'e.g. 98XXXXXXXX',
                    prefixIcon: const Icon(Icons.phone_outlined),
                    filled: true,
                    fillColor: isDark ? AppColors.surfaceVariant : const Color(0xFFF9FAFB),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 16),

                // Role Selector
                const Text('Assigned System Role *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: _selectedRole,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.admin_panel_settings_outlined),
                    filled: true,
                    fillColor: isDark ? AppColors.surfaceVariant : const Color(0xFFF9FAFB),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'election_officer',
                      child: Text('Election Officer — manages voting & candidates'),
                    ),
                    DropdownMenuItem(
                      value: 'observer',
                      child: Text('Independent Observer — monitor-only'),
                    ),
                    DropdownMenuItem(
                      value: 'auditor',
                      child: Text('Auditor — audit logs & hash proofs'),
                    ),
                  ],
                  onChanged: (v) => setState(() => _selectedRole = v ?? 'election_officer'),
                ),
                const SizedBox(height: 16),

                // Signature Upload
                const Text('Update Signature (Optional)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  onPressed: _pickSignature,
                  icon: const Icon(Icons.upload_file_outlined),
                  label: Text(_newSignatureFileName != null ? 'Selected: $_newSignatureFileName' : 'Choose New Signature File'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        LoadingButton(
          isLoading: _isSaving,
          label: 'Save Changes',
          icon: Icons.check_rounded,
          onPressed: _submit,
          fullWidth: false,
        ),
      ],
    );
  }

  Widget _quickChip(String label, bool isDark) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      backgroundColor: isDark ? Colors.white10 : const Color(0xFFF1F5F9),
      side: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade300),
      onPressed: () {
        setState(() {
          _designationCtrl.text = label.split(' (')[0];
        });
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Create Committee Dialog (Search & Select Existing Member OR Create User)
// ─────────────────────────────────────────────────────────────────────────────
class _CreateCommitteeDialog extends ConsumerStatefulWidget {
  final String electionId;
  const _CreateCommitteeDialog({required this.electionId});

  @override
  ConsumerState<_CreateCommitteeDialog> createState() => _CreateCommitteeDialogState();
}

class _CreateCommitteeDialogState extends ConsumerState<_CreateCommitteeDialog> {
  final _formKey = GlobalKey<FormState>();

  String _mode = 'existing'; // 'existing' | 'new'
  MemberModel? _selectedMember;
  String _searchQuery = '';

  String _selectedRole = 'election_officer';
  final _designationCtrl = TextEditingController(text: 'Committee Member');
  final _contactCtrl = TextEditingController();
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
    _designationCtrl.dispose();
    _contactCtrl.dispose();
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
      setState(() => _error = 'Please search and select an existing member from the roster.');
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
        'chair_designation': _designationCtrl.text.trim().isNotEmpty
            ? _designationCtrl.text.trim()
            : 'Committee Member',
        'chair_contact': _contactCtrl.text.trim(),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final membersAsync = ref.watch(membersProvider);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Row(
        children: [
          Icon(Icons.group_add_rounded, color: AppColors.primaryLight, size: 22),
          SizedBox(width: 10),
          Text('Add Election Committee Member', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        ],
      ),
      content: SizedBox(
        width: 580,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Mode Switch Tabs
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => setState(() {
                        _mode = 'existing';
                        _error = null;
                      }),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _mode == 'existing' ? AppColors.primary.withValues(alpha: 0.12) : Colors.transparent,
                          border: Border.all(
                            color: _mode == 'existing' ? AppColors.primary : (isDark ? Colors.white12 : Colors.grey.shade300),
                            width: 1.5,
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.person_search_rounded, size: 18, color: _mode == 'existing' ? AppColors.primaryLight : AppColors.textMuted),
                            const SizedBox(width: 6),
                            Text(
                              'Select Member',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: _mode == 'existing' ? AppColors.primaryLight : (isDark ? Colors.white70 : Colors.grey.shade700),
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
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _mode == 'new' ? AppColors.primary.withValues(alpha: 0.12) : Colors.transparent,
                          border: Border.all(
                            color: _mode == 'new' ? AppColors.primary : (isDark ? Colors.white12 : Colors.grey.shade300),
                            width: 1.5,
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.person_add_rounded, size: 18, color: _mode == 'new' ? AppColors.primaryLight : AppColors.textMuted),
                            const SizedBox(width: 6),
                            Text(
                              'Create New User',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: _mode == 'new' ? AppColors.primaryLight : (isDark ? Colors.white70 : Colors.grey.shade700),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded, color: Colors.red, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12.5, fontWeight: FontWeight.bold))),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],

              Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // MODE 1: SELECT EXISTING MEMBER
                    if (_mode == 'existing') ...[
                      const Text('Search Organization Member *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 6),

                      if (_selectedMember != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
                          ),
                          child: Row(
                            children: [
                              const CircleAvatar(
                                backgroundColor: Color(0xFF10B981),
                                foregroundColor: Colors.white,
                                child: Icon(Icons.check_rounded, size: 20),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(_selectedMember!.fullName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${_selectedMember!.email} • #${_selectedMember!.memberCode}',
                                      style: TextStyle(color: isDark ? Colors.white60 : Colors.grey.shade700, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                              TextButton(
                                onPressed: () => setState(() => _selectedMember = null),
                                child: const Text('Change'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ] else ...[
                        membersAsync.when(
                          loading: () => const Center(
                            child: Padding(
                              padding: EdgeInsets.all(16.0),
                              child: CircularProgressIndicator(),
                            ),
                          ),
                          error: (err, _) => Text('Error loading members: $err', style: const TextStyle(color: Colors.red)),
                          data: (members) {
                            final filteredMembers = members.where((m) {
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
                                    hintText: 'Type name, email, or member code...',
                                    prefixIcon: const Icon(Icons.search_rounded),
                                    filled: true,
                                    fillColor: isDark ? AppColors.surfaceVariant : const Color(0xFFF9FAFB),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                    suffixIcon: _searchQuery.isNotEmpty
                                        ? IconButton(
                                            icon: const Icon(Icons.clear_rounded),
                                            onPressed: () => setState(() => _searchQuery = ''),
                                          )
                                        : null,
                                  ),
                                  onChanged: (val) => setState(() => _searchQuery = val),
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  height: 160,
                                  decoration: BoxDecoration(
                                    border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade300),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: filteredMembers.isEmpty
                                      ? const Center(child: Text('No members found.', style: TextStyle(color: AppColors.textMuted)))
                                      : ListView.separated(
                                          itemCount: filteredMembers.length,
                                          separatorBuilder: (_, _) => const Divider(height: 1),
                                          itemBuilder: (context, index) {
                                              final m = filteredMembers[index];
                                              return ListTile(
                                                dense: true,
                                                leading: CircleAvatar(
                                                  radius: 14,
                                                  backgroundColor: AppColors.primary,
                                                  foregroundColor: Colors.white,
                                                  child: Text(
                                                    m.fullName.isNotEmpty ? m.fullName[0].toUpperCase() : '?',
                                                    style: const TextStyle(fontSize: 12),
                                                  ),
                                                ),
                                                title: Text(m.fullName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                                subtitle: Text('${m.email} • #${m.memberCode}', style: const TextStyle(fontSize: 11)),
                                                trailing: const Icon(Icons.chevron_right_rounded, size: 18),
                                                onTap: () {
                                                  setState(() {
                                                    _selectedMember = m;
                                                    if (m.positionTitle.isNotEmpty) {
                                                      _designationCtrl.text = m.positionTitle;
                                                    }
                                                    if (m.phone.isNotEmpty) {
                                                      _contactCtrl.text = m.phone;
                                                    }
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
                      const Text('Official Email Address *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _emailCtrl,
                        decoration: InputDecoration(
                          hintText: 'e.g. officer@election.org',
                          prefixIcon: const Icon(Icons.email_outlined),
                          filled: true,
                          fillColor: isDark ? AppColors.surfaceVariant : const Color(0xFFF9FAFB),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        keyboardType: TextInputType.emailAddress,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Required';
                          if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(v.trim())) return 'Enter a valid email';
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),

                      const Text('Set Password *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _passwordCtrl,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          hintText: 'Minimum 8 characters',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          filled: true,
                          fillColor: isDark ? AppColors.surfaceVariant : const Color(0xFFF9FAFB),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          suffixIcon: IconButton(
                            icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                          ),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Required';
                          if (v.length < 8) return 'Minimum 8 characters';
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),

                      const Text('Confirm Password *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _confirmCtrl,
                        obscureText: _obscureConfirm,
                        decoration: InputDecoration(
                          hintText: 'Re-enter password',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          filled: true,
                          fillColor: isDark ? AppColors.surfaceVariant : const Color(0xFFF9FAFB),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          suffixIcon: IconButton(
                            icon: Icon(_obscureConfirm ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                            onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                          ),
                        ),
                        validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Committee Designation Field
                    const Text('Committee Designation / पद *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _designationCtrl,
                      decoration: InputDecoration(
                        hintText: 'e.g. Chairperson, Secretary, Member',
                        prefixIcon: const Icon(Icons.workspace_premium_outlined),
                        filled: true,
                        fillColor: isDark ? AppColors.surfaceVariant : const Color(0xFFF9FAFB),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Designation is required' : null,
                    ),
                    const SizedBox(height: 8),

                    // Quick Suggestion Chips for Designation
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _quickChip('Chairperson (अध्यक्ष)', isDark),
                          const SizedBox(width: 6),
                          _quickChip('Secretary (सदस्य सचिव)', isDark),
                          const SizedBox(width: 6),
                          _quickChip('Senior Officer (वरिष्ठ अधिकृत)', isDark),
                          const SizedBox(width: 6),
                          _quickChip('Member (सदस्य)', isDark),
                          const SizedBox(width: 6),
                          _quickChip('Legal Advisor (कानुनी सल्लाहकार)', isDark),
                          const SizedBox(width: 6),
                          _quickChip('Observer (पर्यवेक्षक)', isDark),
                          const SizedBox(width: 6),
                          _quickChip('Auditor (लेखापरीक्षक)', isDark),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Contact Phone Field
                    const Text('Contact Phone (Optional)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _contactCtrl,
                      decoration: InputDecoration(
                        hintText: 'e.g. 98XXXXXXXX',
                        prefixIcon: const Icon(Icons.phone_outlined),
                        filled: true,
                        fillColor: isDark ? AppColors.surfaceVariant : const Color(0xFFF9FAFB),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Role assignment
                    const Text('Assign System Role *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedRole,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: isDark ? AppColors.surfaceVariant : const Color(0xFFF9FAFB),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        prefixIcon: const Icon(Icons.admin_panel_settings_outlined),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'election_officer',
                          child: Text('Election Officer — manages election'),
                        ),
                        DropdownMenuItem(
                          value: 'observer',
                          child: Text('Independent Observer — monitor-only'),
                        ),
                        DropdownMenuItem(
                          value: 'auditor',
                          child: Text('Auditor — audit logs & proofs'),
                        ),
                      ],
                      onChanged: (v) => setState(() => _selectedRole = v ?? 'election_officer'),
                    ),
                    const SizedBox(height: 16),

                    // Signature upload
                    const Text('Signature Image (Optional)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 6),
                    OutlinedButton.icon(
                      onPressed: _pickSignature,
                      icon: const Icon(Icons.upload_file_outlined),
                      label: Text(_signatureFileName != null ? 'Selected: $_signatureFileName' : 'Upload Signature Image (PNG/JPG)'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        LoadingButton(
          isLoading: _isSaving,
          label: 'Assign to Committee',
          icon: Icons.check_rounded,
          onPressed: _submit,
          fullWidth: false,
        ),
      ],
    );
  }

  Widget _quickChip(String label, bool isDark) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      backgroundColor: isDark ? Colors.white10 : const Color(0xFFF1F5F9),
      side: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade300),
      onPressed: () {
        setState(() {
          _designationCtrl.text = label.split(' (')[0];
        });
      },
    );
  }
}
