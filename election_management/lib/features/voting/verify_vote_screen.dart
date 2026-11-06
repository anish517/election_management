import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_constants.dart';
import '../../core/utils/error_helper.dart';

class VerifyVoteScreen extends ConsumerStatefulWidget {
  final String? initialSignature;

  const VerifyVoteScreen({super.key, this.initialSignature});

  @override
  ConsumerState<VerifyVoteScreen> createState() => _VerifyVoteScreenState();
}

class _VerifyVoteScreenState extends ConsumerState<VerifyVoteScreen> {
  final TextEditingController _signatureController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  Map<String, dynamic>? _auditData;

  @override
  void initState() {
    super.initState();
    if (widget.initialSignature != null && widget.initialSignature!.trim().isNotEmpty) {
      _signatureController.text = widget.initialSignature!.trim();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _verifySignature();
      });
    }
  }

  @override
  void dispose() {
    _signatureController.dispose();
    super.dispose();
  }

  Future<void> _verifySignature() async {
    final sig = _signatureController.text.trim();
    if (sig.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter or paste your cryptographic ballot signature.';
        _auditData = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _auditData = null;
    });

    try {
      final dio = ref.read(apiClientProvider);
      final response = await dio.get(ApiConstants.verifyVoteReceipt(sig));
      if (mounted) {
        setState(() {
          _auditData = response.data is Map<String, dynamic> ? response.data : null;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = extractApiErrorMessage(
            e,
            fallback: 'Invalid or unregistered ballot signature. Please check the code in your email confirmation.',
          );
          _isLoading = false;
        });
      }
    }
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).primaryColor;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Ballot Ledger Audit & Verification'),
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        elevation: 0.5,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header Banner
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isDark
                          ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
                          : [Colors.white, const Color(0xFFEFF6FF)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: primaryColor.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.verified_user_rounded, size: 36, color: primaryColor),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Track & Verify Your Ballot Record',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'मतदान रेकर्ड प्रमाणीकरण — Enter the cryptographic receipt signature sent to your confirmation email to verify your vote was sealed in the immutable election roll.',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                          height: 1.45,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Signature Input Card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Cryptographic Ballot Signature (Receipt Hash)',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _signatureController,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                          letterSpacing: 0.5,
                        ),
                        maxLines: 2,
                        minLines: 1,
                        decoration: InputDecoration(
                          hintText: 'e.g. 8f4b2a9e3c7d10294e5b88c... or paste full hash',
                          hintStyle: TextStyle(
                            fontFamily: 'sans-serif',
                            fontSize: 13,
                            color: isDark ? Colors.white30 : Colors.black26,
                          ),
                          filled: true,
                          fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                          prefixIcon: const Icon(Icons.fingerprint_rounded, size: 22),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.paste_rounded, size: 20),
                            tooltip: 'Paste from clipboard',
                            onPressed: () async {
                              final clipData = await Clipboard.getData('text/plain');
                              if (clipData?.text != null) {
                                _signatureController.text = clipData!.text!.trim();
                              }
                            },
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        ),
                        onSubmitted: (_) => _verifySignature(),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: _isLoading ? null : _verifySignature,
                          icon: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.search_rounded, size: 20),
                          label: Text(
                            _isLoading ? 'Verifying in Election Ledger...' : 'Audit Ballot Record',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF10B981),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Error Banner
                if (_errorMessage != null)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.35)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.error_outline_rounded, color: Color(0xFFEF4444), size: 24),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                              color: Color(0xFFDC2626),
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Verified Audit Certificate Card
                if (_auditData != null) ...[
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF10B981).withValues(alpha: 0.08),
                          blurRadius: 20,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Verification Status Header
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: const BoxDecoration(
                                color: Color(0xFF10B981),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.check_rounded, color: Colors.white, size: 24),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'BALLOT SEALED & VERIFIED',
                                    style: TextStyle(
                                      color: Color(0xFF10B981),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _auditData!['election_title'] ?? 'Election Audit Ledger',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                                    ),
                                  ),
                                  if ((_auditData!['organization_name'] ?? '').isNotEmpty)
                                    Text(
                                      _auditData!['organization_name'],
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: isDark ? Colors.white70 : Colors.black54,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 20),
                        const Divider(),
                        const SizedBox(height: 14),

                        // Telemetry Grid
                        _buildAuditRow(
                          icon: Icons.access_time_rounded,
                          label: 'Timestamp (समय):',
                          value: _auditData!['voted_at_formatted'] ?? _auditData!['voted_at'] ?? 'Recorded',
                          isDark: isDark,
                        ),
                        const SizedBox(height: 12),
                        _buildAuditRow(
                          icon: Icons.devices_rounded,
                          label: 'Device & Platform (उपकरण):',
                          value: _auditData!['device_type'] ?? 'Electronic Voting Device',
                          isDark: isDark,
                        ),
                        const SizedBox(height: 12),
                        _buildAuditRow(
                          icon: Icons.location_on_rounded,
                          label: 'Location & IP (स्थान):',
                          value: '${_auditData!['location'] ?? 'Nepal'} (IP: ${_auditData!['ip_masked'] ?? 'Confidential'})',
                          isDark: isDark,
                        ),
                        const SizedBox(height: 12),
                        _buildAuditRow(
                          icon: Icons.how_to_vote_rounded,
                          label: 'Voting Channel (माध्यम):',
                          value: _auditData!['verification_channel_label'] ?? 'Digital Ballot',
                          isDark: isDark,
                        ),
                        const SizedBox(height: 12),
                        _buildAuditRow(
                          icon: Icons.lock_outline_rounded,
                          label: 'Cryptographic Status:',
                          value: '${_auditData!['cryptographic_status'] ?? 'SEALED'} (${_auditData!['hash_algorithm'] ?? 'SHA-256'})',
                          valueColor: const Color(0xFF10B981),
                          isDark: isDark,
                        ),

                        const SizedBox(height: 20),

                        // Signature Display Box
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'OFFICIAL BALLOT SIGNATURE',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                  InkWell(
                                    onTap: () => _copyToClipboard(_auditData!['signature'] ?? '', 'Signature'),
                                    child: const Row(
                                      children: [
                                        Icon(Icons.copy_rounded, size: 14, color: Color(0xFF3B82F6)),
                                        SizedBox(width: 4),
                                        Text(
                                          'Copy',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF3B82F6),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              SelectableText(
                                _auditData!['signature'] ?? '',
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Anonymity Guarantee Notice
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF3B82F6).withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.25)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.shield_rounded, color: Color(0xFF3B82F6), size: 22),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Secret Ballot Anonymity Guarantee (गोप्य मतदान सुनिश्चितता): This cryptographic certificate proves that your ballot has been recorded and counted in the official ledger. Candidate choices are never displayed to preserve complete voter confidentiality.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 1.45,
                                    color: isDark ? const Color(0xFF93C5FD) : const Color(0xFF1D4ED8),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAuditRow({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
    required bool isDark,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: const Color(0xFF64748B)),
        const SizedBox(width: 10),
        SizedBox(
          width: 190,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            ),
          ),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: valueColor ?? (isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A)),
            ),
          ),
        ),
      ],
    );
  }
}

