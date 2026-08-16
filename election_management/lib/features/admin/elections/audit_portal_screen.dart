import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/error_helper.dart';

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

class _AuditPortalScreenState extends ConsumerState<AuditPortalScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Verification state
  bool _isVerifying = false;
  Map<String, dynamic>? _verifyResult;
  String? _verifyError;

  // Receipt lookup state
  final _receiptController = TextEditingController();
  bool _isLookingUp = false;
  Map<String, dynamic>? _receiptResult;

  // Audit logs state
  bool _isLoadingLogs = false;
  List<dynamic> _auditLogs = [];
  String? _logsError;

  // Download state
  bool _isDownloading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _verifyHash();
    _loadAuditLogs();
  }

  @override
  void dispose() {
    _tabController.dispose();
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
      setState(() => _verifyError = extractApiErrorMessage(e));
    } finally {
      setState(() => _isVerifying = false);
    }
  }

  Future<void> _loadAuditLogs() async {
    setState(() {
      _isLoadingLogs = true;
      _logsError = null;
    });
    try {
      final dio = ref.read(apiClientProvider);
      final resp = await dio.get(ApiConstants.auditLogs(widget.electionId));
      final data = resp.data;
      if (data is Map && data.containsKey('results')) {
        setState(() => _auditLogs = data['results'] as List<dynamic>);
      } else if (data is List) {
        setState(() => _auditLogs = data);
      }
    } catch (e) {
      setState(() => _logsError = extractApiErrorMessage(e));
    } finally {
      setState(() => _isLoadingLogs = false);
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
        final err = extractApiErrorMessage(e);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err), backgroundColor: Colors.red));
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.background : const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.verified_user_rounded, color: Colors.blueAccent, size: 20),
                SizedBox(width: 8),
                Text('Auditor Verification Portal (लेखापरीक्षक पोर्टल)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            Text(
              widget.electionTitle,
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textMuted,
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(icon: Icon(Icons.security_rounded, size: 18), text: 'Cryptographic Hashes'),
            Tab(icon: Icon(Icons.receipt_long_rounded, size: 18), text: 'Receipt Validator'),
            Tab(icon: Icon(Icons.history_edu_rounded, size: 18), text: 'System Audit Trail'),
            Tab(icon: Icon(Icons.file_download_outlined, size: 18), text: 'Compliance Export'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildHashTab(),
          _buildReceiptTab(),
          _buildAuditTrailTab(),
          _buildExportTab(),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 1: Cryptographic Hashes
  // ---------------------------------------------------------------------------
  Widget _buildHashTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildBanner(
            title: 'Election Cryptographic Integrity Check',
            description: 'Mathematically verifies that stored ballot records have not been altered, deleted, or inserted out-of-order since voting was initialized.',
            icon: Icons.shield_rounded,
          ),
          const SizedBox(height: 20),
          _buildCard(
            icon: Icons.refresh_rounded,
            iconColor: AppColors.primaryLight,
            title: 'Live Hash Consistency Check',
            subtitle: 'Recomputes SHA-256 ledger checksum in real time',
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
                    label: Text(_isVerifying ? 'Verifying...' : 'Re-Run Verification'),
                  ),
                ),
                if (_verifyError != null) ...[
                  const SizedBox(height: 12),
                  _buildResultBox(isSuccess: false, message: _verifyError!),
                ],
                if (_verifyResult != null) ...[
                  const SizedBox(height: 16),
                  _buildVerifyResultCard(_verifyResult!),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerifyResultCard(Map<String, dynamic> r) {
    final isConsistent = r['counts_are_consistent'] == true;
    final totalVoted = r['total_ballots_cast'] ?? 0;
    final totalRecords = r['total_vote_records_in_db'] ?? 0;
    final eligible = r['total_eligible_voters'] ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildResultBox(
          isSuccess: isConsistent,
          message: isConsistent
              ? '✅ Cryptographic integrity verified. Ballot count matches voter participation exactly.'
              : '⚠️ Discrepancy detected: Cast ballot count does not match database vote records.',
        ),
        const SizedBox(height: 16),
        _buildStatGrid([
          _StatItem('Eligible Voters', eligible.toString(), Icons.people_alt_outlined),
          _StatItem('Ballots Cast', totalVoted.toString(), Icons.how_to_vote_outlined),
          _StatItem('Database Records', totalRecords.toString(), Icons.storage_rounded),
          _StatItem('Ledger Status', isConsistent ? 'MATCH' : 'MISMATCH', Icons.check_circle_outline,
              highlightColor: isConsistent ? Colors.green : Colors.red),
        ]),
        const SizedBox(height: 16),
        _buildHashField('Ballot Snapshot Hash (Pre-Voting Lock)', r['ballot_snapshot_hash'] ?? 'Not generated'),
        const SizedBox(height: 10),
        _buildHashField('Live Votes Merkle/Ledger Hash', r['live_votes_hash'] ?? 'No votes cast yet'),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 2: Receipt Validator
  // ---------------------------------------------------------------------------
  Widget _buildReceiptTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildBanner(
            title: 'Individual Ballot Receipt Lookup',
            description: 'Voters and auditors can check if a 64-character SHA-256 cryptographic receipt exists in the official election database without exposing secret vote selections.',
            icon: Icons.qr_code_2_rounded,
          ),
          const SizedBox(height: 20),
          _buildCard(
            icon: Icons.search_rounded,
            iconColor: AppColors.primary,
            title: 'Verify Receipt Hash',
            subtitle: 'Paste any 64-character receipt hash below',
            child: Column(
              children: [
                const SizedBox(height: 16),
                TextField(
                  controller: _receiptController,
                  decoration: InputDecoration(
                    labelText: '64-character Receipt Hash',
                    hintText: 'e.g. 3a7f8b9c1d2e4f5a...',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    prefixIcon: const Icon(Icons.fingerprint_rounded),
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isLookingUp ? null : _lookupReceipt,
                    icon: _isLookingUp
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.search_rounded),
                    label: Text(_isLookingUp ? 'Searching...' : 'Check Receipt'),
                  ),
                ),
                if (_receiptResult != null) ...[
                  const SizedBox(height: 16),
                  _buildResultBox(
                    isSuccess: _receiptResult!['found'] == true,
                    message: _receiptResult!['message']?.toString() ?? '',
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 3: System Audit Trail
  // ---------------------------------------------------------------------------
  Widget _buildAuditTrailTab() {
    if (_isLoadingLogs) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_logsError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.red, size: 40),
            const SizedBox(height: 12),
            Text(_logsError!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _loadAuditLogs, child: const Text('Retry')),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAuditLogs,
      child: ListView.separated(
        padding: const EdgeInsets.all(20),
        itemCount: _auditLogs.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (index == 0) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildBanner(
                  title: 'Forensic System Audit Trail',
                  description: 'Live immutable record of administrative actions, voter roll updates, candidate qualifications, and system milestones.',
                  icon: Icons.history_edu_rounded,
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Recorded Audit Events (${_auditLogs.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    IconButton(icon: const Icon(Icons.refresh), onPressed: _loadAuditLogs, tooltip: 'Refresh Logs'),
                  ],
                ),
                const SizedBox(height: 10),
                if (_auditLogs.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(32),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark ? AppColors.surface : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: const Column(
                      children: [
                        Icon(Icons.history_toggle_off_rounded, size: 42, color: AppColors.textMuted),
                        SizedBox(height: 12),
                        Text('No Audit Events Recorded Yet', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        SizedBox(height: 4),
                        Text('System state changes, officer rulings, candidate approvals, and voting activity will appear here in real time.',
                            textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                      ],
                    ),
                  ),
              ],
            );
          }

          final log = _auditLogs[index - 1] as Map<String, dynamic>;
          final action = log['action']?.toString() ?? 'unknown_action';
          final actor = log['actor_email']?.toString() ?? 'system';
          final ip = log['ip_address']?.toString() ?? '-';
          final timestamp = log['created_at']?.toString() ?? '';
          final metadata = log['metadata'];

          return Card(
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          action.replaceAll('.', ' · ').toUpperCase(),
                          style: const TextStyle(color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const Spacer(),
                      Text(timestamp.replaceFirst('T', ' ').substring(0, 19), style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Actor: $actor', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  Text('IP Address: $ip', style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                  if (metadata != null && metadata.toString() != '{}') ...[
                    const SizedBox(height: 6),
                    Text('Details: $metadata', style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 4: Compliance Export
  // ---------------------------------------------------------------------------
  Widget _buildExportTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildBanner(
            title: 'Audit Package Export & Regulatory Filing',
            description: 'Download the complete cryptographically signed audit manifest containing anonymized hashes, participation stats, and state transition histories for compliance archival.',
            icon: Icons.archive_rounded,
          ),
          const SizedBox(height: 20),
          _buildCard(
            icon: Icons.file_download_outlined,
            iconColor: Colors.green,
            title: 'Export Official Audit Package',
            subtitle: 'Generates signed JSON file with embedded SHA-256 package hash',
            child: Column(
              children: [
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isDownloading ? null : _downloadAuditPackage,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                    icon: _isDownloading
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.download_rounded),
                    label: Text(_isDownloading ? 'Generating Package...' : 'Download Audit Package (.json)'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // UI Helpers
  // ---------------------------------------------------------------------------
  Widget _buildBanner({required String title, required String description, required IconData icon}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primaryDark, AppColors.primary.withValues(alpha: 0.7)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(description, style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surface : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? AppColors.surfaceVariant : Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    Text(subtitle, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (isSuccess ? Colors.green : Colors.red).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: (isSuccess ? Colors.green : Colors.red).withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(isSuccess ? Icons.check_circle_rounded : Icons.error_rounded,
              color: isSuccess ? Colors.green : Colors.red, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: isSuccess ? Colors.green.shade800 : Colors.red.shade800,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatGrid(List<_StatItem> stats) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 2.3,
      children: stats.map((s) => _buildStatTile(s)).toList(),
    );
  }

  Widget _buildStatTile(_StatItem s) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(s.icon, color: s.highlightColor ?? AppColors.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(s.label, style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
                Text(
                  s.value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: s.highlightColor ?? AppColors.primary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHashField(String label, String hash) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.grey.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  hash,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy_rounded, size: 16),
                tooltip: 'Copy Hash',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: hash));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Hash copied to clipboard')));
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatItem {
  final String label;
  final String value;
  final IconData icon;
  final Color? highlightColor;

  _StatItem(this.label, this.value, this.icon, {this.highlightColor});
}
