import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/admin_providers.dart';
import '../../../core/providers/app_providers.dart';

class CreateVoterScreen extends ConsumerStatefulWidget {
  final String electionId;
  const CreateVoterScreen({super.key, required this.electionId});

  @override
  ConsumerState<CreateVoterScreen> createState() => _CreateVoterScreenState();
}

class _CreateVoterScreenState extends ConsumerState<CreateVoterScreen> {
  final _formKey = GlobalKey<FormState>();
  
  String? _selectedMemberId;
  final _voterIdController = TextEditingController();
  final _prefixController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _middleNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _councilNumberController = TextEditingController();
  final _citizenshipController = TextEditingController();

  bool _isSubmitting = false;

  void _submit() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isSubmitting = true);
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
        'is_eligible': true,
      };

      await ref.read(publishElectionProvider.notifier).addVoter(data);
      
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final membersAsync = ref.watch(membersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create New Voter'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Election Admin > Voters > Create New Voter',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Theme.of(context).dividerColor),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Select Organization Member (Optional)', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 8),
                      Text('Pick an organization member to auto-fill voter details, or fill the fields below manually:',
                          style: TextStyle(fontSize: 13, color: Theme.of(context).textTheme.bodySmall?.color)),
                      const SizedBox(height: 12),
                      membersAsync.when(
                        loading: () => const LinearProgressIndicator(),
                        error: (e, _) => Text('Could not load members: $e', style: const TextStyle(color: Colors.red, fontSize: 13)),
                        data: (members) {
                          if (members.isEmpty) return const SizedBox.shrink();
                          return DropdownButtonFormField<String?>(
                            initialValue: _selectedMemberId,
                            decoration: const InputDecoration(
                              labelText: 'Select Member (Auto-fill)',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.person_search_rounded),
                            ),
                            items: [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text('— None (Enter Voter Manually) —'),
                              ),
                              ...members.map((m) => DropdownMenuItem<String?>(
                                value: m.id,
                                child: Text('${m.fullName} (${m.email}) — ${m.memberCode}'),
                              )),
                            ],
                            onChanged: (val) {
                              setState(() {
                                _selectedMemberId = val;
                                if (val != null) {
                                  final m = members.firstWhere((mem) => mem.id == val);
                                  _voterIdController.text = m.memberCode.isNotEmpty ? m.memberCode : m.id.substring(0, 8);
                                  _prefixController.text = m.prefix;
                                  _firstNameController.text = m.firstName;
                                  _middleNameController.text = m.middleName;
                                  _lastNameController.text = m.lastName;
                                  _emailController.text = m.email;
                                  _phoneController.text = m.phone;
                                  _councilNumberController.text = m.councilNumber;
                                  _citizenshipController.text = m.citizenshipNumber;
                                }
                              });
                            },
                          );
                        },
                      ),
                      const SizedBox(height: 32),
                      Text('Voter Profile Information', style: Theme.of(context).textTheme.titleLarge),
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
                          Expanded(child: _buildTextField('Email *', _emailController, 'Enter email address')),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(child: _buildTextField('Phone Number *', _phoneController, 'Enter contact number')),
                          const SizedBox(width: 24),
                          Expanded(child: _buildTextField('Council Number', _councilNumberController, 'Enter council number', required: false)),
                          const SizedBox(width: 24),
                          Expanded(child: _buildTextField('Citizenship Number *', _citizenshipController, 'Enter citizenship number')),
                        ],
                      ),
                      
                      const SizedBox(height: 48),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            style: TextButton.styleFrom(
                              backgroundColor: Colors.grey.shade600,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                            ),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 16),
                          ElevatedButton(
                            onPressed: _isSubmitting ? null : _submit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                            ),
                            child: _isSubmitting ? const CircularProgressIndicator(color: Colors.white) : const Text('Create'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, String hint, {bool required = true, int maxLines = 1}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          decoration: InputDecoration(
            hintText: hint,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          validator: required ? (val) => val!.isEmpty ? 'Required' : null : null,
        ),
      ],
    );
  }
}
