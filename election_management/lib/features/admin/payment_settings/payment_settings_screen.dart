import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/org_providers.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_constants.dart';
import '../../../shared/widgets/loading_button.dart';
import '../../../shared/widgets/admin_drawer.dart';
import '../../../shared/widgets/shimmer_loaders.dart';
import '../../../shared/widgets/responsive_layout.dart';

Map<String, dynamic> _gatewayMap(Map<String, dynamic> ps, String key) {
  final v = ps[key];
  if (v is Map<String, dynamic>) return Map<String, dynamic>.from(v);
  return {};
}

String _str(Map<String, dynamic> m, String key) => (m[key] as String?) ?? '';

class _SecretField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  const _SecretField({required this.controller, required this.label, this.hint});
  @override
  State<_SecretField> createState() => _SecretFieldState();
}

class _SecretFieldState extends State<_SecretField> {
  bool _obscure = true;
  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      obscureText: _obscure,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        prefixIcon: const Icon(Icons.key_rounded, size: 20),
        suffixIcon: IconButton(
          icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
          onPressed: () => setState(() => _obscure = !_obscure),
          tooltip: _obscure ? 'Show' : 'Hide',
        ),
      ),
    );
  }
}

class _QrImageTile extends StatefulWidget {
  final String? initialUrl;
  final Future<String?> Function(Uint8List bytes, String name) onUpload;
  final void Function(String url) onUploaded;
  const _QrImageTile({this.initialUrl, required this.onUpload, required this.onUploaded});
  @override
  State<_QrImageTile> createState() => _QrImageTileState();
}

class _QrImageTileState extends State<_QrImageTile> {
  bool _uploading = false;
  String? _url;

  @override
  void initState() {
    super.initState();
    _url = widget.initialUrl;
  }

  Future<void> _pick() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png'],
      withData: true,
    );
    if (result == null || result.files.isEmpty || result.files.first.bytes == null) return;
    setState(() => _uploading = true);
    final url = await widget.onUpload(result.files.first.bytes!, result.files.first.name);
    if (mounted) {
      setState(() {
        _uploading = false;
        if (url != null) _url = url;
      });
      if (url != null) widget.onUploaded(url);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasImg = _url != null && _url!.isNotEmpty;
    final fullUrl = hasImg ? ApiConstants.getFullImageUrl(_url) : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Payment QR Standee / Passbook Image', style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _uploading ? null : _pick,
          child: Container(
            height: 220,
            width: double.infinity,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF27272A) : const Color(0xFFF4F4F5),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDark ? Colors.white12 : Colors.grey.shade300,
                width: 1.5,
              ),
              image: fullUrl != null ? DecorationImage(image: NetworkImage(fullUrl), fit: BoxFit.contain) : null,
            ),
            child: _uploading
                ? const Center(child: CircularProgressIndicator())
                : hasImg
                    ? Align(
                        alignment: Alignment.bottomRight,
                        child: Container(
                          margin: const EdgeInsets.all(10),
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
                            ],
                          ),
                          child: const Icon(Icons.edit, color: Colors.white, size: 16),
                        ),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.qr_code_scanner_rounded, color: AppColors.textMuted, size: 44),
                          const SizedBox(height: 10),
                          const Text('Tap to upload official QR code image', style: TextStyle(color: AppColors.textMuted, fontSize: 13, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          const Text('jpeg, png · Max 2 MB', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                        ],
                      ),
          ),
        ),
      ],
    );
  }
}

class PaymentSettingsScreen extends ConsumerStatefulWidget {
  const PaymentSettingsScreen({super.key});
  @override
  ConsumerState<PaymentSettingsScreen> createState() => _PaymentSettingsScreenState();
}

