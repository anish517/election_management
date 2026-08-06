import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_constants.dart';
import '../../../shared/widgets/loading_button.dart';

class AssignOfficerDialog extends ConsumerStatefulWidget {
  final String electionId;
  const AssignOfficerDialog({super.key, required this.electionId});

  @override
  ConsumerState<AssignOfficerDialog> createState() => _AssignOfficerDialogState();
}

class _AssignOfficerDialogState extends ConsumerState<AssignOfficerDialog> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  String _selectedRole = 'election_officer';
  bool _isSubmitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    try {
      final dio = ref.read(apiClientProvider);
      await dio.post('${ApiConstants.elections}${widget.electionId}/assign_role/', data: {
        'email': _emailController.text.trim(),
        'role': _selectedRole,
      });

      if (mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Role assigned successfully!')),
        );
      }
    } on DioException catch (e) {
      final msg = (e.response?.data is Map)
          ? e.response?.data['error'] ?? 'Assignment failed'
          : 'Assignment failed';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
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
            TextFormField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'User Email'),
              keyboardType: TextInputType.emailAddress,
              validator: (v) => v == null || v.isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: 'Role'),
              value: _selectedRole,
              items: const [
                DropdownMenuItem(value: 'election_officer', child: Text('Election Officer')),
                DropdownMenuItem(value: 'observer', child: Text('Observer')),
                DropdownMenuItem(value: 'auditor', child: Text('Auditor')),
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
          onPressed: () => context.pop(),
          child: const Text('Cancel'),
        ),
        LoadingButton(
          onPressed: _submit,
          isLoading: _isSubmitting,
          label: 'Assign',
        ),
      ],
    );
  }
}
