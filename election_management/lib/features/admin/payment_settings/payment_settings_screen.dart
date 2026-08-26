import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/providers/org_providers.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_constants.dart';
import '../../../shared/widgets/loading_button.dart';
import '../../../shared/widgets/admin_drawer.dart';
import '../../../shared/widgets/shimmer_loaders.dart';
import '../../../shared/widgets/responsive_layout.dart';

class PaymentSettingsScreen extends ConsumerStatefulWidget {
  const PaymentSettingsScreen({super.key});

  @override
  ConsumerState<PaymentSettingsScreen> createState() => _PaymentSettingsScreenState();
}

class _PaymentSettingsScreenState extends ConsumerState<PaymentSettingsScreen> {
  bool _isPaymentEnabled = false;
  String _qrImageUrl = '';
  bool _uploadingQr = false;

  late TextEditingController _bankNameCtrl;
  late TextEditingController _accountNameCtrl;
  late TextEditingController _accountNumberCtrl;
  late TextEditingController _branchCtrl;
  
  late TextEditingController _esewaIdCtrl;
  String _esewaQrUrl = '';
  bool _uploadingEsewaQr = false;

  late TextEditingController _khaltiIdCtrl;
  String _khaltiQrUrl = '';
  bool _uploadingKhaltiQr = false;

