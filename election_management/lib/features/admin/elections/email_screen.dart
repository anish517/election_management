import 'dart:async';
import 'package:flutter/material.dart';
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

  // Logs state
  bool _isLoadingLogs = false;
  bool _isRetrying = false;
  List<Map<String, dynamic>> _logs = [];
  Map<String, int> _logSummary = {'total': 0, 'sent': 0, 'failed': 0, 'queued': 0};
  String _selectedStatusFilter = 'all';
  final _searchLogController = TextEditingController();
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _fetchLogs();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _subjectController.dispose();
    _bodyController.dispose();
    _searchLogController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    setState(() {});
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) _fetchLogs();
    });
  }

  Future<void> _fetchLogs() async {
    setState(() => _isLoadingLogs = true);
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
      // Ignored
    } finally {
      if (mounted) setState(() => _isLoadingLogs = false);
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
        content: Text('Email template applied to compose form.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
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

  Future<void> _sendEmail() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedRecipients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one recipient group (Voters, Candidates, or Election Office).'),
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
          'This will dispatch broadcast emails to all members in: $_recipientDescription.\n\nAre you sure you want to proceed with live queueing?',
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
        _subjectController.clear();
        _bodyController.clear();
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final canPop = Navigator.of(context).canPop();
    final shouldShowAppBar = widget.showAppBar ?? canPop;

    Widget bodyContent = SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Text(
                'Email Broadcast & Delivery Tracking',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 2),
              Text(
                'Send targeted official election broadcasts and monitor live email delivery telemetry.',
                style: TextStyle(color: isDark ? Colors.white60 : AppColors.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 20),

              // Compose Card
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
                              'Compose Broadcast Email',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Quick Templates
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              const Icon(Icons.auto_awesome_rounded, size: 14, color: AppColors.primaryLight),
                              const SizedBox(width: 6),
                              const Text('Templates:', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                              const SizedBox(width: 8),
                              ActionChip(
                                label: const Text('Voter Roll Published', style: TextStyle(fontSize: 11)),
                                onPressed: () => _insertTemplate(
                                  subject: 'Notice: Official Preliminary Voter Roll Published',
                                  body: '<p>Dear Member,</p><p>The preliminary voter roll for the upcoming election has been officially published for review.</p><p>Please verify your registration and credentials. You may file claims or objections within the statutory window.</p><p>Regards,<br>Election Commission</p>',
                                ),
                              ),
                              const SizedBox(width: 8),
                              ActionChip(
                                label: const Text('Voting Now Open', style: TextStyle(fontSize: 11)),
                                onPressed: () => _insertTemplate(
                                  subject: 'Urgent: Voting Window is Now Live — Cast Your Secret Ballot',
                                  body: '<p>Dear Elector,</p><p>The secret electronic voting window is now officially OPEN.</p><p>Please log in with your credentials to cast your ballot. Your vote is cryptographically secured.</p><p>Regards,<br>Election Commission</p>',
                                ),
                              ),
                              const SizedBox(width: 8),
                              ActionChip(
                                label: const Text('Results Published', style: TextStyle(fontSize: 11)),
                                onPressed: () => _insertTemplate(
                                  subject: 'Official Election Results & Tally Published',
                                  body: '<p>Dear Member,</p><p>The final certified election results have been officially tally-verified and published.</p><p>You can review the full breakdown and winner standings on the election results portal.</p><p>Regards,<br>Election Commission</p>',
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
                              label: const Text('Candidates'),
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
                            labelText: 'Email Subject (इमेल विषय) *',
                            hintText: 'e.g. Official Election Notice',
                            prefixIcon: const Icon(Icons.title_rounded),
                            filled: true,
                            fillColor: isDark ? AppColors.surfaceVariant : const Color(0xFFF9FAFB),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          validator: (v) => v == null || v.trim().isEmpty ? 'Email subject is required' : null,
                        ),
                        const SizedBox(height: 16),

                        // Placeholder tags helper
                        Row(
                          children: [
                            const Text('Insert Variable: ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                            const SizedBox(width: 4),
                            Wrap(
                              spacing: 6,
                              children: [
                                InkWell(
                                  onTap: () => _insertTag('{{name}}'),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text('{{name}}', style: TextStyle(fontSize: 11, fontFamily: 'monospace')),
                                  ),
                                ),
                                InkWell(
                                  onTap: () => _insertTag('{{election_title}}'),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text('{{election_title}}', style: TextStyle(fontSize: 11, fontFamily: 'monospace')),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // Email Body Field
                        TextFormField(
                          controller: _bodyController,
                          decoration: InputDecoration(
                            labelText: 'Email Body HTML / Plain Text (इमेलको विवरण) *',
                            hintText: 'Enter your broadcast communication body...',
                            prefixIcon: const Icon(Icons.description_outlined),
                            alignLabelWithHint: true,
                            filled: true,
                            fillColor: isDark ? AppColors.surfaceVariant : const Color(0xFFF9FAFB),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          maxLines: 7,
                          validator: (v) => v == null || v.trim().isEmpty ? 'Email body is required' : null,
                        ),
                        const SizedBox(height: 20),

                        // Dispatch Action
                        LoadingButton(
                          onPressed: _sendEmail,
                          isLoading: _isSending,
                          label: 'Dispatch Broadcast Email (इमेल पठाउनुहोस्)',
                          icon: Icons.send_rounded,
                          backgroundColor: const Color(0xFF4F46E5),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // Delivery Telemetry & Logs Section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.history_edu_rounded, color: Color(0xFF4F46E5), size: 22),
                      SizedBox(width: 8),
                      Text(
                        'Live Delivery Logs & Telemetry',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      if (_logSummary['failed']! > 0)
                        FilledButton.icon(
                          onPressed: _isRetrying ? null : _retryFailedEmails,
                          icon: _isRetrying
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.replay_rounded, size: 16),
                          label: Text('Retry Failed (${_logSummary['failed']})'),
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
                        onPressed: _fetchLogs,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Summary Stats Grid
              LayoutBuilder(
                builder: (context, constraints) {
                  final cardWidth = constraints.maxWidth > 700
                      ? (constraints.maxWidth - 36) / 4
                      : (constraints.maxWidth - 12) / 2;

                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(width: cardWidth, child: _buildStatCard('Total Logged', '${_logSummary['total']}', Icons.email_outlined, Colors.blue, isDark)),
                      SizedBox(width: cardWidth, child: _buildStatCard('Delivered / Sent', '${_logSummary['sent']}', Icons.check_circle_outline, Colors.green, isDark)),
                      SizedBox(width: cardWidth, child: _buildStatCard('Failed Deliveries', '${_logSummary['failed']}', Icons.error_outline, Colors.red, isDark)),
                      SizedBox(width: cardWidth, child: _buildStatCard('Queued', '${_logSummary['queued']}', Icons.hourglass_top_outlined, Colors.amber, isDark)),
                    ],
                  );
                },
              ),
              const SizedBox(height: 18),

              // Search & Filter Row
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchLogController,
                      decoration: InputDecoration(
                        hintText: 'Search logs by recipient email or subject...',
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
                        setState(() => _selectedStatusFilter = val);
                        _fetchLogs();
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
                              : 'No email broadcast records logged yet.',
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

                      return Padding(
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
                                      Text(
                                        email,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
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
                            Text(
                              _formatLogTime(createdAt),
                              style: TextStyle(fontSize: 11, color: isDark ? Colors.white54 : Colors.grey.shade500),
                            ),
                          ],
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

  Widget _buildStatCard(String title, String value, IconData icon, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.12 : 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: isDark ? 0.3 : 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
                Text(title, style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : Colors.grey.shade700)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
