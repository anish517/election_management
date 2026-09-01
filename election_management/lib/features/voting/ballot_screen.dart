import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nepali_date_picker/nepali_date_picker.dart';
import 'package:intl/intl.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/org_providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/network/api_constants.dart';
import '../../shared/models/models.dart';
import '../candidates/candidate_profile_sheet.dart';
import '../shared/digital_id_card_dialog.dart';
import 'ballot_l10n.dart';

class BallotScreen extends ConsumerStatefulWidget {
  final String electionId;
  const BallotScreen({super.key, required this.electionId});

  @override
  ConsumerState<BallotScreen> createState() => _BallotScreenState();
}

class _BallotScreenState extends ConsumerState<BallotScreen> {
  final PageController _pageController = PageController();
  int _currentIndex = 0;
  bool? _isSinglePage;

  // Voting duration stopwatch & countdown
  final Stopwatch _stopwatch = Stopwatch();
  Timer? _timer;
  Duration _elapsed = Duration.zero;
  int _remainingSeconds = 300;
  bool _countdownInitialized = false;
  bool _timeExpired = false;

  @override
  void initState() {
    super.initState();
    _stopwatch.start();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _elapsed = _stopwatch.elapsed;
        final org = ref.read(orgProfileProvider).valueOrNull;
        if (org?.enableVotingCountdown == true) {
          if (!_countdownInitialized) {
            _remainingSeconds = (org?.votingTimeLimitMinutes ?? 5) * 60;
            _countdownInitialized = true;
          }
          if (_remainingSeconds > 0) {
            _remainingSeconds--;
            if (_remainingSeconds == 0 && !_timeExpired) {
              _timeExpired = true;
              _showTimeExpiredDialog();
            }
          }
        }
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

  String get _countdownStr {
    final m = (_remainingSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (_remainingSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _showTimeExpiredDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          icon: const Icon(Icons.timer_off_rounded, color: Colors.red, size: 48),
          title: const Text(
            'Voting Time Expired\n(मतदान समय समाप्त भयो)',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          content: const Text(
            'Your allotted voting time limit has elapsed. To ensure election integrity, ballot papers must be submitted within the established time frame.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                context.pop();
              },
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              label: const Text('Return to Elections'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE11D48),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _nextPage(int totalPages) {
    if (_currentIndex < totalPages - 1) {
      _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    }
  }

  void _prevPage() {
    if (_currentIndex > 0) {
      _pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    }
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

  @override
  Widget build(BuildContext context) {
    final ballotAsync = ref.watch(ballotDataProvider(widget.electionId));
    final orgAsync = ref.watch(orgProfileProvider);
    final selections = ref.watch(ballotSelectionsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final org = orgAsync.valueOrNull;
    final showDurationTimer = (org?.showVotingDuration == true);
    final enableCountdown = (org?.enableVotingCountdown == true);
    final ballotLang = ref.watch(ballotLanguageProvider);
    final l10n = BallotL10n(ballotLang);

    if (enableCountdown && !_countdownInitialized && org != null) {
      _remainingSeconds = org.votingTimeLimitMinutes * 60;
      _countdownInitialized = true;
    }

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
              l10n.secretElectronicBallotSub,
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white60 : Colors.grey.shade600,
              ),
            ),
          ],
        ),
        leading: IconButton(
          icon: Icon(
            Icons.close_rounded,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
          ),
          onPressed: () => context.pop(),
        ),
        actions: [
          // Language Switcher (Bilingual vs EN vs NE)
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

          // View Mode Switcher: Single-Page vs Wizard
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
                        color: (_isSinglePage ?? true)
                            ? AppColors.primary
                            : Colors.transparent,
                        borderRadius: const BorderRadius.horizontal(left: Radius.circular(9)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.article_outlined,
                            size: 14,
                            color: (_isSinglePage ?? true) ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                          ),
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
                        color: (_isSinglePage == false)
                            ? AppColors.primary
                            : Colors.transparent,
                        borderRadius: const BorderRadius.horizontal(right: Radius.circular(9)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.view_carousel_outlined,
                            size: 14,
                            color: (_isSinglePage == false) ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                          ),
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

          // Elapsed Stopwatch Badge (if enabled)
          if (showDurationTimer)
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
                      Icon(
                        Icons.timer_outlined,
                        size: 15,
                        color: isDark ? Colors.white70 : const Color(0xFF475569),
                      ),
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

          // Remaining Time Countdown Badge (if enabled)
          if (enableCountdown)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                  decoration: BoxDecoration(
                    color: _remainingSeconds < 60
                        ? (isDark ? const Color(0xFF7F1D1D).withValues(alpha: 0.6) : const Color(0xFFFEE2E2))
                        : (_remainingSeconds < 120
                            ? (isDark ? const Color(0xFF78350F).withValues(alpha: 0.6) : const Color(0xFFFEF3C7))
                            : (isDark ? const Color(0xFF1E293B) : const Color(0xFFEFF6FF))),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _remainingSeconds < 60
                          ? const Color(0xFFEF4444)
                          : (_remainingSeconds < 120 ? const Color(0xFFF59E0B) : (isDark ? Colors.blue.shade700 : const Color(0xFF3B82F6))),
                      width: 1.5,
                    ),
                    boxShadow: [
                      if (_remainingSeconds < 60)
                        BoxShadow(
                          color: const Color(0xFFEF4444).withValues(alpha: 0.25),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.hourglass_top_rounded,
                        size: 15,
                        color: _remainingSeconds < 60
                            ? (isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626))
                            : (_remainingSeconds < 120
                                ? (isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706))
                                : (isDark ? Colors.blue.shade300 : const Color(0xFF2563EB))),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        l10n.countdownTimer(_countdownStr),
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: _remainingSeconds < 60
                              ? (isDark ? const Color(0xFFFCA5A5) : const Color(0xFF991B1B))
                              : (_remainingSeconds < 120
                                  ? (isDark ? const Color(0xFFFDE68A) : const Color(0xFF92400E))
                                  : (isDark ? Colors.blue.shade100 : const Color(0xFF1E40AF))),
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
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 48),
              const SizedBox(height: 16),
              Text('Cannot Load Ballot', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(e.toString(), style: const TextStyle(color: AppColors.textMuted, fontSize: 13), textAlign: TextAlign.center),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => context.pop(),
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('Go Back'),
              ),
            ],
          ),
        ),
        data: (ballotData) {
          // 1. Admin / non-voter block
          if (ballotData.notEligible) {
            return _buildNotEligibleScreen(context, ballotData.notEligibleReason, isDark);
          }

          // 2. Already voted
          if (ballotData.hasVoted) {
            return _buildAlreadyVotedScreen(context, isDark);
          }

          final positions = ballotData.positions;
          final allowBoycott = ballotData.allowBoycott;

          if (positions.isEmpty) {
            return const Center(
              child: Text('No positions available on this ballot.', style: TextStyle(fontSize: 14, color: AppColors.textMuted)),
            );
          }

          // Auto-default to Single-Page view if minimum candidates (<= 8) or positions (<= 3)
          if (_isSinglePage == null) {
            final totalCands = positions.fold<int>(0, (sum, p) => sum + p.candidates.length);
            _isSinglePage = positions.length <= 3 || totalCands <= 8;
          }

          if (_isSinglePage == true) {
            return _buildSinglePageBallot(context, ref, positions, allowBoycott, selections, isDark, l10n);
          }

          return _buildWizardBallot(context, ref, positions, allowBoycott, selections, isDark, l10n);
        },
      ),
    );
  }

  Widget _buildSinglePageBallot(
    BuildContext context,
    WidgetRef ref,
    List<PositionModel> positions,
    bool allowBoycott,
    Map<String, List<String>> selections,
    bool isDark,
    BallotL10n l10n,
  ) {
    final completedCount = ref.read(ballotSelectionsProvider.notifier).completedContestsCount(positions);
    final allDecided = completedCount == positions.length;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              children: [
                _buildBallotHeader(context, positions, allowBoycott, isDark, l10n),
                ...positions.map(
                  (p) => Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: _BallotPositionCard(
                      position: p,
                      electionId: widget.electionId,
                      allowBoycott: allowBoycott,
                      l10n: l10n,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),

        // Single-Page Fixed Bottom Action Bar
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
                    color: allDecided
                        ? Colors.green.withValues(alpha: 0.12)
                        : AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: allDecided
                          ? Colors.green.withValues(alpha: 0.3)
                          : AppColors.primary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        allDecided ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                        size: 16,
                        color: allDecided ? Colors.green : AppColors.primaryLight,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        l10n.contestsDecidedCount(completedCount, positions.length),
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: allDecided ? Colors.green : AppColors.primaryLight,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () => context.pushNamed('vote-confirm', pathParameters: {'electionId': widget.electionId}),
                  icon: const Icon(Icons.how_to_vote_rounded, size: 18),
                  label: Text(
                    l10n.reviewAndSignBallot,
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

  Widget _buildWizardBallot(
    BuildContext context,
    WidgetRef ref,
    List<PositionModel> positions,
    bool allowBoycott,
    Map<String, List<String>> selections,
    bool isDark,
    BallotL10n l10n,
  ) {
    final progressValue = (_currentIndex + 1) / positions.length;

    return Column(
      children: [
        // Stepper Header Bar
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
                        overflow: TextOverflow.ellipsis,
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

        // Position Page View
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
                    if (i == 0) _buildBallotHeader(context, positions, allowBoycott, isDark, l10n),
                    _BallotPositionCard(
                      position: positions[i],
                      electionId: widget.electionId,
                      allowBoycott: allowBoycott,
                      l10n: l10n,
                    ),
                  ],
                ),
              );
            },
          ),
        ),

        // Bottom Wizard Action Controls
        _buildWizardControls(context, ref, selections, positions, isDark, l10n),
      ],
    );
  }

  Widget _buildBallotHeader(BuildContext context, List<PositionModel> positions, bool allowBoycott, bool isDark, BallotL10n l10n) {
    final ballotData = ref.watch(ballotDataProvider(widget.electionId)).valueOrNull;
    final election = ref.watch(electionProvider(widget.electionId)).valueOrNull;
    final org = ref.watch(orgProfileProvider).valueOrNull;

    final now = DateTime.now();
    final nepaliNow = now.toNepaliDateTime();
    final nepaliDateStr = '${NepaliDateFormat('yyyy/MM/dd').format(nepaliNow)} BS (${NepaliDateFormat('MMM d, yyyy').format(nepaliNow)})';
    final engDateStr = DateFormat('yyyy/MM/dd (MMM d, yyyy)').format(now);
    final nepaliDateFormatted = '${BallotL10n.toNepaliDigits(NepaliDateFormat('yyyy/MM/dd').format(nepaliNow))} वि.सं.';
    final votingDate = l10n.isEnglish ? engDateStr : (l10n.isNepali ? nepaliDateFormatted : nepaliDateStr);
    final votingTime = l10n.isNepali ? BallotL10n.toNepaliDigits(DateFormat('hh:mm a').format(now)) : DateFormat('hh:mm a').format(now);
    final voterName = (ballotData?.voterInfo?['full_name'] as String?)?.trim() ?? '';
    final voterId = (ballotData?.voterInfo?['voter_id'] as String?)?.trim() ?? '';
    final electionName = election?.title.trim() ?? '';
    final orgName = org?.name.trim() ?? '';

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
          // Top Header Banner with Swastiks & Election Title
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              gradient: isDark
                  ? const LinearGradient(
                      colors: [Color(0xFF331317), Color(0xFF1E293B)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : const LinearGradient(
                      colors: [Color(0xFFFFF7ED), Color(0xFFFFFAF0)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
              border: Border(
                bottom: BorderSide(
                  color: isDark ? Colors.white10 : const Color(0xFFB91C1C).withValues(alpha: 0.15),
                ),
              ),
            ),
            child: Row(
              children: [
                // Left Swastik Emblem
                SizedBox(
                  width: 38,
                  height: 38,
                  child: CustomPaint(
                    painter: const _SwastikPainter(color: Color(0xFFB91C1C)),
                  ),
                ),
                const SizedBox(width: 16),

                // Center Title & Election Branding
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
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 12.5,
                            color: Color(0xFFB91C1C),
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                      if (electionName.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          electionName,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                            letterSpacing: 0.2,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (orgName.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          orgName,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            color: isDark ? Colors.white70 : const Color(0xFF64748B),
                          ),
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(width: 16),
                // Right Swastik Emblem
                SizedBox(
                  width: 38,
                  height: 38,
                  child: CustomPaint(
                    painter: const _SwastikPainter(color: Color(0xFFB91C1C)),
                  ),
                ),
              ],
            ),
          ),

          // Metadata Grid: 4 items (Voter Name, Voter ID, Voting Date, Voting Time)
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
                          Expanded(
                            child: _buildBallotInfoCard(
                              label: l10n.voterNameLabel,
                              value: voterName.isNotEmpty ? voterName : l10n.authenticatedVoter,
                              icon: Icons.person_rounded,
                              isDark: isDark,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildBallotInfoCard(
                              label: l10n.voterIdLabel,
                              value: voterId.isNotEmpty ? (l10n.isNepali ? BallotL10n.toNepaliDigits(voterId) : voterId) : '—',
                              icon: Icons.badge_outlined,
                              isDark: isDark,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildBallotInfoCard(
                              label: l10n.votingDateLabel,
                              value: votingDate,
                              icon: Icons.calendar_today_outlined,
                              isDark: isDark,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildBallotInfoCard(
                              label: l10n.votingTimeLabel,
                              value: votingTime,
                              icon: Icons.access_time_rounded,
                              isDark: isDark,
                            ),
                          ),
                        ],
                      )
                    else ...[
                      Row(
                        children: [
                          Expanded(
                            child: _buildBallotInfoCard(
                              label: l10n.voterNameLabel,
                              value: voterName.isNotEmpty ? voterName : l10n.authenticatedVoter,
                              icon: Icons.person_rounded,
                              isDark: isDark,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _buildBallotInfoCard(
                              label: l10n.voterIdLabel,
                              value: voterId.isNotEmpty ? (l10n.isNepali ? BallotL10n.toNepaliDigits(voterId) : voterId) : '—',
                              icon: Icons.badge_outlined,
                              isDark: isDark,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _buildBallotInfoCard(
                              label: l10n.votingDateLabel,
                              value: votingDate,
                              icon: Icons.calendar_today_outlined,
                              isDark: isDark,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _buildBallotInfoCard(
                              label: l10n.votingTimeLabel,
                              value: votingTime,
                              icon: Icons.access_time_rounded,
                              isDark: isDark,
                            ),
                          ),
                        ],
                      ),
                    ],

                    // Footer security notice & Boycott button
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
                          Icon(
                            Icons.verified_user_outlined,
                            size: 15,
                            color: isDark ? Colors.blue.shade300 : const Color(0xFF2563EB),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              l10n.securitySealNotice,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: isDark ? Colors.white70 : const Color(0xFF475569),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (_) => DigitalIdCardDialog(
                                  cardType: 'voter',
                                  fullName: voterName.isNotEmpty ? voterName : 'Authenticated Voter',
                                  idNumber: voterId.isNotEmpty ? voterId : 'VOTER-1',
                                  electionTitle: electionName.isNotEmpty ? electionName : 'Official Election',
                                  orgName: orgName,
                                  electionId: widget.electionId,
                                  entityId: voterId.isNotEmpty ? voterId : widget.electionId,
                                ),
                              );
                            },
                            icon: const Icon(Icons.badge_outlined, size: 14, color: Color(0xFF10B981)),
                            label: const Text('Digital ID Card (परिचयपत्र)'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF10B981),
                              side: const BorderSide(color: Color(0xFF10B981)),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                          if (allowBoycott) ...[
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: () => _confirmBoycottAll(context, positions),
                              icon: const Icon(Icons.block_rounded, size: 13, color: Colors.deepOrange),
                              label: Text(l10n.boycottEntireElection),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.deepOrange,
                                side: BorderSide(color: Colors.deepOrange.withValues(alpha: 0.4)),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ],
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

  Widget _buildBallotInfoCard({
    required String label,
    required String value,
    required IconData icon,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A).withValues(alpha: 0.6) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFFB91C1C).withValues(alpha: 0.2) : const Color(0xFFB91C1C).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 16,
              color: isDark ? const Color(0xFFFCA5A5) : const Color(0xFFB91C1C),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: isDark ? Colors.white54 : const Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotEligibleScreen(BuildContext context, String reason, bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.gavel_rounded, color: Colors.orange, size: 40),
            ),
            const SizedBox(height: 20),
            const Text(
              'Not Eligible to Vote',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const Text(
              'मतदान गर्न अयोग्य',
              style: TextStyle(fontSize: 13, color: AppColors.primaryLight, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: Text(
                reason.isNotEmpty
                    ? reason
                    : 'Your account role does not have voting privileges. Only registered voters may cast a ballot.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13.5, height: 1.4),
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () => context.pop(),
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text('Go Back'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlreadyVotedScreen(BuildContext context, bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF10B981), Color(0xFF059669)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: const Color(0xFF10B981).withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 8)),
                ],
              ),
              child: const Icon(Icons.how_to_vote_rounded, color: Colors.white, size: 46),
            ),
            const SizedBox(height: 24),
            const Text(
              'Already Voted!',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const Text(
              'मतदान भइसकेको छ',
              style: TextStyle(fontSize: 14, color: Color(0xFF10B981), fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'You have already cast your secret ballot in this election. Each voter is permitted to vote only once to ensure electoral integrity.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13.5, color: isDark ? Colors.white70 : Colors.grey.shade700, height: 1.4),
              ),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: () => context.pop(),
              icon: const Icon(Icons.check_circle_rounded),
              label: const Text('Return to Election'),
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmBoycottAll(BuildContext context, List<PositionModel> positions) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.block_rounded, color: Colors.red),
            SizedBox(width: 10),
            Text('Boycott Entire Election?'),
          ],
        ),
        content: const Text(
          'This will select "No Vote / Boycott (बहिष्कार)" for all positions across this ballot. You can still review or edit before final submission.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(ballotSelectionsProvider.notifier).boycottEntireElection(positions);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('All positions marked as No Vote / Boycott.'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Confirm Boycott All'),
          ),
        ],
      ),
    );
  }

  Widget _buildWizardControls(BuildContext context, WidgetRef ref,
      Map<String, List<String>> selections, List<PositionModel> positions, bool isDark, BallotL10n l10n) {
    final hasSelections = selections.values.any((l) => l.isNotEmpty);
    final isLastStep = _currentIndex == positions.length - 1;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surface : Colors.white,
        border: Border(top: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade200)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            if (_currentIndex > 0)
              OutlinedButton.icon(
                onPressed: _prevPage,
                icon: const Icon(Icons.arrow_back_ios_rounded, size: 14),
                label: Text(l10n.previousContest),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              )
            else
              const SizedBox.shrink(),

            const Spacer(),

            FilledButton.icon(
              onPressed: isLastStep
                  ? (hasSelections
                      ? () => context.pushNamed('vote-confirm', pathParameters: {'electionId': widget.electionId})
                      : null)
                  : () => _nextPage(positions.length),
              icon: Icon(isLastStep ? Icons.how_to_vote_rounded : Icons.arrow_forward_ios_rounded, size: 16),
              label: Text(
                isLastStep ? l10n.reviewAndSignBallot : l10n.nextContest,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: isLastStep ? const Color(0xFF10B981) : AppColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BallotPositionCard extends ConsumerStatefulWidget {
  final PositionModel position;
  final String electionId;
  final bool allowBoycott;
  final BallotL10n l10n;
  const _BallotPositionCard({
    required this.position,
    required this.electionId,
    this.allowBoycott = true,
    required this.l10n,
  });

  @override
  ConsumerState<_BallotPositionCard> createState() => _BallotPositionCardState();
}

class _BallotPositionCardState extends ConsumerState<_BallotPositionCard> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final selections = ref.watch(ballotSelectionsProvider);
    final positionSelections = selections[widget.position.id] ?? [];
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final position = widget.position;
    final l10n = widget.l10n;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surface : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? AppColors.surfaceVariant : Colors.grey.shade200),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Position Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: position.bgColor.isNotEmpty
                  ? Color(int.parse(position.bgColor.replaceAll('#', 'FF'), radix: 16)).withValues(alpha: 0.08)
                  : (isDark ? AppColors.surfaceVariant.withValues(alpha: 0.3) : const Color(0xFFF8FAFC)),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(19)),
              border: Border(bottom: BorderSide(color: isDark ? Colors.white10 : Colors.grey.shade200)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: position.bgColor.isNotEmpty
                        ? Color(int.parse(position.bgColor.replaceAll('#', 'FF'), radix: 16)).withValues(alpha: 0.2)
                        : AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.military_tech_rounded,
                    color: position.bgColor.isNotEmpty
                        ? Color(int.parse(position.bgColor.replaceAll('#', 'FF'), radix: 16))
                        : AppColors.primaryLight,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.translatePositionTitle(position.title),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        position.isRankedChoice
                            ? (l10n.isEnglish
                                ? 'Rank your choices in order of preference'
                                : (l10n.isNepali
                                    ? 'वरियता क्रममा मतदान गर्नुहोस्'
                                    : 'Rank your choices in order of preference (वरियता क्रममा मतदान गर्नुहोस्)'))
                            : position.isApproval
                                ? (l10n.isEnglish
                                    ? 'Select all candidates you approve of'
                                    : (l10n.isNepali
                                        ? 'स्वीकृत उम्मेदवारहरू छनोट गर्नुहोस्'
                                        : 'Select all candidates you approve of (स्वीकृत उम्मेदवारहरू छनोट गर्नुहोस्)'))
                                : position.isYesNo
                                    ? (l10n.isEnglish
                                        ? 'Select Yes or No'
                                        : (l10n.isNepali
                                            ? 'हो वा होइन छनोट गर्नुहोस्'
                                            : 'Select Yes or No (हो वा होइन छनोट गर्नुहोस्)'))
                                    : l10n.selectionInstruction(position.seatsAvailable),
                        style: TextStyle(color: isDark ? Colors.white60 : AppColors.textMuted, fontSize: 12),
                      ),
                    ],
                  ),
                ),

                // Quota Pills
                if (position.quotas.isNotEmpty) ...[
                  () {
                    final activeQuotas = position.quotas.where((q) => q.isActive).toList();
                    final quotaSeats = activeQuotas.fold<int>(0, (sum, q) => sum + q.seats);
                    final openSeats = position.seatsAvailable - quotaSeats;

                    return Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        ...activeQuotas.map((q) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.purple.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.purple.withValues(alpha: 0.3)),
                          ),
                          child: Text(
                            '${q.name}: ${l10n.formatNumber(q.seats)} Seat(s)',
                            style: const TextStyle(color: Colors.purple, fontWeight: FontWeight.bold, fontSize: 11),
                          ),
                        )),
                        if (openSeats > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.blueGrey.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.blueGrey.withValues(alpha: 0.3)),
                            ),
                            child: Text(
                              'Open: ${l10n.formatNumber(openSeats)}',
                              style: const TextStyle(color: Colors.blueGrey, fontWeight: FontWeight.bold, fontSize: 11),
                            ),
                          ),
                      ],
                    );
                  }(),
                  const SizedBox(width: 10),
                ] else if (position.quotaName.isNotEmpty) ...[
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.purple.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.purple.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      'Quota: ${position.quotaName}',
                      style: const TextStyle(color: Colors.purple, fontWeight: FontWeight.bold, fontSize: 11),
                    ),
                  ),
                ],

                // Contest Completion Badge
                if (position.candidates.isNotEmpty) ...[
                  () {
                    final isNoVote = ref.watch(ballotSelectionsProvider.notifier).isNoVote(position.id);
                    if (isNoVote) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD97706).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFD97706).withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.block_rounded, size: 14, color: Color(0xFFD97706)),
                            const SizedBox(width: 4),
                            Text(
                              l10n.abstainedBadge,
                              style: const TextStyle(
                                color: Color(0xFFD97706),
                                fontWeight: FontWeight.bold,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    final isComplete = positionSelections.length == position.seatsAvailable;
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isComplete
                            ? Colors.green.withValues(alpha: 0.15)
                            : (positionSelections.isNotEmpty ? AppColors.primaryLight.withValues(alpha: 0.12) : (isDark ? Colors.white10 : Colors.grey.shade100)),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isComplete
                              ? Colors.green
                              : (positionSelections.isNotEmpty ? AppColors.primaryLight.withValues(alpha: 0.3) : (isDark ? Colors.white24 : Colors.grey.shade300)),
                        ),
                      ),
                      child: Text(
                        l10n.selectedCounter(positionSelections.length, position.seatsAvailable),
                        style: TextStyle(
                          color: isComplete ? Colors.green : (positionSelections.isNotEmpty ? AppColors.primaryLight : (isDark ? Colors.white60 : Colors.grey.shade700)),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    );
                  }(),
                ],
              ],
            ),
          ),

          // In-Contest Search Filter
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
          if (position.candidates.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Text(
                  l10n.noApprovedCandidates,
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                ),
              ),
            )
          else
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
                      final rank = position.isRankedChoice
                          ? ref.read(ballotSelectionsProvider.notifier).getRank(position.id, candidate.id)
                          : null;

                      return SizedBox(
                        width: itemWidth,
                        child: _CandidateTile(
                          candidate: candidate,
                          isSelected: isSelected,
                          rank: rank,
                          l10n: l10n,
                          onTap: () {
                            final prevLength = positionSelections.length;
                            ref.read(ballotSelectionsProvider.notifier).toggleCandidate(
                                  positionId: position.id,
                                  candidateId: candidate.id,
                                  maxSeats: position.seatsAvailable,
                                  isApproval: position.isApproval,
                                  isRankedChoice: position.isRankedChoice,
                                );
                            final newLength = ref.read(ballotSelectionsProvider)[position.id]?.length ?? 0;

                            if (!isSelected &&
                                prevLength == position.seatsAvailable &&
                                prevLength == newLength &&
                                position.seatsAvailable > 1) {
                              ScaffoldMessenger.of(context).clearSnackBars();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('You can only select up to ${position.seatsAvailable} candidates for this position.'),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          },
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ),

          // Dedicated Per-Position "No Vote / None of the Above / Abstain" Option
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: _NoVotePositionTile(
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

class _NoVotePositionTile extends StatelessWidget {
  final bool isNoVote;
  final VoidCallback onTap;
  final BallotL10n l10n;

  const _NoVotePositionTile({
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


class _CandidateTile extends StatelessWidget {
  final CandidateModel candidate;
  final bool isSelected;
  final int? rank;
  final VoidCallback onTap;
  final BallotL10n l10n;

  const _CandidateTile({
    required this.candidate,
    required this.isSelected,
    this.rank,
    required this.onTap,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const stampColor = Color(0xFFB91C1C);
    final primaryColor = isSelected ? stampColor : AppColors.primary;

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
                  // Candidate Portrait
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.surfaceVariant : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: ApiConstants.getFullImageUrl(candidate.photoUrl) != null
                          ? Image.network(
                              ApiConstants.getFullImageUrl(candidate.photoUrl)!,
                              fit: BoxFit.cover,
                              errorBuilder: (ctx, err, stack) => _buildPlaceholder(),
                            )
                          : _buildPlaceholder(),
                    ),
                  ),
                  const SizedBox(width: 14),

                  // Candidate Details
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          candidate.name,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: isSelected ? stampColor : (isDark ? Colors.white : Colors.black87),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),

                        // Badges Row
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            if (candidate.quotaName != null && candidate.quotaName!.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.purple.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.purple.withValues(alpha: 0.3)),
                                ),
                                child: Text(
                                  candidate.quotaName!,
                                  style: const TextStyle(color: Colors.purple, fontSize: 10.5, fontWeight: FontWeight.bold),
                                ),
                              ),
                          ],
                        ),

                        // Manifesto excerpt
                        if (candidate.manifesto.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            candidate.manifesto,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: isDark ? Colors.white60 : Colors.grey.shade600,
                              height: 1.35,
                            ),
                          ),
                        ],

                        const SizedBox(height: 8),
                        // View Full Dossier Action
                        InkWell(
                          onTap: () => showCandidateProfile(context, candidate),
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.info_outline_rounded, size: 13, color: primaryColor),
                                const SizedBox(width: 4),
                                Text(
                                  l10n.viewCandidateDossier,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: primaryColor,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Selection Indicator: Traditional Swastik Stamp (स्वस्तिक छाप)
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
                        boxShadow: [
                          BoxShadow(
                            color: stampColor.withValues(alpha: 0.2),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CustomPaint(
                            size: Size(16, 16),
                            painter: _SwastikPainter(color: stampColor),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            rank != null
                                ? (l10n.isNepali ? '#${BallotL10n.toNepaliDigits(rank)} मत' : '#$rank Vote')
                                : (l10n.isNepali ? 'स्वस्तिक छाप' : (l10n.isEnglish ? 'VOTED' : 'स्वस्तिक छाप')),
                            style: const TextStyle(
                              color: stampColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 10.5,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white10 : const Color(0xFFF1F5F9),
                        shape: BoxShape.circle,
                        border: Border.all(color: isDark ? Colors.white24 : Colors.grey.shade400),
                      ),
                      child: Icon(
                        Icons.radio_button_unchecked_rounded,
                        color: isDark ? Colors.white38 : Colors.grey.shade400,
                        size: 14,
                      ),
                    ),
            ),
          ],
        ),
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

