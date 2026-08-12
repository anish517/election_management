import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/network/api_constants.dart';
import '../../../core/network/api_client.dart';
import '../../../core/providers/app_providers.dart';
import '../../../shared/widgets/glass_card.dart';

class NoticeScreen extends ConsumerStatefulWidget {
  final String electionId;
  const NoticeScreen({super.key, required this.electionId});

  @override
  ConsumerState<NoticeScreen> createState() => _NoticeScreenState();
}

class _NoticeScreenState extends ConsumerState<NoticeScreen> {
  bool _isLoading = true;
  List<dynamic> _notices = [];

  @override
  void initState() {
    super.initState();
    _fetchNotices();
  }

  Future<void> _fetchNotices() async {
    setState(() => _isLoading = true);
    try {
      final dio = ref.read(apiClientProvider);
      final url = ApiConstants.electionNotices(widget.electionId);
      final response = await dio.get(url);
      
      if (mounted) {
        setState(() {
          _notices = response.data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
  
  Future<void> _deleteNotice(String noticeId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Notice?'),
        content: const Text('Are you sure you want to delete this notice? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    
    try {
      final dio = ref.read(apiClientProvider);
      final url = ApiConstants.electionNoticeDetail(widget.electionId, noticeId);
      await dio.delete(url);
      _fetchNotices();
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete notice: ${e.response?.data ?? e.message}')));
      }
    }
  }

  void _showNoticeDialog({Map<String, dynamic>? notice}) {
    showDialog(
      context: context,
      builder: (context) => _NoticeDialog(
        electionId: widget.electionId,
        notice: notice,
        onSaved: _fetchNotices,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Election Notices',
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Manage public announcements and notices for this election.',
                        style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color, fontSize: 16),
                      ),
                    ],
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _showNoticeDialog(),
                    icon: const Icon(Icons.add),
                    label: const Text('New Notice'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              
              if (_notices.isEmpty)
                const Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.campaign_outlined, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text('No notices yet.', style: TextStyle(fontSize: 18, color: Colors.grey)),
                      ],
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.builder(
                    itemCount: _notices.length,
                    itemBuilder: (context, index) {
                      final notice = _notices[index];
                      final createdAt = DateTime.tryParse(notice['created_at'] ?? '');
                      final formattedDate = createdAt != null ? DateFormat.yMMMd().add_jm().format(createdAt) : 'Unknown date';
                      
                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        child: GlassCard(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      notice['title'] ?? 'Untitled',
                                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      if (notice['is_published'] == true)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: AppColors.success.withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(16),
                                            border: Border.all(color: AppColors.success.withValues(alpha: 0.5)),
                                          ),
                                          child: const Text('Published', style: TextStyle(color: AppColors.success, fontSize: 12, fontWeight: FontWeight.bold)),
                                        )
                                      else
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.orange.withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(16),
                                            border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
                                          ),
                                          child: const Text('Draft', style: TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.bold)),
                                        ),
                                      const SizedBox(width: 8),
                                      IconButton(
                                        icon: const Icon(Icons.edit_outlined, size: 20, color: AppColors.primary),
                                        onPressed: () => _showNoticeDialog(notice: notice),
                                        tooltip: 'Edit',
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline, size: 20, color: AppColors.error),
                                        onPressed: () => _deleteNotice(notice['id'].toString()),
                                        tooltip: 'Delete',
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                formattedDate,
                                style: const TextStyle(color: Colors.grey, fontSize: 12),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                notice['content'] ?? '',
                                style: const TextStyle(height: 1.5),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoticeDialog extends ConsumerStatefulWidget {
  final String electionId;
  final Map<String, dynamic>? notice;
  final VoidCallback onSaved;

  const _NoticeDialog({required this.electionId, this.notice, required this.onSaved});

  @override
  ConsumerState<_NoticeDialog> createState() => _NoticeDialogState();
}

class _NoticeDialogState extends ConsumerState<_NoticeDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _contentController;
  bool _isPublished = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.notice?['title'] ?? '');
    _contentController = TextEditingController(text: widget.notice?['content'] ?? '');
    _isPublished = widget.notice?['is_published'] ?? true;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isSaving = true);
    
    try {
      final dio = ref.read(apiClientProvider);
      final data = {
        'title': _titleController.text,
        'content': _contentController.text,
        'is_published': _isPublished,
      };
      
      if (widget.notice == null) {
        await dio.post(ApiConstants.electionNotices(widget.electionId), data: data);
      } else {
        await dio.put(ApiConstants.electionNoticeDetail(widget.electionId, widget.notice!['id'].toString()), data: data);
      }
      
      if (mounted) {
        widget.onSaved();
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Notice saved successfully!')));
      }
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${e.response?.data ?? e.message}')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.notice == null ? 'Create Notice' : 'Edit Notice'),
      content: SizedBox(
        width: 600,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => v == null || v.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _contentController,
                decoration: const InputDecoration(
                  labelText: 'Content',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                maxLines: 5,
                validator: (v) => v == null || v.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('Published'),
                subtitle: const Text('If published, voters will see this notice.'),
                value: _isPublished,
                onChanged: (v) => setState(() => _isPublished = v),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _isSaving ? null : _save,
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
          child: Text(_isSaving ? 'Saving...' : 'Save'),
        ),
      ],
    );
  }
}
