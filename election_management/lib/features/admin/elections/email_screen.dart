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
  bool _isSending = false;

  @override
  void dispose() {
    _subjectController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _sendEmail() async {
    if (!_formKey.currentState!.validate()) return;
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Send Broadcast Email?'),
        content: const Text('This will send an email to ALL eligible voters in this election. Are you sure you want to proceed?'),
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
          'subject': _subjectController.text,
          'body_html': _bodyController.text,
        },
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(response.data['message'] ?? 'Emails sent successfully!')));
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
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Email Broadcast',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Send a custom email notification to all eligible voters for this election.',
                style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color, fontSize: 16),
              ),
              const SizedBox(height: 32),
              
              GlassCard(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        controller: _subjectController,
                        decoration: const InputDecoration(
                          labelText: 'Email Subject',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.title),
                        ),
                        validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 24),
                      TextFormField(
                        controller: _bodyController,
                        decoration: const InputDecoration(
                          labelText: 'Email Body (HTML supported)',
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
