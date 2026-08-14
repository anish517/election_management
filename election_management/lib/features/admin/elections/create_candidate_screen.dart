import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_constants.dart';
import '../../../core/providers/admin_providers.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/image_upload_widget.dart';

class CreateCandidateScreen extends ConsumerStatefulWidget {
  final String electionId;
  const CreateCandidateScreen({super.key, required this.electionId});

  @override
  ConsumerState<CreateCandidateScreen> createState() => _CreateCandidateScreenState();
}

class _CreateCandidateScreenState extends ConsumerState<CreateCandidateScreen> {
  final _formKey = GlobalKey<FormState>();
  
  String? _selectedVoterId;
  String? _selectedPositionId;
  String? _selectedQuotaId;
  
  final _firstNameController = TextEditingController();
  final _middleNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _contactController = TextEditingController();
  String? _selectedGender;
  final _dobController = TextEditingController();
  final _addressController = TextEditingController();
  
  String _candidateImageUrl = '';
  
  final _personalDescriptionController = TextEditingController();
  final _manifestoController = TextEditingController();

  bool _isSubmitting = false;

  void _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedPositionId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a designation')));
      return;
    }
    if (_selectedVoterId == null && _emailController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a voter from the voter list')));
      return;
    }
    
    setState(() => _isSubmitting = true);
    try {
      final dio = ref.read(apiClientProvider);
      await dio.post(ApiConstants.electionCandidates(widget.electionId), data: {
        'election': widget.electionId,
        'position': _selectedPositionId,
        if (_selectedQuotaId != null && _selectedQuotaId!.isNotEmpty) 'quota': _selectedQuotaId,
        'first_name': _firstNameController.text.trim(),
        'middle_name': _middleNameController.text.trim(),
        'last_name': _lastNameController.text.trim(),
        'email': _emailController.text.trim(),
        'contact_number': _contactController.text.trim(),
        'gender': _selectedGender ?? 'Other',
        'date_of_birth': _dobController.text.trim().isNotEmpty ? _dobController.text.trim() : null,
        'address': _addressController.text.trim(),
        'candidate_image': _candidateImageUrl,
        'personal_description': _personalDescriptionController.text.trim(),
        'manifesto': _manifestoController.text.trim(),
        'status': 'approved', // Auto approve for admin creation
      });

      ref.invalidate(electionProvider(widget.electionId));
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
    final electionAsync = ref.watch(electionProvider(widget.electionId));
    final votersAsync = ref.watch(votersProvider(widget.electionId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create New Candidate'),
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
                'Election Admin > Candidates > Create New Candidate',
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
                      Text('Voter Selection', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 16),
                      votersAsync.when(
                        loading: () => const LinearProgressIndicator(),
                        error: (e, _) => Text('Error loading voters: $e', style: const TextStyle(color: Colors.red)),
                        data: (voters) => DropdownButtonFormField<String>(
                          initialValue: _selectedVoterId,
                          decoration: const InputDecoration(
                            labelText: 'Select Voter (Candidate must originate from voter list) *',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.person_search_rounded),
                          ),
                          items: voters.map((v) => DropdownMenuItem(
                            value: v['id'].toString(),
                            child: Text('${v['full_name'] ?? '${v['first_name']} ${v['last_name']}'} (${v['email']}) — ${v['voter_id']}'),
                          )).toList(),
                          onChanged: (val) {
                            setState(() {
                              _selectedVoterId = val;
                              final v = voters.firstWhere((item) => item['id'].toString() == val);
                              _firstNameController.text = v['first_name'] ?? '';
                              _middleNameController.text = v['middle_name'] ?? '';
                              _lastNameController.text = v['last_name'] ?? '';
                              _emailController.text = v['email'] ?? '';
                              _contactController.text = v['phone'] ?? '';
                              _addressController.text = v['address'] ?? '';
                            });
                          },
                          validator: (v) => v == null ? 'Voter selection is required' : null,
                        ),
                      ),
                      const SizedBox(height: 32),
                      Text('Candidate Profile Information', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(child: _buildTextField('First Name *', _firstNameController, 'Enter first name')),
                          const SizedBox(width: 24),
                          Expanded(child: _buildTextField('Middle Name', _middleNameController, 'Enter middle name', required: false)),
                          const SizedBox(width: 24),
                          Expanded(child: _buildTextField('Last Name *', _lastNameController, 'Enter last name')),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: electionAsync.when(
                              loading: () => const CircularProgressIndicator(),
                              error: (_, _) => const Text('Error loading designations'),
                              data: (election) => _buildDropdown(
                                'Designation *',
                                _selectedPositionId,
                                election.positions.map((p) => DropdownMenuItem(value: p.id, child: Text(p.title))).toList(),
                                (val) {
                                  setState(() {
                                    _selectedPositionId = val;
                                    _selectedQuotaId = null;
                                  });
                                },
                                'Select Designation',
                              ),
                            ),
                          ),
                          if (_selectedPositionId != null) ...[
                            ...electionAsync.maybeWhen(
                              data: (election) {
                                final selectedPos = election.positions.where((p) => p.id == _selectedPositionId).firstOrNull;
                                if (selectedPos != null && selectedPos.quotas.isNotEmpty) {
                                  final activeQuotas = selectedPos.quotas.where((q) => q.isActive).toList();
                                  if (activeQuotas.isNotEmpty) {
                                    return [
                                      const SizedBox(width: 24),
                                      Expanded(
                                        child: _buildDropdown(
                                          'Quota Category',
                                          _selectedQuotaId,
                                          [
                                            const DropdownMenuItem<String?>(value: null, child: Text('Open / General (No Quota)')),
                                            ...activeQuotas.map((q) => DropdownMenuItem<String?>(
                                              value: q.id,
                                              child: Text('${q.name} (${q.seats} seat(s))'),
                                            )),
                                          ],
                                          (val) => setState(() => _selectedQuotaId = val),
                                          'Select Quota',
                                        ),
                                      ),
                                    ];
                                  }
                                }
                                return <Widget>[];
                              },
                              orElse: () => <Widget>[],
                            ),
                          ],
                          const SizedBox(width: 24),
                          Expanded(child: _buildTextField('Email (From Voter List) *', _emailController, 'Auto-filled from voter list', readOnly: true)),
                          const SizedBox(width: 24),
                          Expanded(child: _buildTextField('Contact Number *', _contactController, 'Enter contact number')),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: _buildDropdown(
                              'Gender *',
                              _selectedGender,
                              const [
                                DropdownMenuItem(value: 'Male', child: Text('Male')),
                                DropdownMenuItem(value: 'Female', child: Text('Female')),
                                DropdownMenuItem(value: 'Other', child: Text('Other')),
                              ],
                              (val) => setState(() => _selectedGender = val),
                              'Select Gender',
                            ),
                          ),
                          const SizedBox(width: 24),
                          Expanded(child: _buildTextField('Date of Birth', _dobController, 'YYYY-MM-DD', required: false)),
                          const SizedBox(width: 24),
                          Expanded(child: _buildTextField('Address', _addressController, 'Enter address', required: false)),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Candidate Photo (Upload Manually)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          const SizedBox(height: 8),
                          ImageUploadWidget(
                            initialImageUrl: _candidateImageUrl,
                            onImageUploaded: (url) => setState(() => _candidateImageUrl = url),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Text('Nomination Manifesto', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 16),
                      _buildTextField('Manifesto / Statement *', _manifestoController, 'Enter candidate manifesto', maxLines: 4, required: true),
                      const SizedBox(height: 24),
                      Text('Additional Details', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 16),
                      _buildTextField('Personal Description', _personalDescriptionController, 'Enter personal description', maxLines: 4, required: false),
                      
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

  Widget _buildTextField(String label, TextEditingController controller, String hint, {bool required = true, int maxLines = 1, bool readOnly = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          readOnly: readOnly,
          decoration: InputDecoration(
            hintText: hint,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          validator: required ? (val) => (val == null || val.isEmpty) ? 'Required' : null : null,
        ),
      ],
    );
  }

  Widget _buildDropdown<T>(String label, T? value, List<DropdownMenuItem<T>> items, ValueChanged<T?> onChanged, String hint) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 8),
        DropdownButtonFormField<T>(
          initialValue: value,
          items: items,
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: hint,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          validator: (val) => val == null ? 'Required' : null,
        ),
      ],
    );
  }
}
