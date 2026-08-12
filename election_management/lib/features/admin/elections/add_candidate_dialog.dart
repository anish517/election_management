import 'package:election_management/core/providers/admin_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_constants.dart';
import '../../../core/providers/app_providers.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/loading_button.dart';
import '../../../shared/widgets/image_upload_widget.dart';
import '../../../core/theme/app_theme.dart';


class AddCandidateDialog extends ConsumerStatefulWidget {
  final ElectionModel election;
  const AddCandidateDialog({super.key, required this.election});

  @override
  ConsumerState<AddCandidateDialog> createState() => _AddCandidateDialogState();
}

class _AddCandidateDialogState extends ConsumerState<AddCandidateDialog> {
  final _formKey = GlobalKey<FormState>();
  
  String? _selectedPositionId;
  String? _selectedMemberId;
  
  // Basic Info Controllers
  final _firstNameController = TextEditingController();
  final _middleNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _genderController = TextEditingController();
  final _dobController = TextEditingController();
  final _addressController = TextEditingController();
  final _citizenshipController = TextEditingController();
  final _membershipIdController = TextEditingController();
  
  final _personalDescController = TextEditingController();
  final _contributionController = TextEditingController();
  final _manifestoController = TextEditingController();
  final _slateNameController = TextEditingController();
  String _candidateImage = '';
  String _candidateSignature = '';

  // Proposer
  final _proposerNameController = TextEditingController();
  final _proposerCitizenshipController = TextEditingController();
  final _proposerPhoneController = TextEditingController();
  final _proposerMemIdController = TextEditingController();
  String _proposerSignature = '';

  // Supporter
  final _supporterNameController = TextEditingController();
  final _supporterCitizenshipController = TextEditingController();
  final _supporterPhoneController = TextEditingController();
  final _supporterMemIdController = TextEditingController();
  String _supporterSignature = '';
  
  bool _isLoading = false;

  @override
  void dispose() {
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _genderController.dispose();
    _dobController.dispose();
    _addressController.dispose();
    _citizenshipController.dispose();
    _membershipIdController.dispose();
    _personalDescController.dispose();
    _contributionController.dispose();
    _manifestoController.dispose();
    _slateNameController.dispose();
    _proposerNameController.dispose();
    _proposerCitizenshipController.dispose();
    _proposerPhoneController.dispose();
    _proposerMemIdController.dispose();
    _supporterNameController.dispose();
    _supporterCitizenshipController.dispose();
    _supporterPhoneController.dispose();
    _supporterMemIdController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedPositionId == null || _selectedMemberId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a position and member.')));
      return;
    }
    
    setState(() => _isLoading = true);
    
    final endorsements = [];
    if (_proposerNameController.text.isNotEmpty) {
      endorsements.add({
        'endorsement_type': 'proposer',
        'name': _proposerNameController.text.trim(),
        'citizenship_number': _proposerCitizenshipController.text.trim(),
        'phone': _proposerPhoneController.text.trim(),
        'membership_id': _proposerMemIdController.text.trim(),
        'signature_url': _proposerSignature,
      });
    }
    if (_supporterNameController.text.isNotEmpty) {
      endorsements.add({
        'endorsement_type': 'supporter',
        'name': _supporterNameController.text.trim(),
        'citizenship_number': _supporterCitizenshipController.text.trim(),
        'phone': _supporterPhoneController.text.trim(),
        'membership_id': _supporterMemIdController.text.trim(),
        'signature_url': _supporterSignature,
      });
    }

