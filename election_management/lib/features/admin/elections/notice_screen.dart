import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import 'package:nepali_date_picker/nepali_date_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

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
  Map<String, dynamic>? _electionData;
  List<dynamic> _committees = [];
  String _searchQuery = '';
  String _filterState = 'all'; // 'all', 'published', 'draft'

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    final dio = ref.read(apiClientProvider);

    try {
      final noticesFuture = dio
          .get(ApiConstants.electionNotices(widget.electionId))
          .catchError((_) => Response(requestOptions: RequestOptions(), data: []));

      final detailFuture = dio
          .get(ApiConstants.electionDetail(widget.electionId))
          .catchError((_) => Response(requestOptions: RequestOptions(), data: <String, dynamic>{}));

      final committeesFuture = dio
          .get(ApiConstants.electionCommittees(widget.electionId))
          .catchError((_) => Response(requestOptions: RequestOptions(), data: []));

      final results = await Future.wait([noticesFuture, detailFuture, committeesFuture]);

      if (mounted) {
        setState(() {
          // Notices
          final noticeData = results[0].data;
          if (noticeData is Map && noticeData.containsKey('results')) {
            _notices = (noticeData['results'] as List?) ?? [];
          } else if (noticeData is List) {
            _notices = noticeData;
          } else {
            _notices = [];
          }

          // Election Detail
          if (results[1].data is Map<String, dynamic>) {
            _electionData = results[1].data as Map<String, dynamic>;
          }

          // Committees
          final commData = results[2].data;
          if (commData is List) {
            _committees = commData;
          } else if (commData is Map && commData.containsKey('results')) {
            _committees = (commData['results'] as List?) ?? [];
          } else {
            _committees = [];
          }

          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
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
      _fetchData();
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
        electionData: _electionData,
        notice: notice,
        onSaved: _fetchData,
      ),
    );
  }

  void _showLetterheadViewer(Map<String, dynamic> notice) {
    showDialog(
      context: context,
      builder: (context) => _NoticeLetterheadDialog(
        electionId: widget.electionId,
        notice: notice,
        electionData: _electionData,
        committees: _committees,
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
      final noticeNo = (map['notice_number'] ?? '').toString().toLowerCase();

      if (_filterState == 'published' && !isPublished) return false;
      if (_filterState == 'draft' && isPublished) return false;

      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        return title.contains(q) || content.contains(q) || noticeNo.contains(q);
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
              Text('Official Election Notices (सूचनाहरू)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Text('आधिकारिक लेटरहेड तथा सूचना पाटी', style: TextStyle(fontSize: 11, color: Colors.white70)),
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
              'Election Notices & Letterhead (सूचनाहरू)',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 2),
            Text(
              canManage
                  ? 'Compose, publish, and generate certified statutory letterhead notices for this election.'
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
                  hintText: 'Search notices by title, dispatch number, or keywords...',
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
              onPressed: _fetchData,
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
                  ? 'Create a new notice to generate certified statutory letterhead announcements, schedule bulletins, or polling guidelines.'
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
    final map = notice as Map<String, dynamic>;
    final isPublished = map['is_published'] == true;
    final createdAt = map['created_at'];
    final noticeNumber = map['notice_number']?.toString() ?? '';
    final stampMode = map['stamp_mode']?.toString() ?? 'digital';

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
          // Notice Top Bar
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
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white60 : Colors.grey.shade600,
                      ),
                    ),
                    if (noticeNumber.isNotEmpty) ...[
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          'चलानी नं: $noticeNumber',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue),
                        ),
                      ),
                    ],
                  ],
                ),
                Row(
                  children: [
                    // Stamp Mode Chip
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: (stampMode == 'digital' ? Colors.purple : Colors.teal).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: (stampMode == 'digital' ? Colors.purple : Colors.teal).withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            stampMode == 'digital' ? Icons.verified_rounded : Icons.radio_button_unchecked_rounded,
                            size: 13,
                            color: stampMode == 'digital' ? Colors.purple : Colors.teal,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            stampMode == 'digital' ? 'DIGITAL STAMP' : 'MANUAL WET STAMP',
                            style: TextStyle(
                              color: stampMode == 'digital' ? Colors.purple : Colors.teal,
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Publication Status Badge
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
                      const SizedBox(width: 6),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 18, color: Colors.indigo),
                        tooltip: 'Edit Notice',
                        onPressed: () => _showNoticeDialog(notice: map),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red),
                        tooltip: 'Delete Notice',
                        onPressed: () => _deleteNotice(map['id'].toString()),
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
                  map['title'] ?? 'Untitled Notice',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  map['content'] ?? '',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.5,
                    color: isDark ? Colors.white70 : const Color(0xFF374151),
                  ),
                ),
                const SizedBox(height: 14),

                // Action Bar
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _showLetterheadViewer(map),
                      icon: const Icon(Icons.description_outlined, size: 16, color: Color(0xFF4F46E5)),
                      label: const Text('View Official Letterhead & Print (लेटरहेड)'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF4F46E5),
                        side: const BorderSide(color: Color(0xFF4F46E5)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    if (map['signatories'] is List && (map['signatories'] as List).isNotEmpty)
                      Row(
                        children: [
                          const Icon(Icons.draw_outlined, size: 15, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text(
                            '${(map['signatories'] as List).length} Signator${(map['signatories'] as List).length > 1 ? 'ies' : 'y'}',
                            style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// NOTICE CREATION / EDIT DIALOG
// ─────────────────────────────────────────────────────────────────────────────
class _NoticeDialog extends ConsumerStatefulWidget {
  final String electionId;
  final Map<String, dynamic>? electionData;
  final Map<String, dynamic>? notice;
  final VoidCallback onSaved;

  const _NoticeDialog({
    required this.electionId,
    this.electionData,
    this.notice,
    required this.onSaved,
  });

  @override
  ConsumerState<_NoticeDialog> createState() => _NoticeDialogState();
}

class _NoticeDialogState extends ConsumerState<_NoticeDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _noticeNumberController;
  late TextEditingController _contentController;
  String _stampMode = 'digital'; // 'digital' | 'manual'
  bool _isPublished = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.notice?['title'] ?? '');
    _noticeNumberController = TextEditingController(
      text: widget.notice?['notice_number'] ?? _generateDefaultNoticeNumber(),
    );
    _contentController = TextEditingController(text: widget.notice?['content'] ?? '');
    _stampMode = widget.notice?['stamp_mode'] ?? 'digital';
    _isPublished = widget.notice?['is_published'] ?? true;
  }

  String _generateDefaultNoticeNumber() {
    final now = DateTime.now().toNepaliDateTime();
    return '${now.year}/${(now.year + 1) % 100}-01';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _noticeNumberController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  void _applyTemplate(String title, String content) {
    setState(() {
      _titleController.text = title;
      _contentController.text = content;
    });
  }

  Future<void> _importResultsTable() async {
    setState(() => _isSaving = true);
    try {
      final dio = ref.read(apiClientProvider);
      final res = await dio.get(ApiConstants.results(widget.electionId));
      final data = res.data;
      if (data is Map && data.containsKey('results')) {
        final results = data['results'] as List<dynamic>;
        final totalVoters = data['total_voters'] ?? 0;
        final ballotsCast = data['ballots_cast'] ?? 0;
        final turnout = data['turnout_percentage'] ?? 0;

        final sb = StringBuffer();
        sb.writeln('यस संस्थाको निर्वाचन कार्यतालिका अनुसार सञ्चालन भएको मतदान कार्य सम्पन्न भई कुल $totalVoters मतदातामध्ये $ballotsCast मत ($turnout%) खसेको र मतगणना कार्य सम्पन्न भई निर्वाचन समितिद्वारा प्रमाणित अन्तिम मत परिणाम निम्नानुसार घोषणा गरिएको छ:\n');
        sb.writeln('| पद (Position) | सिट (Seats) | उम्मेदवार (Candidate Name) | प्राप्त मत (Votes) | स्थिति / नतिजा (Outcome) |');
        sb.writeln('| :--- | :--- | :--- | :--- | :--- |');

        for (final pos in results) {
          final posTitle = pos['title'] ?? 'Position';
          final seats = pos['seats_available'] ?? 1;
          final winners = List<String>.from(pos['winners'] ?? []);
          final breakdown = (pos['breakdown'] as List<dynamic>?) ?? [];

          for (final cand in breakdown) {
            final candId = cand['candidate_id'] ?? '';
            final name = cand['name'] ?? '';
            final score = cand['score'] ?? 0;
            final isElected = cand['is_elected'] == true || winners.contains(candId);
            final isTie = cand['is_tie'] == true;
            final isNota = candId == '__BOYCOTT__' || name.toString().toLowerCase().contains('no vote') || name.toString().toLowerCase().contains('abstained');

            String status = '#${cand['rank'] ?? ''}';
            if (isNota) {
              status = '⚪ NOTA / Abstained';
            } else if (isElected && (score is num ? score > 0 : true)) {
              status = '🏆 ELECTED (विजयी)';
            } else if (isTie) {
              status = '⚠️ TIED (बराबरी)';
            }

            final scoreStr = score is num ? (score == score.toInt() ? '${score.toInt()}' : '$score') : '$score';
            sb.writeln('| $posTitle | $seats | $name | $scoreStr | $status |');
          }
        }

        sb.writeln('\nनिर्वाचित हुनुभएका सम्पूर्ण पदाधिकारी तथा सदस्यहरूलाई हार्दिक बधाई ज्ञापन गर्दै सफल कार्यकालको शुभकामना व्यक्त गर्दछौं।');

        setState(() {
          _titleController.text = 'मतदान कार्य सम्पन्न तथा अन्तिम मत परिणाम घोषणा सम्बन्धी आधिकारिक सूचना';
          _contentController.text = sb.toString();
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle_rounded, color: Colors.white),
                  SizedBox(width: 8),
                  Text('Official Results Table successfully inserted into Notice!'),
                ],
              ),
              backgroundColor: Color(0xFF10B981),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No results data available yet. Ensure election voting has concluded.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to import results table: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final dio = ref.read(apiClientProvider);
      final data = {
        'title': _titleController.text.trim(),
        'notice_number': _noticeNumberController.text.trim(),
        'content': _contentController.text.trim(),
        'stamp_mode': _stampMode,
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
                Text(widget.notice == null ? 'Notice published with official letterhead!' : 'Notice updated successfully!'),
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
            widget.notice == null ? 'Create Statutory Election Notice' : 'Edit Election Notice',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
          ),
        ],
      ),
      content: SizedBox(
        width: 680,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Quick Statutory Templates
                Row(
                  children: [
                    const Text('Statutory Notice Templates (द्रुत सूचना ढाँचा):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                    if (widget.electionData?['state'] == 'voting_closed' ||
                        widget.electionData?['state'] == 'results_provisional' ||
                        widget.electionData?['state'] == 'results_final') ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                        ),
                        child: const Text('Voting Completed (मतदान सम्पन्न)', style: TextStyle(color: Color(0xFF10B981), fontSize: 10.5, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ActionChip(
                        avatar: const Icon(Icons.table_chart_rounded, size: 16, color: Color(0xFF10B981)),
                        backgroundColor: const Color(0xFF10B981).withValues(alpha: 0.15),
                        label: const Text('📊 Auto-Insert Results Table (नतिजा तालिका सहित)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF065F46))),
                        onPressed: _importResultsTable,
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.verified_rounded, size: 16, color: Color(0xFF0D9488)),
                        backgroundColor: const Color(0xFF0D9488).withValues(alpha: 0.12),
                        label: const Text('★ Uncontested Wins (निर्विरोध घोषणा)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0F766E))),
                        onPressed: () => _applyTemplate(
                          'उम्मेदवार निर्विरोध निर्वाचित घोषणा सम्बन्धी आधिकारिक सूचना',
                          'यस संस्थाको निर्वाचन कार्यतालिका अनुसार तोकिएको समयसीमाभित्र दर्ता तथा प्रमाणित उम्मेदवारीहरूको छानविन गर्दा तोकिएका पदहरूमा आवश्यक संख्या बराबर मात्र उम्मेदवारी कायम हुन आएकाले निर्वाचन निर्देशिका अनुसार सम्बन्धित उम्मेदवारहरूलाई निर्विरोध निर्वाचित घोषणा गरिएको छ।\n\nनिर्विरोध निर्वाचित हुनुभएका सम्पूर्ण पदाधिकारी तथा सदस्यहरूलाई हार्दिक बधाई ज्ञापन गर्दछौं।',
                        ),
                      ),
                      const SizedBox(width: 6),
                      ActionChip(
                        avatar: const Icon(Icons.how_to_vote_rounded, size: 16, color: Color(0xFF10B981)),
                        backgroundColor: (widget.electionData?['state'] == 'voting_closed' ||
                                widget.electionData?['state'] == 'results_provisional' ||
                                widget.electionData?['state'] == 'results_final')
                            ? const Color(0xFF10B981).withValues(alpha: 0.12)
                            : null,
                        label: const Text('★ Voting Completed (मतदान सम्पन्न तथा परिणाम)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        onPressed: () => _applyTemplate(
                          'मतदान कार्य सम्पन्न तथा अन्तिम मत परिणाम घोषणा सम्बन्धी आधिकारिक सूचना',
                          'यस संस्थाको निर्वाचन कार्यतालिका अनुसार सञ्चालन भएको मतदान कार्य सफलतापूर्वक सम्पन्न भएको छ।\n\nनिर्वाचन निर्देशिका अनुसार सम्पूर्ण मतपेटिका / विद्युतीय मतपत्रहरूको संकलन तथा प्रमाणीकरण सम्पन्न गरी निर्वाचन समितिद्वारा आधिकारिक मत परिणाम घोषणा गरिएको छ।\n\nनिर्वाचित हुनुभएका सम्पूर्ण पदाधिकारी तथा सदस्यहरूलाई हार्दिक बधाई ज्ञापन गर्दै सफल कार्यकालको शुभकामना व्यक्त गर्दछौं।',
                        ),
                      ),
                      const SizedBox(width: 6),
                      ActionChip(
                        avatar: const Icon(Icons.event_note_rounded, size: 16),
                        label: const Text('1. Election Schedule (कार्यतालिका)', style: TextStyle(fontSize: 11)),
                        onPressed: () => _applyTemplate(
                          'निर्वाचन कार्यतालिका तथा निर्वाचन अधिकृतको कार्यालय स्थापना सम्बन्धी सूचना',
                          'यस संस्थाको आगामी कार्यकालका लागि कार्यसमिति चयन गर्न निर्वाचन कार्यतालिका सार्वजनिक गरिएको छ। सम्पूर्ण योग्य सदस्यहरूलाई तोकिएको मिति र समयभित्र आफ्नो उम्मेदवारी दर्ता तथा मतदाता नामावली प्रमाणीकरण गर्न जानकारी गराइन्छ।\n\nनिर्वाचन अधिकृतको कार्यालयबाट विस्तृत निर्वाचन निर्देशिका तथा आचारसंहिता समेत जारी गरिएको छ।',
                        ),
                      ),
                      const SizedBox(width: 6),
                      ActionChip(
                        avatar: const Icon(Icons.people_outline_rounded, size: 16),
                        label: const Text('2. Voter Roll Publication (नामावली प्रकाशन)', style: TextStyle(fontSize: 11)),
                        onPressed: () => _applyTemplate(
                          'प्रारम्भिक मतदाता नामावली प्रकाशन तथा दाबी विरोध सम्बन्धी सूचना',
                          'निर्वाचन निर्देशिका अनुसार संस्थाको प्रारम्भिक मतदाता नामावली सार्वजनिक सूचना पाटी तथा डिजिटल पोर्टलमा प्रकाशन गरिएको छ। नामावलीमा कुनै त्रुटी वा दाबी-विरोध भएमा तोकिएको समयसीमाभित्र प्रमाणसहित निवेदन पेश गर्नुहुन सूचित गरिन्छ।',
                        ),
                      ),
                      const SizedBox(width: 6),
                      ActionChip(
                        avatar: const Icon(Icons.how_to_reg_rounded, size: 16),
                        label: const Text('3. Candidacy Window (उम्मेदवारी आह्वान)', style: TextStyle(fontSize: 11)),
                        onPressed: () => _applyTemplate(
                          'उम्मेदवारी मनोनयन दर्ता आह्वान सम्बन्धी औपचारिक सूचना',
                          'यस निर्वाचनका विभिन्न पदहरूका लागि इच्छुक तथा योग्य सदस्यहरूबाट उम्मेदवारी मनोनयन फारम दर्ता खुला गरिएको छ। समर्थक तथा प्रस्तावकको हस्ताक्षर र आवश्यक दस्तुरसहित अनलाइन वा भौतिक रूपमा मनोनयन पेश गर्न अनुरोध गरिन्छ।',
                        ),
                      ),
                      const SizedBox(width: 6),
                      ActionChip(
                        avatar: const Icon(Icons.verified_rounded, size: 16),
                        label: const Text('4. Final Results (अन्तिम मत परिणाम)', style: TextStyle(fontSize: 11)),
                        onPressed: () => _applyTemplate(
                          'निर्वाचनको अन्तिम मत परिणाम तथा निर्वाचित घोषणा सम्बन्धी सूचना',
                          'सम्पन्न निर्वाचनको मतगणना कार्य सम्पन्न भई निर्वाचन समितिद्वारा प्रमाणित अन्तिम मत परिणाम घोषणा गरिएको छ। निर्वाचित सम्पूर्ण पदाधिकारी तथा सदस्यहरूलाई हार्दिक बधाई ज्ञापन गरिन्छ।',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Notice Title
                TextFormField(
                  controller: _titleController,
                  decoration: InputDecoration(
                    labelText: 'Notice Title / Subject (सूचनाको विषय) *',
                    hintText: 'e.g. Preliminary Voter Roll Publication',
                    prefixIcon: const Icon(Icons.title_rounded),
                    filled: true,
                    fillColor: isDark ? AppColors.surfaceVariant : const Color(0xFFF9FAFB),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  validator: (v) => v == null || v.trim().isEmpty ? 'Notice title is required' : null,
                ),
                const SizedBox(height: 14),

                // Dispatch / Notice Number
                TextFormField(
                  controller: _noticeNumberController,
                  decoration: InputDecoration(
                    labelText: 'Dispatch / Ref Number (चलानी नं. / पत्र संख्या)',
                    hintText: 'e.g. 2083/84-01',
                    prefixIcon: const Icon(Icons.tag_rounded),
                    filled: true,
                    fillColor: isDark ? AppColors.surfaceVariant : const Color(0xFFF9FAFB),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 14),

                // Notice Content Body
                TextFormField(
                  controller: _contentController,
                  decoration: InputDecoration(
                    labelText: 'Notice Content & Description (सूचनाको पूर्ण विवरण) *',
                    hintText: 'Enter formal declaration, instructions, statutory articles, and directives...',
                    prefixIcon: const Icon(Icons.description_outlined),
                    alignLabelWithHint: true,
                    filled: true,
                    fillColor: isDark ? AppColors.surfaceVariant : const Color(0xFFF9FAFB),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  maxLines: 7,
                  validator: (v) => v == null || v.trim().isEmpty ? 'Notice content is required' : null,
                ),
                const SizedBox(height: 16),

                // Stamp Mode Selector (Requirement #5: Digital vs Manual Wet Stamp)
                const Text('Official Stamp Mode on Letterhead (छापको प्रकार) *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 6),
                Container(
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.surfaceVariant.withValues(alpha: 0.3) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade300),
                  ),
                  child: Column(
                    children: [
                      InkWell(
                        onTap: () => setState(() => _stampMode = 'digital'),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Row(
                            children: [
                              Icon(
                                _stampMode == 'digital' ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                                color: _stampMode == 'digital' ? const Color(0xFF4F46E5) : Colors.grey,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Digital Stamp (डिजिटल छाप)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                                    SizedBox(height: 2),
                                    Text('Stamps uploaded official election committee digital seal onto generated letterhead.', style: TextStyle(fontSize: 11.5)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                      InkWell(
                        onTap: () => setState(() => _stampMode = 'manual'),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Row(
                            children: [
                              Icon(
                                _stampMode == 'manual' ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                                color: _stampMode == 'manual' ? const Color(0xFF4F46E5) : Colors.grey,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Manual Wet Stamp (म्यानुअल मसी छाप)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                                    SizedBox(height: 2),
                                    Text('Leaves designated blank space for physical ink wet stamping after printing.', style: TextStyle(fontSize: 11.5)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                      InkWell(
                        onTap: () => setState(() => _stampMode = 'both'),
                        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Row(
                            children: [
                              Icon(
                                _stampMode == 'both' ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                                color: _stampMode == 'both' ? const Color(0xFF4F46E5) : Colors.grey,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Both Digital & Manual (डिजिटल + म्यानुअल दुवै)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                                    SizedBox(height: 2),
                                    Text('Displays both the official digital committee seal AND the physical ink wet stamp space side-by-side.', style: TextStyle(fontSize: 11.5)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Publication Switch
                Material(
                  color: isDark ? AppColors.surfaceVariant.withValues(alpha: 0.4) : const Color(0xFFF8FAFC),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: isDark ? Colors.white10 : Colors.grey.shade300),
                  ),
                  child: SwitchListTile(
                    title: const Text('Published Notice (सार्वजनिक)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
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

// ─────────────────────────────────────────────────────────────────────────────
// OFFICIAL NOTICE LETTERHEAD & PRINT GENERATOR
// ─────────────────────────────────────────────────────────────────────────────
class _NoticeLetterheadDialog extends StatefulWidget {
  final String electionId;
  final Map<String, dynamic> notice;
  final Map<String, dynamic>? electionData;
  final List<dynamic> committees;

  const _NoticeLetterheadDialog({
    required this.electionId,
    required this.notice,
    this.electionData,
    required this.committees,
  });

  @override
  State<_NoticeLetterheadDialog> createState() => _NoticeLetterheadDialogState();
}

class _NoticeLetterheadDialogState extends State<_NoticeLetterheadDialog> {
  late String _currentStampMode;

  @override
  void initState() {
    super.initState();
    _currentStampMode = widget.notice['stamp_mode']?.toString() ?? 'digital';
  }

  String _formatNepaliDate(String? iso) {
    if (iso == null || iso.isEmpty) return '२०८३/०१/०१';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final nepali = dt.toNepaliDateTime();
      return NepaliDateFormat('yyyy/MM/dd (yyyy MMMM d)').format(nepali);
    } catch (_) {
      return iso;
    }
  }

  String _extractElectionYear() {
    // 1. From serialized notice
    if (widget.notice['election_year'] != null && widget.notice['election_year'].toString().isNotEmpty) {
      return widget.notice['election_year'].toString();
    }
    // 2. From election title regex
    final title = widget.electionData?['title'] ?? widget.notice['election_title'] ?? '';
    final match = RegExp(r'\b(20[0-9]{2})\b').firstMatch(title);
    if (match != null) {
      return match.group(1)!;
    }
    // 3. From Nepali current year
    return DateTime.now().toNepaliDateTime().year.toString();
  }

  Future<void> _printNotice() async {
    final noticeId = widget.notice['id']?.toString() ?? '';
    final base = ApiConstants.baseUrl.startsWith('http')
        ? ApiConstants.baseUrl
        : 'http://localhost:8000${ApiConstants.baseUrl}';
    final url = '$base/elections/${widget.electionId}/notices/$noticeId/print_letterhead/?stamp_mode=$_currentStampMode';
    final uri = Uri.parse(url);
    await launchUrl(uri, webOnlyWindowName: '_blank');
  }

  void _cycleStampMode() {
    setState(() {
      if (_currentStampMode == 'digital') {
        _currentStampMode = 'manual';
      } else if (_currentStampMode == 'manual') {
        _currentStampMode = 'both';
      } else {
        _currentStampMode = 'digital';
      }
    });
  }

  String _stampModeLabel() {
    if (_currentStampMode == 'digital') return 'Mode: Digital Stamp (डिजिटल)';
    if (_currentStampMode == 'manual') return 'Mode: Manual Stamp (म्यानुअल)';
    return 'Mode: Both (डिजिटल + म्यानुअल)';
  }

  IconData _stampModeIcon() {
    if (_currentStampMode == 'digital') return Icons.verified_rounded;
    if (_currentStampMode == 'manual') return Icons.crop_free_rounded;
    return Icons.all_inclusive_rounded;
  }

  void _copyNoticeText() {
    final title = widget.notice['title'] ?? '';
    final content = widget.notice['content'] ?? '';
    final orgName = widget.notice['org_name'] ?? widget.electionData?['organization']?['name'] ?? 'Organization';
    final text = '*** $orgName ***\n${widget.electionData?['title'] ?? 'Election'}\n\nविषय: $title\n\n$content';
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Notice text copied to clipboard!'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final notice = widget.notice;
    final election = widget.electionData;

    final orgName = notice['org_name'] ?? election?['organization']?['name'] ?? 'Nepal Association / संस्था';
    final orgAddress = notice['org_address'] ?? election?['organization']?['address'] ?? 'Kathmandu, Nepal';
    final orgPhone = notice['org_phone'] ?? election?['organization']?['phone'] ?? election?['contact_number'] ?? '+977-1-4XXXXXX';
    final orgEmail = notice['org_email'] ?? election?['organization']?['email'] ?? 'election@org.np';
    final rawLogo = notice['org_logo_url'] ?? election?['organization']?['logo_url'] ?? election?['logo_url'] ?? '';
    final orgLogo = ApiConstants.getFullImageUrl(rawLogo.toString()) ?? '';
    final rawStamp = notice['election_stamp_image'] ?? election?['stamp_image'];
    final stampImageUrl = ApiConstants.getFullImageUrl(rawStamp?.toString());
    final electionYear = _extractElectionYear();
    final noticeNumber = notice['notice_number'] ?? '$electionYear/01';
    final dateIso = notice['created_at'];

    // Get signatories (Filtered committee members with include_in_letterhead == true)
    List<dynamic> signatories = [];
    if (notice['signatories'] is List && (notice['signatories'] as List).isNotEmpty) {
      signatories = notice['signatories'];
    } else {
      signatories = widget.committees.where((c) => c['include_in_letterhead'] != false).toList();
    }

    final titleLower = (notice['title'] ?? '').toString().toLowerCase();
    final contentLower = (notice['content'] ?? '').toString().toLowerCase();
    final isResultsNotice = titleLower.contains('मतदान सम्पन्न') ||
        titleLower.contains('मत परिणाम') ||
        titleLower.contains('परिणाम') ||
        titleLower.contains('voting completed') ||
        titleLower.contains('result') ||
        contentLower.contains('मतदान सम्पन्न') ||
        contentLower.contains('मतगणना सम्पन्न');

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860, maxHeight: 900),
        child: Column(
          children: [
            // Top Toolbar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                border: Border(bottom: BorderSide(color: isDark ? Colors.white10 : Colors.grey.shade200)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.verified_user_rounded, color: Color(0xFF4F46E5), size: 22),
                      const SizedBox(width: 8),
                      const Text(
                        'Official Election Notice Letterhead (आधिकारिक लेटरहेड)',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      // Toggle Stamp Mode live in preview (Digital -> Manual -> Both)
                      OutlinedButton.icon(
                        onPressed: _cycleStampMode,
                        icon: Icon(
                          _stampModeIcon(),
                          size: 15,
                          color: _currentStampMode == 'both' ? const Color(0xFF7C3AED) : const Color(0xFF4F46E5),
                        ),
                        label: Text(_stampModeLabel()),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          textStyle: const TextStyle(fontSize: 12),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.copy_rounded, size: 19),
                        tooltip: 'Copy Text',
                        onPressed: _copyNoticeText,
                      ),
                      IconButton(
                        icon: const Icon(Icons.print_rounded, size: 19, color: Color(0xFF4F46E5)),
                        tooltip: 'Print Letterhead / PDF',
                        onPressed: _printNotice,
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 20),
                        tooltip: 'Close',
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Scrollable Official Letterhead Document Sheet
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Container(
                    width: 760,
                    padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 40),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 18,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: DefaultTextStyle(
                      style: const TextStyle(color: Color(0xFF1E293B), fontFamily: 'Roboto'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ─────────────────────────────────────────────────────────────
                          // LETTERHEAD TOP HEADER (Nepal Medical Association Standard)
                          // ─────────────────────────────────────────────────────────────
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Left: Logo
                              Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: const Color(0xFF0F172A).withValues(alpha: 0.15), width: 1.5),
                                ),
                                child: ClipOval(
                                  child: orgLogo.isNotEmpty
                                      ? Image.network(
                                          orgLogo,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, _, _) => _defaultLogoBadge(),
                                        )
                                      : _defaultLogoBadge(),
                                ),
                              ),
                              const SizedBox(width: 14),

                              // Center: Organization Name (Nepali & English), Election Committee, Tenure, Contacts
                              Expanded(
                                child: Column(
                                  children: [
                                    Text(
                                      orgName,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w900,
                                        color: Color(0xFF0F172A),
                                      ),
                                    ),
                                    Text(
                                      orgName.toUpperCase(),
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF1E293B),
                                        letterSpacing: 0.4,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    const Text(
                                      'ELECTION COMMITTEE',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w900,
                                        color: AppColors.primary,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                    Text(
                                      '($electionYear-${(int.tryParse(electionYear) ?? 2083) + 3})',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '$orgAddress. Telephone no. $orgPhone. Email: $orgEmail',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(fontSize: 10, color: Color(0xFF475569), height: 1.3),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 14),

                              // Right: Registration / Dispatch Regd No. & Official Stamp
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    'Regd. No. $noticeNumber',
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
                                  ),
                                  const SizedBox(height: 6),
                                  _buildStampArea(stampImageUrl),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // Solid Full-Width Letterhead Divider Line
                          Container(height: 1.5, color: const Color(0xFF0F172A)),
                          const SizedBox(height: 8),

                          // ─────────────────────────────────────────────────────────────
                          // TWO-COLUMN STATUTORY DOCUMENT BODY
                          // ─────────────────────────────────────────────────────────────
                          IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // LEFT COLUMN: Election Committee Officers Roster
                                _buildLeftCommitteeSidebar(
                                  (notice['committee_members'] is List && (notice['committee_members'] as List).isNotEmpty)
                                      ? (notice['committee_members'] as List)
                                      : widget.committees,
                                  '($electionYear-${(int.tryParse(electionYear) ?? 2083) + 3})',
                                ),

                                // RIGHT COLUMN: Notice Main Body & Signatories
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.only(left: 20, top: 6),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // Top Right: Nepali Date
                                        Align(
                                          alignment: Alignment.topRight,
                                          child: Text(
                                            'मिति : ${_formatNepaliDate(dateIso)}',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF0F172A),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 8),

                                        // Notice Template Variant: Results Declaration Ribbon
                                        if (isResultsNotice) ...[
                                          Center(
                                            child: Container(
                                              margin: const EdgeInsets.only(bottom: 10),
                                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF065F46).withValues(alpha: 0.08),
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(color: const Color(0xFF059669), width: 1.2),
                                              ),
                                              child: const Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(Icons.verified_rounded, size: 15, color: Color(0xFF059669)),
                                                  SizedBox(width: 6),
                                                  Text(
                                                    '🏆 आधिकारिक मत परिणाम घोषणा (OFFICIAL RESULTS DECLARATION)',
                                                    style: TextStyle(
                                                      fontSize: 10.5,
                                                      fontWeight: FontWeight.w900,
                                                      color: Color(0xFF065F46),
                                                      letterSpacing: 0.3,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],

                                        // Centered Main Notice Header: सूचना !
                                        const Center(
                                          child: Text(
                                            'सूचना !',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w900,
                                              color: Color(0xFF0F172A),
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                        ),
                                        if ((notice['title'] ?? '').isNotEmpty && notice['title'] != 'सूचना' && notice['title'] != 'सूचना !') ...[
                                          const SizedBox(height: 6),
                                          Center(
                                            child: Container(
                                              padding: isResultsNotice
                                                  ? const EdgeInsets.symmetric(horizontal: 14, vertical: 6)
                                                  : EdgeInsets.zero,
                                              decoration: isResultsNotice
                                                  ? BoxDecoration(
                                                      color: const Color(0xFFF8FAFC),
                                                      borderRadius: BorderRadius.circular(6),
                                                      border: Border.all(color: const Color(0xFFCBD5E1)),
                                                    )
                                                  : null,
                                              child: Text(
                                                'विषय: ${notice['title']}',
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.bold,
                                                  color: isResultsNotice ? const Color(0xFF0F172A) : null,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                        const SizedBox(height: 14),

                                        // Notice Content Body with Markdown Table Support
                                        Container(
                                          padding: isResultsNotice ? const EdgeInsets.all(12) : EdgeInsets.zero,
                                          decoration: isResultsNotice
                                              ? BoxDecoration(
                                                  color: const Color(0xFFF0FDF4),
                                                  borderRadius: BorderRadius.circular(8),
                                                  border: Border.all(color: const Color(0xFF86EFAC), width: 1),
                                                )
                                              : null,
                                          child: _buildNoticeRichContent(notice['content'] ?? '', isResultsNotice),
                                        ),
                                        const SizedBox(height: 36),

                                        // Signatories Block with Count-Based Alignment (1 -> Left, 2+ -> Center)
                                        Align(
                                          alignment: signatories.length <= 1 ? Alignment.bottomLeft : Alignment.bottomCenter,
                                          child: _buildSignatoriesBlock(signatories, orgName),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Footnote
                          Center(
                            child: Text(
                              'यस आधिकारिक सूचना निर्वाचन समितिको निर्णय अनुसार प्रमाणित गरिएको छ।',
                              style: TextStyle(fontSize: 9.5, color: Colors.grey.shade500, fontStyle: FontStyle.italic),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoticeRichContent(String content, bool isResultsNotice) {
    if (content.contains('|') && content.contains('---')) {
      final lines = content.split('\n');
      final widgets = <Widget>[];
      final tableLines = <String>[];
      bool inTable = false;

      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.startsWith('|') && trimmed.endsWith('|')) {
          inTable = true;
          tableLines.add(trimmed);
        } else {
          if (inTable && tableLines.isNotEmpty) {
            widgets.add(_renderMarkdownTable(tableLines));
            tableLines.clear();
            inTable = false;
          }
          if (trimmed.isNotEmpty) {
            widgets.add(Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                trimmed,
                textAlign: TextAlign.justify,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.8,
                  color: Color(0xFF1E293B),
                ),
              ),
            ));
          }
        }
      }
      if (inTable && tableLines.isNotEmpty) {
        widgets.add(_renderMarkdownTable(tableLines));
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: widgets);
    }

    return Text(
      content,
      textAlign: TextAlign.justify,
      style: const TextStyle(
        fontSize: 13,
        height: 1.85,
        color: Color(0xFF1E293B),
      ),
    );
  }

  Widget _renderMarkdownTable(List<String> tableLines) {
    if (tableLines.length < 2) return const SizedBox.shrink();

    // Parse header
    final headerCells = tableLines[0]
        .split('|')
        .map((c) => c.trim())
        .where((c) => c.isNotEmpty)
        .toList();

    // Rows (skip index 1 if it's separator)
    final rows = <TableRow>[];

    // Header TableRow
    rows.add(
      TableRow(
        decoration: const BoxDecoration(color: Color(0xFFF1F5F9)),
        children: headerCells.map((header) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            child: Text(
              header,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: Color(0xFF0F172A)),
            ),
          );
        }).toList(),
      ),
    );

    for (int i = 1; i < tableLines.length; i++) {
      final line = tableLines[i];
      if (line.replaceAll(RegExp(r'[\s\|\:\-]'), '').isEmpty) continue; // skip divider line

      final cells = line
          .split('|')
          .map((c) => c.trim())
          .where((c) => c.isNotEmpty)
          .toList();

      if (cells.isEmpty) continue;

      final isElectedRow = line.contains('🏆 ELECTED') || line.contains('विजयी');
      final isTiedRow = line.contains('⚠️ TIED') || line.contains('बराबरी');

      Color? rowColor;
      if (isElectedRow) {
        rowColor = const Color(0xFF10B981).withValues(alpha: 0.1);
      } else if (isTiedRow) {
        rowColor = Colors.amber.withValues(alpha: 0.12);
      }

      rows.add(
        TableRow(
          decoration: rowColor != null ? BoxDecoration(color: rowColor) : null,
          children: cells.asMap().entries.map((entry) {
            final text = entry.value;
            final isStatusCell = entry.key == cells.length - 1;

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isElectedRow ? FontWeight.bold : FontWeight.normal,
                  color: isElectedRow && isStatusCell
                      ? const Color(0xFF059669)
                      : (isTiedRow && isStatusCell ? Colors.amber.shade900 : const Color(0xFF1E293B)),
                ),
              ),
            );
          }).toList(),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Table(
          border: TableBorder.all(color: const Color(0xFFE2E8F0), width: 1),
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: rows,
        ),
      ),
    );
  }

  Widget _defaultLogoBadge() {
    return Container(
      color: const Color(0xFFEFF6FF),
      child: const Center(
        child: Icon(Icons.account_balance_rounded, color: Color(0xFF1E3A8A), size: 36),
      ),
    );
  }

  Widget _buildLeftCommitteeSidebar(List<dynamic> committeeList, String tenureRange) {
    return Container(
      width: 190,
      padding: const EdgeInsets.only(right: 14, top: 6),
      decoration: const BoxDecoration(
        border: Border(
          right: BorderSide(color: Color(0xFF0F172A), width: 1.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ELECTION COMMITTEE',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 12,
              color: AppColors.primary,
              letterSpacing: 0.3,
            ),
          ),
          Text(
            tenureRange,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 11.5,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 18),
          if (committeeList.isEmpty) ...[
            const SizedBox.shrink(),
          ] else ...[
            ...committeeList.map((m) {
              final name = m['name'] ?? m['chair_full_name'] ?? m['committee_name'] ?? m['chair_email'] ?? 'Officer';
              final designation = m['designation'] ?? m['chair_designation'] ?? 'Election Officer';
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$designation:',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11.5,
                        color: Color(0xFF0F172A),
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      name.toString(),
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF334155),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  // Stamp Section (Digital Stamp vs Manual Wet Stamp vs Both)
  Widget _buildStampArea(String? stampImageUrl) {
    if (_currentStampMode == 'both') {
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _buildDigitalSeal(stampImageUrl),
          const SizedBox(width: 12),
          _buildManualSeal(),
        ],
      );
    } else if (_currentStampMode == 'manual') {
      return _buildManualSeal();
    } else {
      return _buildDigitalSeal(stampImageUrl);
    }
  }

  Widget _buildDigitalSeal(String? stampImageUrl) {
    if (stampImageUrl != null && stampImageUrl.isNotEmpty) {
      return Container(
        width: 92,
        height: 92,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFDC2626).withValues(alpha: 0.85), width: 1.8),
        ),
        child: ClipOval(
          child: Image.network(
            stampImageUrl,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => _defaultDigitalSeal(),
          ),
        ),
      );
    }
    return _defaultDigitalSeal();
  }

  Widget _buildManualSeal() {
    return Container(
      width: 92,
      height: 92,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.grey.shade400,
          width: 1.4,
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(4.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.crop_free_rounded, size: 16, color: Colors.grey.shade400),
              const SizedBox(height: 2),
              Text(
                '[ आधिकारिक छाप ]\nOFFICIAL SEAL',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 7.5,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade500,
                ),
              ),
              Text(
                '(स्थान)',
                style: TextStyle(fontSize: 6.5, color: Colors.grey.shade400),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _defaultDigitalSeal() {
    return Container(
      width: 92,
      height: 92,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFDC2626).withValues(alpha: 0.85), width: 2.0),
      ),
      child: Container(
        margin: const EdgeInsets.all(2.5),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFDC2626).withValues(alpha: 0.65), width: 1.0),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('★ निर्वाचन समिति ★', style: TextStyle(fontSize: 7.5, fontWeight: FontWeight.bold, color: Color(0xFFDC2626))),
            const Icon(Icons.verified_rounded, size: 18, color: Color(0xFFDC2626)),
            const Text('आधिकारिक छाप', style: TextStyle(fontSize: 7.5, fontWeight: FontWeight.bold, color: Color(0xFFDC2626))),
            Text('OFFICIAL SEAL', style: TextStyle(fontSize: 6.0, color: const Color(0xFFDC2626).withValues(alpha: 0.8))),
          ],
        ),
      ),
    );
  }

  // Signatories Section with count-based alignment (1 -> Left, 2+ -> Center)
  Widget _buildSignatoriesBlock(List<dynamic> signatories, String orgName) {
    if (signatories.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 140,
            height: 1,
            color: const Color(0xFF1E293B),
          ),
          const SizedBox(height: 6),
          const Text('( प्रमुख निर्वाचन अधिकृत )', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          const Text('केन्द्रीय निर्वाचन समिति', style: TextStyle(fontSize: 11, color: Colors.black87)),
        ],
      );
    }

    final isSingle = signatories.length <= 1;

    return Wrap(
      spacing: 24,
      runSpacing: 16,
      alignment: isSingle ? WrapAlignment.start : WrapAlignment.center,
      crossAxisAlignment: isSingle ? WrapCrossAlignment.start : WrapCrossAlignment.center,
      children: signatories.map((s) {
        final name = s['name'] ?? s['chair_full_name'] ?? s['committee_name'] ?? 'Election Officer';
        final designation = s['designation'] ?? s['chair_designation'] ?? 'Committee Member';
        final rawSig = s['signature_url'] ?? s['chair_signature'];
        final fullSigUrl = ApiConstants.getFullImageUrl(rawSig?.toString());

        return Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Signature Graphic / Line
            SizedBox(
              height: 52,
              width: 140,
              child: fullSigUrl != null && fullSigUrl.isNotEmpty
                  ? Image.network(
                      fullSigUrl,
                      fit: BoxFit.contain,
                      errorBuilder: (ctx, err, stack) => _signatureDottedLine(),
                    )
                  : _signatureDottedLine(),
            ),
            Container(width: 140, height: 1, color: const Color(0xFF1E293B)),
            const SizedBox(height: 4),
            Text(
              '( $name )',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5),
            ),
            Text(
              designation,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 10.5, color: Color(0xFF1E3A8A)),
            ),
            const Text(
              'निर्वाचन समिति',
              style: TextStyle(fontSize: 9.5, color: Colors.black54),
            ),
          ],
        );
      }).toList(),
    );
  }

  Widget _signatureDottedLine() {
    return const Center(
      child: Text(
        '..................................',
        style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
      ),
    );
  }
}
