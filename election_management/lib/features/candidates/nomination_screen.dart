import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import '../../core/providers/app_providers.dart';
import '../../core/network/api_constants.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/loading_button.dart';
import '../../shared/widgets/image_upload_widget.dart';
import '../candidates/nomination_list_screen.dart';
import '../../core/providers/auth_provider.dart';

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

  late List<_EndorsementItem> _proposers;
  late List<_EndorsementItem> _supporters;

  @override
  void initState() {
    super.initState();
    _proposers = [_EndorsementItem(endorsementType: 'proposer')];
    _supporters = [_EndorsementItem(endorsementType: 'supporter')];
  }

  @override
  void dispose() {
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
    if (!_formKey.currentState!.validate()) return;
    if (_selectedPositionId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a position.')));
      return;
    }

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

    setState(() => _isSubmitting = true);
    try {
      final dio = ref.read(apiClientProvider);
      await dio.post(ApiConstants.electionCandidates(widget.electionId), data: {
        'position': _selectedPositionId,
        if (_selectedQuotaId != null && _selectedQuotaId!.isNotEmpty) 'quota': _selectedQuotaId,
        'manifesto': _manifestoController.text.trim(),
        'candidate_image': _photoUrl,
        'election': widget.electionId,
        'endorsements': endorsements,
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
                              separatorBuilder: (_, _) => const Divider(height: 1),
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

  Future<void> _handleWithdraw(String candidateId, String positionTitle) async {
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            SizedBox(width: 8),
            Text('Withdraw Candidacy?'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Are you sure you want to withdraw your nomination for $positionTitle?'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Reason for Withdrawal (Optional)',
                hintText: 'e.g. Personal reasons, health, etc.',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm Withdrawal', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await ref.read(apiClientProvider).post(
          ApiConstants.withdrawCandidate(widget.electionId, candidateId),
          data: {'reason': reasonCtrl.text.trim()},
        );
        ref.invalidate(candidatesProvider(widget.electionId));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Nomination withdrawn successfully.')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to withdraw nomination: $e')),
          );
        }
      }
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
          final user = ref.watch(authProvider).user;
          final isRestricted = user != null && (user.canManageElections || user.isObserver || user.isAuditor);

          if (isRestricted) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.gavel_rounded, size: 54, color: Colors.amber),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Ineligible for Candidacy (Conflict of Interest)',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'As an active ${user.roleDisplay.isNotEmpty ? user.roleDisplay : user.role.replaceAll('_', ' ')}, electoral integrity regulations prohibit you from running as a candidate or submitting nominations in this election.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: () => context.pop(),
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Back to Election'),
                    ),
                  ],
                ),
              ),
            );
          }

          if (election.positions.isEmpty) {
            return const Center(child: Text('No positions available to nominate for.'));
          }

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
                        Row(
                          children: [
                            const Icon(Icons.assignment_ind_outlined, color: AppColors.primary, size: 22),
                            const SizedBox(width: 8),
                            Text('My Nominations (मेरा उम्मेदवारीहरू)', style: Theme.of(context).textTheme.headlineSmall),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ...myNominations.map((c) {
                          final isWithdrawn = c.status == 'withdrawn';
                          final isApproved = c.status == 'approved';
                          final isRejected = c.status == 'rejected';

                          return Card(
                            elevation: 0,
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: isWithdrawn
                                    ? Colors.grey.shade400
                                    : isApproved
                                        ? Colors.green.shade300
                                        : isRejected
                                            ? Colors.red.shade300
                                            : Colors.orange.shade300,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          c.positionTitle ?? 'Position',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: isWithdrawn
                                              ? Colors.grey.shade200
                                              : isApproved
                                                  ? Colors.green.shade50
                                                  : isRejected
                                                      ? Colors.red.shade50
                                                      : Colors.orange.shade50,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          isWithdrawn
                                              ? 'WITHDRAWN (फिर्ता)'
                                              : (c.status?.toUpperCase() ?? 'PENDING'),
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: isWithdrawn
                                                ? Colors.grey.shade700
                                                : isApproved
                                                    ? Colors.green.shade800
                                                    : isRejected
                                                        ? Colors.red.shade800
                                                        : Colors.orange.shade800,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (c.manifesto.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text('Manifesto: ${c.manifesto}', style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
                                  ],
                                  if (!isWithdrawn && !isRejected) ...[
                                    const SizedBox(height: 12),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: OutlinedButton.icon(
                                        onPressed: () => _handleWithdraw(c.id, c.positionTitle ?? 'Position'),
                                        icon: const Icon(Icons.remove_circle_outline, size: 14, color: Colors.red),
                                        label: const Text('Withdraw Candidacy', style: TextStyle(color: Colors.red, fontSize: 12)),
                                        style: OutlinedButton.styleFrom(
                                          side: const BorderSide(color: Colors.red),
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                          minimumSize: Size.zero,
                                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        }),
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
                        initialValue: _selectedPositionId,
                        onChanged: (val) {
                          setState(() {
                            _selectedPositionId = val;
                            _selectedQuotaId = null;
                          });
                        },
                        validator: (val) => val == null ? 'Please select a position' : null,
                      ),
                      const SizedBox(height: 16),
                      
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
                                initialValue: _selectedQuotaId,
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
                          roleSubtitle: 'Primary member who nominates and proposes this candidate',
                          primaryColor: const Color(0xFF2563EB),
                          roleIcon: Icons.how_to_reg_rounded,
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
                          roleSubtitle: 'Secondary member who seconds and backs this nomination',
                          primaryColor: const Color(0xFF059669),
                          roleIcon: Icons.verified_user_rounded,
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

  Widget _buildDynamicEndorsementCard({
    required _EndorsementItem item,
    required int index,
    required int totalCount,
    required String roleTitle,
    required String roleSubtitle,
    required Color primaryColor,
    required IconData roleIcon,
    required VoidCallback? onRemove,
    required VoidCallback onPickRoster,
    required ValueChanged<String> onSignatureUploaded,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
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
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: item.nameCtrl,
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
                        controller: item.phoneCtrl,
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
                        controller: item.memIdCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Voter ID / Member Code (Optional)',
                          prefixIcon: Icon(Icons.badge_outlined, size: 18),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: TextFormField(
                        controller: item.citizenCtrl,
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
