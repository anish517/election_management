import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/providers/admin_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/loading_button.dart';

class EditVoterDialog extends ConsumerStatefulWidget {
  final String electionId;
  final Map<String, dynamic> voter;

  const EditVoterDialog({super.key, required this.electionId, required this.voter});

  @override
  ConsumerState<EditVoterDialog> createState() => _EditVoterDialogState();
}

class _EditVoterDialogState extends ConsumerState<EditVoterDialog> {
  final _formKey = GlobalKey<FormState>();
  
  late final TextEditingController _voterIdController;
  late final TextEditingController _prefixController;
  late final TextEditingController _firstNameController;
  late final TextEditingController _middleNameController;
  late final TextEditingController _lastNameController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  late final TextEditingController _councilNumberController;
  late final TextEditingController _citizenshipController;

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _voterIdController = TextEditingController(text: widget.voter['voter_id']?.toString());
    _prefixController = TextEditingController(text: widget.voter['prefix']?.toString());
    _firstNameController = TextEditingController(text: widget.voter['first_name']?.toString());
    _middleNameController = TextEditingController(text: widget.voter['middle_name']?.toString());
    _lastNameController = TextEditingController(text: widget.voter['last_name']?.toString());
    _emailController = TextEditingController(text: widget.voter['email']?.toString());
    _phoneController = TextEditingController(text: widget.voter['phone']?.toString());
    _councilNumberController = TextEditingController(text: widget.voter['council_number']?.toString());
    _citizenshipController = TextEditingController(text: widget.voter['citizenship_number']?.toString());
  }

  @override
  void dispose() {
    _voterIdController.dispose();
    _prefixController.dispose();
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _councilNumberController.dispose();
    _citizenshipController.dispose();
    super.dispose();
  }

  void _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final data = {
        'election': widget.electionId,
        'voter_id': _voterIdController.text.trim(),
        'prefix': _prefixController.text.trim(),
        'first_name': _firstNameController.text.trim(),
        'middle_name': _middleNameController.text.trim(),
        'last_name': _lastNameController.text.trim(),
        'email': _emailController.text.trim(),
        'phone': _phoneController.text.trim(),
        'council_number': _councilNumberController.text.trim(),
        'citizenship_number': _citizenshipController.text.trim(),
      };

      await ref.read(publishElectionProvider.notifier).editVoter(widget.electionId, widget.voter['id'].toString(), data);
      if (mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Voter updated successfully')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 1000,
        height: MediaQuery.of(context).size.height * 0.9,
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Edit Voter', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.close), onPressed: () => context.pop()),
              ],
            ),
            const Divider(height: 32),
            Expanded(
              child: SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Voter Information', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(child: _buildTextField('Voter ID *', _voterIdController, 'Enter voter ID (e.g. BM - 1)')),
                          const SizedBox(width: 24),
                          Expanded(child: _buildTextField('Name Prefix', _prefixController, 'e.g. Mr., Ms.', required: false)),
                          const SizedBox(width: 24),
                          Expanded(child: _buildTextField('First Name *', _firstNameController, 'Enter first name')),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(child: _buildTextField('Middle Name', _middleNameController, 'Enter middle name', required: false)),
                          const SizedBox(width: 24),
                          Expanded(child: _buildTextField('Last Name *', _lastNameController, 'Enter last name')),
                          const SizedBox(width: 24),
                          Expanded(child: _buildTextField('Email', _emailController, 'Enter email address', required: false)),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(child: _buildTextField('Phone Number', _phoneController, 'Enter contact number', required: false)),
                          const SizedBox(width: 24),
                          Expanded(child: _buildTextField('Council Number', _councilNumberController, 'Enter council number', required: false)),
                          const SizedBox(width: 24),
                          Expanded(child: _buildTextField('Citizenship Number', _citizenshipController, 'Enter citizenship number', required: false)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const Divider(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _isLoading ? null : () => context.pop(),
                  child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
                ),
                const SizedBox(width: 16),
                LoadingButton(
                  fullWidth: false,
                  isLoading: _isLoading,
                  onPressed: _submit,
                  label: 'Save Changes',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, String hint, {bool required = true}) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      validator: required ? (v) => v == null || v.isEmpty ? 'Required' : null : null,
    );
  }
}
