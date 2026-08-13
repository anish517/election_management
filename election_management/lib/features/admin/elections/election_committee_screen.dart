import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/glass_card.dart';

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
  List<dynamic> _assignments = [];

  @override
  void initState() {
    super.initState();
    _fetchAssignments();
  }

  Future<void> _fetchAssignments() async {
    setState(() => _isLoading = true);
    try {
      final dio = ref.read(apiClientProvider);
      final url = '${ApiConstants.elections}${widget.electionId}/assignments/';
      final resp = await dio.get(url);
      if (mounted) {
        final data = resp.data;
        List list;
        if (data is Map && data.containsKey('results')) {
          list = data['results'];
        } else if (data is List) {
          list = data;
        } else {
          list = [];
        }
        setState(() {
          _assignments = list;
          _isLoading = false;
        });
      }
    } on DioException catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showAssignDialog() {
    showDialog<bool>(
      context: context,
      builder: (_) => _AssignRoleDialog(electionId: widget.electionId),
    ).then((assigned) {
      if (assigned == true) _fetchAssignments();
    });
  }

  IconData _roleIcon(String role) {
    switch (role) {
      case 'election_officer':
        return Icons.admin_panel_settings_outlined;
      case 'observer':
        return Icons.visibility_outlined;
      case 'auditor':
        return Icons.fact_check_outlined;
      default:
        return Icons.person_outlined;
    }
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'election_officer':
        return 'Election Officer';
      case 'observer':
        return 'Observer';
      case 'auditor':
        return 'Auditor';
      default:
        return role;
    }
  }

  Color _roleColor(String role) {
    switch (role) {
      case 'election_officer':
        return AppColors.primary;
      case 'observer':
        return Colors.teal;
      case 'auditor':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Election Committee',
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Manage committee members and their roles for this election.',
                        style: TextStyle(
                          color:
                              Theme.of(context).textTheme.bodySmall?.color,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                  ElevatedButton.icon(
                    onPressed: _showAssignDialog,
                    icon: const Icon(Icons.person_add_outlined),
                    label: const Text('Assign Role'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 16),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              if (_isLoading)
                const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_assignments.isEmpty)
                const Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.group_outlined,
                            size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          'No committee members yet.',
                          style:
                              TextStyle(fontSize: 18, color: Colors.grey),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Assign election officers, observers, or auditors to get started.',
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
                    itemCount: _assignments.length,
                    itemBuilder: (context, index) {
                      final a = _assignments[index];
                      final role = a['role']?.toString() ?? '';
                      final email = a['user']?['email']?.toString() ?? 'Unknown';
                      final roleColor = _roleColor(role);
                      return GlassCard(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: roleColor.withValues(alpha: 0.15),
                            child: Icon(_roleIcon(role),
                                color: roleColor, size: 22),
                          ),
                          title: Text(
                            email,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: roleColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: roleColor.withValues(alpha: 0.3)),
                            ),
                            child: Text(
                              _roleLabel(role),
                              style: TextStyle(
                                color: roleColor,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
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
    );
  }
}

class _AssignRoleDialog extends ConsumerStatefulWidget {
  final String electionId;
  const _AssignRoleDialog({required this.electionId});

  @override
  ConsumerState<_AssignRoleDialog> createState() => _AssignRoleDialogState();
}

class _AssignRoleDialogState extends ConsumerState<_AssignRoleDialog> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  String _selectedRole = 'election_officer';
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      final dio = ref.read(apiClientProvider);
      await dio.post(
        '${ApiConstants.elections}${widget.electionId}/assign_role/',
        data: {
          'email': _emailController.text.trim(),
          'role': _selectedRole,
        },
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      String msg = 'Assignment failed';
      if (e is DioException && e.response?.data is Map) {
        final errData = e.response?.data['error'];
        if (errData is String) {
          msg = errData;
        } else if (errData is Map && errData['message'] != null) {
          msg = errData['message'].toString();
        }
      }
      if (mounted) setState(() => _errorMessage = msg);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Assign Role'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_errorMessage != null)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_errorMessage!,
                          style: const TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              ),
            TextFormField(
              controller: _emailController,
              decoration:
                  const InputDecoration(labelText: 'User Email', border: OutlineInputBorder()),
              keyboardType: TextInputType.emailAddress,
              validator: (v) => v == null || v.isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(
                  labelText: 'Role', border: OutlineInputBorder()),
              value: _selectedRole,
              items: const [
                DropdownMenuItem(
                    value: 'election_officer',
                    child: Text('Election Officer')),
                DropdownMenuItem(
                    value: 'observer', child: Text('Observer')),
                DropdownMenuItem(
                    value: 'auditor', child: Text('Auditor')),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _selectedRole = val);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isSubmitting ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
          child: _isSubmitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Assign'),
        ),
      ],
    );
  }
}
