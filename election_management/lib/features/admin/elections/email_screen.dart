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

  @override
  void dispose() {
    _subjectController.dispose();
    _bodyController.dispose();
    super.dispose();
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(response.data['message'] ?? 'Emails queued successfully!')));
        _subjectController.clear();
        _bodyController.clear();
      }
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to send emails: ${e.response?.data['error'] ?? e.message}')));
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Email Broadcast',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Send a targeted email announcement or notification for this election.',
                style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color, fontSize: 16),
              ),
              const SizedBox(height: 24),
              
              GlassCard(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Target Recipients *',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Select which groups should receive this email broadcast:',
                        style: TextStyle(fontSize: 13, color: Theme.of(context).textTheme.bodySmall?.color),
                      ),
                      const SizedBox(height: 12),
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
                      const SizedBox(height: 16),
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
                      const SizedBox(height: 24),
                      TextFormField(
                        controller: _subjectController,
                        decoration: const InputDecoration(
                          labelText: 'Email Subject *',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.title),
                        ),
                        validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 24),
                      TextFormField(
                        controller: _bodyController,
                        decoration: const InputDecoration(
                          labelText: 'Email Body (HTML supported) *',
                          border: OutlineInputBorder(),
                          alignLabelWithHint: true,
                        ),
                        maxLines: 8,
                        validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: _isSending ? null : _sendEmail,
                          icon: _isSending ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.send_rounded),
                          label: Text(_isSending ? 'Sending...' : 'Send Broadcast Email'),
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
            ],
          ),
        ),
      ),
    );
  }
}
