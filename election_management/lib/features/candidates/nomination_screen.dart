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
  final _slateController = TextEditingController();
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
    _slateController.dispose();
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

    setState(() => _isSubmitting = true);
    try {
      final dio = ref.read(apiClientProvider);
      await dio.post(ApiConstants.electionCandidates(widget.electionId), data: {
        'position': _selectedPositionId,
        if (_selectedQuotaId != null && _selectedQuotaId!.isNotEmpty) 'quota': _selectedQuotaId,
        'manifesto': _manifestoController.text.trim(),
        'slate_name': _slateController.text.trim(),
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
                  Text('Apply for Candidacy',
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  const Text('Fill out the form below to submit your nomination for this election.'),
                  const SizedBox(height: 24),
                  
                  Center(
                    child: ImageUploadWidget(
                      initialImageUrl: _photoUrl,
                      placeholderText: 'PHOTO',
                      radius: 40,
                      onImageUploaded: (url) => setState(() => _photoUrl = url),
                    ),
                  ),
                  const SizedBox(height: 24),

                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: 'Position *'),
                    initialValue: _selectedPositionId,
                    items: election.positions.map((p) {
                      return DropdownMenuItem(value: p.id, child: Text(p.title));
                    }).toList(),
                    onChanged: (val) {
                      setState(() {
                        _selectedPositionId = val;
                        _selectedQuotaId = null;
                      });
                    },
                    validator: (val) => val == null ? 'Required' : null,
                  ),
                  if (_selectedPositionId != null) ...[
                    () {
                      final selectedPos = election.positions.where((p) => p.id == _selectedPositionId).firstOrNull;
                      if (selectedPos != null && selectedPos.quotas.isNotEmpty) {
                        final activeQuotas = selectedPos.quotas.where((q) => q.isActive).toList();
                        if (activeQuotas.isNotEmpty) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 16.0),
                            child: DropdownButtonFormField<String?>(
                              initialValue: _selectedQuotaId,
                              decoration: const InputDecoration(
                                labelText: 'Quota Category (Reserved Seat)',
                                helperText: 'Select reserved quota category if contesting under quota, or Open category',
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
                          );
                        }
                      }
                      return const SizedBox.shrink();
                    }(),
                  ],
                  const SizedBox(height: 16),
                  
                  TextFormField(
                    controller: _manifestoController,
                    decoration: const InputDecoration(
                      labelText: 'Manifesto / Statement',
                      alignLabelWithHint: true,
                    ),
                    maxLines: 5,
                    validator: (val) =>
                        val == null || val.isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),
                  
                  TextFormField(
                    controller: _slateController,
                    decoration: const InputDecoration(
                      labelText: 'Slate / Party Name (Optional)',
                    ),
                  ),
                  const SizedBox(height: 32),
                  
                  const Text('Proposer Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  const SizedBox(height: 16),
                  _buildEndorsementFields(
                    name: _proposerNameCtrl, 
                    phone: _proposerPhoneCtrl, 
                    citizenship: _proposerCitizenshipCtrl, 
                    voterId: _proposerVoterIdCtrl,
                    signatureUrl: _proposerSignatureUrl,
                    onSignatureUploaded: (url) => setState(() => _proposerSignatureUrl = url),
                  ),
                  const SizedBox(height: 32),
                  
                  const Text('Supporter Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  const SizedBox(height: 16),
                  _buildEndorsementFields(
                    name: _supporterNameCtrl, 
                    phone: _supporterPhoneCtrl, 
                    citizenship: _supporterCitizenshipCtrl, 
                    voterId: _supporterVoterIdCtrl,
                    signatureUrl: _supporterSignatureUrl,
                    onSignatureUploaded: (url) => setState(() => _supporterSignatureUrl = url),
                  ),
                  const SizedBox(height: 32),
                  
                  LoadingButton(
                    onPressed: _submit,
                    isLoading: _isSubmitting,
                    label: 'Submit Nomination',
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

  Widget _buildEndorsementFields({
    required TextEditingController name, 
    required TextEditingController phone, 
    required TextEditingController citizenship, 
    required TextEditingController voterId,
    required String signatureUrl,
    required Function(String) onSignatureUploaded,
  }) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: TextFormField(controller: name, decoration: const InputDecoration(labelText: 'Full Name *'), validator: (v) => v == null || v.isEmpty ? 'Required' : null)),
            const SizedBox(width: 16),
            Expanded(child: TextFormField(controller: phone, decoration: const InputDecoration(labelText: 'Phone Number *'), validator: (v) => v == null || v.isEmpty ? 'Required' : null)),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: Column(
                children: [
                  TextFormField(controller: citizenship, decoration: const InputDecoration(labelText: 'Citizenship Number (Optional)')),
                  const SizedBox(height: 16),
                  TextFormField(controller: voterId, decoration: const InputDecoration(labelText: 'Voter ID (Optional)')),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 1,
              child: ImageUploadWidget(
                initialImageUrl: signatureUrl,
                placeholderText: 'Sign',
                radius: 32,
                onImageUploaded: onSignatureUploaded,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
