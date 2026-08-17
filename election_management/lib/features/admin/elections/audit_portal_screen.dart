import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:nepali_date_picker/nepali_date_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:go_router/go_router.dart';
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
  String _logSearchQuery = '';
  String _logCategoryFilter = 'all';

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
      if (mounted) setState(() => _isVerifying = false);
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
      if (mounted) setState(() => _isLoadingLogs = false);
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(err),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLookingUp = false);
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
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.background : const Color(0xFFF8FAFC),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          tooltip: 'Back',
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              context.go('/dashboard');
            }
          },
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.verified_user_rounded, color: AppColors.primaryLight, size: 20),
                SizedBox(width: 8),
                Text('Auditor Verification Portal', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            Text(
              '${widget.electionTitle} • लेखापरीक्षक प्रमाणीकरण केन्द्र',
              style: TextStyle(fontSize: 11.5, color: isDark ? Colors.white70 : AppColors.textMuted),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: AppColors.primary,
          unselectedLabelColor: isDark ? Colors.white60 : Colors.grey.shade600,
          indicatorColor: AppColors.primary,
          indicatorWeight: 3,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
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
          _buildHashTab(isDark),
          _buildReceiptTab(isDark),
          _buildAuditTrailTab(isDark),
          _buildExportTab(isDark),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 1: Cryptographic Hashes
  // ---------------------------------------------------------------------------
  Widget _buildHashTab(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildBanner(
                title: 'Election Cryptographic Integrity & Ledger Audit',
                description: 'Mathematically verifies that all cast ballot records conform to SHA-256 Merkle chain consistency and have not been altered, omitted, or reordered.',
                icon: Icons.shield_rounded,
                isDark: isDark,
              ),
              const SizedBox(height: 20),
              _buildCard(
                icon: Icons.refresh_rounded,
                iconColor: AppColors.primaryLight,
                title: 'Live Hash Consistency Check (अखण्डता प्रमाणीकरण)',
                subtitle: 'Recomputes SHA-256 database ledger checksum in real time',
                isDark: isDark,
                child: Column(
                  children: [
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _isVerifying ? null : _verifyHash,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF4F46E5),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: _isVerifying
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.refresh_rounded),
                        label: Text(_isVerifying ? 'Verifying Hashes...' : 'Re-Run Cryptographic Verification'),
                      ),
                    ),
                    if (_verifyError != null) ...[
                      const SizedBox(height: 14),
                      _buildResultBox(isSuccess: false, message: _verifyError!),
                    ],
                    if (_verifyResult != null) ...[
                      const SizedBox(height: 18),
                      _buildVerifyResultCard(_verifyResult!, isDark),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVerifyResultCard(Map<String, dynamic> r, bool isDark) {
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
              ? 'Cryptographic integrity verified. Ballot count matches voter participation telemetry exactly.'
              : 'Discrepancy detected: Cast ballot count does not match database vote records.',
        ),
        const SizedBox(height: 18),
        _buildStatGrid([
          _StatItem('Eligible Voters', eligible.toString(), Icons.people_alt_outlined),
          _StatItem('Ballots Cast', totalVoted.toString(), Icons.how_to_vote_outlined),
          _StatItem('Database Records', totalRecords.toString(), Icons.storage_rounded),
          _StatItem('Ledger Status', isConsistent ? 'MATCH' : 'MISMATCH', Icons.check_circle_outline,
              highlightColor: isConsistent ? Colors.green : Colors.red),
        ], isDark),
        const SizedBox(height: 20),
        _buildHashField('Ballot Snapshot Hash (Pre-Voting Lock)', r['ballot_snapshot_hash'] ?? 'Not generated', isDark),
        const SizedBox(height: 12),
        _buildHashField('Live Votes Merkle/Ledger Hash', r['live_votes_hash'] ?? 'No votes cast yet', isDark),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 2: Receipt Validator
  // ---------------------------------------------------------------------------
  Widget _buildReceiptTab(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildBanner(
                title: 'Individual Ballot Receipt Lookup',
                description: 'Voters and independent auditors can check if a 64-character SHA-256 cryptographic receipt exists in the official database without exposing secret vote selections.',
                icon: Icons.qr_code_2_rounded,
                isDark: isDark,
              ),
              const SizedBox(height: 20),
              _buildCard(
                icon: Icons.search_rounded,
                iconColor: AppColors.primary,
                title: 'Verify Receipt Hash (भौचर जाँच)',
                subtitle: 'Paste any 64-character receipt hash below to confirm inclusion',
                isDark: isDark,
                child: Column(
                  children: [
                    const SizedBox(height: 16),
                    TextField(
                      controller: _receiptController,
                      decoration: InputDecoration(
                        labelText: '64-character Receipt Hash',
                        hintText: 'e.g. 3a7f8b9c1d2e4f5a6b7c8d9e0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        prefixIcon: const Icon(Icons.fingerprint_rounded),
                        filled: true,
                        fillColor: isDark ? AppColors.surfaceVariant : const Color(0xFFF9FAFB),
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _isLookingUp ? null : _lookupReceipt,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF4F46E5),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: _isLookingUp
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.search_rounded),
                        label: Text(_isLookingUp ? 'Verifying Receipt in Ledger...' : 'Check Receipt in Blockchain Roll'),
                      ),
                    ),
                    if (_receiptResult != null) ...[
                      const SizedBox(height: 18),
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
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 3: System Audit Trail
  // ---------------------------------------------------------------------------
  Widget _buildAuditTrailTab(bool isDark) {
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

    // Filter audit logs
    final filteredLogs = _auditLogs.where((item) {
      final log = item as Map<String, dynamic>;
      final action = (log['action'] ?? '').toString().toLowerCase();
      final actor = (log['actor_email'] ?? '').toString().toLowerCase();
      final ip = (log['ip_address'] ?? '').toString().toLowerCase();

      if (_logCategoryFilter != 'all') {
        if (!action.contains(_logCategoryFilter)) return false;
      }

      if (_logSearchQuery.isNotEmpty) {
        final q = _logSearchQuery.toLowerCase();
        return action.contains(q) || actor.contains(q) || ip.contains(q);
      }
      return true;
    }).toList();

    return RefreshIndicator(
      onRefresh: _loadAuditLogs,
      child: ListView.separated(
        padding: const EdgeInsets.all(24),
        itemCount: filteredLogs.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (index == 0) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildBanner(
                  title: 'Forensic System Audit Trail (प्रणाली लग)',
                  description: 'Live immutable record of administrative actions, voter roll changes, candidate qualifications, scrutiny decisions, and system milestones.',
                  icon: Icons.history_edu_rounded,
                  isDark: isDark,
                ),
                const SizedBox(height: 18),

                // Search & Category Filter Toolbar
                Material(
                  color: isDark ? AppColors.surfaceVariant.withValues(alpha: 0.3) : Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade200),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                decoration: InputDecoration(
                                  hintText: 'Search audit logs by action, actor email, or IP address...',
                                  hintStyle: const TextStyle(fontSize: 13),
                                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                                  isDense: true,
                                  filled: true,
                                  fillColor: isDark ? AppColors.surfaceVariant : const Color(0xFFF9FAFB),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                onChanged: (v) => setState(() => _logSearchQuery = v),
                              ),
                            ),
                            const SizedBox(width: 10),
                            IconButton(
                              icon: const Icon(Icons.refresh_rounded),
                              tooltip: 'Refresh Logs',
                              onPressed: _loadAuditLogs,
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              ChoiceChip(
                                label: Text('All Events (${_auditLogs.length})', style: const TextStyle(fontSize: 12)),
                                selected: _logCategoryFilter == 'all',
                                onSelected: (val) => setState(() => _logCategoryFilter = 'all'),
                              ),
                              const SizedBox(width: 8),
                              ChoiceChip(
                                label: const Text('Voter Roll', style: TextStyle(fontSize: 12)),
                                selected: _logCategoryFilter == 'voter',
                                onSelected: (val) => setState(() => _logCategoryFilter = 'voter'),
                              ),
                              const SizedBox(width: 8),
                              ChoiceChip(
                                label: const Text('Candidates', style: TextStyle(fontSize: 12)),
                                selected: _logCategoryFilter == 'candidate',
                                onSelected: (val) => setState(() => _logCategoryFilter = 'candidate'),
                              ),
                              const SizedBox(width: 8),
                              ChoiceChip(
                                label: const Text('Ballot & Voting', style: TextStyle(fontSize: 12)),
                                selected: _logCategoryFilter == 'vote',
                                onSelected: (val) => setState(() => _logCategoryFilter = 'vote'),
                              ),
                              const SizedBox(width: 8),
                              ChoiceChip(
                                label: const Text('Admin / System', style: TextStyle(fontSize: 12)),
                                selected: _logCategoryFilter == 'election',
                                onSelected: (val) => setState(() => _logCategoryFilter = 'election'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (filteredLogs.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(36),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.surface : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade200),
                    ),
                    child: const Column(
                      children: [
                        Icon(Icons.history_toggle_off_rounded, size: 44, color: AppColors.textMuted),
                        SizedBox(height: 12),
                        Text('No Matching Audit Events', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        SizedBox(height: 4),
                        Text('System state changes and officer actions will appear here.',
                            textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                      ],
                    ),
                  ),
              ],
            );
          }

          final log = filteredLogs[index - 1] as Map<String, dynamic>;
          final action = log['action']?.toString() ?? 'unknown_action';
          final actor = log['actor_email']?.toString() ?? 'system';
          final ip = log['ip_address']?.toString() ?? '-';
          final timestamp = log['created_at']?.toString() ?? '';
          final metadata = log['metadata'];

          return Card(
            elevation: 0,
            color: isDark ? AppColors.surface : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: isDark ? AppColors.surfaceVariant : Colors.grey.shade200),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          action.replaceAll('.', ' · ').toUpperCase(),
                          style: const TextStyle(color: AppColors.primaryLight, fontSize: 10.5, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _formatLogTime(timestamp),
                        style: TextStyle(color: isDark ? Colors.white60 : AppColors.textMuted, fontSize: 11.5, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(Icons.person_outline_rounded, size: 14, color: isDark ? Colors.white60 : Colors.grey.shade600),
                      const SizedBox(width: 6),
                      Text('Actor: $actor', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(Icons.location_on_outlined, size: 14, color: isDark ? Colors.white60 : Colors.grey.shade600),
                      const SizedBox(width: 6),
                      Text('IP Address: $ip', style: TextStyle(color: isDark ? Colors.white54 : AppColors.textMuted, fontSize: 11.5)),
                    ],
                  ),
                  if (metadata != null && metadata.toString() != '{}') ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text('Payload: $metadata', style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _formatLogTime(String iso) {
    if (iso.isEmpty) return '-';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final nepali = dt.toNepaliDateTime();
      final timeStr = DateFormat('hh:mm:ss a').format(dt);
      final nepaliDateStr = NepaliDateFormat('MMM d, yyyy').format(nepali);
      return '$nepaliDateStr • $timeStr (BS)';
    } catch (_) {
      return iso.replaceFirst('T', ' ').substring(0, iso.length > 19 ? 19 : iso.length);
    }
  }

  // ---------------------------------------------------------------------------
  // Tab 4: Compliance Export
  // ---------------------------------------------------------------------------
  Widget _buildExportTab(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildBanner(
                title: 'Audit Package Export & Regulatory Filing',
                description: 'Download the complete cryptographically signed audit manifest containing anonymized hashes, participation stats, and state transition histories for compliance archival.',
                icon: Icons.archive_rounded,
                isDark: isDark,
              ),
              const SizedBox(height: 20),
              _buildCard(
                icon: Icons.file_download_outlined,
                iconColor: Colors.green,
                title: 'Export Official Regulatory Audit Package (अडिट प्याकेज डाउनलोड)',
                subtitle: 'Generates cryptographically signed JSON manifest with embedded SHA-256 package hash',
                isDark: isDark,
                child: Column(
                  children: [
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _isDownloading ? null : _downloadAuditPackage,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: _isDownloading
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.download_rounded),
                        label: Text(_isDownloading ? 'Generating Audit Package...' : 'Download Signed Audit Package (.json)'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // UI Helpers
  // ---------------------------------------------------------------------------
  Widget _buildBanner({required String title, required String description, required IconData icon, required bool isDark}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF1E1B4B), const Color(0xFF312E81)]
              : [const Color(0xFF4338CA), const Color(0xFF6366F1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4338CA).withValues(alpha: 0.25),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(description, style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12.5, height: 1.4)),
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
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surface : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isDark ? AppColors.surfaceVariant : Colors.grey.shade200),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
        ],
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
                    Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5)),
                    Text(subtitle, style: TextStyle(fontSize: 11.5, color: isDark ? Colors.white60 : AppColors.textMuted)),
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: (isSuccess ? Colors.green : Colors.red).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: (isSuccess ? Colors.green : Colors.red).withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(isSuccess ? Icons.check_circle_rounded : Icons.error_rounded,
              color: isSuccess ? Colors.green : Colors.red, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: isSuccess ? Colors.green.shade800 : Colors.red.shade800,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatGrid(List<_StatItem> stats, bool isDark) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 2.5,
      children: stats.map((s) => _buildStatTile(s, isDark)).toList(),
    );
  }

  Widget _buildStatTile(_StatItem s, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceVariant.withValues(alpha: 0.3) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(s.icon, color: s.highlightColor ?? AppColors.primaryLight, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(s.label, style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : AppColors.textMuted)),
                Text(
                  s.value,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: s.highlightColor ?? (isDark ? Colors.white : Colors.black87),
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

  Widget _buildHashField(String label, String hash, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: isDark ? Colors.white70 : AppColors.textMuted)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade300),
          ),
          child: Row(
            children: [
              Expanded(
                child: SelectableText(
                  hash,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5, fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy_rounded, size: 16),
                tooltip: 'Copy Hash',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: hash));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Hash copied to clipboard'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
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
