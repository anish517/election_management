import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_constants.dart';
import '../../../core/providers/admin_providers.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/image_upload_widget.dart';
import '../../../shared/widgets/loading_button.dart';

class _EndorsementItem {
  final String endorsementType;
  final TextEditingController nameCtrl = TextEditingController();
  final TextEditingController phoneCtrl = TextEditingController();
  final TextEditingController citizenCtrl = TextEditingController();
  final TextEditingController memIdCtrl = TextEditingController();
  String signatureUrl = '';

  _EndorsementItem({
    required this.endorsementType,
    String name = '',
    String phone = '',
    String citizen = '',
    String memId = '',
    String signature = '',
  }) {
    nameCtrl.text = name;
    phoneCtrl.text = phone;
    citizenCtrl.text = citizen;
    memIdCtrl.text = memId;
    signatureUrl = signature;
  }

  void dispose() {
    nameCtrl.dispose();
    phoneCtrl.dispose();
    citizenCtrl.dispose();
    memIdCtrl.dispose();
  }

  bool get isNotEmpty => nameCtrl.text.trim().isNotEmpty;

  Map<String, dynamic> toMap() => {
        'endorsement_type': endorsementType,
        'name': nameCtrl.text.trim(),
        'citizenship_number': citizenCtrl.text.trim(),
        'phone': phoneCtrl.text.trim(),
        'membership_id': memIdCtrl.text.trim(),
        'signature_url': signatureUrl,
      };
}

class AddCandidateDialog extends ConsumerStatefulWidget {
  final ElectionModel election;
  const AddCandidateDialog({super.key, required this.election});

  @override
  ConsumerState<AddCandidateDialog> createState() => _AddCandidateDialogState();
}

class _AddCandidateDialogState extends ConsumerState<AddCandidateDialog> {
  final _formKey = GlobalKey<FormState>();

  String? _selectedPositionId;
  String? _selectedQuotaId;
  String? _selectedMemberId;

  // Basic Info Controllers
  final _firstNameController = TextEditingController();
  final _middleNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _genderController = TextEditingController(text: 'Male');
  final _dobController = TextEditingController();
  final _addressController = TextEditingController();
  final _citizenshipController = TextEditingController();
  final _membershipIdController = TextEditingController();

  final _personalDescController = TextEditingController();
  final _contributionController = TextEditingController();
  final _manifestoController = TextEditingController();
  String _candidateImage = '';

