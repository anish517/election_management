import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_constants.dart';
import '../../../core/theme/app_theme.dart';

class AuditPortalScreen extends ConsumerStatefulWidget {
  final String electionId;
  final String electionTitle;

  const AuditPortalScreen({
    super.key,
    required this.electionId,
    required this.electionTitle,
  });

  @override
  ConsumerState<AuditPortalScreen> createState() => _AuditPortalScreenState();
}

class _AuditPortalScreenState extends ConsumerState<AuditPortalScreen> {
  // Verification state
  bool _isVerifying = false;
  Map<String, dynamic>? _verifyResult;
  String? _verifyError;

  // Receipt lookup state
  final _receiptController = TextEditingController();
  bool _isLookingUp = false;
  Map<String, dynamic>? _receiptResult;

  // Download state
  bool _isDownloading = false;

  @override
  void dispose() {
    _receiptController.dispose();
    super.dispose();
  }

  Future<void> _verifyHash() async {
    setState(() {
      _isVerifying = true;
      _verifyResult = null;
      _verifyError = null;
    });
    try {
      final dio = ref.read(apiClientProvider);
      final resp = await dio.get(ApiConstants.auditVerifyHash(widget.electionId));
      setState(() => _verifyResult = resp.data);
    } catch (e) {
      setState(() => _verifyError = e.toString());
    } finally {
      setState(() => _isVerifying = false);
    }
  }

