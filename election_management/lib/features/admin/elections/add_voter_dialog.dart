import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/providers/admin_providers.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/loading_button.dart';

class AddVoterDialog extends ConsumerStatefulWidget {
  final String electionId;

  const AddVoterDialog({super.key, required this.electionId});

  @override
  ConsumerState<AddVoterDialog> createState() => _AddVoterDialogState();
}

class _AddVoterDialogState extends ConsumerState<AddVoterDialog> {
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

  bool _isEligible = true;
  bool _isLoading = false;

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
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please complete all required fields.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

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
        'is_eligible': _isEligible,
      };

      await ref.read(publishElectionProvider.notifier).addVoter(data);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white),
                const SizedBox(width: 10),
                Text('Voter "${_firstNameController.text.trim()} ${_lastNameController.text.trim()}" added successfully!'),
              ],
            ),
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to add voter: ${e.toString()}'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _applyMemberData(MemberModel m) {
    setState(() {
      _selectedMemberId = m.id;
      _voterIdController.text = m.memberCode.isNotEmpty ? m.memberCode : (m.id.length > 8 ? m.id.substring(0, 8) : m.id);
      _prefixController.text = m.prefix;
      _firstNameController.text = m.firstName;
      _middleNameController.text = m.middleName;
      _lastNameController.text = m.lastName;
      _emailController.text = m.email;
      _phoneController.text = m.phone;
      _councilNumberController.text = m.councilNumber;
      _citizenshipController.text = m.citizenshipNumber;
      _isEligible = m.isEligibleToVote;
    });
  }

  void _clearMemberData() {
    setState(() {
      _selectedMemberId = null;
      _voterIdController.clear();
      _prefixController.clear();
      _firstNameController.clear();
      _middleNameController.clear();
      _lastNameController.clear();
      _emailController.clear();
      _phoneController.clear();
      _councilNumberController.clear();
      _citizenshipController.clear();
      _isEligible = true;
    });
  }

  InputDecoration _dec(
    String label, {
    String? hint,
    Widget? prefix,
    String? helper,
    bool isDark = false,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helper,
      prefixIcon: prefix,
      filled: true,
      fillColor: isDark ? AppColors.surfaceVariant.withValues(alpha: 0.5) : const Color(0xFFF9FAFB),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: isDark ? Colors.white12 : Colors.grey.shade300,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final membersAsync = ref.watch(membersProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: isDark ? AppColors.surface : Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860, maxHeight: 880),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Dialog Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.person_add_alt_1_rounded, color: AppColors.primaryLight, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Add Voter (मतदाता दर्ता)',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Enroll a qualified member to the preliminary voter roll for this election.',
                          style: TextStyle(color: isDark ? Colors.white60 : Colors.grey.shade600, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => context.pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),

              // Form Scrollable Body
              Expanded(
                child: Form(
                  key: _formKey,
                  child: ListView(
                    children: [
                      // ════════════════════════════════════════════════════════
                      // 1. AUTO-FILL FROM ROSTER
                      // ════════════════════════════════════════════════════════
                      _buildSectionCard(
                        context,
                        title: '1. Organization Roster Auto-fill (सदस्य छनोट)',
                        subtitle: 'Select an existing organization member to populate identity details automatically',
                        icon: Icons.person_search_rounded,
                        isDark: isDark,
                        children: [
                          membersAsync.when(
                            loading: () => const LinearProgressIndicator(),
                            error: (e, _) => Text('Could not load members: $e', style: const TextStyle(color: Colors.red, fontSize: 12)),
                            data: (members) {
                              if (members.isEmpty) {
                                return Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: isDark ? AppColors.surfaceVariant : const Color(0xFFF4F4F5),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Text('No members found in organization. Enter voter manually below.', style: TextStyle(fontSize: 12)),
                                );
                              }

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: DropdownButtonFormField<String?>(
                                          initialValue: _selectedMemberId,
                                          isExpanded: true,
                                          decoration: _dec(
                                            'Select Member to Auto-fill',
                                            prefix: const Icon(Icons.person_search_rounded),
                                            isDark: isDark,
                                          ),
                                          items: [
                                            const DropdownMenuItem<String?>(
                                              value: null,
                                              child: Text('— Enter Voter Manually (स्वनिर्धारित प्रविष्टि) —', style: TextStyle(fontStyle: FontStyle.italic)),
                                            ),
                                            ...members.map((m) => DropdownMenuItem<String?>(
                                              value: m.id,
                                              child: Text(
                                                '${m.fullName} (${m.email}) • Code: ${m.memberCode.isNotEmpty ? m.memberCode : "N/A"}',
                                                style: const TextStyle(fontSize: 13),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            )),
                                          ],
                                          onChanged: (val) {
                                            if (val != null) {
                                              final m = members.firstWhere((mem) => mem.id == val);
                                              _applyMemberData(m);
                                            } else {
                                              _clearMemberData();
                                            }
                                          },
                                        ),
                                      ),
                                      if (_selectedMemberId != null) ...[
                                        const SizedBox(width: 10),
                                        IconButton(
                                          icon: const Icon(Icons.clear_rounded, color: Colors.red),
                                          tooltip: 'Clear Selection',
                                          onPressed: _clearMemberData,
                                        ),
                                      ],
                                    ],
                                  ),
                                  if (_selectedMemberId != null) ...[
                                    const SizedBox(height: 10),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.green.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.check_circle_rounded, size: 14, color: Colors.green),
                                          SizedBox(width: 6),
                                          Text(
                                            'Member profile synchronized into identity fields below.',
                                            style: TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.w600),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),

                      // ════════════════════════════════════════════════════════
                      // 2. VOTER IDENTITY & CLASSIFICATION
                      // ════════════════════════════════════════════════════════
                      _buildSectionCard(
                        context,
                        title: '2. Voter Identity & Nomenclature (मतदाता विवरण)',
                        subtitle: 'Official voter roll identifier and legal name',
                        icon: Icons.badge_outlined,
                        isDark: isDark,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 2,
                                child: TextFormField(
                                  controller: _voterIdController,
                                  decoration: _dec('Voter ID / Roll Number *', hint: 'e.g. V-001, MEM-104', prefix: const Icon(Icons.tag_rounded), isDark: isDark),
                                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Voter ID is required' : null,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                flex: 1,
                                child: TextFormField(
                                  controller: _prefixController,
                                  decoration: _dec('Prefix', hint: 'Mr. / Ms. / Dr.', isDark: isDark),
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
                                  controller: _firstNameController,
                                  decoration: _dec('First Name *', hint: 'e.g. Ramesh', prefix: const Icon(Icons.person_outline_rounded), isDark: isDark),
                                  validator: (v) => (v == null || v.trim().isEmpty) ? 'First name is required' : null,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextFormField(
                                  controller: _middleNameController,
                                  decoration: _dec('Middle Name', hint: 'e.g. Prasad', isDark: isDark),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextFormField(
                                  controller: _lastNameController,
                                  decoration: _dec('Last Name *', hint: 'e.g. Shrestha', isDark: isDark),
                                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Last name is required' : null,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),

                      // ════════════════════════════════════════════════════════
                      // 3. CONTACT & NOTIFICATION
                      // ════════════════════════════════════════════════════════
                      _buildSectionCard(
                        context,
                        title: '3. Contact & Secure Dispatch (सम्पर्क विवरण)',
                        subtitle: 'Email address and phone number for voting credentials and receipts',
                        icon: Icons.contact_mail_outlined,
                        isDark: isDark,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _emailController,
                                  decoration: _dec('Email Address *', hint: 'voter@example.com', prefix: const Icon(Icons.email_outlined), isDark: isDark),
                                  keyboardType: TextInputType.emailAddress,
                                  validator: (v) {
                                    if (v == null || v.trim().isEmpty) return 'Email is required';
                                    if (!v.contains('@') || !v.contains('.')) return 'Valid email required';
                                    return null;
                                  },
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: TextFormField(
                                  controller: _phoneController,
                                  decoration: _dec('Phone Number *', hint: 'e.g. 98XXXXXXXX', prefix: const Icon(Icons.phone_outlined), isDark: isDark),
                                  keyboardType: TextInputType.phone,
                                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Phone number is required' : null,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),

                      // ════════════════════════════════════════════════════════
                      // 4. STATUTORY VERIFICATION & ELIGIBILITY
                      // ════════════════════════════════════════════════════════
                      _buildSectionCard(
                        context,
                        title: '4. Statutory Identifiers & Eligibility (प्रमाणीकरण)',
                        subtitle: 'Citizenship record and voting franchise approval status',
                        icon: Icons.verified_user_outlined,
                        isDark: isDark,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _citizenshipController,
                                  decoration: _dec('Citizenship Number *', hint: 'e.g. 27-01-76-12345', prefix: const Icon(Icons.credit_card_rounded), isDark: isDark),
                                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Citizenship is required' : null,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: TextFormField(
                                  controller: _councilNumberController,
                                  decoration: _dec('Council / License Number (Optional)', hint: 'e.g. NNC-1234', prefix: const Icon(Icons.badge_outlined), isDark: isDark),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Franchise Toggle Switch Card
                          Material(
                            color: isDark ? AppColors.surfaceVariant.withValues(alpha: 0.5) : const Color(0xFFF4F4F5),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: _isEligible
                                    ? Colors.green.withValues(alpha: 0.5)
                                    : (isDark ? Colors.white12 : Colors.grey.shade300),
                              ),
                            ),
                            child: SwitchListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                              title: const Text('Voting Franchise Active (मतदान अधिकार स्वीकृत)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              subtitle: const Text('Permit this voter to receive ballots and cast votes when election opens.', style: TextStyle(fontSize: 11)),
                              value: _isEligible,
                              activeThumbColor: Colors.green,
                              onChanged: (val) => setState(() => _isEligible = val),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),

              // Action Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: _isLoading ? null : () => context.pop(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 14),
                  LoadingButton(
                    isLoading: _isLoading,
                    label: 'Enroll Voter',
                    icon: Icons.check_circle_outline_rounded,
                    onPressed: _submit,
                    fullWidth: false,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isDark,
    required List<Widget> children,
  }) {
    return Material(
      color: isDark ? AppColors.surfaceVariant.withValues(alpha: 0.3) : const Color(0xFFFAFAFA),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.shade200,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: AppColors.primaryLight, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      Text(subtitle, style: TextStyle(color: isDark ? Colors.white60 : Colors.grey.shade600, fontSize: 11)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }
}
