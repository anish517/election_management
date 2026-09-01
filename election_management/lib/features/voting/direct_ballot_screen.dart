import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nepali_date_picker/nepali_date_picker.dart';
import 'package:intl/intl.dart';
import '../../core/providers/app_providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/network/api_constants.dart';
import '../../shared/models/models.dart';
import '../candidates/candidate_profile_sheet.dart';
import 'ballot_l10n.dart';

class DirectBallotScreen extends ConsumerStatefulWidget {
  final String directToken;
  const DirectBallotScreen({super.key, required this.directToken});

  @override
  ConsumerState<DirectBallotScreen> createState() => _DirectBallotScreenState();
}

class _DirectBallotScreenState extends ConsumerState<DirectBallotScreen> {
  final PageController _pageController = PageController();
  int _currentIndex = 0;
  bool? _isSinglePage;
  bool _isCasting = false;
  String? _castError;

  // Stopwatch timer
  final Stopwatch _stopwatch = Stopwatch();
  Timer? _timer;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _stopwatch.start();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _elapsed = _stopwatch.elapsed;
      });
    });
  }

  @override
  void dispose() {
    _stopwatch.stop();
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  String get _elapsedStr {
    final m = _elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = _elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Widget _buildLangItem(WidgetRef ref, BallotLanguage lang, String label, bool isDark) {
    final currentLang = ref.watch(ballotLanguageProvider);
    final isSelected = currentLang == lang;
    return InkWell(
      onTap: () => ref.read(ballotLanguageProvider.notifier).state = lang,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
            color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
          ),
        ),
      ),
    );
  }

  Future<void> _submitDirectBallot(DirectBallotData data, BallotL10n l10n) async {
    final selections = ref.read(ballotSelectionsProvider);

    // Check if any position is unvoted
    final unvotedPositions = <String>[];
    for (final pos in data.positions) {
      final chosen = selections[pos.id] ?? [];
      final isNoVote = ref.read(ballotSelectionsProvider.notifier).isNoVote(pos.id);
      if (chosen.isEmpty && !isNoVote) {
        unvotedPositions.add(pos.title);
      }
    }

    if (unvotedPositions.isNotEmpty) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 24),
              SizedBox(width: 10),
              Text('Incomplete Ballot (अपूर्ण मतपत्र)'),
            ],
          ),
          content: Text(
            'You have not made a choice for:\n• ${unvotedPositions.join("\n• ")}\n\nDo you want to proceed and cast your ballot anyway?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Go Back'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Proceed & Cast'),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }

    if (!mounted) return;

    // Final Confirmation Dialog
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          backgroundColor: isDark ? AppColors.surface : Colors.white,
          contentPadding: const EdgeInsets.all(0),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.1),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  border: Border(bottom: BorderSide(color: const Color(0xFF10B981).withValues(alpha: 0.2))),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        SizedBox(width: 28, height: 28, child: CustomPaint(painter: const _SwastikPainter(color: Color(0xFF10B981)))),
                        const Expanded(
                          child: Column(
                            children: [
                              Text('Final Confirmation', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              Text('अन्तिम पुष्टि', style: TextStyle(fontSize: 11, color: Color(0xFF10B981), fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                        SizedBox(width: 28, height: 28, child: CustomPaint(painter: const _SwastikPainter(color: Color(0xFF10B981)))),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.lock_outline_rounded, color: AppColors.primary, size: 32),
                    const SizedBox(height: 10),
                    const Text(
                      'Confirm Official Secret Ballot Submission',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Once cast, this single-use ballot link will be permanently burned and deactivated. Your vote will be recorded with end-to-end cryptographic sealing.',
                      style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.grey.shade700, height: 1.4),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.security_rounded, color: Colors.red, size: 16),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Your vote is secret — no one can link your identity to your cast vote.',
                              style: TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Review Choices'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: () => Navigator.pop(ctx, true),
                        icon: const Icon(Icons.how_to_vote_rounded, size: 18),
                        label: const Text('Cast Official Ballot', style: TextStyle(fontWeight: FontWeight.bold)),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );

    if (confirmed != true) return;

    setState(() {
      _isCasting = true;
      _castError = null;
    });

    try {
      final receiptHash = await ref.read(votingServiceProvider).directCastVote(
            directToken: widget.directToken,
            ballotData: selections,
          );

      if (mounted) {
        context.go(
          '/vote/receipt',
          extra: {
            'receipt_hash': receiptHash,
            'election_title': data.electionTitle,
            'voted_at': DateTime.now().toIso8601String(),
          },
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCasting = false;
          _castError = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ballotAsync = ref.watch(directBallotProvider(widget.directToken));
    final selections = ref.watch(ballotSelectionsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ballotLang = ref.watch(ballotLanguageProvider);
    final l10n = BallotL10n(ballotLang);

    return Scaffold(
      backgroundColor: isDark ? AppColors.background : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.secretElectronicBallot,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
            Text(
              'Method 1 Type 2 • Single-Use Direct Web Ballot',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white60 : Colors.grey.shade600,
              ),
            ),
          ],
        ),
        automaticallyImplyLeading: false,
        actions: [
          // Language Switcher
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: isDark ? Colors.white24 : Colors.grey.shade300),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildLangItem(ref, BallotLanguage.bilingual, 'द्विभाषी', isDark),
                  _buildLangItem(ref, BallotLanguage.english, 'EN', isDark),
                  _buildLangItem(ref, BallotLanguage.nepali, 'नेपाली', isDark),
                ],
              ),
            ),
          ),

          // View Mode Switcher
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: isDark ? Colors.white24 : Colors.grey.shade300),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    onTap: () => setState(() => _isSinglePage = true),
                    borderRadius: const BorderRadius.horizontal(left: Radius.circular(9)),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: (_isSinglePage ?? true) ? AppColors.primary : Colors.transparent,
                        borderRadius: const BorderRadius.horizontal(left: Radius.circular(9)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.article_outlined, size: 14, color: (_isSinglePage ?? true) ? Colors.white : (isDark ? Colors.white70 : Colors.black87)),
                          const SizedBox(width: 4),
                          Text(
                            l10n.allInOneView,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: (_isSinglePage ?? true) ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () => setState(() => _isSinglePage = false),
                    borderRadius: const BorderRadius.horizontal(right: Radius.circular(9)),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: (_isSinglePage == false) ? AppColors.primary : Colors.transparent,
                        borderRadius: const BorderRadius.horizontal(right: Radius.circular(9)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.view_carousel_outlined, size: 14, color: (_isSinglePage == false) ? Colors.white : (isDark ? Colors.white70 : Colors.black87)),
                          const SizedBox(width: 4),
                          Text(
                            l10n.wizardView,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: (_isSinglePage == false) ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
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

          // Duration Stopwatch
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: isDark ? Colors.white24 : Colors.grey.shade300),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.timer_outlined, size: 15, color: isDark ? Colors.white70 : const Color(0xFF475569)),
                    const SizedBox(width: 5),
                    Text(
                      l10n.elapsedTimer(_elapsedStr),
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: ballotAsync.when(
        loading: () => const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Decrypting and loading official ballot...'),
            ],
          ),
        ),
        error: (err, stack) {
          final errStr = err.toString().toLowerCase();
          final isNotFound = errStr.contains('404') || errStr.contains('not found');
          final isUsedOrExpired = errStr.contains('410') ||
              errStr.contains('used') ||
              errStr.contains('expired');

          String displayTitle = 'Unable to Open Ballot';
          String displayMsg;

          if (isUsedOrExpired) {
            displayTitle = 'Single-Use Link Deactivated';
            displayMsg = 'This single-use ballot link has already been used or has expired. To maintain electoral integrity, each ballot token can only be cast once.';
          } else if (isNotFound) {
            displayTitle = 'Invalid Ballot Token';
            displayMsg = 'This single-use ballot link is invalid or was not found. Please request a fresh verification link from the election overview page.';
          } else {
            displayMsg = 'Unable to securely connect to the election server. Please check your network connection and try again.';
          }

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Card(
                margin: const EdgeInsets.all(24),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                elevation: 3,
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: (isUsedOrExpired || isNotFound) ? Colors.amber.withValues(alpha: 0.12) : Colors.red.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          (isUsedOrExpired || isNotFound) ? Icons.lock_clock_rounded : Icons.error_outline_rounded,
                          color: (isUsedOrExpired || isNotFound) ? Colors.amber.shade800 : Colors.red,
                          size: 48,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        displayTitle,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        displayMsg,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13.5,
                          color: isDark ? Colors.white70 : Colors.black87,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.home_rounded, size: 18),
                        label: const Text('Return to Home'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () => context.go('/login'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
        data: (data) {
          final positions = data.positions;
          if (positions.isEmpty) {
            return const Center(
              child: Text('No positions available on this ballot.', style: TextStyle(fontSize: 14, color: AppColors.textMuted)),
            );
          }

          if (_isSinglePage == null) {
            final totalCands = positions.fold<int>(0, (sum, p) => sum + p.candidates.length);
            _isSinglePage = positions.length <= 3 || totalCands <= 8;
          }

          if (_isSinglePage == true) {
            return _buildSinglePageLayout(context, data, positions, selections, isDark, l10n);
          }

          return _buildWizardLayout(context, data, positions, selections, isDark, l10n);
        },
      ),
    );
  }

  Widget _buildSinglePageLayout(
    BuildContext context,
    DirectBallotData data,
    List<PositionModel> positions,
    Map<String, List<String>> selections,
    bool isDark,
    BallotL10n l10n,
  ) {
    final completedCount = ref.read(ballotSelectionsProvider.notifier).completedContestsCount(positions);
    final allDecided = completedCount == positions.length;

    return Column(
      children: [
        if (_castError != null)
          Container(
            width: double.infinity,
            color: Colors.red.shade700,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(_castError!, style: const TextStyle(color: Colors.white, fontSize: 13))),
              ],
            ),
          ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              children: [
                _buildOfficialHeader(data, isDark, l10n),
                ...positions.map(
                  (p) => Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: _DirectPositionCard(
                      position: p,
                      allowBoycott: data.allowBoycott,
                      enableParty: data.enableParty,
                      enablePanel: data.enablePanel,
                      enableSymbol: data.enableSymbol,
                      enableCandidatePhoto: data.enableCandidatePhoto,
                      electionType: data.electionType,
                      l10n: l10n,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),

        // Bottom Action Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: BoxDecoration(
            color: isDark ? AppColors.surface : Colors.white,
            border: Border(top: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade200)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, -3),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: allDecided ? Colors.green.withValues(alpha: 0.12) : AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: allDecided ? Colors.green.withValues(alpha: 0.3) : AppColors.primary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(allDecided ? Icons.check_circle_rounded : Icons.info_outline_rounded, size: 16, color: allDecided ? Colors.green : AppColors.primaryLight),
                      const SizedBox(width: 8),
                      Text(
                        l10n.contestsDecidedCount(completedCount, positions.length),
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: allDecided ? Colors.green : AppColors.primaryLight),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _isCasting ? null : () => _submitDirectBallot(data, l10n),
                  icon: _isCasting
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.how_to_vote_rounded, size: 18),
                  label: Text(
                    _isCasting ? (l10n.isNepali ? 'मतदान दर्ता हुँदैछ...' : 'Submitting Ballot...') : l10n.reviewAndSignBallot,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWizardLayout(
    BuildContext context,
    DirectBallotData data,
    List<PositionModel> positions,
    Map<String, List<String>> selections,
    bool isDark,
    BallotL10n l10n,
  ) {
    final progressValue = (_currentIndex + 1) / positions.length;
    final isLastStep = _currentIndex == positions.length - 1;

    return Column(
      children: [
        Container(
          color: isDark ? AppColors.surface : Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          l10n.contestStepProgress(_currentIndex + 1, positions.length),
                          style: const TextStyle(color: AppColors.primaryLight, fontWeight: FontWeight.bold, fontSize: 11.5),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        l10n.translatePositionTitle(positions[_currentIndex].title),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ],
                  ),
                  Text(
                    l10n.percentCompleted((progressValue * 100).toInt()),
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: isDark ? Colors.white60 : Colors.grey.shade600),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progressValue,
                  minHeight: 6,
                  backgroundColor: isDark ? AppColors.surfaceVariant : const Color(0xFFE2E8F0),
                  valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primaryLight),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            physics: const NeverScrollableScrollPhysics(),
            onPageChanged: (idx) => setState(() => _currentIndex = idx),
            itemCount: positions.length,
            itemBuilder: (context, i) {
              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Column(
                  children: [
                    if (i == 0) _buildOfficialHeader(data, isDark, l10n),
                    _DirectPositionCard(
                      position: positions[i],
                      allowBoycott: data.allowBoycott,
                      enableParty: data.enableParty,
                      enablePanel: data.enablePanel,
                      enableSymbol: data.enableSymbol,
                      enableCandidatePhoto: data.enableCandidatePhoto,
                      electionType: data.electionType,
                      l10n: l10n,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        // Wizard Controls
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: BoxDecoration(
            color: isDark ? AppColors.surface : Colors.white,
            border: Border(top: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade200)),
          ),
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                if (_currentIndex > 0)
                  OutlinedButton.icon(
                    onPressed: () => _pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut),
                    icon: const Icon(Icons.arrow_back_ios_rounded, size: 14),
                    label: Text(l10n.previousContest),
                  ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: isLastStep
                      ? () => _submitDirectBallot(data, l10n)
                      : () => _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut),
                  icon: Icon(isLastStep ? Icons.how_to_vote_rounded : Icons.arrow_forward_ios_rounded, size: 16),
                  label: Text(isLastStep ? l10n.reviewAndSignBallot : l10n.nextContest, style: const TextStyle(fontWeight: FontWeight.bold)),
                  style: FilledButton.styleFrom(
                    backgroundColor: isLastStep ? const Color(0xFF10B981) : AppColors.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOfficialHeader(DirectBallotData data, bool isDark, BallotL10n l10n) {
    final now = DateTime.now();
    final nepaliNow = now.toNepaliDateTime();
    final nepaliDateStr = '${NepaliDateFormat('yyyy/MM/dd').format(nepaliNow)} BS (${NepaliDateFormat('MMM d, yyyy').format(nepaliNow)})';
    final engDateStr = DateFormat('yyyy/MM/dd (MMM d, yyyy)').format(now);
    final nepaliDateFormatted = '${BallotL10n.toNepaliDigits(NepaliDateFormat('yyyy/MM/dd').format(nepaliNow))} वि.सं.';
    final votingDate = l10n.isEnglish ? engDateStr : (l10n.isNepali ? nepaliDateFormatted : nepaliDateStr);
    final votingTime = l10n.isNepali ? BallotL10n.toNepaliDigits(DateFormat('hh:mm a').format(now)) : DateFormat('hh:mm a').format(now);

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFFB91C1C).withValues(alpha: 0.4) : const Color(0xFFE2E8F0),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black.withValues(alpha: 0.25) : const Color(0xFFB91C1C).withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Top Red Stamp Banner with Swastik
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              gradient: isDark
                  ? const LinearGradient(colors: [Color(0xFF331317), Color(0xFF1E293B)], begin: Alignment.topLeft, end: Alignment.bottomRight)
                  : const LinearGradient(colors: [Color(0xFFFFF7ED), Color(0xFFFFFAF0)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
              border: Border(bottom: BorderSide(color: isDark ? Colors.white10 : const Color(0xFFB91C1C).withValues(alpha: 0.15))),
            ),
            child: Row(
              children: [
                SizedBox(width: 38, height: 38, child: CustomPaint(painter: const _SwastikPainter(color: Color(0xFFB91C1C)))),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFB91C1C).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFB91C1C).withValues(alpha: 0.25)),
                        ),
                        child: Text(
                          l10n.officialBallotBadge,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: Color(0xFFB91C1C), letterSpacing: 1.2),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(data.electionTitle, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(width: 38, height: 38, child: CustomPaint(painter: const _SwastikPainter(color: Color(0xFFB91C1C)))),
              ],
            ),
          ),

          // Metadata Grid: 4 items (Voter Name, Voter ID, Date, Time)
          Padding(
            padding: const EdgeInsets.all(16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 768;
                return Column(
                  children: [
                    if (isWide)
                      Row(
                        children: [
                          Expanded(child: _buildInfoCard(l10n.voterNameLabel, data.voterName.isNotEmpty ? data.voterName : l10n.authenticatedVoter, Icons.person_rounded, isDark)),
                          const SizedBox(width: 12),
                          Expanded(child: _buildInfoCard(l10n.voterIdLabel, data.voterId.isNotEmpty ? data.voterId : '—', Icons.badge_outlined, isDark)),
                          const SizedBox(width: 12),
                          Expanded(child: _buildInfoCard(l10n.votingDateLabel, votingDate, Icons.calendar_today_outlined, isDark)),
                          const SizedBox(width: 12),
                          Expanded(child: _buildInfoCard(l10n.votingTimeLabel, votingTime, Icons.access_time_rounded, isDark)),
                        ],
                      )
                    else ...[
                      Row(
                        children: [
                          Expanded(child: _buildInfoCard(l10n.voterNameLabel, data.voterName.isNotEmpty ? data.voterName : l10n.authenticatedVoter, Icons.person_rounded, isDark)),
                          const SizedBox(width: 10),
                          Expanded(child: _buildInfoCard(l10n.voterIdLabel, data.voterId.isNotEmpty ? data.voterId : '—', Icons.badge_outlined, isDark)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(child: _buildInfoCard(l10n.votingDateLabel, votingDate, Icons.calendar_today_outlined, isDark)),
                          const SizedBox(width: 10),
                          Expanded(child: _buildInfoCard(l10n.votingTimeLabel, votingTime, Icons.access_time_rounded, isDark)),
                        ],
                      ),
                    ],
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.verified_user_outlined, size: 15, color: isDark ? Colors.blue.shade300 : const Color(0xFF2563EB)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'End-to-End Cryptographically Sealed Ballot • Single-Use Magic Link',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: isDark ? Colors.white70 : const Color(0xFF475569)),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(String label, String value, IconData icon, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A).withValues(alpha: 0.6) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFFB91C1C).withValues(alpha: 0.2) : const Color(0xFFB91C1C).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: isDark ? const Color(0xFFFCA5A5) : const Color(0xFFB91C1C)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: isDark ? Colors.white54 : const Color(0xFF64748B))),
                const SizedBox(height: 2),
                Text(value, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: isDark ? Colors.white : const Color(0xFF0F172A)), overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DirectPositionCard extends ConsumerStatefulWidget {
  final PositionModel position;
  final bool allowBoycott;
  final BallotL10n l10n;
  final bool enableParty;
  final bool enablePanel;
  final bool enableSymbol;
  final bool enableCandidatePhoto;
  final String electionType;

  const _DirectPositionCard({
    required this.position,
    required this.allowBoycott,
    required this.l10n,
    this.enableParty = true,
    this.enablePanel = true,
    this.enableSymbol = true,
    this.enableCandidatePhoto = true,
    this.electionType = 'fptp',
  });

  @override
  ConsumerState<_DirectPositionCard> createState() => _DirectPositionCardState();
}

class _DirectPositionCardState extends ConsumerState<_DirectPositionCard> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final selections = ref.watch(ballotSelectionsProvider);
    final position = widget.position;
    final l10n = widget.l10n;
    final positionSelections = selections[position.id] ?? [];
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surface : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? AppColors.surfaceVariant : Colors.grey.shade200),
        boxShadow: [
          if (!isDark)
            BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 14, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Position Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? AppColors.surfaceVariant.withValues(alpha: 0.3) : const Color(0xFFF8FAFC),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(19)),
              border: Border(bottom: BorderSide(color: isDark ? Colors.white10 : Colors.grey.shade200)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.military_tech_rounded, color: AppColors.primaryLight, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.translatePositionTitle(position.title), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                      const SizedBox(height: 2),
                      Text(
                        position.isSamanupatik
                            ? (l10n.isEnglish
                                ? 'Select 1 Political Party / Symbol'
                                : (l10n.isNepali
                                    ? '१ राजनीतिक दल वा चुनाव चिन्ह छनोट गर्नुहोस्'
                                    : 'Select 1 Political Party / Symbol (१ राजनीतिक दल वा चुनाव चिन्ह छनोट गर्नुहोस्)'))
                            : l10n.selectionInstruction(position.effectiveMaxVotes),
                        style: TextStyle(color: isDark ? Colors.white60 : AppColors.textMuted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                // Counter Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: positionSelections.length == position.effectiveMaxVotes
                        ? Colors.green.withValues(alpha: 0.15)
                        : (positionSelections.isNotEmpty ? AppColors.primaryLight.withValues(alpha: 0.12) : (isDark ? Colors.white10 : Colors.grey.shade100)),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: positionSelections.length == position.effectiveMaxVotes
                          ? Colors.green
                          : (positionSelections.isNotEmpty ? AppColors.primaryLight.withValues(alpha: 0.3) : (isDark ? Colors.white24 : Colors.grey.shade300)),
                    ),
                  ),
                  child: Text(
                    l10n.selectedCounter(positionSelections.length, position.effectiveMaxVotes),
                    style: TextStyle(
                      color: positionSelections.length == position.effectiveMaxVotes ? Colors.green : (positionSelections.isNotEmpty ? AppColors.primaryLight : (isDark ? Colors.white60 : Colors.grey.shade700)),
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // In-Contest Search Filter (for positions with 8 or more candidates)
          if (position.candidates.length >= 8)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: TextField(
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search, size: 18),
                  hintText: l10n.isNepali ? 'उम्मेदवार खोज्नुहोस् (नाम वा घोषणापत्र)...' : 'Search candidates by name, number, or manifesto...',
                  hintStyle: TextStyle(fontSize: 13, color: isDark ? Colors.white38 : Colors.grey.shade500),
                  filled: true,
                  fillColor: isDark ? AppColors.surfaceVariant.withValues(alpha: 0.3) : const Color(0xFFF8FAFC),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade300),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade300),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                  ),
                ),
                onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
              ),
            ),

          // Candidates Grid
          Padding(
            padding: const EdgeInsets.all(20),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final filteredCandidates = _searchQuery.isEmpty
                    ? position.candidates
                    : position.candidates.where((c) {
                        final name = c.name.toLowerCase();
                        final manifesto = c.manifesto.toLowerCase();
                        return name.contains(_searchQuery) || manifesto.contains(_searchQuery);
                      }).toList();

                if (filteredCandidates.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        l10n.isNepali ? 'कुनै मिल्दो उम्मेदवार भेटिएन।' : 'No candidates match your search.',
                        style: TextStyle(color: isDark ? Colors.white60 : Colors.grey.shade600, fontSize: 13),
                      ),
                    ),
                  );
                }

                int crossAxisCount;
                if (constraints.maxWidth >= 1500) {
                  crossAxisCount = 4;
                } else if (constraints.maxWidth >= 1100) {
                  crossAxisCount = 3;
                } else if (constraints.maxWidth >= 680) {
                  crossAxisCount = 2;
                } else {
                  crossAxisCount = 1;
                }
                const spacing = 20.0;
                final totalSpacing = spacing * (crossAxisCount - 1);
                final itemWidth = (constraints.maxWidth - totalSpacing) / crossAxisCount;

                return Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: filteredCandidates.map((candidate) {
                    final isSelected = positionSelections.contains(candidate.id);
                    return SizedBox(
                      width: itemWidth,
                      child: _DirectCandidateTile(
                        candidate: candidate,
                        isSelected: isSelected,
                        l10n: l10n,
                        enableParty: widget.enableParty,
                        enablePanel: widget.enablePanel,
                        enableSymbol: widget.enableSymbol,
                        enableCandidatePhoto: widget.enableCandidatePhoto,
                        electionType: widget.electionType,
                        onTap: () {
                          ref.read(ballotSelectionsProvider.notifier).toggleCandidate(
                                positionId: position.id,
                                candidateId: candidate.id,
                                maxSeats: position.effectiveMaxVotes,
                              );
                        },
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ),

          // NOTA Card
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: _DirectNoVoteTile(
              isNoVote: ref.read(ballotSelectionsProvider.notifier).isNoVote(position.id),
              l10n: l10n,
              onTap: () {
                ref.read(ballotSelectionsProvider.notifier).toggleNoVote(position.id);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DirectCandidateTile extends StatelessWidget {
  final CandidateModel candidate;
  final bool isSelected;
  final VoidCallback onTap;
  final BallotL10n l10n;
  final bool enableParty;
  final bool enablePanel;
  final bool enableSymbol;
  final bool enableCandidatePhoto;
  final String electionType;

  const _DirectCandidateTile({
    required this.candidate,
    required this.isSelected,
    required this.onTap,
    required this.l10n,
    this.enableParty = true,
    this.enablePanel = true,
    this.enableSymbol = true,
    this.enableCandidatePhoto = true,
    this.electionType = 'fptp',
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const stampColor = Color(0xFFB91C1C);
    final primaryColor = isSelected ? stampColor : AppColors.primary;

    final fullPhotoUrl = ApiConstants.getFullImageUrl(candidate.photoUrl);
    final hasValidPhoto = enableCandidatePhoto && (fullPhotoUrl != null && fullPhotoUrl.isNotEmpty);
    final hasSymbolImage = enableSymbol && candidate.symbolImage.trim().isNotEmpty;
    final hasSymbolName = enableSymbol && candidate.symbolName.trim().isNotEmpty;
    final hasParty = enableParty && candidate.partyName.trim().isNotEmpty;
    final panelText = candidate.panelName.trim().isNotEmpty
        ? candidate.panelName.trim()
        : candidate.slateName.trim();
    final hasPanel = enablePanel && panelText.isNotEmpty;
    final isSamanupatik = electionType.toLowerCase() == 'samanupatik' || electionType.toLowerCase() == 'pr';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isSelected
              ? stampColor.withValues(alpha: isDark ? 0.12 : 0.06)
              : (isDark ? AppColors.surfaceVariant.withValues(alpha: 0.4) : const Color(0xFFFAFAFA)),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? stampColor : (isDark ? Colors.white12 : Colors.grey.shade300),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: stampColor.withValues(alpha: 0.15),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
          ],
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Candidate Portrait / Large Symbol Box
                  _buildVisualBox(context, isDark, hasValidPhoto, fullPhotoUrl, hasSymbolImage, hasSymbolName),
                  const SizedBox(width: 14),

                  // Candidate Details
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Name & Symbol Badge
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                candidate.name,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15.5,
                                  letterSpacing: -0.2,
                                  color: isSelected ? stampColor : (isDark ? Colors.white : const Color(0xFF0F172A)),
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (hasSymbolName) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF59E0B).withValues(alpha: isDark ? 0.2 : 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.how_to_vote_rounded, size: 12, color: Color(0xFFD97706)),
                                    const SizedBox(width: 4),
                                    Text(
                                      candidate.symbolName,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: isDark ? const Color(0xFFFDE68A) : const Color(0xFFB45309),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),

                        // Badges Row: Party, Slate/Panel, Quota, PR Rank
                        if (hasParty || hasPanel || (candidate.quotaName != null && candidate.quotaName!.isNotEmpty) || (isSamanupatik && candidate.prRank > 0)) ...[
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 5,
                            children: [
                              if (hasParty)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF1E3A8A).withValues(alpha: 0.35) : const Color(0xFFEFF6FF),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: isDark ? const Color(0xFF3B82F6).withValues(alpha: 0.5) : const Color(0xFF93C5FD)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.flag_rounded, size: 12, color: isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB)),
                                      const SizedBox(width: 4.5),
                                      Text(
                                        candidate.partyName,
                                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: isDark ? const Color(0xFFBFDBFE) : const Color(0xFF1D4ED8)),
                                      ),
                                    ],
                                  ),
                                ),
                              if (hasPanel)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF581C87).withValues(alpha: 0.35) : const Color(0xFFFAF5FF),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: isDark ? const Color(0xFF8B5CF6).withValues(alpha: 0.5) : const Color(0xFFC4B5FD)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.groups_rounded, size: 12, color: isDark ? const Color(0xFFA78BFA) : const Color(0xFF7C3AED)),
                                      const SizedBox(width: 4.5),
                                      Text(
                                        panelText,
                                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: isDark ? const Color(0xFFE9D5FF) : const Color(0xFF6D28D9)),
                                      ),
                                    ],
                                  ),
                                ),
                              if (candidate.quotaName != null && candidate.quotaName!.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                  decoration: BoxDecoration(
                                    color: Colors.teal.withValues(alpha: isDark ? 0.2 : 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: Colors.teal.withValues(alpha: 0.4)),
                                  ),
                                  child: Text(
                                    candidate.quotaName!,
                                    style: TextStyle(color: isDark ? Colors.teal.shade200 : Colors.teal.shade800, fontSize: 10.5, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              if (isSamanupatik && candidate.prRank > 0)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                  decoration: BoxDecoration(
                                    color: Colors.indigo.withValues(alpha: isDark ? 0.25 : 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: Colors.indigo.withValues(alpha: 0.4)),
                                  ),
                                  child: Text(
                                    l10n.isNepali ? 'समानुपातिक #${BallotL10n.toNepaliDigits(candidate.prRank)}' : 'PR Rank #${candidate.prRank}',
                                    style: TextStyle(color: isDark ? Colors.indigo.shade200 : Colors.indigo.shade800, fontSize: 10.5, fontWeight: FontWeight.bold),
                                  ),
                                ),
                            ],
                          ),
                        ],

                        if (candidate.manifesto.trim().isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            candidate.manifesto.trim(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white70 : const Color(0xFF475569),
                              height: 1.35,
                            ),
                          ),
                        ],

                        const SizedBox(height: 8),
                        InkWell(
                          onTap: () => showCandidateProfile(context, candidate),
                          borderRadius: BorderRadius.circular(6),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.info_outline_rounded, size: 13, color: primaryColor),
                              const SizedBox(width: 4),
                              Text(
                                l10n.viewCandidateDossier,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: primaryColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: isSelected
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: stampColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: stampColor, width: 1.5),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CustomPaint(painter: const _SwastikPainter(color: stampColor)),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            l10n.isNepali ? 'छाप लगाइयो' : 'VOTED',
                            style: const TextStyle(color: stampColor, fontSize: 10.5, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    )
                  : Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: isDark ? Colors.white24 : Colors.grey.shade400, width: 1.5),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVisualBox(
    BuildContext context,
    bool isDark,
    bool hasValidPhoto,
    String? fullPhotoUrl,
    bool hasSymbolImage,
    bool hasSymbolName,
  ) {
    const boxSize = 76.0;

    // Case 1: Photo enabled & available
    if (hasValidPhoto) {
      return Stack(
        children: [
          Container(
            width: boxSize,
            height: boxSize,
            decoration: BoxDecoration(
              color: isDark ? AppColors.surfaceVariant : Colors.grey.shade200,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: isDark ? Colors.white24 : Colors.grey.shade300, width: 1),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(13),
              child: Image.network(
                fullPhotoUrl!,
                fit: BoxFit.cover,
                errorBuilder: (ctx, err, stack) => _buildPlaceholder(),
              ),
            ),
          ),
          if (hasSymbolImage)
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 4),
                  ],
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: ClipOval(
                  child: Padding(
                    padding: const EdgeInsets.all(2.5),
                    child: Image.network(
                      candidate.symbolImage,
                      fit: BoxFit.contain,
                      errorBuilder: (ctx, err, stack) => const Icon(Icons.star, size: 14, color: Colors.amber),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    }

    // Case 2: Candidate photo toggled off -> LARGE PARTY/ELECTION SYMBOL IMAGE
    if (hasSymbolImage) {
      return Container(
        width: boxSize,
        height: boxSize,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark ? Colors.white24 : const Color(0xFFCBD5E1),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            candidate.symbolImage,
            fit: BoxFit.contain,
            errorBuilder: (ctx, err, stack) => _buildPlaceholder(),
          ),
        ),
      );
    }

    // Case 3: Symbol name only
    if (hasSymbolName) {
      return Container(
        width: boxSize,
        height: boxSize,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.5),
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.how_to_vote_rounded, size: 28, color: Color(0xFFD97706)),
            const SizedBox(height: 2),
            Text(
              candidate.symbolName,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: isDark ? const Color(0xFFFDE68A) : const Color(0xFFB45309),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Container(
      width: boxSize,
      height: boxSize,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(14)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: _buildPlaceholder(),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Text(
          candidate.name.isNotEmpty ? candidate.name[0].toUpperCase() : '?',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 28),
        ),
      ),
    );
  }
}