    try {
      final dio = ref.read(apiClientProvider);
      await dio.post(ApiConstants.electionCandidates(widget.election.id), data: {
        'position': _selectedPositionId,
        'first_name': _firstNameController.text.trim(),
        'middle_name': _middleNameController.text.trim(),
        'last_name': _lastNameController.text.trim(),
        'email': _emailController.text.trim(),
        'contact_number': _phoneController.text.trim(),
        'gender': _genderController.text.trim(),
        'date_of_birth': _dobController.text.isEmpty ? null : _dobController.text.trim(),
        'address': _addressController.text.trim(),
        'citizenship_number': _citizenshipController.text.trim(),
        'membership_id': _membershipIdController.text.trim(),
        'candidate_image': _candidateImage,
        'candidate_signature': _candidateSignature,
        'personal_description': _personalDescController.text.trim(),
        'contribution_to_org': _contributionController.text.trim(),
        'manifesto': _manifestoController.text.trim(),
        'slate_name': _slateNameController.text.trim(),
        'status': 'approved',
        'endorsements': endorsements,
      });
      ref.invalidate(electionProvider(widget.election.id));
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final votersAsync = ref.watch(votersProvider(widget.election.id));

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 1000,
        height: MediaQuery.of(context).size.height * 0.95,
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Add Candidate', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.close), onPressed: () => context.pop()),
              ],
            ),
            const Divider(height: 32),
            Expanded(
              child: votersAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
                data: (voters) {
                  return SingleChildScrollView(
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  initialValue: _selectedMemberId,
                                  decoration: const InputDecoration(labelText: 'Select Voter *'),
                                  items: voters.map((v) => DropdownMenuItem(
                                    value: v['id'].toString(),
                                    child: Text('${v['first_name']} ${v['last_name']} (${v['voter_id']})'),
                                  )).toList(),
                                  onChanged: (val) {
                                    setState(() {
                                      _selectedMemberId = val;
                                      final selectedVoter = voters.firstWhere((v) => v['id'].toString() == val);
                                      _firstNameController.text = selectedVoter['first_name'] ?? '';
                                      _middleNameController.text = selectedVoter['middle_name'] ?? '';
                                      _lastNameController.text = selectedVoter['last_name'] ?? '';
                                      _emailController.text = selectedVoter['email'] ?? '';
                                      _phoneController.text = selectedVoter['phone'] ?? '';
                                      _citizenshipController.text = selectedVoter['citizenship_number'] ?? '';
                                      _membershipIdController.text = selectedVoter['voter_id'] ?? '';
                                    });
                                  },
                                  validator: (v) => v == null ? 'Required' : null,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  initialValue: _selectedPositionId,
                                  decoration: const InputDecoration(labelText: 'Designation *'),
                                  items: widget.election.positions.map((p) => DropdownMenuItem(
                                    value: p.id,
                                    child: Text(p.quotaName.isNotEmpty ? '${p.title} (${p.quotaName})' : p.title),
                                  )).toList(),
                                  onChanged: (v) => setState(() => _selectedPositionId = v),
                                  validator: (v) => v == null ? 'Required' : null,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          const Text('Nomination Details', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 16),
                          TextFormField(controller: _slateNameController, decoration: const InputDecoration(labelText: 'Slate / Party Name (Optional)')),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _manifestoController,
                            decoration: const InputDecoration(labelText: 'Manifesto / Statement'),
                            maxLines: 3,
                          ),
                          const SizedBox(height: 24),
                          const Text('Additional Information', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(child: TextFormField(controller: _firstNameController, decoration: const InputDecoration(labelText: 'First Name *'))),
                              const SizedBox(width: 16),
                              Expanded(child: TextFormField(controller: _middleNameController, decoration: const InputDecoration(labelText: 'Middle Name'))),
                              const SizedBox(width: 16),
                              Expanded(child: TextFormField(controller: _lastNameController, decoration: const InputDecoration(labelText: 'Last Name *'))),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(child: TextFormField(controller: _emailController, decoration: const InputDecoration(labelText: 'Email *'))),
                              const SizedBox(width: 16),
                              Expanded(child: TextFormField(controller: _phoneController, decoration: const InputDecoration(labelText: 'Contact Number *'))),
                              const SizedBox(width: 16),
                              Expanded(child: TextFormField(controller: _genderController, decoration: const InputDecoration(labelText: 'Gender'))),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(child: TextFormField(controller: _dobController, decoration: const InputDecoration(labelText: 'Date of Birth (YYYY-MM-DD)'))),
                              const SizedBox(width: 16),
                              Expanded(flex: 2, child: TextFormField(controller: _addressController, decoration: const InputDecoration(labelText: 'Address'))),
                            ],
                          ),
                            
                            const SizedBox(height: 32),
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('Candidate Image *', style: TextStyle(fontWeight: FontWeight.bold)),
                                      const SizedBox(height: 8),
                                      Center(
                                        child: ImageUploadWidget(
                                          initialImageUrl: _candidateImage,
                                          placeholderText: 'Upload',
                                          onImageUploaded: (url) => setState(() => _candidateImage = url),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('Candidate Signature *', style: TextStyle(fontWeight: FontWeight.bold)),
                                      const SizedBox(height: 8),
                                      Center(
                                        child: ImageUploadWidget(
                                          initialImageUrl: _candidateSignature,
                                          placeholderText: 'Signature',
                                          radius: 0,
                                          onImageUploaded: (url) => setState(() => _candidateSignature = url),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            
                            const SizedBox(height: 32),
                            _buildSectionHeader('Statements'),
                            TextFormField(
                              controller: _personalDescController,
                              decoration: const InputDecoration(labelText: 'Personal Description'),
                              maxLines: 3,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _contributionController,
                              decoration: const InputDecoration(labelText: 'Contribution to Organization', alignLabelWithHint: true),
                              maxLines: 3,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _manifestoController,
                              decoration: const InputDecoration(labelText: 'Manifesto / Platform', alignLabelWithHint: true),
                              maxLines: 4,
                            ),
                            
                            const SizedBox(height: 32),
                            _buildSectionHeader('Membership Information'),
                            Row(
                              children: [
                                Expanded(child: TextFormField(controller: _citizenshipController, decoration: const InputDecoration(labelText: 'Citizenship Number'))),
                                const SizedBox(width: 16),
                                Expanded(child: TextFormField(controller: _membershipIdController, decoration: const InputDecoration(labelText: 'Membership ID'))),
                              ],
                            ),
                            
                            const SizedBox(height: 32),
                            _buildSectionHeader('Proposals'),
                            const Text('Proposal #1', style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(child: TextFormField(controller: _proposerNameController, decoration: const InputDecoration(labelText: 'Name *'))),
                                const SizedBox(width: 16),
                                Expanded(child: TextFormField(controller: _proposerCitizenshipController, decoration: const InputDecoration(labelText: 'Citizenship Number *'))),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(child: TextFormField(controller: _proposerPhoneController, decoration: const InputDecoration(labelText: 'Phone *'))),
                                const SizedBox(width: 16),
                                Expanded(child: TextFormField(controller: _proposerMemIdController, decoration: const InputDecoration(labelText: 'Membership ID *'))),
                              ],
                            ),
                            const SizedBox(height: 16),
                            const Text('Proposal Signature'),
                            const SizedBox(height: 8),
                            ImageUploadWidget(
                              initialImageUrl: _proposerSignature,
                              placeholderText: 'Sign',
                              radius: 32,
                              onImageUploaded: (url) => setState(() => _proposerSignature = url),
                            ),
                            
                            const SizedBox(height: 32),
                            _buildSectionHeader('Supporters'),
                            const Text('Supporter #1', style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(child: TextFormField(controller: _supporterNameController, decoration: const InputDecoration(labelText: 'Name *'))),
                                const SizedBox(width: 16),
                                Expanded(child: TextFormField(controller: _supporterCitizenshipController, decoration: const InputDecoration(labelText: 'Citizenship Number *'))),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(child: TextFormField(controller: _supporterPhoneController, decoration: const InputDecoration(labelText: 'Phone *'))),
                                const SizedBox(width: 16),
                                Expanded(child: TextFormField(controller: _supporterMemIdController, decoration: const InputDecoration(labelText: 'Membership ID *'))),
                              ],
                            ),
                            const SizedBox(height: 16),
                            const Text('Support Signature'),
                            const SizedBox(height: 8),
                            ImageUploadWidget(
                              initialImageUrl: _supporterSignature,
                              placeholderText: 'Sign',
                              radius: 32,
                              onImageUploaded: (url) => setState(() => _supporterSignature = url),
                            ),
                        ],
                      ),
                    ),
                  );
                },
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
                  isLoading: _isLoading,
                  onPressed: _submit,
                  label: 'Add Candidate',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primary)),
    );
  }
}
