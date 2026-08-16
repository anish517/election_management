import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/network/api_constants.dart';
import '../../../core/network/api_client.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../shared/widgets/loading_button.dart';

class GuidelinesScreen extends ConsumerStatefulWidget {
  final String electionId;
  final bool? showAppBar;

  const GuidelinesScreen({
    super.key,
    required this.electionId,
    this.showAppBar,
  });

  @override
  ConsumerState<GuidelinesScreen> createState() => _GuidelinesScreenState();
}

class _GuidelinesScreenState extends ConsumerState<GuidelinesScreen> {
  final _guidelinesController = TextEditingController();
  bool _isSaving = false;
  bool _isLoading = true;
  bool _isPreviewMode = false;

  @override
  void initState() {
    super.initState();
    _fetchGuidelines();
  }

  @override
  void dispose() {
    _guidelinesController.dispose();
    super.dispose();
  }

  Future<void> _fetchGuidelines() async {
    try {
      final dio = ref.read(apiClientProvider);
      final url = ApiConstants.electionDetail(widget.electionId);
      final response = await dio.get(url);

      if (mounted) {
        setState(() {
          _guidelinesController.text = response.data['guidelines'] ?? '';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveGuidelines() async {
    setState(() => _isSaving = true);

    try {
      final dio = ref.read(apiClientProvider);
      final url = ApiConstants.electionDetail(widget.electionId);
      await dio.patch(
        url,
        data: {'guidelines': _guidelinesController.text.trim()},
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.white),
                SizedBox(width: 10),
                Text('Election guidelines saved and published successfully!'),
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
            content: Text('Failed to save guidelines: ${e.response?.data ?? e.message}'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _insertTemplate(String template) {
    final currentText = _guidelinesController.text;
    if (currentText.trim().isNotEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Append or Replace?'),
          content: const Text('Do you want to append this template to your current guidelines or replace the existing content?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                setState(() {
                  _guidelinesController.text = '$currentText\n\n$template';
                });
              },
              child: const Text('Append to End'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                setState(() {
                  _guidelinesController.text = template;
                });
              },
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              child: const Text('Replace Content'),
            ),
          ],
        ),
      );
    } else {
      setState(() {
        _guidelinesController.text = template;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user = ref.watch(authProvider).user;
    final canManage = user?.canManageElections ?? false;
    final canPop = Navigator.of(context).canPop();
    final shouldShowAppBar = widget.showAppBar ?? canPop;
    final guidelinesText = _guidelinesController.text.trim();

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
                  // Top Header & Action Toolbar
                  _buildHeader(context, isDark, canManage),
                  const SizedBox(height: 16),

                  // Main Content Area
                  Expanded(
                    child: canManage && !_isPreviewMode
                        ? _buildEditor(context, isDark)
                        : _buildViewer(context, isDark, guidelinesText),
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
              Text('Election Guidelines (निर्देशिका)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Text('आधिकारिक आचारसंहिता तथा नियमहरू', style: TextStyle(fontSize: 11, color: Colors.white70)),
            ],
          ),
          leading: canPop
              ? IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded),
                  onPressed: () => Navigator.pop(context),
                )
              : null,
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
              'Election Guidelines & Code of Conduct',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 2),
            Text(
              canManage
                  ? 'Define official election regulations, campaigning rules, and voter directives.'
                  : 'Official statutory rules, voting regulations, and code of conduct for this election.',
              style: TextStyle(color: isDark ? Colors.white60 : AppColors.textMuted, fontSize: 13),
            ),
          ],
        ),
        if (canManage)
          Row(
            children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment<bool>(
                    value: false,
                    icon: Icon(Icons.edit_note_rounded, size: 18),
                    label: Text('Edit'),
                  ),
                  ButtonSegment<bool>(
                    value: true,
                    icon: Icon(Icons.preview_rounded, size: 18),
                    label: Text('Preview'),
                  ),
                ],
                selected: {_isPreviewMode},
                onSelectionChanged: (val) => setState(() => _isPreviewMode = val.first),
                style: SegmentedButton.styleFrom(
                  selectedBackgroundColor: AppColors.primary.withValues(alpha: 0.15),
                  selectedForegroundColor: AppColors.primaryLight,
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildEditor(BuildContext context, bool isDark) {
    return Container(
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
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Quick Template Chips
            Row(
              children: [
                const Icon(Icons.auto_awesome_rounded, size: 16, color: AppColors.primaryLight),
                const SizedBox(width: 6),
                const Text('Quick Standard Templates:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(width: 10),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        ActionChip(
                          avatar: const Icon(Icons.gavel_rounded, size: 14),
                          label: const Text('Code of Conduct (आचारसंहिता)', style: TextStyle(fontSize: 11.5)),
                          onPressed: () => _insertTemplate(
                            '# Election Code of Conduct & Regulations\n\n'
                            '## 1. General Principles (सामान्य सिद्धान्तहरू)\n'
                            'All candidates, electors, and committee members must adhere to fair, democratic, and transparent electoral conduct.\n\n'
                            '## 2. Campaigning Ethics (प्रचार-प्रसार)\n'
                            '- Campaigning must cease 24 hours prior to the commencement of voting (Silence Period).\n'
                            '- Defamatory, coercive, or fraudulent statements are strictly prohibited.\n\n'
                            '## 3. Voter Confidentiality (गोपनीयता)\n'
                            'The secrecy of the electronic ballot is inviolable. No elector may be compelled to disclose their vote.\n\n'
                            '## 4. Scrutiny & Objections (दाबी-विरोध)\n'
                            'All disputes regarding voter eligibility or candidate nominations must be formally filed within the statutory schedule window.',
                          ),
                        ),
                        const SizedBox(width: 8),
                        ActionChip(
                          avatar: const Icon(Icons.how_to_vote_rounded, size: 14),
                          label: const Text('Secret Ballot Protocol (मतदान नियम)', style: TextStyle(fontSize: 11.5)),
                          onPressed: () => _insertTemplate(
                            '# Electronic Voting & Ballot Protocol\n\n'
                            '## 1. Voter Verification\n'
                            'Electors must authenticate using their authorized organization credentials and OTP/Password verification.\n\n'
                            '## 2. Casting Ballot\n'
                            '- Voters may select approved candidates according to the seat allocation for each contested office.\n'
                            '- Voters retain the statutory right to cast "No Vote / Boycott (बहिष्कार)" if they choose to abstain.\n\n'
                            '## 3. Cryptographic Receipt\n'
                            'Upon submission, each elector will receive a 64-character SHA-256 digital fingerprint to verify ballot inclusion in the tally roll.',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Editor Field
            Expanded(
              child: TextField(
                controller: _guidelinesController,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: const TextStyle(fontSize: 14, height: 1.6),
                decoration: InputDecoration(
                  labelText: 'Guidelines Content (Markdown supported)',
                  hintText: 'Enter statutory rules, code of conduct clauses, campaign deadlines, and voting procedures...',
                  alignLabelWithHint: true,
                  filled: true,
                  fillColor: isDark ? AppColors.surfaceVariant.withValues(alpha: 0.3) : const Color(0xFFF9FAFB),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade300),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Save Action
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                LoadingButton(
                  onPressed: _saveGuidelines,
                  isLoading: _isSaving,
                  label: 'Save & Publish Guidelines',
                  icon: Icons.save_rounded,
                  fullWidth: false,
                  backgroundColor: const Color(0xFF4F46E5),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildViewer(BuildContext context, bool isDark, String content) {
    if (content.isEmpty) {
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
                child: const Icon(Icons.menu_book_outlined, size: 48, color: AppColors.primaryLight),
              ),
              const SizedBox(height: 16),
              const Text('No Guidelines Published Yet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(
                'Official election directives, voting procedures, and code of conduct will appear here once published by the committee.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: isDark ? Colors.white60 : Colors.grey.shade600),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header toolbar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? AppColors.surfaceVariant.withValues(alpha: 0.3) : const Color(0xFFF8FAFC),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(17)),
              border: Border(bottom: BorderSide(color: isDark ? Colors.white10 : Colors.grey.shade200)),
            ),
            child: Row(
              children: [
                const Icon(Icons.verified_rounded, size: 18, color: Color(0xFF10B981)),
                const SizedBox(width: 8),
                const Text(
                  'Official Statutory Document (आधिकारिक निर्देशिका)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  tooltip: 'Copy Document',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: content));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Guidelines text copied to clipboard.'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          // Scrollable Document Body
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: SelectableText(
                content,
                style: TextStyle(
                  fontSize: 14.5,
                  height: 1.7,
                  color: isDark ? Colors.white.withValues(alpha: 0.9) : const Color(0xFF1F2937),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
