import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import 'package:nepali_date_picker/nepali_date_picker.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/network/api_constants.dart';
import '../../../core/network/api_client.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../shared/widgets/loading_button.dart';

class NoticeScreen extends ConsumerStatefulWidget {
  final String electionId;
  final bool? showAppBar;

  const NoticeScreen({
    super.key,
    required this.electionId,
    this.showAppBar,
  });

  @override
  ConsumerState<NoticeScreen> createState() => _NoticeScreenState();
}

class _NoticeScreenState extends ConsumerState<NoticeScreen> {
  bool _isLoading = true;
  List<dynamic> _notices = [];
  String _searchQuery = '';
  String _filterState = 'all'; // 'all', 'published', 'draft'

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
          final data = response.data;
          if (data is Map && data.containsKey('results')) {
            _notices = data['results'];
          } else if (data is List) {
            _notices = data;
          } else {
            _notices = [];
          }
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Official Notice?'),
        content: const Text('Are you sure you want to delete this public notice? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete Notice'),
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.white),
                SizedBox(width: 10),
                Text('Notice deleted successfully.'),
              ],
            ),
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete notice: ${e.response?.data ?? e.message}'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
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

  String _formatDate(String? iso) {
    if (iso == null || iso.isEmpty) return 'Unknown date';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final nepali = dt.toNepaliDateTime();
      final timeStr = DateFormat('hh:mm a').format(dt);
      final nepaliDateStr = NepaliDateFormat('MMM d, yyyy').format(nepali);
      return '$nepaliDateStr • $timeStr (BS)';
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user = ref.watch(authProvider).user;
    final canManage = user?.canManageElections ?? false;
    final canPop = Navigator.of(context).canPop();
    final shouldShowAppBar = widget.showAppBar ?? canPop;

    final baseNotices = canManage
        ? _notices
        : _notices.where((n) => n['is_published'] == true).toList();

    // Filter by search & publication status
    final filteredNotices = baseNotices.where((item) {
      final map = item as Map<String, dynamic>;
      final isPublished = map['is_published'] == true;
      final title = (map['title'] ?? '').toString().toLowerCase();
      final content = (map['content'] ?? '').toString().toLowerCase();

      if (_filterState == 'published' && !isPublished) return false;
      if (_filterState == 'draft' && isPublished) return false;

      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        return title.contains(q) || content.contains(q);
      }
      return true;
    }).toList();

    Widget bodyWidget;
    if (_isLoading) {
      bodyWidget = const Center(child: CircularProgressIndicator());
    } else {
      bodyWidget = SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Header & Action Suite
                  _buildHeader(context, isDark, canManage),
                  const SizedBox(height: 16),

                  // Search & Filter Toolbar
                  _buildFilterBar(isDark, canManage, baseNotices),
                  const SizedBox(height: 16),

                  // Notices List
                  Expanded(
                    child: filteredNotices.isEmpty
                        ? _buildEmptyState(isDark, canManage)
                        : ListView.builder(
                            itemCount: filteredNotices.length,
                            itemBuilder: (context, index) {
                              return _buildNoticeCard(filteredNotices[index], isDark, canManage);
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (shouldShowAppBar) {
      return Scaffold(
        backgroundColor: isDark ? AppColors.background : const Color(0xFFF8FAFC),
        appBar: AppBar(
          title: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Election Notices (सूचनाहरू)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Text('आधिकारिक सार्वजनिक सूचना पाटी', style: TextStyle(fontSize: 11, color: Colors.white70)),
            ],
          ),
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
        body: bodyWidget,
      );
    }

    return Container(
      color: isDark ? AppColors.background : const Color(0xFFF8FAFC),
      child: bodyWidget,
    );
  }

  Widget _buildHeader(BuildContext context, bool isDark, bool canManage) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Election Notices (सूचनाहरू)',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 2),
            Text(
              canManage
                  ? 'Manage official public announcements and bulletins for this election.'
                  : 'Official bulletins and notices published by the Election Commission.',
              style: TextStyle(color: isDark ? Colors.white60 : AppColors.textMuted, fontSize: 13),
            ),
          ],
        ),
        if (canManage)
          FilledButton.icon(
            onPressed: () => _showNoticeDialog(),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Publish Notice'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF4F46E5),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
      ],
    );
  }

  Widget _buildFilterBar(bool isDark, bool canManage, List<dynamic> baseNotices) {
    return Material(
      color: isDark ? AppColors.surfaceVariant.withValues(alpha: 0.3) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search notices by title or content keywords...',
                  hintStyle: const TextStyle(fontSize: 13),
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  filled: true,
                  fillColor: isDark ? AppColors.surfaceVariant : const Color(0xFFF9FAFB),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade300),
                  ),
                ),
                onChanged: (v) => setState(() => _searchQuery = v),
              ),
            ),
            if (canManage) ...[
              const SizedBox(width: 16),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: Text('All (${baseNotices.length})', style: const TextStyle(fontSize: 12)),
                    selected: _filterState == 'all',
                    onSelected: (val) => setState(() => _filterState = 'all'),
                  ),
                  ChoiceChip(
                    label: Text('Published (${baseNotices.where((n) => n['is_published'] == true).length})', style: const TextStyle(fontSize: 12)),
                    selected: _filterState == 'published',
                    selectedColor: Colors.green.withValues(alpha: 0.2),
                    onSelected: (val) => setState(() => _filterState = 'published'),
                  ),
                  ChoiceChip(
                    label: Text('Drafts (${baseNotices.where((n) => n['is_published'] != true).length})', style: const TextStyle(fontSize: 12)),
                    selected: _filterState == 'draft',
                    selectedColor: Colors.orange.withValues(alpha: 0.2),
                    onSelected: (val) => setState(() => _filterState = 'draft'),
                  ),
                ],
              ),
            ],
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Refresh Notices',
              onPressed: _fetchNotices,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark, bool canManage) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(36),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surface : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade200),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.campaign_outlined, size: 48, color: AppColors.primaryLight),
            ),
            const SizedBox(height: 16),
            const Text('No Election Notices Found', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(
              canManage
                  ? 'Create a new notice to announce deadlines, candidate lists, or polling instructions.'
                  : 'Official bulletins and notices from the election committee will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: isDark ? Colors.white60 : Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoticeCard(dynamic notice, bool isDark, bool canManage) {
    final isPublished = notice['is_published'] == true;
    final createdAt = notice['created_at'];

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surface : Colors.white,
        borderRadius: BorderRadius.circular(16),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Notice Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? AppColors.surfaceVariant.withValues(alpha: 0.3) : const Color(0xFFF8FAFC),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
              border: Border(bottom: BorderSide(color: isDark ? Colors.white10 : Colors.grey.shade200)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.campaign_rounded, size: 20, color: isPublished ? const Color(0xFF4F46E5) : Colors.orange),
                    const SizedBox(width: 8),
                    Text(
                      _formatDate(createdAt),
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white60 : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: (isPublished ? Colors.green : Colors.orange).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: (isPublished ? Colors.green : Colors.orange).withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: isPublished ? Colors.green : Colors.orange,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            isPublished ? 'PUBLISHED' : 'DRAFT',
                            style: TextStyle(
                              color: isPublished ? Colors.green : Colors.orange,
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (canManage) ...[
                      const SizedBox(width: 10),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 18, color: Colors.indigo),
                        tooltip: 'Edit Notice',
                        onPressed: () => _showNoticeDialog(notice: notice),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red),
                        tooltip: 'Delete Notice',
                        onPressed: () => _deleteNotice(notice['id'].toString()),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // Notice Content Body
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  notice['title'] ?? 'Untitled Notice',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Text(
                  notice['content'] ?? '',
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.6,
                    color: isDark ? Colors.white70 : const Color(0xFF374151),
                  ),
                ),
              ],
            ),
          ),
        ],
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
        'title': _titleController.text.trim(),
        'content': _contentController.text.trim(),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white),
                const SizedBox(width: 10),
                Text(widget.notice == null ? 'Notice published successfully!' : 'Notice updated successfully!'),
              ],
            ),
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.response?.data ?? e.message}'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.campaign_rounded, color: AppColors.primaryLight, size: 22),
          ),
          const SizedBox(width: 12),
          Text(
            widget.notice == null ? 'Create Election Notice' : 'Edit Election Notice',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
          ),
        ],
      ),
      content: SizedBox(
        width: 620,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: 'Notice Title (सूचनाको शीर्षक) *',
                  hintText: 'e.g. Preliminary Voter Roll Publication',
                  prefixIcon: const Icon(Icons.title_rounded),
                  filled: true,
                  fillColor: isDark ? AppColors.surfaceVariant : const Color(0xFFF9FAFB),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                validator: (v) => v == null || v.trim().isEmpty ? 'Notice title is required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _contentController,
                decoration: InputDecoration(
                  labelText: 'Notice Content & Description (सूचनाको पूर्ण विवरण) *',
                  hintText: 'Enter announcement details, instructions, or regulatory directives...',
                  prefixIcon: const Icon(Icons.description_outlined),
                  alignLabelWithHint: true,
                  filled: true,
                  fillColor: isDark ? AppColors.surfaceVariant : const Color(0xFFF9FAFB),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                maxLines: 6,
                validator: (v) => v == null || v.trim().isEmpty ? 'Notice content is required' : null,
              ),
              const SizedBox(height: 16),
              Material(
                color: isDark ? AppColors.surfaceVariant.withValues(alpha: 0.4) : const Color(0xFFF8FAFC),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: isDark ? Colors.white10 : Colors.grey.shade300),
                ),
                child: SwitchListTile(
                  title: const Text('Published (सार्वजनिक)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: const Text('When enabled, this notice will be immediately visible to voters and candidates.', style: TextStyle(fontSize: 12)),
                  value: _isPublished,
                  activeThumbColor: const Color(0xFF10B981),
                  onChanged: (v) => setState(() => _isPublished = v),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        LoadingButton(
          isLoading: _isSaving,
          label: widget.notice == null ? 'Publish Notice' : 'Save Changes',
          icon: Icons.send_rounded,
          onPressed: _save,
          fullWidth: false,
        ),
      ],
    );
  }
}