  // Dynamic Multi-Proposers & Multi-Supporters
  late List<_EndorsementItem> _proposers;
  late List<_EndorsementItem> _supporters;

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _proposers = [_EndorsementItem(endorsementType: 'proposer')];
    _supporters = [_EndorsementItem(endorsementType: 'supporter')];
  }

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
    for (final p in _proposers) {
      p.dispose();
    }
    for (final s in _supporters) {
      s.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please complete all required fields.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (_selectedPositionId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a target designation.'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    final endorsements = <Map<String, dynamic>>[];
    for (final p in _proposers) {
      if (p.isNotEmpty) {
        endorsements.add(p.toMap());
      }
    }
    for (final s in _supporters) {
      if (s.isNotEmpty) {
        endorsements.add(s.toMap());
      }
    }

    try {
      final dio = ref.read(apiClientProvider);
      await dio.post(
        ApiConstants.electionCandidates(widget.election.id),
        data: {
          'election': widget.election.id,
          'position': _selectedPositionId,
          if (_selectedQuotaId != null && _selectedQuotaId!.isNotEmpty) 'quota': _selectedQuotaId,
          'first_name': _firstNameController.text.trim(),
          'middle_name': _middleNameController.text.trim(),
          'last_name': _lastNameController.text.trim(),
          'email': _emailController.text.trim(),
          'contact_number': _phoneController.text.trim(),
          'gender': _genderController.text.trim(),
          'date_of_birth': _dobController.text.trim().isEmpty ? null : _dobController.text.trim(),
          'address': _addressController.text.trim(),
          'citizenship_number': _citizenshipController.text.trim(),
          'membership_id': _membershipIdController.text.trim(),
          'candidate_image': _candidateImage,
          'personal_description': _personalDescController.text.trim(),
          'contribution_to_org': _contributionController.text.trim(),
          'manifesto': _manifestoController.text.trim(),
          'status': 'approved',
          if (endorsements.isNotEmpty) 'endorsements': endorsements,
        },
      );

      ref.invalidate(electionProvider(widget.election.id));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white),
                const SizedBox(width: 10),
                Text('Candidate "${_firstNameController.text.trim()} ${_lastNameController.text.trim()}" enrolled successfully!'),
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
            content: Text('Failed to add candidate: $e'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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
    final votersAsync = ref.watch(votersProvider(widget.election.id));
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selectedPosition = widget.election.positions.where((p) => p.id == _selectedPositionId).firstOrNull;
    final activeQuotas = selectedPosition?.quotas.where((q) => q.isActive).toList() ?? [];

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: isDark ? AppColors.surface : Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 900),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
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
                          'Nominate Candidate (उम्मेदवार दर्ता)',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Register a candidate for ${widget.election.title} under statutory election rules.',
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

              // Scrollable Form Body
              Expanded(
                child: Form(
                  key: _formKey,
                  child: ListView(
                    children: [
                      // ════════════════════════════════════════════════════════
                      // 1. VOTER AUTO-FILL & DESIGNATION
                      // ════════════════════════════════════════════════════════
                      _buildSectionCard(
                        context,
                        title: '1. Designation & Voter Auto-fill (पद र मतदाता छनोट)',
                        subtitle: 'Pick the contested office and select a registered voter to auto-fill identity details',
                        icon: Icons.military_tech_rounded,
                        isDark: isDark,
                        children: [
                          // Voter Auto-fill Dropdown
                          votersAsync.when(
                            loading: () => const LinearProgressIndicator(),
                            error: (e, _) => Text('Could not load voter roll: $e', style: const TextStyle(color: Colors.red, fontSize: 12)),
                            data: (voters) {
                              return DropdownButtonFormField<String?>(
                                initialValue: _selectedMemberId,
                                isExpanded: true,
                                decoration: _dec(
                                  'Auto-fill from Registered Voter List *',
                                  prefix: const Icon(Icons.person_search_rounded),
                                  isDark: isDark,
                                ),
                                items: [
                                  const DropdownMenuItem<String?>(
                                    value: null,
                                    child: Text('— Select Registered Voter —', style: TextStyle(fontStyle: FontStyle.italic)),
                                  ),
                                  ...voters.map((v) => DropdownMenuItem<String?>(
                                    value: v['id'].toString(),
                                    child: Text(
                                      '${v['first_name']} ${v['last_name']} (${v['voter_id']}) • ${v['email'] ?? "No Email"}',
                                      style: const TextStyle(fontSize: 13),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  )),
                                ],
                                onChanged: (val) {
                                  setState(() {
                                    _selectedMemberId = val;
                                    if (val != null) {
                                      final selectedVoter = voters.firstWhere((v) => v['id'].toString() == val);
                                      _firstNameController.text = selectedVoter['first_name'] ?? '';
                                      _middleNameController.text = selectedVoter['middle_name'] ?? '';
                                      _lastNameController.text = selectedVoter['last_name'] ?? '';
                                      _emailController.text = selectedVoter['email'] ?? '';
                                      _phoneController.text = selectedVoter['phone'] ?? '';
                                      _citizenshipController.text = selectedVoter['citizenship_number'] ?? '';
                                      _membershipIdController.text = selectedVoter['voter_id'] ?? '';
                                    }
                                  });
                                },
                              );
                            },
                          ),
                          const SizedBox(height: 16),

                          // Target Position & Quota Selector Row
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 2,
                                child: DropdownButtonFormField<String>(
                                  initialValue: _selectedPositionId,
                                  decoration: _dec(
                                    'Target Designation *',
                                    prefix: const Icon(Icons.military_tech_rounded),
                                    isDark: isDark,
                                  ),
                                  items: widget.election.positions.map((p) => DropdownMenuItem(
                                    value: p.id,
                                    child: Text('${p.title} (${p.seatsAvailable} seats)'),
                                  )).toList(),
                                  onChanged: (v) {
                                    setState(() {
                                      _selectedPositionId = v;
                                      _selectedQuotaId = null;
                                    });
                                  },
                                  validator: (v) => v == null ? 'Target designation is required' : null,
                                ),
                              ),
                              if (activeQuotas.isNotEmpty) ...[
                                const SizedBox(width: 14),
                                Expanded(
                                  flex: 2,
                                  child: DropdownButtonFormField<String?>(
                                    initialValue: _selectedQuotaId,
                                    decoration: _dec(
                                      'Affirmative Action Quota',
                                      prefix: const Icon(Icons.pie_chart_outline_rounded),
                                      isDark: isDark,
                                    ),
                                    items: [
                                      const DropdownMenuItem<String?>(value: null, child: Text('Open / General (No Quota)')),
                                      ...activeQuotas.map((q) => DropdownMenuItem<String?>(
                                        value: q.id,
                                        child: Text('${q.name} (${q.seats} seat(s))'),
                                      )),
                                    ],
                                    onChanged: (val) => setState(() => _selectedQuotaId = val),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // ════════════════════════════════════════════════════════
                      // 2. CANDIDATE PROFILE & PHOTO
                      // ════════════════════════════════════════════════════════
                      _buildSectionCard(
                        context,
                        title: '2. Candidate Profile & Photo (उम्मेदवार परिचय)',
                        subtitle: 'Full legal name, contact credentials, and official ballot photograph',
                        icon: Icons.person_outline_rounded,
                        isDark: isDark,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _firstNameController,
                                  decoration: _dec('First Name *', hint: 'e.g. Ramesh', isDark: isDark),
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
                          const SizedBox(height: 16),

                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _emailController,
                                  decoration: _dec('Email Address *', prefix: const Icon(Icons.email_outlined), isDark: isDark),
                                  keyboardType: TextInputType.emailAddress,
                                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Email is required' : null,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: TextFormField(
                                  controller: _phoneController,
                                  decoration: _dec('Contact Number *', prefix: const Icon(Icons.phone_outlined), isDark: isDark),
                                  keyboardType: TextInputType.phone,
                                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Phone number is required' : null,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  initialValue: _genderController.text.isNotEmpty ? _genderController.text : 'Male',
                                  decoration: _dec('Gender', prefix: const Icon(Icons.wc_rounded), isDark: isDark),
                                  items: ['Male', 'Female', 'Other'].map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                                  onChanged: (v) => setState(() => _genderController.text = v ?? 'Male'),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: TextFormField(
                                  controller: _dobController,
                                  decoration: _dec('Date of Birth', hint: 'YYYY-MM-DD', prefix: const Icon(Icons.cake_outlined), isDark: isDark),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                flex: 2,
                                child: TextFormField(
                                  controller: _addressController,
                                  decoration: _dec('Address / Municipality', hint: 'e.g. Kathmandu-4', prefix: const Icon(Icons.location_on_outlined), isDark: isDark),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),

                          // Candidate Photo
                          Center(
                            child: Column(
                              children: [
                                Text(
                                  'Candidate Official Portrait (उम्मेदवार फोटो)',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isDark ? Colors.white70 : Colors.grey.shade700),
                                ),
                                const SizedBox(height: 10),
                                ImageUploadWidget(
                                  initialImageUrl: _candidateImage,
                                  placeholderText: 'Upload Candidate Portrait',
                                  onImageUploaded: (url) => setState(() => _candidateImage = url),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // ════════════════════════════════════════════════════════
                      // 3. STATEMENTS & MANIFESTO
                      // ════════════════════════════════════════════════════════
                      _buildSectionCard(
                        context,
                        title: '3. Platform, Vision & Manifesto (घोषणापत्र र विवरण)',
                        subtitle: 'Candidate credentials, contributions to the organization, and election manifesto',
                        icon: Icons.menu_book_rounded,
                        isDark: isDark,
                        children: [
                          TextFormField(
                            controller: _personalDescController,
                            decoration: _dec('Personal Description & Qualifications', hint: 'Brief biographical background...', isDark: isDark),
                            maxLines: 2,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _contributionController,
                            decoration: _dec('Contributions to the Organization', hint: 'Past initiatives, board memberships, leadership roles...', isDark: isDark),
                            maxLines: 2,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _manifestoController,
                            decoration: _dec('Election Manifesto & Platform Agenda *', hint: 'Key commitments and proposed organizational goals...', isDark: isDark),
                            maxLines: 4,
                            validator: (v) => (v == null || v.trim().isEmpty) ? 'Manifesto is required' : null,
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // ════════════════════════════════════════════════════════
                      // 4. STATUTORY MEMBERSHIP IDENTIFIERS
                      // ════════════════════════════════════════════════════════
                      _buildSectionCard(
                        context,
                        title: '4. Legal & Membership Credentials (सदस्यता विवरण)',
                        subtitle: 'National citizenship number and organizational member code',
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
                                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Citizenship number is required' : null,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: TextFormField(
                                  controller: _membershipIdController,
                                  decoration: _dec('Membership Code / Roll ID *', hint: 'e.g. MEM-104', prefix: const Icon(Icons.badge_outlined), isDark: isDark),
                                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Membership ID is required' : null,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // ════════════════════════════════════════════════════════
                      // 5. PROPOSER & SUPPORTER NOMINATORS
                      // ════════════════════════════════════════════════════════
                      _buildSectionCard(
                        context,
                        title: '5. Nominators & Endorsements (प्रस्तावक र समर्थक)',
                        subtitle: 'Statutory proposer and seconder endorsements supporting this candidacy',
                        icon: Icons.draw_rounded,
                        isDark: isDark,
                        children: [
                          // Proposers Header
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'PROPOSERS (प्रस्तावक) — ${_proposers.length}',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: isDark ? Colors.blue.shade300 : const Color(0xFF2563EB)),
                              ),
                              TextButton.icon(
                                onPressed: () => setState(() => _proposers.add(_EndorsementItem(endorsementType: 'proposer'))),
                                icon: const Icon(Icons.add, size: 16),
                                label: const Text('Add Proposer', style: TextStyle(fontSize: 12)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ..._proposers.asMap().entries.map((entry) {
                            final idx = entry.key;
                            final item = entry.value;
                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: isDark ? AppColors.surfaceVariant.withValues(alpha: 0.4) : const Color(0xFFF4F4F5),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.blue.withValues(alpha: isDark ? 0.3 : 0.2)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('Proposer #${idx + 1} (प्रस्तावक)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF2563EB))),
                                      if (_proposers.length > 1)
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                                          visualDensity: VisualDensity.compact,
                                          onPressed: () => setState(() {
                                            item.dispose();
                                            _proposers.removeAt(idx);
                                          }),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      Expanded(child: TextFormField(controller: item.nameCtrl, decoration: _dec('Proposer Full Name', isDark: isDark))),
                                      const SizedBox(width: 12),
                                      Expanded(child: TextFormField(controller: item.citizenCtrl, decoration: _dec('Citizenship Number', isDark: isDark))),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      Expanded(child: TextFormField(controller: item.phoneCtrl, decoration: _dec('Phone Number', isDark: isDark))),
                                      const SizedBox(width: 12),
                                      Expanded(child: TextFormField(controller: item.memIdCtrl, decoration: _dec('Membership ID', isDark: isDark))),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Text('Proposer Signature:', style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.grey.shade700)),
                                      const SizedBox(width: 14),
                                      ImageUploadWidget(
                                        initialImageUrl: item.signatureUrl,
                                        placeholderText: 'Upload Sign',
                                        radius: 28,
                                        onImageUploaded: (url) => setState(() => item.signatureUrl = url),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          }),
                          const SizedBox(height: 16),
                          const Divider(height: 1),
                          const SizedBox(height: 16),

                          // Supporters Header
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'SUPPORTERS (समर्थक) — ${_supporters.length}',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: isDark ? Colors.green.shade300 : const Color(0xFF059669)),
                              ),
                              TextButton.icon(
                                onPressed: () => setState(() => _supporters.add(_EndorsementItem(endorsementType: 'supporter'))),
                                icon: const Icon(Icons.add, size: 16),
                                label: const Text('Add Supporter', style: TextStyle(fontSize: 12)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ..._supporters.asMap().entries.map((entry) {
                            final idx = entry.key;
                            final item = entry.value;
                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: isDark ? AppColors.surfaceVariant.withValues(alpha: 0.4) : const Color(0xFFF4F4F5),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.green.withValues(alpha: isDark ? 0.3 : 0.2)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('Supporter #${idx + 1} (समर्थक)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF059669))),
                                      if (_supporters.length > 1)
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                                          visualDensity: VisualDensity.compact,
                                          onPressed: () => setState(() {
                                            item.dispose();
                                            _supporters.removeAt(idx);
                                          }),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      Expanded(child: TextFormField(controller: item.nameCtrl, decoration: _dec('Supporter Full Name', isDark: isDark))),
                                      const SizedBox(width: 12),
                                      Expanded(child: TextFormField(controller: item.citizenCtrl, decoration: _dec('Citizenship Number', isDark: isDark))),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      Expanded(child: TextFormField(controller: item.phoneCtrl, decoration: _dec('Phone Number', isDark: isDark))),
                                      const SizedBox(width: 12),
                                      Expanded(child: TextFormField(controller: item.memIdCtrl, decoration: _dec('Membership ID', isDark: isDark))),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Text('Supporter Signature:', style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.grey.shade700)),
                                      const SizedBox(width: 14),
                                      ImageUploadWidget(
                                        initialImageUrl: item.signatureUrl,
                                        placeholderText: 'Upload Sign',
                                        radius: 28,
                                        onImageUploaded: (url) => setState(() => item.signatureUrl = url),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          }),
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
                    label: 'Enroll Candidate',
                    icon: Icons.how_to_reg_rounded,
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
