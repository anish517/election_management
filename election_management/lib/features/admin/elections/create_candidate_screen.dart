import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_constants.dart';
import '../../../core/providers/admin_providers.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_theme.dart';
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
        'phone': phoneCtrl.text.trim(),
        'citizenship_number': citizenCtrl.text.trim(),
        'membership_id': memIdCtrl.text.trim(),
        'signature_url': signatureUrl,
      };
}

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
  String _selectedGender = 'Male';
  final _dobController = TextEditingController();
  final _addressController = TextEditingController();

  String _candidateImageUrl = '';

  final _personalDescriptionController = TextEditingController();
  final _manifestoController = TextEditingController();

  // Affiliation, Symbol & PR Rank
  final _partyController = TextEditingController();
  final _panelController = TextEditingController();
  final _symbolNameController = TextEditingController();
  String _symbolImageUrl = '';
  final _prRankController = TextEditingController(text: '1');

  // Dynamic Multi-Proposers & Multi-Supporters
  late List<_EndorsementItem> _proposers;
  late List<_EndorsementItem> _supporters;

  bool _isSubmitting = false;

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
    _contactController.dispose();
    _dobController.dispose();
    _addressController.dispose();
    _personalDescriptionController.dispose();
    _manifestoController.dispose();
    _partyController.dispose();
    _panelController.dispose();
    _symbolNameController.dispose();
    _prRankController.dispose();
    for (final p in _proposers) {
      p.dispose();
    }
    for (final s in _supporters) {
      s.dispose();
    }
    super.dispose();
  }

  void _submit() async {
    final election = ref.read(electionProvider(widget.electionId)).valueOrNull;
    final isSamanupatik = election?.isSamanupatik ?? false;

    if (isSamanupatik && _selectedPositionId == null && (election?.positions.isNotEmpty ?? false)) {
      _selectedPositionId = election!.positions.first.id;
    }

    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please complete all required fields.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (_selectedPositionId == null && !isSamanupatik) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a designation.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (isSamanupatik && _partyController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Political Party affiliation is strictly required for Samānupātik nomination.'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (_selectedVoterId == null && _emailController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a voter from the registered voter list.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final emailToSubmit = _emailController.text.trim().toLowerCase();
    final phoneToSubmit = _contactController.text.trim();
    final nameToSubmit = '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}'.trim().toLowerCase();

    if (election != null) {
      for (final pos in election.positions) {
        for (final c in pos.candidates) {
          final cEmail = (c.email ?? '').trim().toLowerCase();
          final cPhone = (c.contactNumber ?? '').trim();
          final cName = c.name.trim().toLowerCase();

          if (emailToSubmit.isNotEmpty && cEmail.isNotEmpty && emailToSubmit == cEmail) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.white),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('Candidate with email "$emailToSubmit" is already nominated for "${pos.title}" in this election.'),
                    ),
                  ],
                ),
                backgroundColor: Colors.red.shade700,
                behavior: SnackBarBehavior.floating,
              ),
            );
            return;
          }

          if (phoneToSubmit.isNotEmpty && cPhone.isNotEmpty && phoneToSubmit == cPhone) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.white),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('Candidate with contact number "$phoneToSubmit" is already nominated for "${pos.title}" in this election.'),
                    ),
                  ],
                ),
                backgroundColor: Colors.red.shade700,
                behavior: SnackBarBehavior.floating,
              ),
            );
            return;
          }

          if (nameToSubmit.isNotEmpty && cName.isNotEmpty && nameToSubmit == cName) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.white),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('Candidate "${c.name}" is already nominated for "${pos.title}" in this election.'),
                    ),
                  ],
                ),
                backgroundColor: Colors.red.shade700,
                behavior: SnackBarBehavior.floating,
              ),
            );
            return;
          }
        }
      }
    }

    setState(() => _isSubmitting = true);

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
        ApiConstants.electionCandidates(widget.electionId),
        data: {
          'election': widget.electionId,
          'position': _selectedPositionId,
          if (_selectedQuotaId != null && _selectedQuotaId!.isNotEmpty) 'quota': _selectedQuotaId,
          'first_name': _firstNameController.text.trim(),
          'middle_name': _middleNameController.text.trim(),
          'last_name': _lastNameController.text.trim(),
          'email': _emailController.text.trim(),
          'contact_number': _contactController.text.trim(),
          'gender': _selectedGender,
          'date_of_birth': _dobController.text.trim().isNotEmpty ? _dobController.text.trim() : null,
          'address': _addressController.text.trim(),
          'candidate_image': _candidateImageUrl,
          'photo_url': _candidateImageUrl,
          'personal_description': _personalDescriptionController.text.trim(),
          'manifesto': _manifestoController.text.trim(),
          'status': 'approved', // Auto approve for admin creation
          'party_name': _partyController.text.trim(),
          'panel_name': _panelController.text.trim(),
          'symbol_name': _symbolNameController.text.trim(),
          'symbol_image': _symbolImageUrl,
          'pr_rank': int.tryParse(_prRankController.text.trim()) ?? 1,
          if (endorsements.isNotEmpty) 'endorsements': endorsements,
        },
      );

      ref.invalidate(electionProvider(widget.electionId));
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
            content: Text('Failed to create candidate: $e'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _pickMemberForEndorsement({
    required TextEditingController nameCtrl,
    required TextEditingController phoneCtrl,
    required TextEditingController memIdCtrl,
    required TextEditingController citizenCtrl,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Consumer(
          builder: (context, ref, _) {
            final membersAsync = ref.watch(membersProvider);
            return Container(
              decoration: BoxDecoration(
                color: isDark ? AppColors.surface : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: DraggableScrollableSheet(
                initialChildSize: 0.65,
                minChildSize: 0.4,
                maxChildSize: 0.9,
                expand: false,
                builder: (ctx, scrollCtrl) {
                  return Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.people_outline_rounded, color: AppColors.primaryLight, size: 20),
                                ),
                                const SizedBox(width: 12),
                                const Text(
                                  'Select Endorser from Member Roster',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            IconButton(
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () => Navigator.pop(ctx),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Divider(height: 1),
                        const SizedBox(height: 12),
                        Expanded(
                          child: membersAsync.when(
                            loading: () => const Center(child: CircularProgressIndicator()),
                            error: (e, _) => Center(child: Text('Error loading members: $e', style: const TextStyle(color: Colors.red))),
                            data: (members) {
                              if (members.isEmpty) {
                                return const Center(child: Text('No members found in organization roster.'));
                              }
                              return ListView.separated(
                                controller: scrollCtrl,
                                itemCount: members.length,
                                separatorBuilder: (_, _) => const Divider(height: 1),
                                itemBuilder: (ctx, idx) {
                                  final m = members[idx];
                                  return ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                                      child: Text(
                                        m.fullName.isNotEmpty ? m.fullName[0].toUpperCase() : '?',
                                        style: const TextStyle(color: AppColors.primaryLight, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    title: Text(m.fullName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                    subtitle: Text('${m.email} • Code: #${m.memberCode.isNotEmpty ? m.memberCode : "N/A"}', style: const TextStyle(fontSize: 12)),
                                    trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey),
                                    onTap: () {
                                      nameCtrl.text = m.fullName;
                                      phoneCtrl.text = m.phone;
                                      memIdCtrl.text = m.memberCode;
                                      if (m.citizenshipNumber.isNotEmpty) {
                                        citizenCtrl.text = m.citizenshipNumber;
                                      }
                                      Navigator.pop(ctx);
                                    },
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  InputDecoration _dec(
    String label, {
    String? hint,
    Widget? prefix,
    String? helper,
    bool isDark = false,
    bool readOnly = false,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helper,
      prefixIcon: prefix,
      filled: true,
      fillColor: readOnly
          ? (isDark ? Colors.white10 : Colors.grey.shade100)
          : (isDark ? AppColors.surfaceVariant.withValues(alpha: 0.5) : const Color(0xFFF9FAFB)),
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
    final electionAsync = ref.watch(electionProvider(widget.electionId));
    final votersAsync = ref.watch(votersProvider(widget.electionId));
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Nominate Candidate', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Text(
              'उम्मेदवार मनोनयन तथा दर्ता',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white70 : AppColors.textSecondaryLightMode,
              ),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Hero Header Banner
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isDark
                            ? [const Color(0xFF1E1B4B), const Color(0xFF312E81)]
                            : [const Color(0xFF4F46E5), const Color(0xFF6366F1)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF4F46E5).withValues(alpha: 0.25),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(Icons.how_to_reg_rounded, color: Colors.white, size: 32),
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Candidate Nomination & Scrutiny Filing',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Enroll an elector from the verified voter roll into contested designations and affirmative action quotas.',
                                style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ════════════════════════════════════════════════════════
                  // 1. VOTER ROLL AUTO-FILL SELECTION
                  // ════════════════════════════════════════════════════════
                  _buildSectionCard(
                    context,
                    title: '1. Electoral Roll & Voter Selection (मतदाता छनोट) *',
                    subtitle: 'Candidate must originate from the approved preliminary voter list',
                    icon: Icons.person_search_rounded,
                    isDark: isDark,
                    children: [
                      votersAsync.when(
                        loading: () => const LinearProgressIndicator(),
                        error: (e, _) => Text('Error loading voters: $e', style: const TextStyle(color: Colors.red, fontSize: 12)),
                        data: (voters) {
                          if (voters.isEmpty) {
                            return Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: isDark ? AppColors.surfaceVariant : const Color(0xFFF4F4F5),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Text('No registered voters found for this election. Please enroll voters first.', style: TextStyle(fontSize: 12)),
                            );
                          }

                          // Build lookup of already nominated voters by email / phone
                          final nominatedVoters = <String, String>{}; // key -> position title
                          final electionData = electionAsync.valueOrNull;
                          if (electionData != null) {
                            for (final pos in electionData.positions) {
                              for (final c in pos.candidates) {
                                final cEmail = (c.email ?? '').trim().toLowerCase();
                                final cPhone = (c.contactNumber ?? '').trim();
                                if (cEmail.isNotEmpty) {
                                  nominatedVoters[cEmail] = pos.title;
                                }
                                if (cPhone.isNotEmpty) {
                                  nominatedVoters[cPhone] = pos.title;
                                }
                              }
                            }
                          }

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              DropdownButtonFormField<String>(
                                initialValue: _selectedVoterId,
                                isExpanded: true,
                                decoration: _dec(
                                  'Select Qualified Voter *',
                                  prefix: const Icon(Icons.how_to_vote_outlined),
                                  isDark: isDark,
                                ),
                                items: voters.map((v) {
                                  final fullName = v['full_name'] ?? '${v['first_name']} ${v['last_name']}';
                                  final email = (v['email'] ?? '').toString().trim();
                                  final phone = (v['phone'] ?? '').toString().trim();
                                  final voterId = v['voter_id'] ?? v['id'];

                                  String? nominatedPos = nominatedVoters[email.toLowerCase()];
                                  if (nominatedPos == null && phone.isNotEmpty) {
                                    nominatedPos = nominatedVoters[phone];
                                  }
                                  final isNominated = nominatedPos != null;

                                  return DropdownMenuItem(
                                    value: isNominated ? null : v['id'].toString(),
                                    enabled: !isNominated,
                                    child: Text(
                                      isNominated
                                          ? '$fullName ($email) • ⚠️ Already Nominated for $nominatedPos'
                                          : '$fullName ($email) • ID: $voterId',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: isNominated ? Colors.grey : null,
                                        fontStyle: isNominated ? FontStyle.italic : null,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  if (val == null) return;
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
                              if (_selectedVoterId != null) ...[
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
                                        'Candidate identity credentials synchronized from official voter roll.',
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
                  const SizedBox(height: 20),

                  // ════════════════════════════════════════════════════════
                  // 2. CONTESTED POSITION & QUOTA ALLOCATION
                  // ════════════════════════════════════════════════════════
                  _buildSectionCard(
                    context,
                    title: (electionAsync.valueOrNull?.isSamanupatik ?? false)
                        ? '2. Samānupātik Closed List Allocation (समानुपातिक बन्दसूची)'
                        : '2. Contested Office & Quota Allocation (पद तथा कोटा विवरण)',
                    subtitle: (electionAsync.valueOrNull?.isSamanupatik ?? false)
                        ? 'Electoral candidate registration to the party closed list and inclusion quotas'
                        : 'Electoral designation and affirmative action quota allocation',
                    icon: Icons.military_tech_rounded,
                    isDark: isDark,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Designation Dropdown
                          Expanded(
                            child: electionAsync.when(
                              loading: () => const LinearProgressIndicator(),
                              error: (_, _) => const Text('Error loading designations', style: TextStyle(color: Colors.red)),
                              data: (election) {
                                final isSam = election.isSamanupatik;
                                final initialVal = _selectedPositionId ?? (isSam ? election.positions.firstOrNull?.id : null);
                                if (isSam && _selectedPositionId == null && election.positions.isNotEmpty) {
                                  WidgetsBinding.instance.addPostFrameCallback((_) {
                                    if (mounted && _selectedPositionId == null) {
                                      setState(() => _selectedPositionId = election.positions.first.id);
                                    }
                                  });
                                }
                                return DropdownButtonFormField<String>(
                                  initialValue: initialVal,
                                  isExpanded: true,
                                  decoration: _dec(
                                    isSam ? 'Samānupātik List (समानुपातिक सूची) *' : 'Contested Designation *',
                                    prefix: const Icon(Icons.badge_outlined),
                                    isDark: isDark,
                                  ),
                                  items: election.positions.map((p) => DropdownMenuItem(
                                    value: p.id,
                                    child: Text('${p.title} (${p.seatsAvailable} seat${p.seatsAvailable > 1 ? "s" : ""})', style: const TextStyle(fontSize: 13)),
                                  )).toList(),
                                  onChanged: (val) {
                                    setState(() {
                                      _selectedPositionId = val;
                                      _selectedQuotaId = null;
                                    });
                                  },
                                  validator: (v) {
                                    if (isSam && election.positions.isEmpty) return null;
                                    return v == null ? 'Designation is required' : null;
                                  },
                                );
                              },
                            ),
                          ),
                          // Dynamic Quota Dropdown
                          if (_selectedPositionId != null) ...[
                            ...electionAsync.maybeWhen(
                              data: (election) {
                                final selectedPos = election.positions.where((p) => p.id == _selectedPositionId).firstOrNull;
                                if (selectedPos != null && selectedPos.quotas.isNotEmpty) {
                                  final activeQuotas = selectedPos.quotas.where((q) => q.isActive).toList();
                                  if (activeQuotas.isNotEmpty) {
                                    return [
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: DropdownButtonFormField<String?>(
                                          initialValue: _selectedQuotaId,
                                          isExpanded: true,
                                          decoration: _dec('Quota Category', prefix: const Icon(Icons.category_outlined), isDark: isDark),
                                          items: [
                                            const DropdownMenuItem<String?>(value: null, child: Text('Open / General (No Quota)')),
                                            ...activeQuotas.map((q) => DropdownMenuItem<String?>(
                                              value: q.id,
                                              child: Text('${q.name} (${q.seats} seat(s))', style: const TextStyle(fontSize: 13)),
                                            )),
                                          ],
                                          onChanged: (val) => setState(() => _selectedQuotaId = val),
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
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // ════════════════════════════════════════════════════════
                  // 3. CANDIDATE PROFILE & PORTRAIT
                  // ════════════════════════════════════════════════════════
                  _buildSectionCard(
                    context,
                    title: '3. Candidate Profile & Portrait (उम्मेदवार परिचय र फोटो)',
                    subtitle: 'Full legal nomenclature, contact channels, and official ballot photo',
                    icon: Icons.person_outline_rounded,
                    isDark: isDark,
                    children: [
                      // Name Row
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
                      const SizedBox(height: 16),

                      // Email & Phone
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _emailController,
                              readOnly: true,
                              decoration: _dec('Email Address (Voter Roll) *', prefix: const Icon(Icons.email_outlined), readOnly: true, isDark: isDark),
                              validator: (v) => (v == null || v.trim().isEmpty) ? 'Email is required' : null,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: TextFormField(
                              controller: _contactController,
                              decoration: _dec('Contact Mobile Number *', hint: 'e.g. 98XXXXXXXX', prefix: const Icon(Icons.phone_outlined), isDark: isDark),
                              keyboardType: TextInputType.phone,
                              validator: (v) => (v == null || v.trim().isEmpty) ? 'Phone number is required' : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Gender, DOB, Address
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _selectedGender,
                              decoration: _dec('Gender *', prefix: const Icon(Icons.wc_rounded), isDark: isDark),
                              items: const [
                                DropdownMenuItem(value: 'Male', child: Text('Male')),
                                DropdownMenuItem(value: 'Female', child: Text('Female')),
                                DropdownMenuItem(value: 'Other', child: Text('Other')),
                              ],
                              onChanged: (val) {
                                if (val != null) setState(() => _selectedGender = val);
                              },
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
                            child: TextFormField(
                              controller: _addressController,
                              decoration: _dec('Address / Municipality', hint: 'e.g. Kathmandu-4', prefix: const Icon(Icons.location_on_outlined), isDark: isDark),
                            ),
                          ),
                        ],
                      ),
                      if (electionAsync.valueOrNull?.enableCandidatePhoto == true) ...[
                        const SizedBox(height: 20),
                        Center(
                          child: Column(
                            children: [
                              Text(
                                'Candidate Official Portrait (उम्मेदवार फोटो)',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isDark ? Colors.white70 : Colors.grey.shade700),
                              ),
                              const SizedBox(height: 10),
                              ImageUploadWidget(
                                initialImageUrl: _candidateImageUrl,
                                placeholderText: _firstNameController.text.isNotEmpty
                                    ? _firstNameController.text[0].toUpperCase()
                                    : 'C',
                                radius: 40,
                                onImageUploaded: (url) => setState(() => _candidateImageUrl = url),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 20),

                  // ════════════════════════════════════════════════════════
                  // AFFILIATION, SYMBOL & PR RANK
                  // ════════════════════════════════════════════════════════
                  if (electionAsync.valueOrNull?.enableParty == true ||
                      electionAsync.valueOrNull?.enablePanel == true ||
                      electionAsync.valueOrNull?.enableSymbol == true ||
                      electionAsync.valueOrNull?.hasPrSystem == true ||
                      (electionAsync.valueOrNull?.isSamanupatik ?? false)) ...[
                    _buildSectionCard(
                      context,
                      title: 'Affiliation & Election Symbol (दल, प्यानल तथा चुनाव चिन्ह)',
                      subtitle: 'Configure political party, group panel, election symbol, and PR list rank',
                      icon: Icons.flag_rounded,
                      isDark: isDark,
                      children: [
                        if (electionAsync.valueOrNull?.enableParty == true ||
                            electionAsync.valueOrNull?.enablePanel == true ||
                            (electionAsync.valueOrNull?.isSamanupatik ?? false)) ...[
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (electionAsync.valueOrNull?.enableParty == true ||
                                  (electionAsync.valueOrNull?.isSamanupatik ?? false))
                                Expanded(
                                  child: TextFormField(
                                    controller: _partyController,
                                    decoration: _dec(
                                      (electionAsync.valueOrNull?.isSamanupatik ?? false)
                                          ? 'Political Party (राजनीतिक दल) *'
                                          : 'Political Party (राजनीतिक दल)',
                                      hint: 'e.g. Nepali Congress, UML, RPP...',
                                      prefix: const Icon(Icons.flag_outlined),
                                      isDark: isDark,
                                    ),
                                    validator: (electionAsync.valueOrNull?.isSamanupatik ?? false)
                                        ? (v) => (v == null || v.trim().isEmpty) ? 'Party affiliation is required for Samānupātik' : null
                                        : null,
                                  ),
                                ),
                              if ((electionAsync.valueOrNull?.enableParty == true ||
                                      (electionAsync.valueOrNull?.isSamanupatik ?? false)) &&
                                  electionAsync.valueOrNull?.enablePanel == true)
                                const SizedBox(width: 14),
                              if (electionAsync.valueOrNull?.enablePanel == true)
                                Expanded(
                                  child: TextFormField(
                                    controller: _panelController,
                                    decoration: _dec(
                                      'Panel / Slate (प्यानल / समूह)',
                                      hint: 'e.g. Progressive Slate',
                                      prefix: const Icon(Icons.group_work_outlined),
                                      isDark: isDark,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 16),
                        ],

                        if (electionAsync.valueOrNull?.enableSymbol == true ||
                            (electionAsync.valueOrNull?.isSamanupatik ?? false)) ...[
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 3,
                                child: TextFormField(
                                  controller: _symbolNameController,
                                  decoration: _dec(
                                    'Election Symbol Name (चुनाव चिन्ह)',
                                    hint: 'e.g. Sun (सूर्य), Tree (रुख)',
                                    prefix: const Icon(Icons.how_to_vote_outlined),
                                    isDark: isDark,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                flex: 2,
                                child: Center(
                                  child: ImageUploadWidget(
                                    initialImageUrl: _symbolImageUrl,
                                    placeholderText: 'Symbol Icon',
                                    radius: 28,
                                    onImageUploaded: (url) => setState(() => _symbolImageUrl = url),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                        ],

                        if (electionAsync.valueOrNull?.hasPrSystem == true ||
                            (electionAsync.valueOrNull?.isSamanupatik ?? false)) ...[
                          TextFormField(
                            controller: _prRankController,
                            keyboardType: TextInputType.number,
                            decoration: _dec(
                              (electionAsync.valueOrNull?.isSamanupatik ?? false)
                                  ? 'PR Closed List Priority Rank (समानुपातिक सूची वरियता क्रम) *'
                                  : 'PR Closed List Priority Rank (समानुपातिक सूची वरियता क्रम)',
                              hint: 'e.g. 1 for Top candidate, 2, 3...',
                              prefix: const Icon(Icons.format_list_numbered_rounded),
                              helper: 'Determines election order on the party\'s closed list',
                              isDark: isDark,
                            ),
                            validator: (electionAsync.valueOrNull?.isSamanupatik ?? false)
                                ? (v) => (v == null || v.trim().isEmpty) ? 'PR list rank (e.g. 1, 2, 3) is required' : null
                                : null,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 20),
                  ],

                  // ════════════════════════════════════════════════════════
                  // 4. PLATFORM, MANIFESTO & VISION
                  // ════════════════════════════════════════════════════════
                  _buildSectionCard(
                    context,
                    title: '4. Platform, Vision & Manifesto (घोषणापत्र र विवरण)',
                    subtitle: 'Biographical summary and election platform agenda',
                    icon: Icons.menu_book_rounded,
                    isDark: isDark,
                    children: [
                      TextFormField(
                        controller: _personalDescriptionController,
                        decoration: _dec(
                          'Personal Description & Qualifications',
                          hint: 'Biographical summary, expertise, and service history...',
                          prefix: const Icon(Icons.description_outlined),
                          isDark: isDark,
                        ),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _manifestoController,
                        decoration: _dec(
                          'Nomination Manifesto / Platform Agenda *',
                          hint: 'Key commitments and proposed organizational initiatives...',
                          prefix: const Icon(Icons.menu_book_rounded),
                          isDark: isDark,
                        ),
                        maxLines: 4,
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Manifesto is required' : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // ════════════════════════════════════════════════════════
                  // 5. STATUTORY NOMINATORS & ENDORSEMENTS
                  // ════════════════════════════════════════════════════════
                  _buildSectionCard(
                    context,
                    title: '5. Nominators & Endorsements (प्रस्तावक र समर्थक)',
                    subtitle: 'Official proposer and supporter endorsements supporting this candidacy',
                    icon: Icons.draw_rounded,
                    isDark: isDark,
                    children: [
                      // Section A: Proposers (प्रस्तावक)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF2563EB).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.how_to_reg_rounded, size: 16, color: Color(0xFF2563EB)),
                                    const SizedBox(width: 6),
                                    Text(
                                      'PROPOSERS (प्रस्तावक) — ${_proposers.length}',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Color(0xFF2563EB)),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          OutlinedButton.icon(
                            onPressed: () {
                              setState(() {
                                _proposers.add(_EndorsementItem(endorsementType: 'proposer'));
                              });
                            },
                            icon: const Icon(Icons.add_rounded, size: 16),
                            label: const Text('Add Proposer', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF2563EB),
                              side: const BorderSide(color: Color(0xFF2563EB)),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ..._proposers.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final item = entry.value;
                        return _buildDynamicEndorsementCard(
                          item: item,
                          index: idx,
                          totalCount: _proposers.length,
                          roleTitle: 'PROPOSER (प्रस्तावक) #${idx + 1}',
                          roleSubtitle: 'Primary nominator who proposes this candidate',
                          primaryColor: const Color(0xFF2563EB),
                          roleIcon: Icons.how_to_reg_rounded,
                          isDark: isDark,
                          onRemove: _proposers.length > 1
                              ? () {
                                  setState(() {
                                    item.dispose();
                                    _proposers.removeAt(idx);
                                  });
                                }
                              : null,
                          onPickRoster: () => _pickMemberForEndorsement(
                            nameCtrl: item.nameCtrl,
                            phoneCtrl: item.phoneCtrl,
                            memIdCtrl: item.memIdCtrl,
                            citizenCtrl: item.citizenCtrl,
                          ),
                          onSignatureUploaded: (url) => setState(() => item.signatureUrl = url),
                        );
                      }),
                      const SizedBox(height: 20),
                      const Divider(height: 1),
                      const SizedBox(height: 20),

                      // Section B: Supporters (समर्थक)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF059669).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.verified_user_rounded, size: 16, color: Color(0xFF059669)),
                                    const SizedBox(width: 6),
                                    Text(
                                      'SUPPORTERS (समर्थक) — ${_supporters.length}',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Color(0xFF059669)),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          OutlinedButton.icon(
                            onPressed: () {
                              setState(() {
                                _supporters.add(_EndorsementItem(endorsementType: 'supporter'));
                              });
                            },
                            icon: const Icon(Icons.add_rounded, size: 16),
                            label: const Text('Add Supporter', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF059669),
                              side: const BorderSide(color: Color(0xFF059669)),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ..._supporters.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final item = entry.value;
                        return _buildDynamicEndorsementCard(
                          item: item,
                          index: idx,
                          totalCount: _supporters.length,
                          roleTitle: 'SUPPORTER (समर्थक) #${idx + 1}',
                          roleSubtitle: 'Secondary member who backs and seconds this nomination',
                          primaryColor: const Color(0xFF059669),
                          roleIcon: Icons.verified_user_rounded,
                          isDark: isDark,
                          onRemove: _supporters.length > 1
                              ? () {
                                  setState(() {
                                    item.dispose();
                                    _supporters.removeAt(idx);
                                  });
                                }
                              : null,
                          onPickRoster: () => _pickMemberForEndorsement(
                            nameCtrl: item.nameCtrl,
                            phoneCtrl: item.phoneCtrl,
                            memIdCtrl: item.memIdCtrl,
                            citizenCtrl: item.citizenCtrl,
                          ),
                          onSignatureUploaded: (url) => setState(() => item.signatureUrl = url),
                        );
                      }),
                    ],
                  ),
                  const SizedBox(height: 32),

                  // Bottom Action Toolbar
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton(
                        onPressed: _isSubmitting ? null : () => context.pop(),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 16),
                      LoadingButton(
                        isLoading: _isSubmitting,
                        label: 'Enroll Candidate',
                        icon: Icons.how_to_reg_rounded,
                        onPressed: _submit,
                        fullWidth: false,
                      ),
                    ],
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

  Widget _buildSectionCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isDark,
    required List<Widget> children,
  }) {
    return Material(
      color: isDark ? AppColors.surfaceVariant.withValues(alpha: 0.3) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.shade200,
        ),
      ),
      elevation: isDark ? 0 : 2,
      shadowColor: Colors.black.withValues(alpha: 0.04),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: AppColors.primaryLight, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      Text(subtitle, style: TextStyle(color: isDark ? Colors.white60 : Colors.grey.shade600, fontSize: 11)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildDynamicEndorsementCard({
    required _EndorsementItem item,
    required int index,
    required int totalCount,
    required String roleTitle,
    required String roleSubtitle,
    required Color primaryColor,
    required IconData roleIcon,
    required bool isDark,
    required VoidCallback? onRemove,
    required VoidCallback onPickRoster,
    required ValueChanged<String> onSignatureUploaded,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceVariant.withValues(alpha: 0.4) : const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: primaryColor.withValues(alpha: 0.3), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: 0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              border: Border(bottom: BorderSide(color: primaryColor.withValues(alpha: 0.15))),
            ),
            child: Row(
              children: [
                Icon(roleIcon, size: 18, color: primaryColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(roleTitle, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: primaryColor)),
                      Text(roleSubtitle, style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : Colors.grey.shade600)),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: onPickRoster,
                  icon: const Icon(Icons.people_outline, size: 14),
                  label: const Text('Pick from Roster', style: TextStyle(fontSize: 11)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: primaryColor,
                    side: BorderSide(color: primaryColor.withValues(alpha: 0.4)),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                if (onRemove != null) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red),
                    tooltip: 'Remove',
                    visualDensity: VisualDensity.compact,
                    onPressed: onRemove,
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: item.nameCtrl,
                        decoration: _dec('Full Legal Name', hint: 'e.g. Ram Bahadur', isDark: isDark),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: TextFormField(
                        controller: item.phoneCtrl,
                        decoration: _dec('Contact Phone', hint: '98XXXXXXXX', isDark: isDark),
                        keyboardType: TextInputType.phone,
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
                        controller: item.memIdCtrl,
                        decoration: _dec('Voter ID / Member Code', hint: 'e.g. MEM-101', isDark: isDark),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: TextFormField(
                        controller: item.citizenCtrl,
                        decoration: _dec('Citizenship / Council No', hint: 'e.g. 27-01-76-12345', isDark: isDark),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Text('Endorsement Signature: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: isDark ? Colors.white70 : Colors.grey.shade700)),
                    const SizedBox(width: 14),
                    ImageUploadWidget(
                      initialImageUrl: item.signatureUrl,
                      placeholderText: 'Upload Sign',
                      radius: 28,
                      onImageUploaded: onSignatureUploaded,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