  Future<void> _lookupReceipt() async {
    final hash = _receiptController.text.trim();
    if (hash.isEmpty) return;
    setState(() {
      _isLookingUp = true;
      _receiptResult = null;
    });
    try {
      final dio = ref.read(apiClientProvider);
      final resp = await dio.get(ApiConstants.auditReceiptLookup(widget.electionId, hash));
      setState(() => _receiptResult = resp.data);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lookup failed: $e')));
      }
    } finally {
      setState(() => _isLookingUp = false);
    }
  }

  Future<void> _downloadAuditPackage() async {
    setState(() => _isDownloading = true);
    try {
      final token = await JwtInterceptor.getAccessToken();
      final url = Uri.parse(
        '${ApiConstants.baseUrl}${ApiConstants.auditExport(widget.electionId)}?token=$token',
      );
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open download link.')),
          );
        }
      }
    } finally {
      setState(() => _isDownloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Audit Portal', style: TextStyle(fontSize: 16)),
            Text(
              widget.electionTitle,
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoBanner(),
            const SizedBox(height: 20),
            _buildVerifySection(),
            const SizedBox(height: 20),
            _buildReceiptSection(),
            const SizedBox(height: 20),
            _buildDownloadSection(),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Info Banner
  // ---------------------------------------------------------------------------
  Widget _buildInfoBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primaryDark, AppColors.primary.withValues(alpha: 0.7)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.verified_user_rounded, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              const Text(
                'Election Integrity Verification',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'This portal allows anyone to independently verify that votes were counted correctly and that no data was tampered with after voting closed.',
            style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Section 1: Live Hash Verification
  // ---------------------------------------------------------------------------
  Widget _buildVerifySection() {
    return _buildCard(
      icon: Icons.security_rounded,
      iconColor: AppColors.primaryLight,
      title: 'Live Integrity Check',
      subtitle: 'Recompute and verify cryptographic hashes in real time',
      child: Column(
        children: [
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isVerifying ? null : _verifyHash,
              icon: _isVerifying
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.refresh_rounded),
              label: Text(_isVerifying ? 'Verifying...' : 'Run Verification Now'),
            ),
          ),
          if (_verifyError != null) ...[
            const SizedBox(height: 12),
            _buildResultBox(isSuccess: false, message: 'Error: $_verifyError'),
          ],
          if (_verifyResult != null) ...[
            const SizedBox(height: 16),
            _buildVerifyResultCard(_verifyResult!),
          ],
        ],
      ),
    );
  }

  Widget _buildVerifyResultCard(Map<String, dynamic> r) {
    final isConsistent = r['counts_are_consistent'] == true;
    final totalVoted = r['total_ballots_cast'] ?? 0;
    final totalRecords = r['total_vote_records_in_db'] ?? 0;
    final eligible = r['total_eligible_voters'] ?? 0;
    final turnout = eligible > 0 ? (totalVoted / eligible * 100).toStringAsFixed(1) : '0.0';

    return Column(
      children: [
        _buildResultBox(
          isSuccess: isConsistent,
          message: isConsistent
              ? '✅ VERIFIED — Vote counts are consistent. No discrepancies detected.'
              : '❌ MISMATCH — Vote record counts do not match participation records!',
        ),
        const SizedBox(height: 12),
        // Stats grid
        Row(
          children: [
            Expanded(child: _buildStatTile('Eligible', '$eligible', AppColors.textSecondary)),
            const SizedBox(width: 8),
            Expanded(child: _buildStatTile('Voted', '$totalVoted', AppColors.success)),
            const SizedBox(width: 8),
            Expanded(child: _buildStatTile('Turnout', '$turnout%', AppColors.accent)),
          ],
        ),
        const SizedBox(height: 12),
        // Live votes hash
        _buildHashRow('Live Votes Hash', r['live_votes_hash'] ?? '—'),
        const SizedBox(height: 8),
        _buildHashRow('Ballot Snapshot Hash', r['ballot_snapshot_hash'] ?? '(not generated)'),
      ],
    );
  }

  Widget _buildStatTile(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
        ],
      ),
    );
  }

  Widget _buildHashRow(String label, String hash) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.surfaceVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: hash));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Hash copied!'), duration: Duration(seconds: 1)),
                  );
                },
                child: const Icon(Icons.copy_rounded, size: 14, color: AppColors.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            hash,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: AppColors.primaryLight,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Section 2: Receipt Lookup
  // ---------------------------------------------------------------------------
  Widget _buildReceiptSection() {
    return _buildCard(
      icon: Icons.receipt_long_rounded,
      iconColor: AppColors.accent,
      title: 'Verify Your Vote',
      subtitle: 'Enter your receipt hash to confirm your ballot was counted',
      child: Column(
        children: [
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _receiptController,
                  decoration: const InputDecoration(
                    hintText: 'Paste your 64-character receipt hash here...',
                    prefixIcon: Icon(Icons.key_rounded, size: 18),
                  ),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                  maxLines: 2,
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: _isLookingUp ? null : _lookupReceipt,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  backgroundColor: AppColors.accent,
                ),
                child: _isLookingUp
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.search_rounded),
              ),
            ],
          ),
          if (_receiptResult != null) ...[
            const SizedBox(height: 12),
            _buildResultBox(
              isSuccess: _receiptResult!['found'] == true,
              message: _receiptResult!['message'] ?? '',
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'Your receipt hash was shown on screen after you voted and also on your vote confirmation page.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 11),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Section 3: Download Audit Package
  // ---------------------------------------------------------------------------
  Widget _buildDownloadSection() {
    return _buildCard(
      icon: Icons.download_rounded,
      iconColor: AppColors.success,
      title: 'Download Audit Package',
      subtitle: 'Full cryptographic audit trail as a JSON file',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          _buildInfoItem('📋', 'All anonymized ballot receipt hashes'),
          _buildInfoItem('🔐', 'Election cryptographic hash (ballot snapshot)'),
          _buildInfoItem('📜', 'Complete state transition history'),
          _buildInfoItem('🔍', 'Full audit log of every system action'),
          _buildInfoItem('🚫', 'Does NOT contain voter identities or vote choices'),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isDownloading ? null : _downloadAuditPackage,
              icon: _isDownloading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.download_rounded),
              label: Text(_isDownloading ? 'Preparing...' : 'Download audit_package.json'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(String icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: AppColors.textSecondary, fontSize: 12))),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Shared Widgets
  // ---------------------------------------------------------------------------
  Widget _buildCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    Text(subtitle, style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
          child,
        ],
      ),
    );
  }

  Widget _buildResultBox({required bool isSuccess, required String message}) {
    final color = isSuccess ? AppColors.success : AppColors.error;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        message,
        style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );
  }
}
