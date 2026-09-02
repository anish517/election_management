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
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/providers/org_providers.dart';
import '../../core/providers/payment_providers.dart';
import '../../shared/models/models.dart';

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
  final _txnRefCtrl = TextEditingController();
  final _paymentNotesCtrl = TextEditingController();
  final _partyCtrl = TextEditingController();
  final _panelCtrl = TextEditingController();
  final _symbolNameCtrl = TextEditingController();
  String _symbolImageUrl = '';
  final _prRankCtrl = TextEditingController(text: '1');
  String _voucherImageUrl = '';
  bool _isUploadingVoucher = false;
  String _selectedPaymentChannel = 'fonepay';

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
    _txnRefCtrl.dispose();
    _paymentNotesCtrl.dispose();
    _partyCtrl.dispose();
    _panelCtrl.dispose();
    _symbolNameCtrl.dispose();
    _prRankCtrl.dispose();
    for (final p in _proposers) {
      p.dispose();
    }
    for (final s in _supporters) {
      s.dispose();
    }
    super.dispose();
  }

  Future<void> _handleResubmitPayment(CandidateModel c) async {
    final payment = c.latestPayment;
    if (payment == null) return;

    final txnCtrl = TextEditingController(text: payment.transactionReference);
    final notesCtrl = TextEditingController(text: payment.paymentNotes);
    String selectedMethod = payment.paymentMethod.isNotEmpty ? payment.paymentMethod : 'static_qr_bank';
    String receiptUrl = payment.receiptImageUrl;
    bool isUploading = false;

    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(
                payment.isCorrectionRequested ? Icons.edit_note_rounded : Icons.replay_rounded,
                color: payment.isCorrectionRequested ? const Color(0xFFD97706) : AppColors.primary,
              ),
              const SizedBox(width: 8),
              Text(
                payment.isCorrectionRequested ? 'Correct & Resubmit Payment' : 'Re-submit Payment Proof',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (payment.correctionNotes.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFF59E0B)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706), size: 18),
                            SizedBox(width: 6),
                            Text(
                              'Officer Correction Request (सच्याउने निर्देशन):',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Color(0xFF92400E)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          payment.correctionNotes,
                          style: const TextStyle(fontSize: 12.5, color: Color(0xFF78350F), height: 1.35),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                if (payment.rejectionReason.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      'Officer Rejection Reason: ${payment.rejectionReason}',
                      style: const TextStyle(color: AppColors.error, fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                TextField(
                  controller: txnCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Updated Transaction Reference / ID *',
                    hintText: 'e.g. 1234567890 / Voucher Ref',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.receipt_long_rounded),
                  ),
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: isUploading
                      ? null
                      : () async {
                          final f = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['jpg', 'png', 'jpeg'], withData: true);
                          if (f == null || f.files.isEmpty || f.files.first.bytes == null) return;
                          setModalState(() => isUploading = true);
                          try {
                            final dio = ref.read(apiClientProvider);
                            final resp = await dio.post(
                              ApiConstants.fileUpload,
                              data: FormData.fromMap({'file': MultipartFile.fromBytes(f.files.first.bytes!, filename: f.files.first.name)}),
                            );
                            final url = resp.data['url'] as String?;
                            setModalState(() {
                              isUploading = false;
                              if (url != null) receiptUrl = url;
                            });
                          } catch (_) {
                            setModalState(() => isUploading = false);
                          }
                        },
                  icon: isUploading
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.upload_file),
                  label: Text(receiptUrl.isNotEmpty ? 'Voucher Attached (Replace)' : 'Attach Clear Voucher Screenshot'),
                ),
                if (receiptUrl.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.green, size: 14),
                      const SizedBox(width: 4),
                      const Text('Receipt voucher attached', style: TextStyle(color: Colors.green, fontSize: 11)),
                    ],
                  ),
                ],
                const SizedBox(height: 14),
                TextField(
                  controller: notesCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Explanation / Note to Officer (Optional)',
                    hintText: 'e.g. Attached clear voucher screenshot with visible TXN ID',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton.icon(
              onPressed: () {
                if (txnCtrl.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter Transaction ID.')),
                  );
                  return;
                }
                Navigator.pop(ctx, true);
              },
              icon: const Icon(Icons.send_rounded, size: 16),
              label: const Text('Submit Updated Proof'),
              style: ElevatedButton.styleFrom(
                backgroundColor: payment.isCorrectionRequested ? const Color(0xFFD97706) : AppColors.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );

    if (res == true) {
      try {
        final dio = ref.read(apiClientProvider);
        final payload = <String, dynamic>{
          'transaction_reference': txnCtrl.text.trim(),
          if (selectedMethod.isNotEmpty) 'payment_method': selectedMethod,
          if (receiptUrl.isNotEmpty) 'receipt_image_url': receiptUrl,
          if (notesCtrl.text.trim().isNotEmpty) 'payment_notes': notesCtrl.text.trim(),
        };
        await dio.post(ApiConstants.resubmitPayment(payment.id), data: payload);
        ref.invalidate(candidatesProvider(widget.electionId));
        ref.invalidate(electionProvider(widget.electionId));
        ref.invalidate(paymentsListProvider);
        ref.invalidate(paymentStatsProvider);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Payment details successfully resubmitted for officer review!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        String msg = 'Resubmission failed';
        if (e is DioException && e.response?.data is Map) {
          final data = e.response!.data as Map;
          if (data.containsKey('detail')) {
            msg = data['detail'].toString();
          } else if (data.containsKey('error')) {
            msg = data['error'].toString();
          } else if (data.values.isNotEmpty) {
            msg = data.values.first.toString();
          }
        } else {
          msg = 'Resubmission failed: $e';
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _submit() async {
    final election = ref.read(electionProvider(widget.electionId)).valueOrNull;
    final isSam = election?.isSamanupatik ?? false;

    if (isSam && _selectedPositionId == null && (election?.positions.isNotEmpty ?? false)) {
      _selectedPositionId = election!.positions.first.id;
    }

    if (!_formKey.currentState!.validate()) return;
    if (_selectedPositionId == null && !isSam) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a position.')));
      return;
    }
    if (isSam && _partyCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Political Party affiliation is strictly required for Samānupātik nomination.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final user = ref.read(authProvider).user;
    final userEmail = (user?.email ?? '').trim().toLowerCase();
    final userPhone = (user?.phone ?? '').trim();
    final userName = (user?.fullName ?? '').trim().toLowerCase();

    final candidates = ref.read(candidatesProvider(widget.electionId)).valueOrNull ?? [];
    final activeNomination = candidates.where((c) {
      if (c.status == 'withdrawn' || c.status == 'rejected') return false;
      final cEmail = (c.email ?? '').trim().toLowerCase();
      final cPhone = (c.contactNumber ?? '').trim();
      final cName = c.name.trim().toLowerCase();

      return (userEmail.isNotEmpty && cEmail == userEmail) ||
             (userPhone.isNotEmpty && cPhone == userPhone) ||
             (userName.isNotEmpty && cName == userName);
    }).firstOrNull;

    if (activeNomination != null) {
      final posTitle = activeNomination.positionTitle ?? 'another position';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('You already have an active nomination for "$posTitle" in this election. Candidates may only apply for one position per election (एउटै निर्वाचनमा एकभन्दा बढी पदका लागि उम्मेदवारी दिन पाइँदैन).'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final org = ref.read(orgProfileProvider).valueOrNull;

    // Check fee calculation directly from designation
    double fee = 0.0;
    if (election != null && _selectedPositionId != null) {
      final pos = election.positions.where((p) => p.id == _selectedPositionId).firstOrNull;
      if (pos != null) {
        fee = pos.nomineeCharge;
      }
    }

    final isPaymentEnabled = (org?.isPaymentEnabled ?? false) && fee > 0;

    if (isPaymentEnabled && _txnRefCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter the Transaction Reference ID (भौचर / ट्रान्ज्याक्सन नम्बर) below.'),
          backgroundColor: Colors.red,
        ),
      );
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

    final minProps = org?.minProposers ?? 1;
    final minSupps = org?.minSupporters ?? 1;
    final validProps = _proposers.where((p) => p.isNotEmpty).length;
    final validSupps = _supporters.where((s) => s.isNotEmpty).length;

    if (validProps < minProps) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('At least $minProps proposer(s) (प्रस्तावक) are required by institutional bylaws.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (validSupps < minSupps) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('At least $minSupps supporter(s) (समर्थक) are required by institutional bylaws.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final dio = ref.read(apiClientProvider);
      final payload = <String, dynamic>{
        'position': _selectedPositionId,
        'quota': _selectedQuotaId,
        'manifesto': _manifestoController.text.trim(),
        'candidate_image': _photoUrl,
        'party_name': _partyCtrl.text.trim(),
        'panel_name': _panelCtrl.text.trim(),
        'symbol_name': _symbolNameCtrl.text.trim(),
        'symbol_image': _symbolImageUrl,
        'pr_rank': int.tryParse(_prRankCtrl.text.trim()) ?? 1,
        'election': widget.electionId,
        'endorsements': endorsements,
        if (isPaymentEnabled) ...{
          'transaction_reference': _txnRefCtrl.text.trim(),
          'receipt_image_url': _voucherImageUrl,
          'payment_notes': _paymentNotesCtrl.text.trim(),
          'payment_method': _selectedPaymentChannel,
        },
      };

      await dio.post(ApiConstants.electionCandidates(widget.electionId), data: payload);

      ref.invalidate(candidatesProvider(widget.electionId));

      if (mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Nomination submitted successfully!')));
      }
    } on DioException catch (e) {
      String msg = 'Submission failed';
      if (e.response?.data is Map) {
        final data = e.response!.data as Map;
        if (data.containsKey('detail')) {
          msg = data['detail'].toString();
        } else if (data.containsKey('error')) {
          msg = data['error'].toString();
        } else if (data.containsKey('non_field_errors')) {
          final errs = data['non_field_errors'];
          msg = errs is List ? errs.join(', ') : errs.toString();
        } else if (data.values.isNotEmpty) {
          final firstVal = data.values.first;
          msg = firstVal is List ? firstVal.join(', ') : firstVal.toString();
        }
      } else if (e.response?.data is String) {
        msg = e.response!.data as String;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
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
          if (candidatesAsync.isLoading) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32.0),
                child: CircularProgressIndicator(),
              ),
            );
          }

          final org = ref.watch(orgProfileProvider).valueOrNull;
          final isDark = Theme.of(context).brightness == Brightness.dark;

          final candidates = candidatesAsync.valueOrNull ?? [];
          final userEmail = (user?.email ?? '').trim().toLowerCase();
          final userPhone = (user?.phone ?? '').trim();
          final userName = (user?.fullName ?? '').trim().toLowerCase();

          final myNominations = candidates.where((c) {
            final cEmail = (c.email ?? '').trim().toLowerCase();
            final cPhone = (c.contactNumber ?? '').trim();
            final cName = c.name.trim().toLowerCase();

            return (userEmail.isNotEmpty && cEmail == userEmail) ||
                   (userPhone.isNotEmpty && cPhone == userPhone) ||
                   (userName.isNotEmpty && cName == userName);
          }).toList();

          final myActiveNominations = myNominations
              .where((n) => n.status != 'withdrawn' && n.status != 'rejected')
              .toList();
          final myActiveNominatedPosIds = myActiveNominations
              .map((n) => n.positionId)
              .whereType<String>()
              .toSet();
          final hasActiveNomination = myActiveNominations.isNotEmpty;

          if (election.isSamanupatik && _selectedPositionId == null && election.positions.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _selectedPositionId == null) {
                setState(() => _selectedPositionId = election.positions.first.id);
              }
            });
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                        if (myNominations.isNotEmpty) ...[
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
                            final isWaived = c.paymentStatus == 'waived';
                            final isCorrectionReq = !isWaived &&
                                (c.latestPayment?.isCorrectionRequested == true ||
                                    (c.latestPayment?.correctionNotes.isNotEmpty == true));
                            final isVerified = !isWaived && (c.latestPayment?.isVerified == true || c.paymentStatus == 'paid');
                            final isPayRejected = !isWaived && (c.latestPayment?.isRejected == true);
                            final isSuccess = isWaived || isVerified;

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
                                          : isRejected || isPayRejected
                                              ? Colors.red.shade300
                                              : isCorrectionReq
                                                  ? Colors.amber.shade600
                                                  : Colors.orange.shade300,
                                  width: isCorrectionReq ? 1.5 : 1,
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
                                                        : isCorrectionReq
                                                            ? const Color(0xFFFEF3C7)
                                                            : Colors.orange.shade50,
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            isWithdrawn
                                                ? 'WITHDRAWN (फिर्ता)'
                                                : isCorrectionReq
                                                    ? 'CORRECTION REQUIRED (सच्याउनुहोस्)'
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
                                                          : isCorrectionReq
                                                              ? const Color(0xFF92400E)
                                                              : Colors.orange.shade800,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (c.partyName.isNotEmpty || c.panelName.isNotEmpty || c.symbolName.isNotEmpty || c.prRank > 0) ...[
                                      const SizedBox(height: 6),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 4,
                                        children: [
                                          if (c.partyName.isNotEmpty)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: isDark ? const Color(0xFF1E3A8A).withValues(alpha: 0.35) : const Color(0xFFEFF6FF),
                                                borderRadius: BorderRadius.circular(5),
                                                border: Border.all(color: isDark ? const Color(0xFF3B82F6).withValues(alpha: 0.4) : const Color(0xFF93C5FD)),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(Icons.flag_rounded, size: 11, color: isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB)),
                                                  const SizedBox(width: 4),
                                                  Text(c.partyName, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: isDark ? const Color(0xFFBFDBFE) : const Color(0xFF1D4ED8))),
                                                ],
                                              ),
                                            ),
                                          if (c.panelName.isNotEmpty)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: isDark ? const Color(0xFF581C87).withValues(alpha: 0.35) : const Color(0xFFFAF5FF),
                                                borderRadius: BorderRadius.circular(5),
                                                border: Border.all(color: isDark ? const Color(0xFF8B5CF6).withValues(alpha: 0.4) : const Color(0xFFC4B5FD)),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(Icons.groups_rounded, size: 11, color: isDark ? const Color(0xFFA78BFA) : const Color(0xFF7C3AED)),
                                                  const SizedBox(width: 4),
                                                  Text(c.panelName, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: isDark ? const Color(0xFFE9D5FF) : const Color(0xFF6D28D9))),
                                                ],
                                              ),
                                            ),
                                          if (c.symbolName.isNotEmpty)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFF59E0B).withValues(alpha: isDark ? 0.2 : 0.12),
                                                borderRadius: BorderRadius.circular(5),
                                                border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const Icon(Icons.how_to_vote_rounded, size: 11, color: Color(0xFFD97706)),
                                                  const SizedBox(width: 4),
                                                  Text(c.symbolName, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: isDark ? const Color(0xFFFDE68A) : const Color(0xFFB45309))),
                                                ],
                                              ),
                                            ),
                                          if (c.prRank > 0)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: isDark ? const Color(0xFF312E81).withValues(alpha: 0.35) : const Color(0xFFEEF2FF),
                                                borderRadius: BorderRadius.circular(5),
                                                border: Border.all(color: isDark ? const Color(0xFF6366F1).withValues(alpha: 0.4) : const Color(0xFFA5B4FC)),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(Icons.format_list_numbered_rounded, size: 11, color: isDark ? const Color(0xFF818CF8) : const Color(0xFF4F46E5)),
                                                  const SizedBox(width: 4),
                                                  Text('PR Rank #${c.prRank}', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: isDark ? const Color(0xFFC7D2FE) : const Color(0xFF3730A3))),
                                                ],
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                    if (c.manifesto.isNotEmpty) ...[
                                      const SizedBox(height: 8),
                                      Text('Manifesto: ${c.manifesto}', style: TextStyle(color: isDark ? Colors.white70 : Colors.grey.shade700, fontSize: 13)),
                                    ],
                                    if (c.latestPayment != null || c.paymentStatus == 'paid' || c.paymentStatus == 'waived') ...[
                                      const SizedBox(height: 10),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: isSuccess
                                              ? Colors.green.withValues(alpha: 0.1)
                                              : isPayRejected
                                                  ? AppColors.error.withValues(alpha: 0.1)
                                                  : isCorrectionReq
                                                      ? const Color(0xFFFEF3C7)
                                                      : const Color(0xFFF59E0B).withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(
                                            color: isSuccess
                                                ? Colors.green.withValues(alpha: 0.3)
                                                : isPayRejected
                                                    ? AppColors.error.withValues(alpha: 0.3)
                                                    : isCorrectionReq
                                                        ? const Color(0xFFF59E0B)
                                                        : const Color(0xFFF59E0B).withValues(alpha: 0.3),
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              isSuccess
                                                  ? Icons.check_circle_outline_rounded
                                                  : isPayRejected
                                                      ? Icons.error_outline_rounded
                                                      : isCorrectionReq
                                                          ? Icons.warning_amber_rounded
                                                          : Icons.hourglass_top_rounded,
                                              size: 16,
                                              color: isSuccess
                                                  ? Colors.green.shade800
                                                  : isPayRejected
                                                      ? AppColors.error
                                                      : isCorrectionReq
                                                          ? const Color(0xFFD97706)
                                                          : const Color(0xFFD97706),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                isWaived
                                                    ? 'Free Nomination (निःशुल्क दर्ता)'
                                                    : isVerified
                                                        ? 'Payment Verified (भुक्तानी स्वीकृत) — Rs. ${c.latestPayment?.amount.toStringAsFixed(0) ?? ""}'
                                                        : isPayRejected
                                                            ? 'Payment Rejected (भुक्तानी अस्वीकृत)'
                                                            : isCorrectionReq
                                                                ? 'Payment Correction Requested (सच्याउन अनुरोध) — Rs. ${c.latestPayment?.amount.toStringAsFixed(0) ?? ""}'
                                                                : 'Payment: Pending Verification (Rs. ${c.latestPayment?.amount.toStringAsFixed(0) ?? ""})',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: isSuccess
                                                      ? Colors.green.shade800
                                                      : isPayRejected
                                                          ? AppColors.error
                                                          : isCorrectionReq
                                                              ? const Color(0xFF92400E)
                                                              : const Color(0xFFD97706),
                                                ),
                                              ),
                                            ),
                                            if (isPayRejected || isCorrectionReq) ...[
                                              OutlinedButton(
                                                onPressed: () => _handleResubmitPayment(c),
                                                style: OutlinedButton.styleFrom(
                                                  foregroundColor: isCorrectionReq ? const Color(0xFFD97706) : AppColors.error,
                                                  side: BorderSide(color: isCorrectionReq ? const Color(0xFFD97706) : AppColors.error),
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                  minimumSize: Size.zero,
                                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                ),
                                                child: Text(isCorrectionReq ? 'Correct Details' : 'Re-submit Proof', style: const TextStyle(fontSize: 11)),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ],
                                    if (isCorrectionReq) ...[
                                      const SizedBox(height: 10),
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFFFBEB),
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(color: const Color(0xFFF59E0B)),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                const Icon(Icons.edit_note_rounded, color: Color(0xFFD97706), size: 18),
                                                const SizedBox(width: 6),
                                                const Text(
                                                  'Officer Correction Note (सच्याउने निर्देशन):',
                                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Color(0xFF92400E)),
                                                ),
                                                const Spacer(),
                                                ElevatedButton.icon(
                                                  onPressed: () => _handleResubmitPayment(c),
                                                  icon: const Icon(Icons.refresh_rounded, size: 13),
                                                  label: const Text('Correct & Resubmit', style: TextStyle(fontSize: 11)),
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor: const Color(0xFFD97706),
                                                    foregroundColor: Colors.white,
                                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                    minimumSize: Size.zero,
                                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            if (c.latestPayment?.correctionNotes.isNotEmpty == true) ...[
                                              const SizedBox(height: 6),
                                              Text(
                                                c.latestPayment!.correctionNotes,
                                                style: const TextStyle(fontSize: 12, color: Color(0xFF78350F), height: 1.35),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
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

                        if (hasActiveNomination) ...[
                          () {
                            final active = myActiveNominations.first;
                            final posTitle = active.positionTitle ?? 'Designation';
                            return Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFEFF6FF),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: isDark ? const Color(0xFF3B82F6).withValues(alpha: 0.3) : const Color(0xFFBFDBFE)),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.verified_user_rounded, color: Color(0xFF2563EB), size: 24),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Active Nomination on File (सक्रिय उम्मेदवारी दर्ता भइसकेको)',
                                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Institutional election regulations permit candidates to apply for only ONE position per election. You currently hold an active nomination for "$posTitle" (Status: ${active.status?.toUpperCase() ?? "PENDING"}).',
                                          style: TextStyle(fontSize: 12.5, color: isDark ? Colors.white70 : const Color(0xFF1E3A8A), height: 1.4),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'If you wish to apply for a different designation, you must first withdraw your current nomination for $posTitle above (माथिको उम्मेदवारी फिर्ता लिएपछि मात्र अर्को पदमा आवेदन दिन सकिन्छ).',
                                          style: TextStyle(fontSize: 11.5, color: isDark ? Colors.white60 : const Color(0xFF475569)),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }(),
                        ] else ...[
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
                                
                                if (election.enableCandidatePhoto) ...[
                                  Center(
                                    child: ImageUploadWidget(
                                      initialImageUrl: _photoUrl,
                                      placeholderText: 'Upload Candidate Photo (उम्मेदवार फोटो)',
                                      radius: 50,
                                      onImageUploaded: (url) => setState(() => _photoUrl = url),
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                ],

                                if (election.isSamanupatik) ...[
                                  Container(
                                    padding: const EdgeInsets.all(14),
                                    margin: const EdgeInsets.only(bottom: 16),
                                    decoration: BoxDecoration(
                                      color: isDark ? const Color(0xFF1E1B4B) : const Color(0xFFEEF2FF),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: isDark ? const Color(0xFF6366F1).withValues(alpha: 0.4) : const Color(0xFFA5B4FC)),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.how_to_vote_rounded, color: Color(0xFF4F46E5), size: 24),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const Text(
                                                'Samānupātik Closed-List System (समानुपातिक निर्वाचन प्रणाली)',
                                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                'Candidates are registered to the Political Party\'s Closed List (बन्दसूची) with priority ranking. Total Seats: ${election.totalPrSeats}.',
                                                style: TextStyle(fontSize: 11.5, color: isDark ? Colors.white70 : const Color(0xFF3730A3)),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],

                                DropdownButtonFormField<String>(
                                  isExpanded: true,
                                  decoration: InputDecoration(
                                    labelText: election.isSamanupatik ? 'Samānupātik List (समानुपातिक सूची) *' : 'Position / Designation *',
                                    prefixIcon: const Icon(Icons.military_tech_outlined),
                                  ),
                                  items: election.positions.map((p) {
                                    final isAlreadyNominated = myActiveNominatedPosIds.contains(p.id);
                                    final posFee = p.nomineeCharge;
                                    final isGlobalActive = org?.isPaymentEnabled ?? false;
                                    final feeText = (isGlobalActive && posFee > 0)
                                        ? ' — (Fee: Rs. ${posFee.toStringAsFixed(0)} NPR)'
                                        : (posFee > 0 && !isGlobalActive)
                                            ? ' — (Free: Payments OFF)'
                                            : ' — (Free)';
                                    return DropdownMenuItem(
                                      value: isAlreadyNominated ? null : p.id,
                                      enabled: !isAlreadyNominated,
                                      child: Text(
                                        isAlreadyNominated
                                            ? '${p.title} (Already Nominated — पहिले नै दर्ता)'
                                            : '${p.title}$feeText',
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: isAlreadyNominated ? Colors.grey : (isDark ? Colors.white : Colors.black87),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                  initialValue: _selectedPositionId ?? (election.isSamanupatik ? election.positions.firstOrNull?.id : null),
                                  onChanged: (val) {
                                    if (val == null) return;
                                    setState(() {
                                      _selectedPositionId = val;
                                      _selectedQuotaId = null;
                                    });
                                  },
                                  validator: (val) {
                                    if (election.isSamanupatik && election.positions.isEmpty) return null;
                                    return val == null ? 'Please select an available position' : null;
                                  },
                                ),
                                const SizedBox(height: 16),
                                
                                if (_selectedPositionId != null || (election.isSamanupatik && election.positions.isNotEmpty)) ...[
                                  () {
                                    final posId = _selectedPositionId ?? election.positions.firstOrNull?.id;
                                    final pos = election.positions.where((p) => p.id == posId).firstOrNull;
                                    if (pos == null || pos.quotas.isEmpty) return const SizedBox.shrink();
                                    return Column(
                                      children: [
                                        DropdownButtonFormField<String>(
                                          decoration: const InputDecoration(labelText: 'Affirmative Action Quota / समावेशी समूह (Optional)'),
                                          items: [
                                            const DropdownMenuItem(value: null, child: Text('Open / General (खुल्ला)')),
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

                                if (election.enableParty || election.enablePanel || election.isSamanupatik) ...[
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (election.enableParty || election.isSamanupatik)
                                        Expanded(
                                          child: TextFormField(
                                            controller: _partyCtrl,
                                            decoration: InputDecoration(
                                              labelText: election.isSamanupatik ? 'Political Party (राजनीतिक दल) *' : 'Party Affiliation (दल / पार्टी)',
                                              hintText: 'e.g. Nepali Congress, UML, RPP...',
                                              prefixIcon: const Icon(Icons.flag_outlined),
                                            ),
                                            validator: (election.isSamanupatik)
                                                ? (v) => (v == null || v.trim().isEmpty) ? 'Party affiliation is strictly required for Samānupātik' : null
                                                : null,
                                          ),
                                        ),
                                      if ((election.enableParty || election.isSamanupatik) && election.enablePanel)
                                        const SizedBox(width: 12),
                                      if (election.enablePanel)
                                        Expanded(
                                          child: TextFormField(
                                            controller: _panelCtrl,
                                            decoration: const InputDecoration(
                                              labelText: 'Panel / Slate (प्यानल / समूह)',
                                              prefixIcon: Icon(Icons.group_work_outlined),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                ],

                                if (election.enableSymbol || election.isSamanupatik) ...[
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        flex: 3,
                                        child: TextFormField(
                                          controller: _symbolNameCtrl,
                                          decoration: const InputDecoration(
                                            labelText: 'Election Symbol Name (चुनाव चिन्ह)',
                                            hintText: 'e.g. Sun (सूर्य), Tree (रुख), Pen (कलम)',
                                            prefixIcon: Icon(Icons.how_to_vote_outlined),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
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

                                if (election.hasPrSystem || election.isSamanupatik) ...[
                                  TextFormField(
                                    controller: _prRankCtrl,
                                    keyboardType: TextInputType.number,
                                    decoration: InputDecoration(
                                      labelText: election.isSamanupatik ? 'PR Closed List Rank (बन्दसूची वरीयता क्रम) *' : 'PR Closed List Rank (समानुपातिक सूची वरीयता क्रम)',
                                      hintText: '1 for Top candidate, 2, 3...',
                                      prefixIcon: const Icon(Icons.format_list_numbered_rounded),
                                      helperText: 'Determines election priority order on the party\'s list',
                                    ),
                                    validator: (election.isSamanupatik)
                                        ? (v) => (v == null || v.trim().isEmpty) ? 'PR list rank (e.g. 1, 2, 3) is required' : null
                                        : null,
                                  ),
                                  const SizedBox(height: 16),
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
                                  color: AppColors.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text('${_proposers.length}/${org?.maxProposers ?? 5}', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
                              ),
                              const SizedBox(width: 8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('PROPOSERS (प्रस्तावक)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                                  Text(
                                    'Required: Min ${org?.minProposers ?? 1}, Max ${org?.maxProposers ?? 5}',
                                    style: TextStyle(fontSize: 10.5, color: isDark ? Colors.white54 : Colors.grey.shade600),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          if (_proposers.length < (org?.maxProposers ?? 5))
                            OutlinedButton.icon(
                              onPressed: () => setState(() => _proposers.add(_EndorsementItem(endorsementType: 'proposer'))),
                              icon: const Icon(Icons.add_rounded, size: 16),
                              label: const Text('Add Proposer', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                              style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.primary,
                                    side: const BorderSide(color: AppColors.primary),
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
                          primaryColor: AppColors.primary,
                          roleIcon: Icons.how_to_reg_rounded,
                          onRemove: _proposers.length > (org?.minProposers ?? 1)
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
                                  color: const Color(0xFF059669).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text('${_supporters.length}/${org?.maxSupporters ?? 5}', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF059669))),
                              ),
                              const SizedBox(width: 8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('SUPPORTERS (समर्थक)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                                  Text(
                                    'Required: Min ${org?.minSupporters ?? 1}, Max ${org?.maxSupporters ?? 5}',
                                    style: TextStyle(fontSize: 10.5, color: isDark ? Colors.white54 : Colors.grey.shade600),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          if (_supporters.length < (org?.maxSupporters ?? 5))
                            OutlinedButton.icon(
                              onPressed: () => setState(() => _supporters.add(_EndorsementItem(endorsementType: 'supporter'))),
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
                          onRemove: _supporters.length > (org?.minSupporters ?? 1)
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
                      const SizedBox(height: 28),

                      _buildEmbeddedPaymentCard(
                        isDark: isDark,
                        org: org,
                        election: election,
                      ),
                      const SizedBox(height: 24),
                      
                      LoadingButton(
                        onPressed: _submit,
                        isLoading: _isSubmitting,
                        label: 'Submit Nomination Form',
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    ),
  );
}

  Widget _buildEmbeddedPaymentCard({
    required bool isDark,
    required OrganizationModel? org,
    required ElectionModel? election,
  }) {
    final effectivePositionId = _selectedPositionId ?? (election?.isSamanupatik == true ? election?.positions.firstOrNull?.id : null);
    // If no position selected yet, show an inviting helper banner
    if (effectivePositionId == null) {
      return Container(
        margin: const EdgeInsets.only(bottom: 24),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.blue.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline_rounded, color: Colors.blue, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Nomination Fee & Static QR Payment Step',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Colors.blue),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Please select a Position / Designation from the dropdown above to display the applicable fee (e.g. President: Rs. 250), bank details, and upload your payment voucher.',
                    style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.blue.shade900),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final pos = election?.positions.where((p) => p.id == effectivePositionId).firstOrNull;
    final positionTitle = pos?.title ?? 'Selected Designation';
    final fee = pos?.nomineeCharge ?? 0.0;

    final isGlobalPaymentEnabled = org?.isPaymentEnabled ?? false;
    final isPaymentEnabled = isGlobalPaymentEnabled && fee > 0;

    if (!isPaymentEnabled) {
      final message = !isGlobalPaymentEnabled && fee > 0
          ? 'Payment Collection Disabled: Online payments are currently turned OFF in organization settings. No payment or voucher is required for $positionTitle.'
          : 'Free Candidacy (निःशुल्क उम्मेदवारी): No nomination filing fee is required for $positionTitle.';

      return Container(
        margin: const EdgeInsets.only(bottom: 24),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle_outline_rounded, color: Colors.green, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, color: Colors.green),
              ),
            ),
          ],
        ),
      );
    }

    // Determine available payment channels based on configured payment settings
    final hasFonepay = (org?.staticQrImageUrl.isNotEmpty == true) || (org?.bankQrUrl.isNotEmpty == true);
    final hasBankTransfer = (org?.staticAccountNumber.isNotEmpty == true) || (org?.bankAccountNumber.isNotEmpty == true) || (org?.staticBankName.isNotEmpty == true);
    final hasEsewa = (org?.staticEsewaId.isNotEmpty == true) || (org?.staticEsewaQrUrl.isNotEmpty == true);
    final hasKhalti = (org?.staticKhaltiId.isNotEmpty == true) || (org?.staticKhaltiQrUrl.isNotEmpty == true);
    final hasConnectIps = (org?.staticConnectIpsId.isNotEmpty == true);

    final channels = <Map<String, dynamic>>[
      if (hasFonepay)
        {
          'id': 'fonepay',
          'title': 'FonePay / Bank QR',
          'icon': Icons.qr_code_2_rounded,
          'color': const Color(0xFF2563EB),
        },
      if (hasBankTransfer)
        {
          'id': 'bank_transfer',
          'title': 'Bank Transfer (A/C)',
          'icon': Icons.account_balance_rounded,
          'color': const Color(0xFF1E3A8A),
        },
      if (hasEsewa)
        {
          'id': 'esewa',
          'title': 'eSewa',
          'icon': Icons.account_balance_wallet_rounded,
          'color': const Color(0xFF60BB46),
        },
      if (hasKhalti)
        {
          'id': 'khalti',
          'title': 'Khalti',
          'icon': Icons.wallet_rounded,
          'color': const Color(0xFF5C2D91),
        },
      if (hasConnectIps)
        {
          'id': 'connectips',
          'title': 'ConnectIPS',
          'icon': Icons.sync_alt_rounded,
          'color': const Color(0xFF0284C7),
        },
    ];

    // Fallback if payment is enabled but no specific method is configured
    if (channels.isEmpty) {
      channels.add({
        'id': 'bank_transfer',
        'title': 'Direct Bank / Voucher Deposit',
        'icon': Icons.receipt_long_rounded,
        'color': const Color(0xFF2563EB),
      });
    }

    // Selected channel details
    final activeChannel = channels.any((c) => c['id'] == _selectedPaymentChannel)
        ? channels.firstWhere((c) => c['id'] == _selectedPaymentChannel)
        : channels.first;
    final activeChannelId = activeChannel['id'] as String;
    final activeColor = activeChannel['color'] as Color;

    return Container(
      margin: const EdgeInsets.only(bottom: 28),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: activeColor.withValues(alpha: 0.4),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: activeColor.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: activeColor.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              border: Border(bottom: BorderSide(color: activeColor.withValues(alpha: 0.2))),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: activeColor.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(activeChannel['icon'] as IconData, color: activeColor, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Nomination Fee Payment (उम्मेदवारी दर्ता दस्तुर)',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      Text(
                        'Designation: $positionTitle',
                        style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.grey.shade700),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: activeColor,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(color: activeColor.withValues(alpha: 0.3), blurRadius: 6, offset: const Offset(0, 2)),
                    ],
                  ),
                  child: Text(
                    'Rs. ${fee.toStringAsFixed(0)} NPR',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 14.5),
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ══════════════════════════════════════════════════════════
                // 1. SELECT PAYMENT METHOD CHANNEL TABS
                // ══════════════════════════════════════════════════════════
                const Text(
                  'Select Payment Method (भुक्तानी माध्यम छान्नुहोस्):',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: channels.map((c) {
                    final isSelected = c['id'] == activeChannelId;
                    final chColor = c['color'] as Color;

                    return ChoiceChip(
                      selected: isSelected,
                      onSelected: (val) {
                        if (val) setState(() => _selectedPaymentChannel = c['id'] as String);
                      },
                      avatar: Icon(c['icon'] as IconData, size: 16, color: isSelected ? Colors.white : chColor),
                      label: Text(c['title'] as String),
                      selectedColor: chColor,
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : (isDark ? Colors.white : Colors.black87),
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        fontSize: 12.5,
                      ),
                      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                      side: BorderSide(
                        color: isSelected ? chColor : (isDark ? Colors.white12 : Colors.grey.shade300),
                      ),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),

                // ══════════════════════════════════════════════════════════
                // 2. ACTIVE CHANNEL PAYMENT DETAILS CARD
                // ══════════════════════════════════════════════════════════
                _buildActiveChannelContent(
                  channelId: activeChannelId,
                  activeColor: activeColor,
                  org: org,
                  isDark: isDark,
                ),

                if (org != null && org.staticInstructions.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline, size: 18, color: Colors.blue),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            org.staticInstructions,
                            style: const TextStyle(fontSize: 12, color: Colors.blue),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 20),
                const Divider(height: 1),
                const SizedBox(height: 20),

                // ══════════════════════════════════════════════════════════
                // 3. VOUCHER & TRANSACTION ID SUBMISSION
                // ══════════════════════════════════════════════════════════
                const Text(
                  'Submit Payment Proof & Voucher (भौचर तथा भुक्तानी प्रमाण) *',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 14),

                TextFormField(
                  controller: _txnRefCtrl,
                  decoration: InputDecoration(
                    labelText: 'Transaction Reference ID / Voucher Number *',
                    hintText: 'e.g. TXN-99887766 or Bank Voucher No',
                    prefixIcon: const Icon(Icons.pin_outlined, size: 20),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  validator: (v) {
                    if (isPaymentEnabled && (v == null || v.trim().isEmpty)) {
                      return 'Please enter Transaction Reference ID';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Voucher uploader with preview box
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _voucherImageUrl.isNotEmpty
                        ? Colors.green.withValues(alpha: 0.06)
                        : (isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC)),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _voucherImageUrl.isNotEmpty
                          ? Colors.green.withValues(alpha: 0.4)
                          : (isDark ? Colors.white12 : Colors.grey.shade300),
                      style: _voucherImageUrl.isNotEmpty ? BorderStyle.solid : BorderStyle.solid,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _voucherImageUrl.isNotEmpty
                              ? Colors.green.withValues(alpha: 0.15)
                              : AppColors.primary.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _voucherImageUrl.isNotEmpty ? Icons.receipt_long_rounded : Icons.upload_file_rounded,
                          color: _voucherImageUrl.isNotEmpty ? Colors.green : AppColors.primary,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _voucherImageUrl.isNotEmpty
                                  ? 'Receipt Voucher Attached'
                                  : 'Upload Payment Voucher / Receipt Screenshot',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: _voucherImageUrl.isNotEmpty ? Colors.green.shade800 : null,
                              ),
                            ),
                            Text(
                              _voucherImageUrl.isNotEmpty
                                  ? _voucherImageUrl.split("/").last
                                  : 'PNG, JPG, PDF (Screenshot from Mobile Banking/eSewa/Khalti)',
                              style: TextStyle(fontSize: 11.5, color: isDark ? Colors.white60 : Colors.grey.shade600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton.icon(
                        onPressed: _isUploadingVoucher
                            ? null
                            : () async {
                                final res = await FilePicker.platform.pickFiles(
                                  type: FileType.custom,
                                  allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
                                  withData: true,
                                );
                                if (res == null || res.files.isEmpty || res.files.first.bytes == null) return;
                                setState(() => _isUploadingVoucher = true);
                                try {
                                  final dio = ref.read(apiClientProvider);
                                  final resp = await dio.post(
                                    ApiConstants.fileUpload,
                                    data: FormData.fromMap({
                                      'file': MultipartFile.fromBytes(
                                        res.files.first.bytes!,
                                        filename: res.files.first.name,
                                      ),
                                    }),
                                  );
                                  final url = resp.data['url'] as String?;
                                  setState(() {
                                    _isUploadingVoucher = false;
                                    if (url != null) _voucherImageUrl = url;
                                  });
                                } catch (_) {
                                  setState(() => _isUploadingVoucher = false);
                                }
                              },
                        icon: _isUploadingVoucher
                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                            : Icon(_voucherImageUrl.isNotEmpty ? Icons.change_circle_rounded : Icons.attach_file_rounded, size: 16),
                        label: Text(_voucherImageUrl.isNotEmpty ? 'Change' : 'Browse File'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _voucherImageUrl.isNotEmpty ? Colors.green.shade700 : AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _paymentNotesCtrl,
                  decoration: InputDecoration(
                    labelText: 'Payment Remarks / Notes (Optional)',
                    hintText: 'e.g. Paid via eSewa by Candidate',
                    prefixIcon: const Icon(Icons.note_alt_outlined, size: 20),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveChannelContent({
    required String channelId,
    required Color activeColor,
    required dynamic org,
    required bool isDark,
  }) {
    if (channelId == 'fonepay') {
      final qrPath = org?.staticQrImageUrl ?? (org?.bankQrUrl ?? '');
      final fullQrUrl = qrPath.isNotEmpty ? ApiConstants.getFullImageUrl(qrPath) : null;

      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: activeColor.withValues(alpha: 0.25)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 130,
              height: 130,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: fullQrUrl != null
                    ? Image.network(
                        fullQrUrl,
                        fit: BoxFit.contain,
                        errorBuilder: (ctx, err, stack) => _buildQrPlaceholder(activeColor, isDark),
                      )
                    : _buildQrPlaceholder(activeColor, isDark),
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: activeColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('Official FonePay / Standee QR', style: TextStyle(color: activeColor, fontWeight: FontWeight.bold, fontSize: 11)),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Scan this QR code using any Mobile Banking App (Global IME, NIC Asia, Nabil, etc.) or FonePay.',
                    style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.grey.shade700),
                  ),
                  const SizedBox(height: 8),
                  if (org?.staticBankName.isNotEmpty == true) ...[
                    Text('Bank: ${org!.staticBankName}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  ],
                  if (org?.staticAccountName.isNotEmpty == true) ...[
                    const SizedBox(height: 2),
                    Text('A/C Name: ${org!.staticAccountName}', style: const TextStyle(fontSize: 12)),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (channelId == 'bank_transfer') {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: activeColor.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: activeColor.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.account_balance_rounded, color: activeColor, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        org?.staticBankName.isNotEmpty == true ? org!.staticBankName : 'Direct Bank Account Deposit',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                      ),
                      if (org?.staticBranch.isNotEmpty == true)
                        Text('Branch: ${org!.staticBranch}', style: TextStyle(fontSize: 11.5, color: isDark ? Colors.white60 : Colors.grey.shade600)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (org?.staticAccountNumber.isNotEmpty == true) ...[
              _buildCopyableRow(label: 'Account Number (खाता नम्बर)', value: org!.staticAccountNumber, isDark: isDark),
              const SizedBox(height: 6),
            ],
            if (org?.staticAccountName.isNotEmpty == true) ...[
              Text('Account Holder: ${org!.staticAccountName}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500)),
              const SizedBox(height: 6),
            ],
            Text(
              '💡 Tip: Transfer the nomination fee via your Mobile Banking app or Bank Counter, then upload the voucher screenshot below.',
              style: TextStyle(fontSize: 11.5, color: isDark ? Colors.white54 : Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    if (channelId == 'esewa') {
      final hasQr = org?.staticEsewaQrUrl.isNotEmpty == true;
      final fullQrUrl = hasQr ? ApiConstants.getFullImageUrl(org!.staticEsewaQrUrl) : null;

      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: activeColor.withValues(alpha: 0.25)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasQr && fullQrUrl != null) ...[
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(11),
                  child: Image.network(
                    fullQrUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (ctx, err, stack) => _buildQrPlaceholder(activeColor, isDark),
                  ),
                ),
              ),
              const SizedBox(width: 16),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF60BB46).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('eSewa Wallet Transfer', style: TextStyle(color: Color(0xFF60BB46), fontWeight: FontWeight.bold, fontSize: 11)),
                  ),
                  const SizedBox(height: 10),
                  _buildCopyableRow(
                    label: 'eSewa ID / Mobile No',
                    value: org?.staticEsewaId.isNotEmpty == true
                        ? org!.staticEsewaId
                        : (org?.staticWalletId.isNotEmpty == true ? org!.staticWalletId : 'Official Account'),
                    isDark: isDark,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '💡 Send money directly from your eSewa App to the ID above and attach the screenshot.',
                    style: TextStyle(fontSize: 11.5, color: isDark ? Colors.white54 : Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (channelId == 'khalti') {
      final hasQr = org?.staticKhaltiQrUrl.isNotEmpty == true;
      final fullQrUrl = hasQr ? ApiConstants.getFullImageUrl(org!.staticKhaltiQrUrl) : null;

      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: activeColor.withValues(alpha: 0.25)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasQr && fullQrUrl != null) ...[
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(11),
                  child: Image.network(
                    fullQrUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (ctx, err, stack) => _buildQrPlaceholder(activeColor, isDark),
                  ),
                ),
              ),
              const SizedBox(width: 16),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF5C2D91).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('Khalti Wallet Transfer', style: TextStyle(color: Color(0xFF5C2D91), fontWeight: FontWeight.bold, fontSize: 11)),
                  ),
                  const SizedBox(height: 10),
                  _buildCopyableRow(
                    label: 'Khalti ID / Mobile No',
                    value: org?.staticKhaltiId.isNotEmpty == true
                        ? org!.staticKhaltiId
                        : (org?.staticWalletId.isNotEmpty == true ? org!.staticWalletId : 'Official Account'),
                    isDark: isDark,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '💡 Send money directly from your Khalti App to the ID above and attach the screenshot.',
                    style: TextStyle(fontSize: 11.5, color: isDark ? Colors.white54 : Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (channelId == 'connectips') {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: activeColor.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: activeColor.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.sync_alt_rounded, color: activeColor, size: 20),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'ConnectIPS Direct Inter-Bank Transfer (NCHL)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (org?.staticConnectIpsId.isNotEmpty == true) ...[
              _buildCopyableRow(label: 'ConnectIPS Payee / Username', value: org!.staticConnectIpsId, isDark: isDark),
              const SizedBox(height: 6),
            ],
            if (org?.staticAccountNumber.isNotEmpty == true) ...[
              _buildCopyableRow(label: 'Bank A/C Number', value: org!.staticAccountNumber, isDark: isDark),
              const SizedBox(height: 6),
            ],
            if (org?.staticBankName.isNotEmpty == true) ...[
              Text('Bank Name: ${org!.staticBankName}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500)),
              const SizedBox(height: 6),
            ],
            Text(
              '💡 Tip: Transfer via connectips.com or ConnectIPS Mobile App, then input the transaction reference ID below.',
              style: TextStyle(fontSize: 11.5, color: isDark ? Colors.white54 : Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildCopyableRow({required String label, required String value, required bool isDark}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            '$label: $value',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.primaryLight),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.copy_rounded, size: 16),
          visualDensity: VisualDensity.compact,
          tooltip: 'Copy $label',
          onPressed: () {
            Clipboard.setData(ClipboardData(text: value));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('$label copied to clipboard!'),
                duration: const Duration(seconds: 2),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildQrPlaceholder(Color activeColor, bool isDark) {
    return Container(
      color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.qr_code_2_rounded, size: 48, color: activeColor),
          const SizedBox(height: 6),
          Text(
            'Scan via App',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isDark ? Colors.white70 : Colors.grey.shade700),
          ),
        ],
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