class _PaymentSettingsScreenState extends ConsumerState<PaymentSettingsScreen> with TickerProviderStateMixin {
  late TabController _tabController;
  late TextEditingController _eSewaProductCode;
  late TextEditingController _eSewaSecretKey;
  late TextEditingController _mocoMerchantId;
  late TextEditingController _mocoTerminalId;
  late TextEditingController _mocoOutletId;
  late TextEditingController _mocoSharedKey;
  late TextEditingController _fonepayProfileId;
  late TextEditingController _fonepaySharedSecretKey;
  late TextEditingController _khaltiLiveSecretKey;
  late TextEditingController _cipseMerchantId;
  late TextEditingController _cipseAppId;
  late TextEditingController _cipseAppName;
  late TextEditingController _cipsePassword;
  late TextEditingController _cipseCertPath;
  late TextEditingController _cipseCallbackUrl;
  String _cipseEnv = 'uat';
  late TextEditingController _qrAccountDetails;
  String _qrImageUrl = '';
  bool _initialized = false;

  static const _tabs = [
    Tab(icon: Icon(Icons.account_balance_wallet_rounded, size: 18), text: 'eSewa (ईसेवा)'),
    Tab(icon: Icon(Icons.currency_exchange_rounded, size: 18), text: 'Khalti (खल्ती)'),
    Tab(icon: Icon(Icons.phone_android_rounded, size: 18), text: 'FonePay (फोनपे)'),
    Tab(icon: Icon(Icons.qr_code_scanner_rounded, size: 18), text: 'Moco (मोको)'),
    Tab(icon: Icon(Icons.account_balance_rounded, size: 18), text: 'ConnectIPS (कनेक्ट आइपिएस)'),
    Tab(icon: Icon(Icons.qr_code_2_rounded, size: 18), text: 'Direct Bank & QR (बैंक खाता)'),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _eSewaProductCode = TextEditingController();
    _eSewaSecretKey = TextEditingController();
    _mocoMerchantId = TextEditingController();
    _mocoTerminalId = TextEditingController();
    _mocoOutletId = TextEditingController();
    _mocoSharedKey = TextEditingController();
    _fonepayProfileId = TextEditingController();
    _fonepaySharedSecretKey = TextEditingController();
    _khaltiLiveSecretKey = TextEditingController();
    _cipseMerchantId = TextEditingController();
    _cipseAppId = TextEditingController();
    _cipseAppName = TextEditingController();
    _cipsePassword = TextEditingController();
    _cipseCertPath = TextEditingController();
    _cipseCallbackUrl = TextEditingController();
    _qrAccountDetails = TextEditingController();
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (final c in [
      _eSewaProductCode,
      _eSewaSecretKey,
      _mocoMerchantId,
      _mocoTerminalId,
      _mocoOutletId,
      _mocoSharedKey,
      _fonepayProfileId,
      _fonepaySharedSecretKey,
      _khaltiLiveSecretKey,
      _cipseMerchantId,
      _cipseAppId,
      _cipseAppName,
      _cipsePassword,
      _cipseCertPath,
      _cipseCallbackUrl,
      _qrAccountDetails,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _populateForm(Map<String, dynamic> ps) {
    if (_initialized) return;
    final esewa = _gatewayMap(ps, 'esewa');
    _eSewaProductCode.text = _str(esewa, 'product_code');
    _eSewaSecretKey.text = _str(esewa, 'secret_key');
    final moco = _gatewayMap(ps, 'moco');
    _mocoMerchantId.text = _str(moco, 'merchant_id');
    _mocoTerminalId.text = _str(moco, 'terminal_id');
    _mocoOutletId.text = _str(moco, 'outlet_id');
    _mocoSharedKey.text = _str(moco, 'shared_key');
    final fonepay = _gatewayMap(ps, 'fonepay');
    _fonepayProfileId.text = _str(fonepay, 'profile_id');
    _fonepaySharedSecretKey.text = _str(fonepay, 'shared_secret_key');
    final khalti = _gatewayMap(ps, 'khalti');
    _khaltiLiveSecretKey.text = _str(khalti, 'live_secret_key');
    final cips = _gatewayMap(ps, 'connectips');
    _cipseMerchantId.text = _str(cips, 'merchant_id');
    _cipseAppId.text = _str(cips, 'app_id');
    _cipseAppName.text = _str(cips, 'app_name');
    _cipsePassword.text = _str(cips, 'password');
    _cipseCertPath.text = _str(cips, 'certificate_path');
    _cipseCallbackUrl.text = _str(cips, 'callback_url');
    _cipseEnv = (cips['environment'] as String?) ?? 'uat';
    final qr = _gatewayMap(ps, 'qr_account');
    if (_str(qr, 'details').isNotEmpty) {
      _qrAccountDetails.text = _str(qr, 'details');
    } else {
      final legacy = <String>[];
      if (_str(qr, 'bank_name').isNotEmpty) legacy.add('Bank Name: ${_str(qr, 'bank_name')}');
      if (_str(qr, 'account_name').isNotEmpty) legacy.add('Account Name: ${_str(qr, 'account_name')}');
      if (_str(qr, 'account_number').isNotEmpty) legacy.add('Account Number: ${_str(qr, 'account_number')}');
      if (_str(qr, 'branch').isNotEmpty) legacy.add('Branch: ${_str(qr, 'branch')}');
      _qrAccountDetails.text = legacy.join('\n');
    }
    _qrImageUrl = _str(qr, 'qr_image_url');
    _initialized = true;
  }

  Map<String, dynamic> _buildPayload() => {
        'mode': 'national',
        'esewa': {'product_code': _eSewaProductCode.text.trim(), 'secret_key': _eSewaSecretKey.text.trim()},
        'moco': {
          'merchant_id': _mocoMerchantId.text.trim(),
          'terminal_id': _mocoTerminalId.text.trim(),
          'outlet_id': _mocoOutletId.text.trim(),
          'shared_key': _mocoSharedKey.text.trim()
        },
        'fonepay': {'profile_id': _fonepayProfileId.text.trim(), 'shared_secret_key': _fonepaySharedSecretKey.text.trim()},
        'khalti': {'live_secret_key': _khaltiLiveSecretKey.text.trim()},
        'connectips': {
          'merchant_id': _cipseMerchantId.text.trim(),
          'app_id': _cipseAppId.text.trim(),
          'app_name': _cipseAppName.text.trim(),
          'password': _cipsePassword.text.trim(),
          'certificate_path': _cipseCertPath.text.trim(),
          'callback_url': _cipseCallbackUrl.text.trim(),
          'environment': _cipseEnv
        },
        'qr_account': {'details': _qrAccountDetails.text.trim(), 'qr_image_url': _qrImageUrl},
      };

  Future<void> _submit() async {
    try {
      await ref.read(updateOrgSettingsProvider.notifier).updateSettings({'payment_settings': _buildPayload()});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Row(children: [
            Icon(Icons.check_circle, color: Colors.white),
            SizedBox(width: 12),
            Text('Payment gateway credentials saved successfully!', style: TextStyle(fontWeight: FontWeight.bold))
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
            Expanded(child: Text('Error: $e'))
          ]),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(24),
        ));
      }
    }
  }

