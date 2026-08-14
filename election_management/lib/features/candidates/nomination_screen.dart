import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import '../../core/providers/app_providers.dart';
import '../../core/network/api_constants.dart';
import '../../core/network/api_client.dart';
import '../../shared/widgets/loading_button.dart';
import '../../shared/widgets/image_upload_widget.dart';
import '../candidates/nomination_list_screen.dart';
import '../../core/providers/auth_provider.dart';

class NominationScreen extends ConsumerStatefulWidget {
  final String electionId;
  const NominationScreen({super.key, required this.electionId});

  @override
  ConsumerState<NominationScreen> createState() => _NominationScreenState();
}

class _NominationScreenState extends ConsumerState<NominationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _manifestoController = TextEditingController();
  String? _selectedPositionId;
  String? _selectedQuotaId;
  String _photoUrl = '';
  bool _isSubmitting = false;

  final _proposerNameCtrl = TextEditingController();
  final _proposerPhoneCtrl = TextEditingController();
  final _proposerCitizenshipCtrl = TextEditingController();
  final _proposerVoterIdCtrl = TextEditingController();
  String _proposerSignatureUrl = '';

  final _supporterNameCtrl = TextEditingController();
  final _supporterPhoneCtrl = TextEditingController();
  final _supporterCitizenshipCtrl = TextEditingController();
  final _supporterVoterIdCtrl = TextEditingController();
  String _supporterSignatureUrl = '';

  @override
  void dispose() {
    _manifestoController.dispose();
    _proposerNameCtrl.dispose();
    _proposerPhoneCtrl.dispose();
    _proposerCitizenshipCtrl.dispose();
    _proposerVoterIdCtrl.dispose();
    _supporterNameCtrl.dispose();
    _supporterPhoneCtrl.dispose();
    _supporterCitizenshipCtrl.dispose();
    _supporterVoterIdCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedPositionId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a position.')));
      return;
    }

    if (_proposerNameCtrl.text.trim().toLowerCase() == _supporterNameCtrl.text.trim().toLowerCase() && _proposerNameCtrl.text.trim().isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Proposer and Supporter must be different individuals.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final dio = ref.read(apiClientProvider);
      await dio.post(ApiConstants.electionCandidates(widget.electionId), data: {
        'position': _selectedPositionId,
        if (_selectedQuotaId != null && _selectedQuotaId!.isNotEmpty) 'quota': _selectedQuotaId,
        'manifesto': _manifestoController.text.trim(),
        'candidate_image': _photoUrl,
        'election': widget.electionId,
        'endorsements': [
          {
            'endorsement_type': 'proposer',
            'name': _proposerNameCtrl.text.trim(),
            'phone': _proposerPhoneCtrl.text.trim(),
            'citizenship_number': _proposerCitizenshipCtrl.text.trim(),
            'membership_id': _proposerVoterIdCtrl.text.trim(),
            'signature_url': _proposerSignatureUrl,
          },
          {
            'endorsement_type': 'supporter',
            'name': _supporterNameCtrl.text.trim(),
            'phone': _supporterPhoneCtrl.text.trim(),
            'citizenship_number': _supporterCitizenshipCtrl.text.trim(),
            'membership_id': _supporterVoterIdCtrl.text.trim(),
            'signature_url': _supporterSignatureUrl,
          }
        ],
      });

      if (mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Nomination submitted successfully!')));
      }
    } on DioException catch (e) {
      String msg = 'Submission failed';
      if (e.response?.data is Map) {
        final data = e.response!.data as Map;
        if (data.containsKey('error')) {
          msg = data['error'].toString();
        } else if (data.containsKey('non_field_errors')) {
          msg = (data['non_field_errors'] as List).join(', ');
        } else if (data.values.isNotEmpty) {
          msg = data.values.first.toString();
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Consumer(
          builder: (context, ref, _) {
            final membersAsync = ref.watch(membersProvider);
            return DraggableScrollableSheet(
              initialChildSize: 0.6,
              minChildSize: 0.4,
              maxChildSize: 0.85,
              expand: false,
              builder: (ctx, scrollCtrl) {
                return Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Select from Member Roster',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: membersAsync.when(
                          loading: () => const Center(child: CircularProgressIndicator()),
                          error: (e, _) => Center(child: Text('Error loading members: $e')),
                          data: (members) {
                            if (members.isEmpty) {
                              return const Center(child: Text('No members found in organization.'));
                            }
                            return ListView.separated(
                              controller: scrollCtrl,
                              itemCount: members.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (ctx, idx) {
                                final m = members[idx];
                                return ListTile(
                                  leading: CircleAvatar(
                                    child: Text(m.fullName.isNotEmpty ? m.fullName[0].toUpperCase() : '?'),
                                  ),
                                  title: Text(m.fullName, style: const TextStyle(fontWeight: FontWeight.w600)),
                                  subtitle: Text('${m.email} • #${m.memberCode}'),
                                  trailing: const Icon(Icons.check_circle_outline, size: 20),
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
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final electionAsync = ref.watch(electionProvider(widget.electionId));

    return Scaffold(
      appBar: AppBar(title: const Text('Self Nomination')),
      body: electionAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (election) {
          if (election.positions.isEmpty) {
            return const Center(child: Text('No positions available to nominate for.'));
          }

          final user = ref.watch(authProvider).user;
          final candidatesAsync = ref.watch(candidatesProvider(widget.electionId));

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                candidatesAsync.when(
                  data: (candidates) {
                    final myNominations = candidates.where((c) => c.email == user?.email).toList();
                    if (myNominations.isEmpty) return const SizedBox.shrink();

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('My Nominations', style: Theme.of(context).textTheme.headlineSmall),
                        const SizedBox(height: 12),
                        ...myNominations.map((c) => Card(
                              elevation: 0,
                              margin: const EdgeInsets.only(bottom: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                title: Text(c.positionTitle ?? 'Position'),
                                subtitle: Text('Status: ${c.status?.toUpperCase() ?? 'PENDING'}\nManifesto: ${c.manifesto}'),
                                isThreeLine: true,
                                trailing: Icon(
                                  c.status == 'approved' ? Icons.check_circle_rounded :
                                  c.status == 'rejected' ? Icons.cancel_rounded : Icons.pending_rounded,
                                  color: c.status == 'approved' ? Colors.green :
                                         c.status == 'rejected' ? Colors.red : Colors.orange,
                                ),
                              ),
                            )),
                        const SizedBox(height: 32),
                        const Divider(),
                        const SizedBox(height: 32),
                      ],
                    );
                  },
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (_, _) => const SizedBox.shrink(),
                ),
                Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Candidate Nomination Form',
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(
                    'Submit your official candidacy with required Proposer (प्रस्तावक) and Supporter (समर्थक) details.',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 24),
                  
                  // Candidate Photo Upload
                  Center(
                    child: ImageUploadWidget(
                      initialImageUrl: _photoUrl,
                      placeholderText: 'Upload Candidate Photo',
                      radius: 50,
                      onImageUploaded: (url) => setState(() => _photoUrl = url),
                    ),
                  ),
                  const SizedBox(height: 24),

                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: 'Position / Designation *'),
                    items: election.positions.map((p) {
                      return DropdownMenuItem(
                        value: p.id,
                        child: Text(p.title),
                      );
                    }).toList(),
                    value: _selectedPositionId,
                    onChanged: (val) {
                      setState(() {
                        _selectedPositionId = val;
                        _selectedQuotaId = null;
                      });
                    },
                    validator: (val) => val == null ? 'Please select a position' : null,
                  ),
                  const SizedBox(height: 16),
                  
                  // Quota selector if selected position has quotas
                  if (_selectedPositionId != null) ...[
                    () {
                      final pos = election.positions.firstWhere((p) => p.id == _selectedPositionId);
                      if (pos.quotas.isEmpty) return const SizedBox.shrink();
                      return Column(
                        children: [
                          DropdownButtonFormField<String>(
                            decoration: const InputDecoration(labelText: 'Target Quota (Optional)'),
                            items: [
                              const DropdownMenuItem(value: null, child: Text('Open / No Quota')),
                              ...pos.quotas.map((q) => DropdownMenuItem(
                                value: q.id,
                                child: Text('${q.name} (${q.seats} seats)'),
                              )),
                            ],
                            value: _selectedQuotaId,
                            onChanged: (val) => setState(() => _selectedQuotaId = val),
                          ),
                          const SizedBox(height: 16),
                        ],
                      );
                    }(),
                  ],
                  TextFormField(
                    controller: _manifestoController,
                    decoration: const InputDecoration(
                      labelText: 'Manifesto / Statement *',
                      alignLabelWithHint: true,
                    ),
                    maxLines: 4,
                    validator: (val) =>
                        val == null || val.isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 28),
                  
                  // Proposer Card (प्रस्तावक)
                  _buildEndorsementCard(
                    roleTitle: 'PROPOSER (प्रस्तावक) — Endorser 1',
                    roleSubtitle: 'Primary member who nominates and proposes the candidate',
                    primaryColor: const Color(0xFF2563EB),
                    roleIcon: Icons.how_to_reg_rounded,
                    nameCtrl: _proposerNameCtrl,
                    phoneCtrl: _proposerPhoneCtrl,
                    citizenCtrl: _proposerCitizenshipCtrl,
                    voterIdCtrl: _proposerVoterIdCtrl,
                    signatureUrl: _proposerSignatureUrl,
                    onPickRoster: () => _pickMemberForEndorsement(
                      nameCtrl: _proposerNameCtrl,
                      phoneCtrl: _proposerPhoneCtrl,
                      memIdCtrl: _proposerVoterIdCtrl,
                      citizenCtrl: _proposerCitizenshipCtrl,
                    ),
                    onSignatureUploaded: (url) => setState(() => _proposerSignatureUrl = url),
                  ),
                  const SizedBox(height: 24),
                  
                  // Supporter Card (समर्थक)
                  _buildEndorsementCard(
                    roleTitle: 'SUPPORTER (समर्थक) — Endorser 2',
                    roleSubtitle: 'Secondary member who seconds and backs the nomination',
                    primaryColor: const Color(0xFF059669),
                    roleIcon: Icons.verified_user_rounded,
                    nameCtrl: _supporterNameCtrl,
                    phoneCtrl: _supporterPhoneCtrl,
                    citizenCtrl: _supporterCitizenshipCtrl,
                    voterIdCtrl: _supporterVoterIdCtrl,
                    signatureUrl: _supporterSignatureUrl,
                    onPickRoster: () => _pickMemberForEndorsement(
                      nameCtrl: _supporterNameCtrl,
                      phoneCtrl: _supporterPhoneCtrl,
                      memIdCtrl: _supporterVoterIdCtrl,
                      citizenCtrl: _supporterCitizenshipCtrl,
                    ),
                    onSignatureUploaded: (url) => setState(() => _supporterSignatureUrl = url),
                  ),
                  const SizedBox(height: 32),
                  
                  LoadingButton(
                    onPressed: _submit,
                    isLoading: _isSubmitting,
                    label: 'Submit Nomination Form',
                  ),
                ],
              ),
            ),
            ],
          ),
          );
        },
      ),
    );
  }

  Widget _buildEndorsementCard({
    required String roleTitle,
    required String roleSubtitle,
    required Color primaryColor,
    required IconData roleIcon,
    required TextEditingController nameCtrl,
    required TextEditingController phoneCtrl,
    required TextEditingController citizenCtrl,
    required TextEditingController voterIdCtrl,
    required String signatureUrl,
    required VoidCallback onPickRoster,
    required Function(String) onSignatureUploaded,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: primaryColor.withValues(alpha: 0.25), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Ribbon
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: 0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              border: Border(bottom: BorderSide(color: primaryColor.withValues(alpha: 0.15))),
            ),
            child: Row(
              children: [
                Icon(roleIcon, size: 20, color: primaryColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        roleTitle,
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: primaryColor),
                      ),
                      Text(
                        roleSubtitle,
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: onPickRoster,
                  icon: const Icon(Icons.people_outline, size: 14),
                  label: const Text('Pick Member', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: primaryColor,
                    side: BorderSide(color: primaryColor.withValues(alpha: 0.4)),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ),

          // Card Form Body
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Full Name *',
                          prefixIcon: Icon(Icons.person_outline, size: 18),
                        ),
                        validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: TextFormField(
                        controller: phoneCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Phone Number *',
                          prefixIcon: Icon(Icons.phone_outlined, size: 18),
                        ),
                        validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: voterIdCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Voter ID / Member Code (Optional)',
                          prefixIcon: Icon(Icons.badge_outlined, size: 18),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: TextFormField(
                        controller: citizenCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Citizenship / Council No (Optional)',
                          prefixIcon: Icon(Icons.credit_card_outlined, size: 18),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Text('Official Signature: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 12),
                    ImageUploadWidget(
                      initialImageUrl: signatureUrl,
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