  late TextEditingController _connectIpsIdCtrl;
  late TextEditingController _instructionsCtrl;

  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _bankNameCtrl = TextEditingController();
    _accountNameCtrl = TextEditingController();
    _accountNumberCtrl = TextEditingController();
    _branchCtrl = TextEditingController();
    _esewaIdCtrl = TextEditingController();
    _khaltiIdCtrl = TextEditingController();
    _connectIpsIdCtrl = TextEditingController();
    _instructionsCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _bankNameCtrl.dispose();
    _accountNameCtrl.dispose();
    _accountNumberCtrl.dispose();
    _branchCtrl.dispose();
    _esewaIdCtrl.dispose();
    _khaltiIdCtrl.dispose();
    _connectIpsIdCtrl.dispose();
    _instructionsCtrl.dispose();
    super.dispose();
  }

  void _populateForm(Map<String, dynamic> ps, dynamic org) {
    if (_initialized) return;

    _isPaymentEnabled = (ps['is_payment_enabled'] as bool?) ?? false;
    _qrImageUrl = (ps['qr_image_url'] as String?) ?? (org.bankQrUrl ?? '');
    if (_qrImageUrl.isEmpty && ps['qr_account'] is Map) {
      _qrImageUrl = (ps['qr_account']['qr_image_url'] as String?) ?? '';
    }

    _bankNameCtrl.text = (ps['bank_name'] as String?) ?? (org.bankName ?? '');
    _accountNameCtrl.text = (ps['account_name'] as String?) ?? (org.bankAccountName ?? '');
    _accountNumberCtrl.text = (ps['account_number'] as String?) ?? (org.bankAccountNumber ?? '');
    _branchCtrl.text = (ps['branch'] as String?) ?? (org.bankBranch ?? '');
    
    _esewaIdCtrl.text = (ps['esewa_id'] as String?) ?? (ps['wallet_id'] as String? ?? '');
    _esewaQrUrl = (ps['esewa_qr_url'] as String?) ?? '';
    _khaltiIdCtrl.text = (ps['khalti_id'] as String?) ?? ((ps['imepay_id'] as String?) ?? '');
    _khaltiQrUrl = (ps['khalti_qr_url'] as String?) ?? ((ps['imepay_qr_url'] as String?) ?? '');
    _connectIpsIdCtrl.text = (ps['connectips_id'] as String?) ?? '';

    final inst = (ps['instructions'] as String?) ?? '';
    if (inst.isNotEmpty) {
      _instructionsCtrl.text = inst;
    } else if (ps['qr_account'] is Map && (ps['qr_account']['details'] as String?)?.isNotEmpty == true) {
      _instructionsCtrl.text = ps['qr_account']['details'] as String;
    } else {
      _instructionsCtrl.text =
          'Please choose your preferred payment method (FonePay QR, Bank Transfer, eSewa, Khalti, or ConnectIPS). '
          'In the Remarks / Reference field, enter your Full Name & Candidacy Position. '
          'After completing payment, submit the Transaction ID & upload your receipt voucher below.';
    }

    _initialized = true;
  }

  Map<String, dynamic> _buildPayload() => {
        'is_payment_enabled': _isPaymentEnabled,
        'qr_image_url': _qrImageUrl.trim(),
        'bank_name': _bankNameCtrl.text.trim(),
        'account_name': _accountNameCtrl.text.trim(),
        'account_number': _accountNumberCtrl.text.trim(),
        'branch': _branchCtrl.text.trim(),
        'esewa_id': _esewaIdCtrl.text.trim(),
        'esewa_qr_url': _esewaQrUrl.trim(),
        'khalti_id': _khaltiIdCtrl.text.trim(),
        'khalti_qr_url': _khaltiQrUrl.trim(),
        'imepay_id': _khaltiIdCtrl.text.trim(),
        'imepay_qr_url': _khaltiQrUrl.trim(),
        'connectips_id': _connectIpsIdCtrl.text.trim(),
        'wallet_id': _esewaIdCtrl.text.isNotEmpty ? _esewaIdCtrl.text.trim() : _khaltiIdCtrl.text.trim(),
        'wallet_type': 'fonepay',
        'default_nomination_fee': 0.0,
        'instructions': _instructionsCtrl.text.trim(),
        'qr_account': {
          'details': _instructionsCtrl.text.trim(),
          'qr_image_url': _qrImageUrl.trim(),
          'bank_name': _bankNameCtrl.text.trim(),
          'account_name': _accountNameCtrl.text.trim(),
          'account_number': _accountNumberCtrl.text.trim(),
          'branch': _branchCtrl.text.trim(),
        }
      };

  Future<void> _submit() async {
    try {
      final payload = _buildPayload();
      await ref.read(updateOrgSettingsProvider.notifier).updateSettings({
        'payment_settings': payload,
        'bank_name': _bankNameCtrl.text.trim(),
        'bank_account_name': _accountNameCtrl.text.trim(),
        'bank_account_number': _accountNumberCtrl.text.trim(),
        'bank_branch': _branchCtrl.text.trim(),
        'bank_qr_url': _qrImageUrl.trim(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Row(children: [
            Icon(Icons.check_circle_rounded, color: Colors.white),
            SizedBox(width: 12),
            Text('Static QR Payment settings saved successfully!',
                style: TextStyle(fontWeight: FontWeight.bold))
          ]),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(24),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text('Error saving settings: $e'))
          ]),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(24),
        ));
      }
    }
  }

  Future<void> _pickAndUploadQr() async {
    setState(() => _uploadingQr = true);
    final url = await _pickAndUploadSingleImage();
    if (mounted) {
      setState(() {
        _uploadingQr = false;
        if (url != null) _qrImageUrl = url;
      });
    }
  }

  Future<String?> _pickAndUploadSingleImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
        withData: true,
      );
      if (result == null || result.files.isEmpty || result.files.first.bytes == null) return null;

      final fileBytes = result.files.first.bytes!;
      final fileName = result.files.first.name;

      final dio = ref.read(apiClientProvider);
      final resp = await dio.post(
        ApiConstants.fileUpload,
        data: FormData.fromMap({
          'file': MultipartFile.fromBytes(fileBytes, filename: fileName),
        }),
      );

      return resp.data['url'] as String?;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to upload image: $e')),
        );
      }
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final orgAsync = ref.watch(orgProfileProvider);
    final isSaving = ref.watch(updateOrgSettingsProvider).isLoading;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      drawer: const AdminDrawer(),
      appBar: AppBar(
        title: const Text('Payment Settings & Multi-Channel Setup (भुक्तानी व्यवस्थापन)'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          tooltip: 'Back',
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/dashboard');
            }
          },
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16, top: 8, bottom: 8),
            child: LoadingButton(
              onPressed: _submit,
              isLoading: isSaving,
              label: 'Save Settings',
              icon: Icons.save_rounded,
              fullWidth: false,
            ),
          ),
        ],
      ),
      body: ResponsivePageWrapper(
        child: orgAsync.when(
          loading: () => const ListSkeleton(count: 4),
          error: (err, _) => Center(child: Text('Error loading organization profile: $err')),
          data: (org) {
            _populateForm(org.paymentSettings, org);

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 880),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildMasterSwitchCard(isDark),
                        const SizedBox(height: 24),

                        _buildQrUploadCard(isDark),
                        const SizedBox(height: 24),

                        _buildBankDetailsCard(isDark),
                        const SizedBox(height: 24),

                        _buildEsewaCard(isDark),
                        const SizedBox(height: 24),

                        _buildKhaltiCard(isDark),
                        const SizedBox(height: 24),

                        _buildConnectIpsCard(isDark),
                        const SizedBox(height: 24),

                        _buildInstructionsCard(isDark),
                        const SizedBox(height: 24),

                        _buildLivePreviewCard(isDark),
                        const SizedBox(height: 32),

                        SizedBox(
                          width: double.infinity,
                          child: LoadingButton(
                            onPressed: _submit,
                            isLoading: isSaving,
                            label: 'Save & Apply Payment Settings',
                            icon: Icons.check_circle_outline_rounded,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildMasterSwitchCard(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surface : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isPaymentEnabled
              ? const Color(0xFF10B981).withValues(alpha: 0.5)
              : (isDark ? Colors.white12 : Colors.grey.shade300),
          width: _isPaymentEnabled ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: _isPaymentEnabled
                ? const Color(0xFF10B981).withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _isPaymentEnabled
                  ? const Color(0xFF10B981).withValues(alpha: 0.15)
                  : Colors.grey.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _isPaymentEnabled ? Icons.power_rounded : Icons.power_off_rounded,
              color: _isPaymentEnabled ? const Color(0xFF10B981) : Colors.grey,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Global Payment Requirement',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: _isPaymentEnabled
                            ? const Color(0xFF10B981).withValues(alpha: 0.15)
                            : Colors.grey.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _isPaymentEnabled ? 'ACTIVE (सक्रिय)' : 'OFF (निस्क्रिय)',
                        style: TextStyle(
                          color: _isPaymentEnabled ? const Color(0xFF10B981) : Colors.grey,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _isPaymentEnabled
                      ? 'Payments are required. Candidates must scan your static QR code and provide Transaction ID & voucher proof upon filing nomination.'
                      : 'Payments are disabled. Candidate nominations are free and will bypass the payment checkout step completely.',
                  style: TextStyle(
                    color: isDark ? Colors.white60 : Colors.grey.shade600,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch(
            value: _isPaymentEnabled,
            activeThumbColor: const Color(0xFF10B981),
            activeTrackColor: const Color(0xFF10B981).withValues(alpha: 0.3),
            onChanged: (val) {
              setState(() => _isPaymentEnabled = val);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildQrUploadCard(bool isDark) {
    final hasImg = _qrImageUrl.isNotEmpty;
    final fullUrl = hasImg ? ApiConstants.getFullImageUrl(_qrImageUrl) : null;

    return _cardWrapper(
      isDark: isDark,
      title: 'Official Static QR Code Standee (आधिकारिक QR कोड)',
      subtitle: 'Upload your organization’s standard FonePay, Bank QR, eSewa, or Khalti standee image',
      icon: Icons.qr_code_scanner_rounded,
      brandColor: const Color(0xFF2563EB),
      children: [
        GestureDetector(
          onTap: _uploadingQr ? null : _pickAndUploadQr,
          child: Container(
            height: 240,
            width: double.infinity,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF27272A) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? Colors.white12 : Colors.grey.shade300,
                width: 1.5,
              ),
              image: fullUrl != null
                  ? DecorationImage(image: NetworkImage(fullUrl), fit: BoxFit.contain)
                  : null,
            ),
            child: _uploadingQr
                ? const Center(child: CircularProgressIndicator())
                : hasImg
                    ? Align(
                        alignment: Alignment.bottomRight,
                        child: Container(
                          margin: const EdgeInsets.all(12),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: const [
                              BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2)),
                            ],
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.edit_rounded, color: Colors.white, size: 16),
                              SizedBox(width: 6),
                              Text('Change QR Image', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.add_photo_alternate_rounded, color: AppColors.primary, size: 36),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Click to upload official Bank / Wallet QR Code',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Supports PNG, JPG, WEBP (Max 5 MB)',
                            style: TextStyle(color: isDark ? Colors.white54 : Colors.grey.shade600, fontSize: 12),
                          ),
                        ],
                      ),
          ),
        ),
        if (hasImg) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: () => setState(() => _qrImageUrl = ''),
                icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 16),
                label: const Text('Remove QR Image', style: TextStyle(color: Colors.red, fontSize: 12)),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildBankDetailsCard(bool isDark) {
    return _cardWrapper(
      isDark: isDark,
      title: 'Direct Bank Transfer (बैंक खाता विवरण)',
      subtitle: 'Provide organization bank account details for candidates making direct mobile/bank transfers',
      icon: Icons.account_balance_rounded,
      brandColor: const Color(0xFF1E3A8A),
      children: [
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _bankNameCtrl,
                decoration: _dec('Bank Name (बैंकको नाम)', hint: 'e.g. Global IME Bank / Nabil Bank', prefix: const Icon(Icons.account_balance_outlined)),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: TextFormField(
                controller: _branchCtrl,
                decoration: _dec('Branch (शाखा)', hint: 'e.g. Kantipath, Kathmandu', prefix: const Icon(Icons.location_on_outlined)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _accountNameCtrl,
                decoration: _dec('Account Holder Name (खातावालाको नाम) *', hint: 'e.g. Election Committee Account', prefix: const Icon(Icons.person_outline)),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: TextFormField(
                controller: _accountNumberCtrl,
                decoration: _dec('Account Number (खाता नम्बर) *', hint: 'e.g. 01234567890123', prefix: const Icon(Icons.pin_outlined)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEsewaCard(bool isDark) {
    final hasImg = _esewaQrUrl.isNotEmpty;
    final fullUrl = hasImg ? ApiConstants.getFullImageUrl(_esewaQrUrl) : null;

    return _cardWrapper(
      isDark: isDark,
      title: 'eSewa Payment Details (ई-सेवा विवरण)',
      subtitle: 'Candidates can transfer directly to this eSewa ID or scan the designated eSewa QR',
      icon: Icons.account_balance_wallet_rounded,
      brandColor: const Color(0xFF60BB46),
      children: [
        TextFormField(
          controller: _esewaIdCtrl,
          decoration: _dec('eSewa ID / Mobile Number (ई-सेवा आईडी / नम्बर)', hint: 'e.g. 98XXXXXXXX or election@esewa', prefix: const Icon(Icons.phone_android_rounded, color: Color(0xFF60BB46))),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: _uploadingEsewaQr
                  ? null
                  : () async {
                      setState(() => _uploadingEsewaQr = true);
                      final url = await _pickAndUploadSingleImage();
                      setState(() {
                        _uploadingEsewaQr = false;
                        if (url != null) _esewaQrUrl = url;
                      });
                    },
              icon: _uploadingEsewaQr
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(hasImg ? Icons.check_circle_rounded : Icons.qr_code_2_rounded, color: hasImg ? const Color(0xFF60BB46) : null),
              label: Text(hasImg ? 'Change eSewa QR Code' : 'Upload eSewa QR Code (Optional)'),
            ),
            if (hasImg) ...[
              const SizedBox(width: 12),
              if (fullUrl != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.network(fullUrl, width: 36, height: 36, fit: BoxFit.cover, errorBuilder: (ctx, err, stack) => const Icon(Icons.qr_code)),
                ),
              const Spacer(),
              TextButton(
                onPressed: () => setState(() => _esewaQrUrl = ''),
                child: const Text('Remove', style: TextStyle(color: Colors.red, fontSize: 12)),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildKhaltiCard(bool isDark) {
    final hasImg = _khaltiQrUrl.isNotEmpty;
    final fullUrl = hasImg ? ApiConstants.getFullImageUrl(_khaltiQrUrl) : null;

    return _cardWrapper(
      isDark: isDark,
      title: 'Khalti Payment Details (खल्ती विवरण)',
      subtitle: 'Candidates can transfer directly to this Khalti ID or scan the designated Khalti QR',
      icon: Icons.wallet_rounded,
      brandColor: const Color(0xFF5C2D91),
      children: [
        TextFormField(
          controller: _khaltiIdCtrl,
          decoration: _dec('Khalti ID / Mobile Number (खल्ती आईडी / नम्बर) *', hint: 'e.g. 98XXXXXXXX', prefix: const Icon(Icons.phone_android_rounded, color: Color(0xFF5C2D91))),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: _uploadingKhaltiQr
                  ? null
                  : () async {
                      setState(() => _uploadingKhaltiQr = true);
                      final url = await _pickAndUploadSingleImage();
                      setState(() {
                        _uploadingKhaltiQr = false;
                        if (url != null) _khaltiQrUrl = url;
                      });
                    },
              icon: _uploadingKhaltiQr
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(hasImg ? Icons.check_circle_rounded : Icons.qr_code_2_rounded, color: hasImg ? const Color(0xFF5C2D91) : null),
              label: Text(hasImg ? 'Change Khalti QR Code' : 'Upload Khalti QR Code (Optional)'),
            ),
            if (hasImg) ...[
              const SizedBox(width: 12),
              if (fullUrl != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.network(fullUrl, width: 36, height: 36, fit: BoxFit.cover, errorBuilder: (ctx, err, stack) => const Icon(Icons.qr_code)),
                ),
              const Spacer(),
              TextButton(
                onPressed: () => setState(() => _khaltiQrUrl = ''),
                child: const Text('Remove', style: TextStyle(color: Colors.red, fontSize: 12)),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildConnectIpsCard(bool isDark) {
    return _cardWrapper(
      isDark: isDark,
      title: 'ConnectIPS & NCHL Transfer (कनेक्ट आइपिएस)',
      subtitle: 'Provide ConnectIPS payee details for inter-bank digital transfers',
      icon: Icons.sync_alt_rounded,
      brandColor: const Color(0xFF0284C7),
      children: [
        TextFormField(
          controller: _connectIpsIdCtrl,
          decoration: _dec('ConnectIPS Payee ID / Username', hint: 'e.g. ELECT2026 or Organization Payee Name', prefix: const Icon(Icons.link_rounded, color: Color(0xFF0284C7))),
        ),
      ],
    );
  }

  Widget _buildInstructionsCard(bool isDark) {
    return _cardWrapper(
      isDark: isDark,
      title: 'Payment Guidelines & Remarks Guide (भुक्तानी निर्देशन)',
      subtitle: 'Clear instructions presented to candidates when they complete their QR payment and upload proof',
      icon: Icons.assignment_outlined,
      brandColor: const Color(0xFF8B5CF6),
      children: [
        TextFormField(
          controller: _instructionsCtrl,
          maxLines: 4,
          decoration: _dec(
            'Instructions for Candidate',
            hint: 'Specify remarks guidelines, acceptable payment formats, and voucher verification rules...',
            prefix: const Icon(Icons.notes_outlined),
          ),
        ),
      ],
    );
  }

  Widget _buildLivePreviewCard(bool isDark) {
    final fullUrl = _qrImageUrl.isNotEmpty ? ApiConstants.getFullImageUrl(_qrImageUrl) : null;

    return _cardWrapper(
      isDark: isDark,
      title: 'Candidate Live Checkout Preview (उम्मेदवारलाई देखिने रूप)',
      subtitle: 'This is the interactive payment sheet that candidates see during nomination submission',
      icon: Icons.preview_rounded,
      brandColor: const Color(0xFF059669),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF059669).withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.qr_code_2_rounded, color: Color(0xFF059669), size: 22),
                      SizedBox(width: 8),
                      Text(
                        'Nomination Fee Checkout',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF059669).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Per Designation Fee',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF059669), fontSize: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 14),

              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // QR preview box
                  Container(
                    width: 130,
                    height: 130,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade300),
                      image: fullUrl != null
                          ? DecorationImage(image: NetworkImage(fullUrl), fit: BoxFit.contain)
                          : null,
                    ),
                    child: fullUrl == null
                        ? const Center(
                            child: Icon(Icons.qr_code_scanner, color: Colors.grey, size: 40),
                          )
                        : null,
                  ),
                  const SizedBox(width: 16),

                  // Account preview info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_bankNameCtrl.text.isNotEmpty) ...[
                          Text('Bank: ${_bankNameCtrl.text}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          const SizedBox(height: 4),
                        ],
                        if (_accountNameCtrl.text.isNotEmpty) ...[
                          Text('A/C Name: ${_accountNameCtrl.text}', style: const TextStyle(fontSize: 12)),
                          const SizedBox(height: 4),
                        ],
                        if (_accountNumberCtrl.text.isNotEmpty) ...[
                          Row(
                            children: [
                              Text('A/C No: ${_accountNumberCtrl.text}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.primaryLight)),
                              const SizedBox(width: 6),
                              IconButton(
                                icon: const Icon(Icons.copy_rounded, size: 14),
                                visualDensity: VisualDensity.compact,
                                tooltip: 'Copy Account Number',
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: _accountNumberCtrl.text));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Account number copied to clipboard!')),
                                  );
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                        ],
                        if (_esewaIdCtrl.text.isNotEmpty) ...[
                          Text('eSewa: ${_esewaIdCtrl.text}', style: const TextStyle(fontSize: 12)),
                          const SizedBox(height: 2),
                        ],
                        if (_khaltiIdCtrl.text.isNotEmpty) ...[
                          Text('Khalti: ${_khaltiIdCtrl.text}', style: const TextStyle(fontSize: 12)),
                          const SizedBox(height: 2),
                        ],
                        if (_connectIpsIdCtrl.text.isNotEmpty) ...[
                          Text('ConnectIPS: ${_connectIpsIdCtrl.text}', style: const TextStyle(fontSize: 12)),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 16, color: Colors.blue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _instructionsCtrl.text.isNotEmpty
                            ? _instructionsCtrl.text
                            : 'Scan QR and enter Transaction Reference ID after payment.',
                        style: const TextStyle(fontSize: 11.5, color: Colors.blue),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _cardWrapper({
    required bool isDark,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color brandColor,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: brandColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: brandColor.withValues(alpha: 0.3)),
              ),
              child: Icon(icon, color: brandColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  Text(subtitle, style: TextStyle(color: isDark ? Colors.white60 : Colors.grey.shade600, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Material(
          color: isDark ? AppColors.surface : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.shade200,
            ),
          ),
          elevation: isDark ? 0 : 1,
          shadowColor: Colors.black.withValues(alpha: 0.04),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
          ),
        ),
      ],
    );
  }

  InputDecoration _dec(String label, {String? hint, Widget? prefix}) => InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: prefix,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      );
}
