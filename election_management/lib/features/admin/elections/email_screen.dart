import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import 'package:nepali_date_picker/nepali_date_picker.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/network/api_constants.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/widgets/loading_button.dart';

class EmailScreen extends ConsumerStatefulWidget {
  final String electionId;
  final bool? showAppBar;

  const EmailScreen({
    super.key,
    required this.electionId,
    this.showAppBar,
  });

  @override
  ConsumerState<EmailScreen> createState() => _EmailScreenState();
}

class _EmailScreenState extends ConsumerState<EmailScreen> {
  final _formKey = GlobalKey<FormState>();
  final _subjectController = TextEditingController();
  final _bodyController = TextEditingController();

  bool _sendToVoters = true;
  bool _sendToCandidates = false;
  bool _sendToElectionOffice = false;
  bool _isSending = false;

  // Editor View Mode (0 = Compose, 1 = Live Preview)
  int _editorTab = 0;

  // Logs & Telemetry state
  bool _isLoadingLogs = false;
  bool _isRetrying = false;
  bool _autoRefresh = true;
  Timer? _autoRefreshTimer;

  List<Map<String, dynamic>> _logs = [];
  Map<String, int> _logSummary = {'total': 0, 'sent': 0, 'failed': 0, 'queued': 0};
  String _selectedStatusFilter = 'all';
  final _searchLogController = TextEditingController();
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _fetchLogs();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _autoRefreshTimer?.cancel();
    _subjectController.dispose();
    _bodyController.dispose();
    _searchLogController.dispose();
    super.dispose();
  }

  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    if (_autoRefresh) {
      _autoRefreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (mounted && !_isLoadingLogs) {
          _fetchLogs(silent: true);
        }
      });
    }
  }

  void _toggleAutoRefresh(bool val) {
    setState(() => _autoRefresh = val);
    if (val) {
      _startAutoRefresh();
      _fetchLogs();
    } else {
      _autoRefreshTimer?.cancel();
    }
  }

  void _onSearchChanged(String query) {
    setState(() {});
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) _fetchLogs();
    });
  }

  Future<void> _fetchLogs({bool silent = false}) async {
    if (!silent) setState(() => _isLoadingLogs = true);
    try {
      final dio = ref.read(apiClientProvider);
      final url = ApiConstants.electionEmailLogs(widget.electionId);
      final response = await dio.get(url, queryParameters: {
        if (_selectedStatusFilter != 'all') 'status': _selectedStatusFilter,
        if (_searchLogController.text.trim().isNotEmpty) 'search': _searchLogController.text.trim(),
      });

      final data = response.data;
      if (data is Map) {
        final summary = data['summary'] as Map<String, dynamic>?;
        final list = (data['logs'] as List<dynamic>?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList() ??
            [];
        if (mounted) {
          setState(() {
            _logs = list;
            if (summary != null) {
              _logSummary = {
                'total': summary['total'] as int? ?? 0,
                'sent': summary['sent'] as int? ?? 0,
                'failed': summary['failed'] as int? ?? 0,
                'queued': summary['queued'] as int? ?? 0,
              };
            }
          });
        }
      }
    } catch (_) {
      // Silently catch in polling
    } finally {
      if (mounted && !silent) setState(() => _isLoadingLogs = false);
    }
  }

  Future<void> _retryFailedEmails() async {
    setState(() => _isRetrying = true);
    try {
      final dio = ref.read(apiClientProvider);
      final url = ApiConstants.retryFailedEmails(widget.electionId);
      final response = await dio.post(url);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white),
                const SizedBox(width: 10),
                Text(response.data['message'] ?? 'Failed emails re-queued for delivery!'),
              ],
            ),
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
        _fetchLogs();
      }
    } on DioException catch (e) {
      if (mounted) {
        final err = e.response?.data is Map ? e.response?.data['error'] ?? e.message : e.message;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to retry: $err'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isRetrying = false);
    }
  }

  List<String> get _selectedRecipients {
    final list = <String>[];
    if (_sendToVoters) list.add('voters');
    if (_sendToCandidates) list.add('candidates');
    if (_sendToElectionOffice) list.add('election_office');
    return list;
  }

  String get _recipientDescription {
    final list = <String>[];
    if (_sendToVoters) list.add('Registered Voters');
    if (_sendToCandidates) list.add('Approved Candidates');
    if (_sendToElectionOffice) list.add('Election Committee');
    return list.isEmpty ? 'No recipients selected' : list.join(', ');
  }

  void _insertTemplate({required String subject, required String body}) {
    setState(() {
      _subjectController.text = subject;
      _bodyController.text = body;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Broadcast template loaded into editor.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _wrapSelection(String startTag, String endTag, {String placeholder = 'text'}) {
    final text = _bodyController.text;
    final selection = _bodyController.selection;

    if (selection.start >= 0 && selection.end > selection.start) {
      final selectedText = text.substring(selection.start, selection.end);
      final replacement = '$startTag$selectedText$endTag';
      final newText = text.replaceRange(selection.start, selection.end, replacement);
      _bodyController.value = TextEditingValue(
        text: newText,
        selection: TextSelection(
          baseOffset: selection.start,
          extentOffset: selection.start + replacement.length,
        ),
      );
    } else {
      final insertPos = selection.start >= 0 ? selection.start : text.length;
      final insertion = '$startTag$placeholder$endTag';
      final newText = text.replaceRange(insertPos, insertPos, insertion);
      _bodyController.value = TextEditingValue(
        text: newText,
        selection: TextSelection(
          baseOffset: insertPos + startTag.length,
          extentOffset: insertPos + startTag.length + placeholder.length,
        ),
      );
    }
  }

  void _insertTag(String tag) {
    final text = _bodyController.text;
    final selection = _bodyController.selection;
    if (selection.start >= 0) {
      final newText = text.replaceRange(selection.start, selection.end, tag);
      _bodyController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: selection.start + tag.length),
      );
    } else {
      _bodyController.text = '$text $tag';
    }
  }

  void _applyFilter({String? status, String? search}) {
    setState(() {
      if (status != null) _selectedStatusFilter = status;
      if (search != null) _searchLogController.text = search;
    });
    _fetchLogs();
  }

  void _clearAllFilters() {
    setState(() {
      _selectedStatusFilter = 'all';
      _searchLogController.clear();
    });
    _fetchLogs();
  }

  Future<void> _sendEmail() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedRecipients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one recipient group (Voters, Candidates, or Election Committee).'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.send_rounded, color: AppColors.primaryLight),
            SizedBox(width: 10),
            Text('Dispatch Broadcast Email?'),
          ],
        ),
        content: Text(
          'This will dispatch broadcast communication to all members in: $_recipientDescription.\n\nAre you sure you want to proceed with live queueing?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.send_rounded, size: 16),
            label: const Text('Yes, Dispatch Now'),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF4F46E5)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isSending = true);

    try {
      final dio = ref.read(apiClientProvider);
      final url = ApiConstants.broadcastEmail(widget.electionId);
      final response = await dio.post(
        url,
        data: {
          'subject': _subjectController.text.trim(),
          'body_html': _bodyController.text.trim(),
          'recipients': _selectedRecipients,
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white),
                const SizedBox(width: 10),
                Text(response.data['message'] ?? 'Emails queued for broadcast successfully!'),
              ],
            ),
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
        _fetchLogs();
      }
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send emails: ${e.response?.data?['error'] ?? e.message}'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  String _formatLogTime(String? iso) {
    if (iso == null || iso.isEmpty) return '-';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final nepali = dt.toNepaliDateTime();
      final timeStr = DateFormat('hh:mm:ss a').format(dt);
      final nepaliDateStr = NepaliDateFormat('MMM d, yyyy').format(nepali);
      return '$nepaliDateStr • $timeStr (BS)';
    } catch (_) {
      return iso;
    }
  }

  void _showLogDetailModal(Map<String, dynamic> log) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final status = (log['status'] ?? 'queued').toString().toLowerCase();
    final isSuccess = status == 'sent';
    final isFailed = status == 'failed';
    final email = log['recipient_email'] ?? 'Unknown';
    final subject = log['subject'] ?? 'No Subject';
    final errorMsg = log['error_message'] ?? '';
    final createdAt = log['created_at']?.toString();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppColors.surface : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: (isSuccess ? Colors.green : isFailed ? Colors.red : Colors.amber).withValues(alpha: 0.15),
                        child: Icon(
                          isSuccess ? Icons.check_rounded : isFailed ? Icons.close_rounded : Icons.schedule_rounded,
                          size: 18,
                          color: isSuccess ? Colors.green : isFailed ? Colors.red : Colors.amber.shade900,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Delivery Log Record', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          Text(status.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isSuccess ? Colors.green : isFailed ? Colors.red : Colors.amber.shade900)),
                        ],
                      ),
                    ],
                  ),
                  IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
                ],
              ),
              const SizedBox(height: 18),
              const Divider(height: 1),
              const SizedBox(height: 18),
              _buildDetailRow('Recipient Email', email, isCopyable: true),
              _buildDetailRow('Subject', subject),
              _buildDetailRow('Timestamp', _formatLogTime(createdAt)),
              if (errorMsg.isNotEmpty)
                _buildDetailRow('Delivery Diagnostic / Error', errorMsg, isError: true),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _applyFilter(search: email);
                      },
                      icon: const Icon(Icons.filter_alt_outlined, size: 16),
                      label: const Text('Filter by This Recipient'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _applyFilter(status: status);
                      },
                      icon: const Icon(Icons.tune_rounded, size: 16),
                      label: Text('Filter by Status: $status'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value, {bool isCopyable = false, bool isError = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Row(
            children: [
              Expanded(
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    color: isError ? Colors.red.shade700 : null,
                  ),
                ),
              ),
              if (isCopyable)
                IconButton(
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Copy Email',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: value));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Copied to clipboard!'), duration: Duration(seconds: 1)),
                    );
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final canPop = Navigator.of(context).canPop();
    final shouldShowAppBar = widget.showAppBar ?? canPop;

    final total = _logSummary['total'] ?? 0;
    final sent = _logSummary['sent'] ?? 0;
    final failed = _logSummary['failed'] ?? 0;
    final queued = _logSummary['queued'] ?? 0;
    final deliveryRate = total > 0 ? (sent / total * 100).toStringAsFixed(1) : '100.0';

    final hasActiveFilter = _selectedStatusFilter != 'all' || _searchLogController.text.trim().isNotEmpty;

    Widget bodyContent = SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1060),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Bar Title & Live Telemetry Pill
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Email Broadcast & Delivery Tracking',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Send targeted official election notices and monitor live email delivery telemetry.',
                        style: TextStyle(color: isDark ? Colors.white60 : AppColors.textMuted, fontSize: 13),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _autoRefresh
                          ? Colors.green.withValues(alpha: isDark ? 0.2 : 0.1)
                          : Colors.grey.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _autoRefresh ? Colors.green.withValues(alpha: 0.4) : Colors.grey.shade400,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _autoRefresh ? Colors.green : Colors.grey,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _autoRefresh ? 'Live Polling Active' : 'Polling Paused',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: _autoRefresh ? Colors.green.shade800 : Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Switch(
                          value: _autoRefresh,
                          onChanged: _toggleAutoRefresh,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ════════════════════════════════════════════════════════════════
              // COMPOSE & LIVE PREVIEW CONTAINER
              // ════════════════════════════════════════════════════════════════
              Container(
                decoration: BoxDecoration(
                  color: isDark ? AppColors.surface : Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: isDark ? AppColors.surfaceVariant : Colors.grey.shade200),
                  boxShadow: [
                    if (!isDark)
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Composer Header & Tab Selector
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF4F46E5).withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.mark_email_read_outlined, color: Color(0xFF4F46E5), size: 20),
                                ),
                                const SizedBox(width: 10),
                                const Text(
                                  'Compose Broadcast Notice',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            // Editor Mode Toggle Tabs
                            Container(
                              decoration: BoxDecoration(
                                color: isDark ? AppColors.surfaceVariant : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              padding: const EdgeInsets.all(3),
                              child: Row(
                                children: [
                                  _buildModeTab(
                                    index: 0,
                                    label: 'Compose / Editor',
                                    icon: Icons.edit_note_rounded,
                                    isSelected: _editorTab == 0,
                                    isDark: isDark,
                                  ),
                                  _buildModeTab(
                                    index: 1,
                                    label: 'Live Preview',
                                    icon: Icons.visibility_outlined,
                                    isSelected: _editorTab == 1,
                                    isDark: isDark,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Quick Pre-Built Templates
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              const Icon(Icons.auto_awesome_rounded, size: 14, color: Color(0xFF4F46E5)),
                              const SizedBox(width: 6),
                              const Text('Templates:', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                              const SizedBox(width: 8),
                              ActionChip(
                                label: const Text('Voter Roll Published', style: TextStyle(fontSize: 11)),
                                onPressed: () => _insertTemplate(
                                  subject: 'Notice: Official Preliminary Voter Roll Published',
                                  body: '<h3>Official Preliminary Voter Roll Published</h3><p>Dear <b>{{name}}</b>,</p><p>The preliminary voter roll for <b>{{election_title}}</b> has been officially published for review.</p><p>Please log in to verify your registration and credentials. You may file claims or objections within the statutory window.</p><hr style="border:0;border-top:1px solid #e2e8f0;margin:16px 0;"><p>Regards,<br><b>Election Commission</b><br>{{organization_name}}</p>',
                                ),
                              ),
                              const SizedBox(width: 8),
                              ActionChip(
                                label: const Text('Nominations Window Open', style: TextStyle(fontSize: 11)),
                                onPressed: () => _insertTemplate(
                                  subject: 'Notice: Candidate Nomination Filing Window is Now Active',
                                  body: '<h3>Candidacy Nomination Window is Open</h3><p>Dear <b>{{name}}</b>,</p><p>Nominations for elective positions in <b>{{election_title}}</b> are now open.</p><p>Eligible members may submit nomination papers along with required statutory proposer and supporter endorsements.</p><p>Deadline: Please refer to the statutory election calendar on the portal.</p><hr style="border:0;border-top:1px solid #e2e8f0;margin:16px 0;"><p>Regards,<br><b>Election Commission</b></p>',
                                ),
                              ),
                              const SizedBox(width: 8),
                              ActionChip(
                                label: const Text('Voting Now Live', style: TextStyle(fontSize: 11)),
                                onPressed: () => _insertTemplate(
                                  subject: 'Urgent: Voting Window is Now Live — Cast Your Secret Ballot',
                                  body: '<h3>Electronic Ballot Window is Live</h3><p>Dear Elector <b>{{name}}</b> (Voter ID: <code>{{voter_id}}</code>),</p><p>The secret electronic voting window for <b>{{election_title}}</b> is now officially <b>OPEN</b>.</p><p>Please log in with your secure credentials to cast your vote. Your ballot is cryptographically encrypted and sealed.</p><p><a href="{{voting_link}}" style="background-color:#4F46E5;color:white;padding:10px 18px;text-decoration:none;border-radius:6px;font-weight:bold;display:inline-block;">Cast Your Secret Ballot Now</a></p><hr style="border:0;border-top:1px solid #e2e8f0;margin:16px 0;"><p>Regards,<br><b>Election Commission</b></p>',
                                ),
                              ),
                              const SizedBox(width: 8),
                              ActionChip(
                                label: const Text('Results Published', style: TextStyle(fontSize: 11)),
                                onPressed: () => _insertTemplate(
                                  subject: 'Official Certified Election Results & Tally Published',
                                  body: '<h3>Certified Election Results Published</h3><p>Dear Member <b>{{name}}</b>,</p><p>The final certified results for <b>{{election_title}}</b> have been tally-verified and officially published.</p><p>You can review the full breakdown of votes, candidate standings, and quota allocations on the election results portal.</p><hr style="border:0;border-top:1px solid #e2e8f0;margin:16px 0;"><p>Regards,<br><b>Election Commission</b><br>{{organization_name}}</p>',
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),

                        // Recipients Choice
                        const Text('Target Recipients *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          children: [
                            FilterChip(
                              avatar: const Icon(Icons.how_to_vote_rounded, size: 16),
                              label: const Text('Registered Voters'),
                              selected: _sendToVoters,
                              selectedColor: const Color(0xFF4F46E5).withValues(alpha: 0.15),
                              checkmarkColor: const Color(0xFF4F46E5),
                              onSelected: (val) => setState(() => _sendToVoters = val),
                            ),
                            FilterChip(
                              avatar: const Icon(Icons.person_rounded, size: 16),
                              label: const Text('Approved Candidates'),
                              selected: _sendToCandidates,
                              selectedColor: Colors.blue.withValues(alpha: 0.15),
                              checkmarkColor: Colors.blue,
                              onSelected: (val) => setState(() => _sendToCandidates = val),
                            ),
                            FilterChip(
                              avatar: const Icon(Icons.security_rounded, size: 16),
                              label: const Text('Election Committee'),
                              selected: _sendToElectionOffice,
                              selectedColor: Colors.purple.withValues(alpha: 0.15),
                              checkmarkColor: Colors.purple,
                              onSelected: (val) => setState(() => _sendToElectionOffice = val),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Recipient info banner
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: _selectedRecipients.isEmpty
                                ? Colors.amber.withValues(alpha: 0.1)
                                : const Color(0xFF4F46E5).withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: _selectedRecipients.isEmpty
                                  ? Colors.amber.withValues(alpha: 0.4)
                                  : const Color(0xFF4F46E5).withValues(alpha: 0.25),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _selectedRecipients.isEmpty ? Icons.warning_amber_rounded : Icons.info_outline_rounded,
                                size: 18,
                                color: _selectedRecipients.isEmpty ? Colors.amber.shade800 : const Color(0xFF4F46E5),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Broadcasting to: $_recipientDescription',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: _selectedRecipients.isEmpty ? Colors.amber.shade800 : const Color(0xFF4F46E5),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),

                        // Email Subject Field
                        TextFormField(
                          controller: _subjectController,
                          decoration: InputDecoration(
                            labelText: 'Notice / Email Subject (विषय) *',
                            hintText: 'e.g. Official Election Notice',
                            prefixIcon: const Icon(Icons.title_rounded),
                            filled: true,
                            fillColor: isDark ? AppColors.surfaceVariant : const Color(0xFFF9FAFB),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          validator: (v) => v == null || v.trim().isEmpty ? 'Email subject is required' : null,
                        ),
                        const SizedBox(height: 16),

                        // Dynamic Variable Pills
                        Row(
                          children: [
                            const Text('Insert Variable: ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                            const SizedBox(width: 4),
                            Expanded(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    _buildVariableChip('{{name}}', 'Name', isDark),
                                    const SizedBox(width: 6),
                                    _buildVariableChip('{{election_title}}', 'Election', isDark),
                                    const SizedBox(width: 6),
                                    _buildVariableChip('{{organization_name}}', 'Organization', isDark),
                                    const SizedBox(width: 6),
                                    _buildVariableChip('{{voter_id}}', 'Voter ID', isDark),
                                    const SizedBox(width: 6),
                                    _buildVariableChip('{{voting_link}}', 'Ballot URL', isDark),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        // Switch between COMPOSE TOOLBAR & LIVE PREVIEW
                        if (_editorTab == 0) ...[
                          // Formatting Toolbar
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            decoration: BoxDecoration(
                              color: isDark ? AppColors.surfaceVariant.withValues(alpha: 0.6) : const Color(0xFFF1F5F9),
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                              border: Border.all(color: isDark ? AppColors.surfaceVariant : Colors.grey.shade300),
                            ),
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  _buildToolBtn(label: 'B', tooltip: 'Bold', onPressed: () => _wrapSelection('<b>', '</b>', placeholder: 'bold text')),
                                  _buildToolBtn(label: 'I', tooltip: 'Italic', isItalic: true, onPressed: () => _wrapSelection('<i>', '</i>', placeholder: 'italic text')),
                                  _buildToolBtn(label: 'U', tooltip: 'Underline', isUnderline: true, onPressed: () => _wrapSelection('<u>', '</u>', placeholder: 'underlined text')),
                                  const SizedBox(width: 6),
                                  _buildToolDivider(isDark),
                                  const SizedBox(width: 6),
                                  _buildToolBtn(label: 'H3', tooltip: 'Heading 3', onPressed: () => _wrapSelection('<h3>', '</h3>', placeholder: 'Heading Title')),
                                  _buildToolBtn(label: 'P', tooltip: 'Paragraph', onPressed: () => _wrapSelection('<p>', '</p>', placeholder: 'Paragraph content')),
                                  const SizedBox(width: 6),
                                  _buildToolDivider(isDark),
                                  const SizedBox(width: 6),
                                  _buildToolIconBtn(icon: Icons.format_list_bulleted_rounded, tooltip: 'Bullet List', onPressed: () => _wrapSelection('<ul>\n  <li>', '</li>\n</ul>', placeholder: 'List Item')),
                                  _buildToolIconBtn(icon: Icons.format_list_numbered_rounded, tooltip: 'Numbered List', onPressed: () => _wrapSelection('<ol>\n  <li>', '</li>\n</ol>', placeholder: 'Step Item')),
                                  _buildToolIconBtn(icon: Icons.format_quote_rounded, tooltip: 'Blockquote', onPressed: () => _wrapSelection('<blockquote>', '</blockquote>', placeholder: 'Quoted notice statement')),
                                  _buildToolIconBtn(icon: Icons.code_rounded, tooltip: 'Code / Highlight', onPressed: () => _wrapSelection('<code>', '</code>', placeholder: 'highlighted code')),
                                  _buildToolIconBtn(icon: Icons.horizontal_rule_rounded, tooltip: 'Horizontal Line', onPressed: () => _insertTag('<hr style="border:0;border-top:1px solid #e2e8f0;margin:16px 0;">')),
                                  _buildToolIconBtn(icon: Icons.link_rounded, tooltip: 'Button Link', onPressed: () => _wrapSelection('<a href="https://" style="background-color:#4F46E5;color:white;padding:8px 16px;text-decoration:none;border-radius:6px;display:inline-block;">', '</a>', placeholder: 'Action Button')),
                                ],
                              ),
                            ),
                          ),
                          // Editor Text Field
                          TextFormField(
                            controller: _bodyController,
                            decoration: InputDecoration(
                              hintText: 'Enter notice content using HTML or formatting tools...',
                              alignLabelWithHint: true,
                              filled: true,
                              fillColor: isDark ? AppColors.surfaceVariant : const Color(0xFFF9FAFB),
                              border: const OutlineInputBorder(
                                borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
                              ),
                            ),
                            maxLines: 8,
                            validator: (v) => v == null || v.trim().isEmpty ? 'Notice body is required' : null,
                            onChanged: (_) => setState(() {}),
                          ),
                        ] else ...[
                          // Live HTML Preview Card
                          _buildLivePreviewCard(isDark),
                        ],
                        const SizedBox(height: 20),

                        // Dispatch Action
                        LoadingButton(
                          onPressed: _sendEmail,
                          isLoading: _isSending,
                          label: 'Dispatch Broadcast Communication (प्रसारण पठाउनुहोस्)',
                          icon: Icons.send_rounded,
                          backgroundColor: const Color(0xFF4F46E5),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // ════════════════════════════════════════════════════════════════
              // DELIVERY TELEMETRY & LIVE STATUS TRACKING
              // ════════════════════════════════════════════════════════════════
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.history_edu_rounded, color: Color(0xFF4F46E5), size: 22),
                      const SizedBox(width: 8),
                      const Text(
                        'Delivery Telemetry & Audit Logs',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF4F46E5).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Success Rate: $deliveryRate%',
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF4F46E5)),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      if (failed > 0)
                        FilledButton.icon(
                          onPressed: _isRetrying ? null : _retryFailedEmails,
                          icon: _isRetrying
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.replay_rounded, size: 16),
                          label: Text('Retry Failed ($failed)'),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.red.shade700,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            textStyle: const TextStyle(fontSize: 12),
                          ),
                        ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Refresh Logs',
                        icon: const Icon(Icons.refresh_rounded),
                        onPressed: () => _fetchLogs(),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Segmented Progress Bar
              if (total > 0) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    height: 10,
                    width: double.infinity,
                    color: isDark ? Colors.white10 : Colors.grey.shade200,
                    child: Row(
                      children: [
                        if (sent > 0)
                          Expanded(
                            flex: sent,
                            child: Container(color: Colors.green),
                          ),
                        if (failed > 0)
                          Expanded(
                            flex: failed,
                            child: Container(color: Colors.red),
                          ),
                        if (queued > 0)
                          Expanded(
                            flex: queued,
                            child: Container(color: Colors.amber),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Interactive Summary Stats Grid (Click to filter!)
              LayoutBuilder(
                builder: (context, constraints) {
                  final cardWidth = constraints.maxWidth > 700
                      ? (constraints.maxWidth - 36) / 4
                      : (constraints.maxWidth - 12) / 2;

                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: cardWidth,
                        child: _buildInteractiveStatCard(
                          title: 'Total Logged',
                          value: '$total',
                          filterKey: 'all',
                          icon: Icons.email_outlined,
                          color: Colors.blue,
                          isSelected: _selectedStatusFilter == 'all',
                          isDark: isDark,
                        ),
                      ),
                      SizedBox(
                        width: cardWidth,
                        child: _buildInteractiveStatCard(
                          title: 'Delivered / Sent',
                          value: '$sent',
                          filterKey: 'sent',
                          icon: Icons.check_circle_outline,
                          color: Colors.green,
                          isSelected: _selectedStatusFilter == 'sent',
                          isDark: isDark,
                        ),
                      ),
                      SizedBox(
                        width: cardWidth,
                        child: _buildInteractiveStatCard(
                          title: 'Failed Deliveries',
                          value: '$failed',
                          filterKey: 'failed',
                          icon: Icons.error_outline,
                          color: Colors.red,
                          isSelected: _selectedStatusFilter == 'failed',
                          isDark: isDark,
                        ),
                      ),
                      SizedBox(
                        width: cardWidth,
                        child: _buildInteractiveStatCard(
                          title: 'Queued Deliveries',
                          value: '$queued',
                          filterKey: 'queued',
                          icon: Icons.hourglass_top_outlined,
                          color: Colors.amber,
                          isSelected: _selectedStatusFilter == 'queued',
                          isDark: isDark,
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 18),

              // Active Filters Ribbon
              if (hasActiveFilter) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.surfaceVariant : const Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF4F46E5).withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.filter_list_rounded, size: 16, color: Color(0xFF4F46E5)),
                      const SizedBox(width: 8),
                      const Text('Active Filters: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      if (_selectedStatusFilter != 'all') ...[
                        Chip(
                          visualDensity: VisualDensity.compact,
                          label: Text('Status: ${_selectedStatusFilter.toUpperCase()}', style: const TextStyle(fontSize: 11)),
                          deleteIcon: const Icon(Icons.close, size: 14),
                          onDeleted: () => _applyFilter(status: 'all'),
                        ),
                        const SizedBox(width: 6),
                      ],
                      if (_searchLogController.text.trim().isNotEmpty) ...[
                        Chip(
                          visualDensity: VisualDensity.compact,
                          label: Text('Search: "${_searchLogController.text.trim()}"', style: const TextStyle(fontSize: 11)),
                          deleteIcon: const Icon(Icons.close, size: 14),
                          onDeleted: () {
                            _searchLogController.clear();
                            _onSearchChanged('');
                          },
                        ),
                        const SizedBox(width: 6),
                      ],
                      const Spacer(),
                      TextButton(
                        onPressed: _clearAllFilters,
                        child: const Text('Clear All', style: TextStyle(fontSize: 12, color: Colors.red)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Search & Filter Row
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchLogController,
                      decoration: InputDecoration(
                        hintText: 'Search logs by recipient email or subject (or tap any log entry)...',
                        hintStyle: const TextStyle(fontSize: 13),
                        prefixIcon: const Icon(Icons.search_rounded, size: 20),
                        suffixIcon: _searchLogController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 18),
                                onPressed: () {
                                  _searchLogController.clear();
                                  _onSearchChanged('');
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: isDark ? AppColors.surfaceVariant : const Color(0xFFF9FAFB),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      onChanged: _onSearchChanged,
                      onSubmitted: (_) => _fetchLogs(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  DropdownButton<String>(
                    value: _selectedStatusFilter,
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('All Statuses', style: TextStyle(fontSize: 13))),
                      DropdownMenuItem(value: 'sent', child: Text('Sent Only', style: TextStyle(fontSize: 13))),
                      DropdownMenuItem(value: 'failed', child: Text('Failed Only', style: TextStyle(fontSize: 13))),
                      DropdownMenuItem(value: 'queued', child: Text('Queued Only', style: TextStyle(fontSize: 13))),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        _applyFilter(status: val);
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Logs List Container
              Builder(builder: (context) {
                final search = _searchLogController.text.trim().toLowerCase();
                final displayLogs = _logs.where((l) {
                  if (search.isEmpty) return true;
                  final email = (l['recipient_email'] ?? '').toString().toLowerCase();
                  final subject = (l['subject'] ?? '').toString().toLowerCase();
                  final name = (l['recipient_name'] ?? '').toString().toLowerCase();
                  return email.contains(search) || subject.contains(search) || name.contains(search);
                }).toList();

                if (_isLoadingLogs) {
                  return const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()));
                }

                if (displayLogs.isEmpty) {
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.surface : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: isDark ? AppColors.surfaceVariant : Colors.grey.shade200),
                    ),
                    child: Column(
                      children: [
                        Icon(Icons.inbox_outlined, size: 40, color: isDark ? Colors.white38 : Colors.grey.shade400),
                        const SizedBox(height: 8),
                        Text(
                          search.isNotEmpty
                              ? 'No email delivery records matching "$search".'
                              : 'No email broadcast records logged for selected filter.',
                          style: TextStyle(color: isDark ? Colors.white60 : Colors.grey.shade600, fontSize: 13),
                        ),
                      ],
                    ),
                  );
                }

                return Container(
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.surface : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: isDark ? AppColors.surfaceVariant : Colors.grey.shade200),
                    boxShadow: [
                      if (!isDark)
                        BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6, offset: const Offset(0, 2)),
                    ],
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: displayLogs.length,
                    separatorBuilder: (_, _) => Divider(height: 1, color: isDark ? Colors.white10 : Colors.grey.shade200),
                    itemBuilder: (ctx, idx) {
                      final item = displayLogs[idx];
                      final status = item['status']?.toString().toLowerCase() ?? 'queued';
                      final isSuccess = status == 'sent';
                      final isFailed = status == 'failed';
                      final email = item['recipient_email'] ?? 'Unknown';
                      final subject = item['subject'] ?? 'No Subject';
                      final errorMsg = item['error_message'] ?? '';
                      final createdAt = item['created_at']?.toString();

                      return InkWell(
                        onTap: () => _showLogDetailModal(item),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                radius: 16,
                                backgroundColor: isSuccess
                                    ? Colors.green.withValues(alpha: 0.12)
                                    : isFailed
                                        ? Colors.red.withValues(alpha: 0.12)
                                        : Colors.amber.withValues(alpha: 0.12),
                                child: Icon(
                                  isSuccess
                                      ? Icons.check_rounded
                                      : isFailed
                                          ? Icons.close_rounded
                                          : Icons.schedule_rounded,
                                  size: 16,
                                  color: isSuccess
                                      ? Colors.green
                                      : isFailed
                                          ? Colors.red
                                          : Colors.amber.shade800,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        // Tap email directly to filter by recipient
                                        InkWell(
                                          onTap: () => _applyFilter(search: email),
                                          child: Text(
                                            email,
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, decoration: TextDecoration.underline),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        // Tap status directly to filter by status
                                        InkWell(
                                          onTap: () => _applyFilter(status: status),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: (isSuccess
                                                      ? Colors.green
                                                      : isFailed
                                                          ? Colors.red
                                                          : Colors.amber)
                                                  .withValues(alpha: 0.12),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              status.toUpperCase(),
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: isSuccess
                                                    ? Colors.green
                                                    : isFailed
                                                        ? Colors.red
                                                        : Colors.amber.shade900,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      'Subject: $subject',
                                      style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.grey.shade800),
                                    ),
                                    if (isFailed && errorMsg.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        'Error: $errorMsg',
                                        style: const TextStyle(fontSize: 11, color: Colors.red, fontStyle: FontStyle.italic),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    _formatLogTime(createdAt),
                                    style: TextStyle(fontSize: 11, color: isDark ? Colors.white54 : Colors.grey.shade500),
                                  ),
                                  const SizedBox(height: 4),
                                  const Icon(Icons.chevron_right_rounded, size: 16, color: Colors.grey),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );

    if (shouldShowAppBar) {
      return Scaffold(
        backgroundColor: isDark ? AppColors.background : const Color(0xFFF8FAFC),
        appBar: AppBar(
          title: const Text('Email Broadcast Dispatcher (इमेल प्रसारण)'),
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
        ),
        body: bodyContent,
      );
    }

    return Container(
      color: isDark ? AppColors.background : const Color(0xFFF8FAFC),
      child: bodyContent,
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // HELPER WIDGETS
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildModeTab({
    required int index,
    required String label,
    required IconData icon,
    required bool isSelected,
    required bool isDark,
  }) {
    return InkWell(
      onTap: () => setState(() => _editorTab = index),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? const Color(0xFF4F46E5) : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: isSelected && !isDark
              ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 1))]
              : null,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 15,
              color: isSelected
                  ? (isDark ? Colors.white : const Color(0xFF4F46E5))
                  : (isDark ? Colors.white60 : Colors.grey.shade600),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected
                    ? (isDark ? Colors.white : const Color(0xFF4F46E5))
                    : (isDark ? Colors.white60 : Colors.grey.shade600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVariableChip(String tag, String label, bool isDark) {
    return InkWell(
      onTap: () => _insertTag(tag),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: isDark ? Colors.white10 : const Color(0xFFEEF2FF),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFF4F46E5).withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.add, size: 12, color: Color(0xFF4F46E5)),
            const SizedBox(width: 4),
            Text(
              '$label: $tag',
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Color(0xFF4F46E5), fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolBtn({
    required String label,
    required String tooltip,
    required VoidCallback onPressed,
    bool isItalic = false,
    bool isUnderline = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              fontStyle: isItalic ? FontStyle.italic : FontStyle.normal,
              decoration: isUnderline ? TextDecoration.underline : TextDecoration.none,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToolIconBtn({required IconData icon, required String tooltip, required VoidCallback onPressed}) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Icon(icon, size: 17),
        ),
      ),
    );
  }

  Widget _buildToolDivider(bool isDark) {
    return Container(
      height: 16,
      width: 1,
      color: isDark ? Colors.white24 : Colors.grey.shade300,
    );
  }

  Widget _buildLivePreviewCard(bool isDark) {
    final rawSubject = _subjectController.text.trim().isEmpty ? 'Notice Subject Preview' : _subjectController.text.trim();
    final rawBody = _bodyController.text.trim().isEmpty
        ? '<p>Your broadcast content will appear here formatted as recipients will see it in their email inbox.</p>'
        : _bodyController.text;

    // Substitute mock variable tags for clean visual preview
    final previewBody = rawBody
        .replaceAll('{{name}}', '<b style="color:#4F46E5;">Ram Bahadur Thapa</b>')
        .replaceAll('{{election_title}}', '<b>Executive Committee Election 2083</b>')
        .replaceAll('{{organization_name}}', '<b>Nepal Central Association</b>')
        .replaceAll('{{voter_id}}', '<code style="background:#e0e7ff;padding:2px 4px;border-radius:4px;">VOTER-2083-9981</code>')
        .replaceAll('{{voting_link}}', 'https://election.system/vote');

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceVariant : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF4F46E5).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.email_outlined, size: 16, color: Color(0xFF4F46E5)),
              const SizedBox(width: 8),
              Text(
                'Simulated Recipient Inbox Preview',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade600),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? AppColors.surface : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rawSubject,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 6),
                Text(
                  'From: Election Commission • To: member@example.com',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),
                // Render content text
                Text(
                  _stripTags(previewBody),
                  style: const TextStyle(fontSize: 13.5, height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _stripTags(String html) {
    return html
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n\n')
        .replaceAll(RegExp(r'</h3>', caseSensitive: false), '\n\n')
        .replaceAll(RegExp(r'</li>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<li>', caseSensitive: false), ' • ')
        .replaceAll(RegExp(r'<[^>]*>'), '');
  }

  Widget _buildInteractiveStatCard({
    required String title,
    required String value,
    required String filterKey,
    required IconData icon,
    required Color color,
    required bool isSelected,
    required bool isDark,
  }) {
    return InkWell(
      onTap: () => _applyFilter(status: filterKey),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: isDark ? 0.25 : 0.15)
              : color.withValues(alpha: isDark ? 0.10 : 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : color.withValues(alpha: isDark ? 0.3 : 0.2),
            width: isSelected ? 2.0 : 1.0,
          ),
          boxShadow: isSelected
              ? [BoxShadow(color: color.withValues(alpha: 0.15), blurRadius: 8, offset: const Offset(0, 2))]
              : null,
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
                      if (isSelected)
                        Icon(Icons.check_circle_rounded, size: 14, color: color),
                    ],
                  ),
                  Text(title, style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : Colors.grey.shade700)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