// ─────────────────────────────────────────────────────────────────────────────
// Traditional Hindu / Nepali Swastik CustomPainter
// ─────────────────────────────────────────────────────────────────────────────

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
    // Unit fractions — works at any size
    // arm width = 1/3, arm length = 1/3 + center (1/3) = full span
    final double t = w / 3; // thickness of each arm
    final double c = w / 3; // size of center block

    final path = Path();

    // Center square
    path.addRect(Rect.fromLTWH(t, t, c, c));

    // Top arm
    path.addRect(Rect.fromLTWH(t, 0, c, t));

    // Bottom arm
    path.addRect(Rect.fromLTWH(t, h - t, c, t));

    // Left arm
    path.addRect(Rect.fromLTWH(0, t, t, c));

    // Right arm
    path.addRect(Rect.fromLTWH(w - t, t, t, c));

    // Hooks (right-facing swastik / प्रदक्षिण स्वस्तिक)
    // Top-right hook → points RIGHT then down
    path.addRect(Rect.fromLTWH(w - t, 0, t, t));

    // Bottom-left hook → points LEFT then up
    path.addRect(Rect.fromLTWH(0, h - t, t, t));

    // Now carve out the connecting regions that are NOT part of the swastik
    // by using the Even-Odd fill rule. Flutter uses nonzero by default, so
    // we paint the shape using a clip approach instead:

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_SwastikPainter old) => old.color != color;
}