class _DirectNoVoteTile extends StatelessWidget {
  final bool isNoVote;
  final VoidCallback onTap;
  final BallotL10n l10n;

  const _DirectNoVoteTile({
    required this.isNoVote,
    required this.onTap,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isNoVote
              ? const Color(0xFFD97706).withValues(alpha: isDark ? 0.15 : 0.08)
              : (isDark ? Colors.white.withValues(alpha: 0.03) : const Color(0xFFFAFAFA)),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isNoVote ? const Color(0xFFD97706) : (isDark ? Colors.white12 : Colors.grey.shade300),
            width: isNoVote ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isNoVote ? const Color(0xFFD97706) : Colors.grey.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.do_not_disturb_alt_rounded,
                size: 18,
                color: isNoVote ? Colors.white : Colors.grey,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.noVoteTitle,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                        ),
                      ),
                      if (isNoVote) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFD97706),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            l10n.abstainedBadge,
                            style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l10n.noVoteSubtitle,
                    style: TextStyle(color: isDark ? Colors.white54 : AppColors.textMuted, fontSize: 11.5),
                  ),
                ],
              ),
            ),
            Checkbox(
              value: isNoVote,
              activeColor: const Color(0xFFD97706),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              onChanged: (_) => onTap(),
            ),
          ],
        ),
      ),
    );
  }
}

class _SwastikPainter extends CustomPainter {
  final Color color;
  const _SwastikPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final double w = size.width;
    final double h = size.height;
    final double t = w / 3;
    final double c = w / 3;

    final path = Path();
    path.addRect(Rect.fromLTWH(t, t, c, c));
    path.addRect(Rect.fromLTWH(t, 0, c, t));
    path.addRect(Rect.fromLTWH(t, h - t, c, t));
    path.addRect(Rect.fromLTWH(0, t, t, c));
    path.addRect(Rect.fromLTWH(w - t, t, t, c));
    path.addRect(Rect.fromLTWH(w - t, 0, t, t));
    path.addRect(Rect.fromLTWH(0, h - t, t, t));

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_SwastikPainter old) => old.color != color;
}
