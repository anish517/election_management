import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_constants.dart';
import '../../../core/providers/app_providers.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/loading_button.dart';
import '../../../core/theme/app_theme.dart';

class EditMemberDialog extends ConsumerStatefulWidget {
  final MemberModel member;
  const EditMemberDialog({super.key, required this.member});

  @override
  ConsumerState<EditMemberDialog> createState() => _EditMemberDialogState();
}

class _EditMemberDialogState extends ConsumerState<EditMemberDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _emailController;
  late TextEditingController _memberCodeController;
  late TextEditingController _phoneController;
  late TextEditingController _departmentController;
  late TextEditingController _regionController;
  late TextEditingController _positionTitleController;
  late TextEditingController _votingWeightController;
  late String _membershipStatus;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.member.fullName);
    _emailController = TextEditingController(text: widget.member.email);
    _memberCodeController = TextEditingController(text: widget.member.memberCode);
    _phoneController = TextEditingController(text: widget.member.phone);
    _departmentController = TextEditingController(text: widget.member.department);
    _regionController = TextEditingController(text: widget.member.region);
    _positionTitleController = TextEditingController(text: widget.member.positionTitle);
    _votingWeightController = TextEditingController(text: widget.member.votingWeight.toString());
    _membershipStatus = widget.member.membershipStatus;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _memberCodeController.dispose();
    _phoneController.dispose();
    _departmentController.dispose();
    _regionController.dispose();
    _positionTitleController.dispose();
    _votingWeightController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final dio = ref.read(apiClientProvider);
      await dio.patch('${ApiConstants.members}${widget.member.id}/', data: {
        'full_name': _nameController.text.trim(),
        'member_code': _memberCodeController.text.trim(),
        'phone': _phoneController.text.trim(),
        'department': _departmentController.text.trim(),
        'region': _regionController.text.trim(),
        'position_title': _positionTitleController.text.trim(),
        'voting_weight': double.parse(_votingWeightController.text),
        'membership_status': _membershipStatus,
        if (_emailController.text.trim().isNotEmpty) 'email': _emailController.text.trim(),
      });
      ref.invalidate(membersProvider);
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Member'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Full Name'),
                validator: (v) => v!.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(labelText: 'Email Address (Optional)'),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _memberCodeController,
                      decoration: const InputDecoration(labelText: 'Member Code'),
                      validator: (v) => v!.isEmpty ? 'Required' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _phoneController,
                      decoration: const InputDecoration(labelText: 'Phone'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _departmentController,
                      decoration: const InputDecoration(labelText: 'Department'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _regionController,
                      decoration: const InputDecoration(labelText: 'Region'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _votingWeightController,
                      decoration: const InputDecoration(labelText: 'Voting Weight'),
                      keyboardType: TextInputType.number,
                      validator: (v) => double.tryParse(v ?? '') == null ? 'Invalid' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _membershipStatus,
                      decoration: const InputDecoration(labelText: 'Status'),
                      items: const [
                        DropdownMenuItem(value: 'active', child: Text('Active')),
                        DropdownMenuItem(value: 'suspended', child: Text('Suspended')),
                        DropdownMenuItem(value: 'expired', child: Text('Expired')),
                      ],
                      onChanged: (v) => setState(() => _membershipStatus = v!),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => context.pop(),
          child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
        ),
        LoadingButton(
          isLoading: _isLoading,
          onPressed: _submit,
          label: 'Save Changes',
        ),
      ],
    );
  }
}
