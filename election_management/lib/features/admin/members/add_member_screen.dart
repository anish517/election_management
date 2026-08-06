import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/providers/admin_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/loading_button.dart';
import 'package:intl/intl.dart';

class AddMemberScreen extends ConsumerStatefulWidget {
  const AddMemberScreen({super.key});

  @override
  ConsumerState<AddMemberScreen> createState() => _AddMemberScreenState();
}

class _AddMemberScreenState extends ConsumerState<AddMemberScreen> {
  final _formKey = GlobalKey<FormState>();
  
  // Identity
  final _nameController = TextEditingController();
  final _codeController = TextEditingController();
  final _photoUrlController = TextEditingController();
  String _selectedGender = '';

  // Contact
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();

  // Org Structure
  final _departmentController = TextEditingController();
  final _regionController = TextEditingController();
  final _positionTitleController = TextEditingController();

  // Membership
  String _selectedMembershipStatus = 'invited';
  DateTime? _expiryDate;
  final _votingWeightController = TextEditingController(text: '1.0');

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    _photoUrlController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _departmentController.dispose();
    _regionController.dispose();
    _positionTitleController.dispose();
    _votingWeightController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiryDate ?? DateTime.now().add(const Duration(days: 365)),
      firstDate: DateTime.now(),
      lastDate: DateTime(2101),
    );
    if (picked != null && picked != _expiryDate) {
      setState(() {
        _expiryDate = picked;
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    
    try {
      await ref.read(addMemberProvider.notifier).addMember(
        fullName: _nameController.text.trim(),
        memberCode: _codeController.text.trim(),
        photoUrl: _photoUrlController.text.trim(),
        gender: _selectedGender,
        email: _emailController.text.trim(),
        phone: _phoneController.text.trim(),
        department: _departmentController.text.trim(),
        region: _regionController.text.trim(),
        positionTitle: _positionTitleController.text.trim(),
        membershipStatus: _selectedMembershipStatus,
        membershipExpiryDate: _expiryDate != null ? DateFormat('yyyy-MM-dd').format(_expiryDate!) : null,
        votingWeight: double.tryParse(_votingWeightController.text.trim()) ?? 1.0,
      );
      if (mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Member added successfully!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Widget _buildSectionCard({required String title, required IconData icon, required List<Widget> children}) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.withOpacity(0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: AppColors.primary),
                ),
                const SizedBox(width: 12),
                Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 24),
            ...children,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(addMemberProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Member'),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 800),
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  
                  _buildSectionCard(
                    title: 'Identity',
                    icon: Icons.person_rounded,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _nameController,
                              decoration: const InputDecoration(labelText: 'Full Name', prefixIcon: Icon(Icons.badge)),
                              validator: (v) => v!.isEmpty ? 'Required' : null,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _codeController,
                              decoration: const InputDecoration(labelText: 'Member ID (Code)', prefixIcon: Icon(Icons.tag)),
                              validator: (v) => v!.isEmpty ? 'Required' : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _selectedGender.isEmpty ? null : _selectedGender,
                              decoration: const InputDecoration(labelText: 'Gender', prefixIcon: Icon(Icons.wc)),
                              items: const [
                                DropdownMenuItem(value: 'male', child: Text('Male')),
                                DropdownMenuItem(value: 'female', child: Text('Female')),
                                DropdownMenuItem(value: 'other', child: Text('Other')),
                                DropdownMenuItem(value: 'prefer_not_to_say', child: Text('Prefer not to say')),
                              ],
                              onChanged: (val) => setState(() => _selectedGender = val ?? ''),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _photoUrlController,
                              decoration: const InputDecoration(labelText: 'Photo URL', prefixIcon: Icon(Icons.image)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  
                  _buildSectionCard(
                    title: 'Contact',
                    icon: Icons.contact_mail_rounded,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _emailController,
                              decoration: const InputDecoration(labelText: 'Email Address', prefixIcon: Icon(Icons.email)),
                              keyboardType: TextInputType.emailAddress,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _phoneController,
                              decoration: const InputDecoration(labelText: 'Phone Number', prefixIcon: Icon(Icons.phone)),
                              keyboardType: TextInputType.phone,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  _buildSectionCard(
                    title: 'Organization Structure',
                    icon: Icons.account_tree_rounded,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _departmentController,
                              decoration: const InputDecoration(labelText: 'Department', prefixIcon: Icon(Icons.domain)),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _regionController,
                              decoration: const InputDecoration(labelText: 'Region', prefixIcon: Icon(Icons.map)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _positionTitleController,
                        decoration: const InputDecoration(labelText: 'Position Title (e.g. Regional Manager)', prefixIcon: Icon(Icons.work)),
                      ),
                    ],
                  ),

                  _buildSectionCard(
                    title: 'Membership Settings',
                    icon: Icons.verified_user_rounded,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _selectedMembershipStatus,
                              decoration: const InputDecoration(labelText: 'Membership Status', prefixIcon: Icon(Icons.rule)),
                              items: const [
                                DropdownMenuItem(value: 'invited', child: Text('Invited')),
                                DropdownMenuItem(value: 'active', child: Text('Active')),
                                DropdownMenuItem(value: 'suspended', child: Text('Suspended')),
                                DropdownMenuItem(value: 'expired', child: Text('Expired')),
                              ],
                              onChanged: (val) => setState(() => _selectedMembershipStatus = val!),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: InkWell(
                              onTap: () => _selectDate(context),
                              child: InputDecorator(
                                decoration: const InputDecoration(
                                  labelText: 'Membership Expiry Date',
                                  prefixIcon: Icon(Icons.calendar_today),
                                ),
                                child: Text(_expiryDate != null ? DateFormat('yyyy-MM-dd').format(_expiryDate!) : 'No Expiry'),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _votingWeightController,
                        decoration: const InputDecoration(labelText: 'Voting Weight', prefixIcon: Icon(Icons.scale)),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Required';
                          if (double.tryParse(v) == null) return 'Must be a number';
                          return null;
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: LoadingButton(
                      isLoading: state.isLoading,
                      onPressed: () {
                        if (mounted) _submit();
                      },
                      label: 'Add Member',
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
