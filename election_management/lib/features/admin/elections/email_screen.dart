import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/network/api_constants.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/widgets/glass_card.dart';

class EmailScreen extends ConsumerStatefulWidget {
  final String electionId;
  const EmailScreen({super.key, required this.electionId});

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
    setState(() {}); // trigger instant local re-filter
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
          SnackBar(content: Text(response.data['message'] ?? 'Retried successfully!'), backgroundColor: Colors.green),
        );
        _fetchLogs();
      }
    } on DioException catch (e) {
      if (mounted) {
        final err = e.response?.data is Map ? e.response?.data['error'] ?? e.message : e.message;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to retry: $err'), backgroundColor: Colors.red),
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
    if (_sendToVoters) list.add('Voters');
    if (_sendToCandidates) list.add('Candidates');
    if (_sendToElectionOffice) list.add('Election Office / Committee');
    return list.isEmpty ? 'No recipients selected' : list.join(', ');
  }

  Future<void> _sendEmail() async {
    if (!_formKey.currentState!.validate()) return;
    
    if (_selectedRecipients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one recipient group (Voters, Candidates, or Election Office).'))
      );
      return;
    }
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Send Broadcast Email?'),
        content: Text('This will dispatch an email to all members in: $_recipientDescription. Are you sure you want to proceed?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Yes, Send'),
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(response.data['message'] ?? 'Emails queued successfully!'), backgroundColor: Colors.green));
        _subjectController.clear();
        _bodyController.clear();
        _fetchLogs();
      }
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to send emails: ${e.response?.data['error'] ?? e.message}'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Email Broadcast & Delivery Tracking',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Send targeted election broadcasts and monitor live delivery status (success/failure logs).',
                style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color, fontSize: 15),
              ),
              const SizedBox(height: 24),
              
              // Broadcast Form Card
              GlassCard(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.mark_email_read_outlined, color: AppColors.primary, size: 22),
                          SizedBox(width: 8),
                          Text(
                            'Compose Broadcast Email',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      const Text(
                        'Target Recipients *',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          FilterChip(
                            avatar: const Icon(Icons.how_to_vote_rounded, size: 18),
                            label: const Text('Voters'),
                            selected: _sendToVoters,
                            selectedColor: AppColors.primaryLight.withValues(alpha: 0.25),
                            checkmarkColor: AppColors.primary,
                            onSelected: (val) => setState(() => _sendToVoters = val),
                          ),
                          FilterChip(
                            avatar: const Icon(Icons.person_rounded, size: 18),
                            label: const Text('Candidates'),
                            selected: _sendToCandidates,
                            selectedColor: AppColors.accent.withValues(alpha: 0.25),
                            checkmarkColor: AppColors.accent,
                            onSelected: (val) => setState(() => _sendToCandidates = val),
                          ),
                          FilterChip(
                            avatar: const Icon(Icons.account_balance_rounded, size: 18),
                            label: const Text('Election Office / Committee'),
                            selected: _sendToElectionOffice,
                            selectedColor: Colors.purple.withValues(alpha: 0.25),
                            checkmarkColor: Colors.purple,
                            onSelected: (val) => setState(() => _sendToElectionOffice = val),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: _selectedRecipients.isEmpty
                              ? Colors.amber.withValues(alpha: 0.1)
                              : AppColors.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _selectedRecipients.isEmpty
                                ? Colors.amber.withValues(alpha: 0.5)
                                : AppColors.primary.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _selectedRecipients.isEmpty ? Icons.warning_amber_rounded : Icons.info_outline_rounded,
                              size: 18,
                              color: _selectedRecipients.isEmpty ? Colors.amber.shade800 : AppColors.primary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Broadcasting to: $_recipientDescription',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: _selectedRecipients.isEmpty ? Colors.amber.shade800 : AppColors.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _subjectController,
                        decoration: const InputDecoration(
                          labelText: 'Email Subject *',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.title),
                        ),
                        validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _bodyController,
                        decoration: const InputDecoration(
                          labelText: 'Email Body (HTML supported) *',
                          border: OutlineInputBorder(),
                          alignLabelWithHint: true,
                        ),
                        maxLines: 6,
                        validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: _isSending ? null : _sendEmail,
                          icon: _isSending
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.send_rounded),
                          label: Text(_isSending ? 'Sending Broadcast...' : 'Dispatch Broadcast Email'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // Broadcast & Delivery Logs Section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.history_edu_rounded, color: AppColors.primary, size: 22),
                      SizedBox(width: 8),
                      Text(
                        'Delivery Logs & History',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      if (_logSummary['failed']! > 0)
                        ElevatedButton.icon(
                          onPressed: _isRetrying ? null : _retryFailedEmails,
                          icon: _isRetrying
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.replay_rounded, size: 16),
                          label: Text('Retry Failed (${_logSummary['failed']})'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.shade700,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            textStyle: const TextStyle(fontSize: 12),
                          ),
                        ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Refresh Logs',
                        icon: const Icon(Icons.refresh),
                        onPressed: _fetchLogs,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Summary Stats Cards
              Row(
                children: [
                  _buildStatCard('Total Logged', '${_logSummary['total']}', Icons.email_outlined, Colors.blue),
                  const SizedBox(width: 12),
                  _buildStatCard('Delivered / Sent', '${_logSummary['sent']}', Icons.check_circle_outline, Colors.green),
                  const SizedBox(width: 12),
                  _buildStatCard('Failed Deliveries', '${_logSummary['failed']}', Icons.error_outline, Colors.red),
                  const SizedBox(width: 12),
                  _buildStatCard('Queued', '${_logSummary['queued']}', Icons.hourglass_top_outlined, Colors.amber),
                ],
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
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon: _searchLogController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  _searchLogController.clear();
                                  _onSearchChanged('');
                                },
                              )
                            : null,
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                      DropdownMenuItem(value: 'all', child: Text('All Statuses')),
                      DropdownMenuItem(value: 'sent', child: Text('Sent Only')),
                      DropdownMenuItem(value: 'failed', child: Text('Failed Only')),
                      DropdownMenuItem(value: 'queued', child: Text('Queued Only')),
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
              const SizedBox(height: 10),

              // Helper count label
              Builder(builder: (context) {
                final search = _searchLogController.text.trim().toLowerCase();
                final displayLogs = _logs.where((l) {
                  if (search.isEmpty) return true;
                  final email = (l['recipient_email'] ?? '').toString().toLowerCase();
                  final subject = (l['subject'] ?? '').toString().toLowerCase();
                  final name = (l['recipient_name'] ?? '').toString().toLowerCase();
                  return email.contains(search) || subject.contains(search) || name.contains(search);
                }).toList();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Showing ${displayLogs.length} delivery record(s) • 1 entry logged per recipient email',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
                    ),
                    const SizedBox(height: 10),
                    if (_isLoadingLogs)
                      const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
                    else if (displayLogs.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(32),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          children: [
                            Icon(Icons.inbox_outlined, size: 40, color: Colors.grey.shade400),
                            const SizedBox(height: 8),
                            Text(
                              search.isNotEmpty
                                  ? 'No email delivery records matching "$search".'
                                  : 'No email broadcast records found.',
                              style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                            ),
                          ],
                        ),
                      )
                    else
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6, offset: const Offset(0, 2)),
                          ],
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: displayLogs.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (ctx, idx) {
                            final item = displayLogs[idx];
                            final status = item['status']?.toString().toLowerCase() ?? 'queued';
                            final isSuccess = status == 'sent';
                            final isFailed = status == 'failed';
                            final email = item['recipient_email'] ?? 'Unknown';
                            final subject = item['subject'] ?? 'No Subject';
                            final errorMsg = item['error_message'] ?? '';
                            final createdAt = item['created_at']?.toString().split('T').first ?? '';

                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CircleAvatar(
                                    radius: 16,
                                    backgroundColor: isSuccess
                                        ? Colors.green.shade50
                                        : isFailed
                                            ? Colors.red.shade50
                                            : Colors.amber.shade50,
                                    child: Icon(
                                      isSuccess
                                          ? Icons.check_rounded
                                          : isFailed
                                              ? Icons.close_rounded
                                              : Icons.schedule_rounded,
                                      size: 16,
                                      color: isSuccess
                                          ? Colors.green.shade700
                                          : isFailed
                                              ? Colors.red.shade700
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
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: isSuccess
                                                    ? Colors.green.shade100
                                                    : isFailed
                                                        ? Colors.red.shade100
                                                        : Colors.amber.shade100,
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                              child: Text(
                                                status.toUpperCase(),
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w700,
                                                  color: isSuccess
                                                      ? Colors.green.shade800
                                                      : isFailed
                                                          ? Colors.red.shade800
                                                          : Colors.amber.shade900,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          'Subject: $subject',
                                          style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
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
                                    createdAt,
                                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
                Text(title, style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