  Future<String?> _upload(Uint8List bytes, String name) async {
    try {
      final dio = ref.read(apiClientProvider);
      final resp = await dio.post(ApiConstants.fileUpload,
          data: FormData.fromMap({'file': MultipartFile.fromBytes(bytes, filename: name)}));
      return resp.data['url'] as String?;
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Upload failed. Please try again.')));
      return null;
    }
  }

  Widget _section({required String title, required String subtitle, required IconData icon, required Color brandColor, required List<Widget> children}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
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
      ),
    );
  }

  InputDecoration _dec(String label, {String? hint, Widget? prefix}) => InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: prefix,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      );

  Widget _infoChip(String text, Color brandColor) => Container(
        margin: const EdgeInsets.only(bottom: 18),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: brandColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: brandColor.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline_rounded, size: 18, color: brandColor),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: brandColor, fontWeight: FontWeight.w600))),
          ],
        ),
      );

  Widget _envButton(String value, String label, IconData icon) {
    final selected = _cipseEnv == value;
    return Expanded(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: selected ? (value == 'production' ? Colors.green.shade700 : AppColors.primary) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => _cipseEnv = value),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16, color: selected ? Colors.white : AppColors.textSecondary),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildESewaTab() => ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
        children: [
          _section(
            title: 'eSewa epay V2 Integration',
            subtitle: 'Direct online payment collection via Nepal’s leading digital wallet',
            icon: Icons.account_balance_wallet_rounded,
            brandColor: const Color(0xFF60BB46),
            children: [
              _infoChip('Obtain your Merchant Product Code and Secret Key from merchant.esewa.com.np.', const Color(0xFF60BB46)),
              TextFormField(
                controller: _eSewaProductCode,
                decoration: _dec('Merchant Product Code *', hint: 'e.g. EPAYTEST', prefix: const Icon(Icons.code_outlined)),
              ),
              const SizedBox(height: 16),
              _SecretField(controller: _eSewaSecretKey, label: 'Merchant Secret Key *', hint: 'Your eSewa HMAC-SHA256 secret key'),
            ],
          ),
        ],
      );

  Widget _buildKhaltiTab() => ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
        children: [
          _section(
            title: 'Khalti e-Payment Gateway',
            subtitle: 'Instant digital transactions via Khalti Wallet and Mobile Banking',
            icon: Icons.currency_exchange_rounded,
            brandColor: const Color(0xFF5C2D91),
            children: [
              _infoChip('Copy your Live Secret Key from khalti.com/business. Do not use sandbox keys in production.', const Color(0xFF5C2D91)),
              _SecretField(controller: _khaltiLiveSecretKey, label: 'Khalti Live Secret Key *', hint: 'live_secret_key_...'),
            ],
          ),
        ],
      );

  Widget _buildFonePayTab() => ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
        children: [
          _section(
            title: 'FonePay Direct Network',
            subtitle: 'Dynamic QR and Inter-Bank payment routing across Nepal',
            icon: Icons.phone_android_rounded,
            brandColor: const Color(0xFFC8102E),
            children: [
              _infoChip('Get your Profile ID and Shared Secret Key from fonepay.com/business.', const Color(0xFFC8102E)),
              TextFormField(
                controller: _fonepayProfileId,
                decoration: _dec('Merchant Profile ID *', hint: 'Your FonePay profile ID', prefix: const Icon(Icons.badge_outlined)),
              ),
              const SizedBox(height: 16),
              _SecretField(controller: _fonepaySharedSecretKey, label: 'Shared Secret Key *', hint: 'Your FonePay shared secret key'),
            ],
          ),
        ],
      );

  Widget _buildMocoTab() => ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
        children: [
          _section(
            title: 'Moco Digital Wallet',
            subtitle: 'Credentials issued by your Moco integration partner',
            icon: Icons.qr_code_scanner_rounded,
            brandColor: const Color(0xFF0070BA),
            children: [
              _infoChip('All IDs below are provided by Moco during merchant onboarding.', const Color(0xFF0070BA)),
              TextFormField(controller: _mocoMerchantId, decoration: _dec('Merchant ID *', hint: 'e.g. M000003269', prefix: const Icon(Icons.store_outlined))),
              const SizedBox(height: 16),
              TextFormField(controller: _mocoTerminalId, decoration: _dec('Terminal ID *', hint: 'e.g. T000000039', prefix: const Icon(Icons.point_of_sale_outlined))),
              const SizedBox(height: 16),
              TextFormField(controller: _mocoOutletId, decoration: _dec('Outlet ID *', hint: 'e.g. O000058633', prefix: const Icon(Icons.business_outlined))),
              const SizedBox(height: 16),
              _SecretField(controller: _mocoSharedKey, label: 'Shared Key *', hint: 'Your Moco shared key'),
            ],
          ),
        ],
      );

  Widget _buildConnectIPSTab() => ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
        children: [
          _section(
            title: 'ConnectIPS (NCHL Gateway)',
            subtitle: 'Direct bank account debit gateway operated by Nepal Clearing House',
            icon: Icons.account_balance_rounded,
            brandColor: const Color(0xFF003366),
            children: [
              _infoChip('Requires server IP whitelisted with ConnectIPS. PFX token certificates must be stored on your secure server.', const Color(0xFF003366)),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: TextFormField(controller: _cipseMerchantId, decoration: _dec('Merchant ID *', hint: 'e.g. MERCHANTTEST', prefix: const Icon(Icons.store_outlined)))),
                  const SizedBox(width: 12),
                  Expanded(child: TextFormField(controller: _cipseAppId, decoration: _dec('App ID *', hint: 'e.g. 47', prefix: const Icon(Icons.apps_outlined)))),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(controller: _cipseAppName, decoration: _dec('App Name *', hint: 'e.g. MERCHANTTEST', prefix: const Icon(Icons.label_outlined))),
              const SizedBox(height: 16),
              _SecretField(controller: _cipsePassword, label: 'Password (Basic Auth) *', hint: 'Your ConnectIPS password'),
              const SizedBox(height: 16),
              TextFormField(controller: _cipseCertPath, decoration: _dec('PFX Certificate Path', hint: 'storage/certificates/connectips/{id}/cert.pfx', prefix: const Icon(Icons.description_outlined))),
              const SizedBox(height: 16),
              TextFormField(
                controller: _cipseCallbackUrl,
                keyboardType: TextInputType.url,
                decoration: _dec('Callback URL', hint: 'https://yourdomain.com/payment/callback/', prefix: const Icon(Icons.webhook_outlined)),
              ),
              const SizedBox(height: 20),
              Text('Environment', style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF27272A) : const Color(0xFFF4F4F5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    _envButton('uat', 'UAT Sandbox (Testing)', Icons.bug_report_outlined),
                    _envButton('production', 'Live Production', Icons.verified_rounded),
                  ],
                ),
              ),
            ],
          ),
        ],
      );

  Widget _buildQrAccountTab() => ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
        children: [
          _section(
            title: 'Direct Bank Deposit & Official QR Standee',
            subtitle: 'Manual payment instructions and QR code for bank transfers or cash vouchers',
            icon: Icons.qr_code_2_rounded,
            brandColor: const Color(0xFFD97706),
            children: [
              _infoChip('Members will see these bank account details and QR code when making offline/voucher payments for nomination fees.', const Color(0xFFD97706)),
              TextFormField(
                controller: _qrAccountDetails,
                maxLines: 6,
                decoration: _dec(
                  'Bank Account Details & Payment Instructions',
                  hint: 'e.g.\nBank Name: Nepal Bank Limited\nAccount Name: Organization Central Account\nAccount Number: 01234567890123\nBranch: Putalisadak, Kathmandu\nNotes: Please mention your Member ID and Election Name in the transaction remarks.',
                  prefix: const Icon(Icons.description_outlined),
                ),
              ),
              const SizedBox(height: 20),
              _QrImageTile(
                initialUrl: _qrImageUrl.isEmpty ? null : _qrImageUrl,
                onUpload: _upload,
                onUploaded: (url) => setState(() => _qrImageUrl = url),
              ),
            ],
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final orgAsync = ref.watch(orgProfileProvider);
    final isSaving = ref.watch(updateOrgSettingsProvider).isLoading;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      drawer: const AdminDrawer(),
      appBar: AppBar(
        title: const Text('Payment Gateways & Banking'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16, top: 8, bottom: 8),
            child: LoadingButton(
              onPressed: _submit,
              isLoading: isSaving,
              label: 'Save Gateways',
              icon: Icons.save_rounded,
              fullWidth: false,
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: _tabs,
          indicatorColor: AppColors.primary,
          indicatorWeight: 3,
          labelColor: AppColors.primary,
          unselectedLabelColor: isDark ? Colors.white70 : Colors.grey.shade700,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
      ),
      body: ResponsivePageWrapper(
        child: orgAsync.when(
          loading: () => const ListSkeleton(count: 4),
          error: (err, _) => Center(child: Text('Error: $err')),
          data: (org) {
            _populateForm(org.paymentSettings);
            return TabBarView(
              controller: _tabController,
              children: [
                Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 860), child: _buildESewaTab())),
                Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 860), child: _buildKhaltiTab())),
                Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 860), child: _buildFonePayTab())),
                Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 860), child: _buildMocoTab())),
                Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 860), child: _buildConnectIPSTab())),
                Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 860), child: _buildQrAccountTab())),
              ],
            );
          },
        ),
      ),
    );
  }
}
