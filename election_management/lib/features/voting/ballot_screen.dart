import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/org_providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/network/api_constants.dart';
import '../../shared/models/models.dart';
import '../candidates/candidate_profile_sheet.dart';

class BallotScreen extends ConsumerStatefulWidget {
  final String electionId;
  const BallotScreen({super.key, required this.electionId});

  @override
  ConsumerState<BallotScreen> createState() => _BallotScreenState();
}

class _BallotScreenState extends ConsumerState<BallotScreen> {
  final PageController _pageController = PageController();
  int _currentIndex = 0;

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

  @override
  Widget build(BuildContext context) {
    final ballotAsync = ref.watch(ballotDataProvider(widget.electionId));
    final orgAsync = ref.watch(orgProfileProvider);
    final selections = ref.watch(ballotSelectionsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final org = orgAsync.valueOrNull;
    final showDurationTimer = (org?.showVotingDuration == true);
    final enableCountdown = (org?.enableVotingCountdown == true);

    if (enableCountdown && !_countdownInitialized && org != null) {
      _remainingSeconds = org.votingTimeLimitMinutes * 60;
      _countdownInitialized = true;
    }

    return Scaffold(
      backgroundColor: isDark ? AppColors.background : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Secret Electronic Ballot', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Text('गोप्य विद्युतीय मतपत्र', style: TextStyle(fontSize: 11, color: Colors.white70)),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => context.pop(),
        ),
        actions: [
          if (enableCountdown)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _remainingSeconds < 60
                        ? Colors.red.withValues(alpha: 0.3)
                        : (_remainingSeconds < 120
                            ? Colors.orange.withValues(alpha: 0.3)
                            : Colors.white.withValues(alpha: 0.15)),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _remainingSeconds < 60
                          ? Colors.red.shade300
                          : (_remainingSeconds < 120 ? Colors.orange.shade300 : Colors.white24),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.hourglass_top_rounded,
                        size: 14,
                        color: _remainingSeconds < 60
                            ? Colors.red.shade200
                            : (_remainingSeconds < 120 ? Colors.orange.shade200 : Colors.white70),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'Time Left: $_countdownStr',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                          fontSize: 12.5,
                          color: _remainingSeconds < 60
                              ? Colors.red.shade100
                              : (_remainingSeconds < 120 ? Colors.orange.shade100 : Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else if (showDurationTimer)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.timer_outlined, size: 14, color: Colors.white70),
                      const SizedBox(width: 4),
                      Text(
                        _elapsedStr,
                        style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ),
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
          // ── 1. Admin / non-voter block ──
          if (ballotData.notEligible) {
            return _buildNotEligibleScreen(context, ballotData.notEligibleReason, isDark);
          }

          // ── 2. Already voted ──
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
                                'Contest ${_currentIndex + 1} of ${positions.length}',
                                style: const TextStyle(color: AppColors.primaryLight, fontWeight: FontWeight.bold, fontSize: 11.5),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              positions[_currentIndex].title,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                        Text(
                          '${(progressValue * 100).toInt()}% Completed',
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
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1100),
                          child: Column(
                            children: [
                              if (i == 0) _buildBallotHeader(context, positions, allowBoycott, isDark),
                              _BallotPositionCard(
                                position: positions[i],
                                electionId: widget.electionId,
                                allowBoycott: allowBoycott,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              // Bottom Wizard Action Controls
              _buildWizardControls(context, ref, selections, positions, isDark),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBallotHeader(BuildContext context, List<PositionModel> positions, bool allowBoycott, bool isDark) {
    final ballotData = ref.watch(ballotDataProvider(widget.electionId)).valueOrNull;
    final election = ref.watch(electionProvider(widget.electionId)).valueOrNull;
    final now = DateTime.now();
    final votingDate = '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
    final votingTime = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final voterName = ballotData?.voterInfo?['full_name'] as String? ?? '';
    final voterId = ballotData?.voterInfo?['voter_id'] as String? ?? '';
    final electionName = election?.title ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        gradient: isDark
            ? const LinearGradient(colors: [Color(0xFF1E293B), Color(0xFF0F172A)], begin: Alignment.topLeft, end: Alignment.bottomRight)
            : const LinearGradient(colors: [Color(0xFFFFF7ED), Color(0xFFFFEDD5)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFB91C1C).withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(color: const Color(0xFFB91C1C).withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        children: [
          // Top Header strip with Swastik
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFB91C1C).withValues(alpha: isDark ? 0.3 : 0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
              border: Border(bottom: BorderSide(color: const Color(0xFFB91C1C).withValues(alpha: 0.2))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Left Swastik
                SizedBox(width: 32, height: 32, child: CustomPaint(painter: _SwastikPainter(color: const Color(0xFFB91C1C)))),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        'मतपत्र — OFFICIAL BALLOT',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: isDark ? Colors.white : const Color(0xFFB91C1C),
                          letterSpacing: 0.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (electionName.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          electionName,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white70 : const Color(0xFF78350F),
                          ),
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                // Right Swastik
                SizedBox(width: 32, height: 32, child: CustomPaint(painter: _SwastikPainter(color: const Color(0xFFB91C1C)))),
              ],
            ),
          ),

          // Voter Info Grid
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: _ballotInfoField('Voter Name', voterName.isNotEmpty ? voterName : '—', Icons.person_rounded, isDark)),
                    const SizedBox(width: 10),
                    Expanded(child: _ballotInfoField('Voter ID', voterId.isNotEmpty ? voterId : '—', Icons.badge_rounded, isDark)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _ballotInfoField('Voting Date', votingDate, Icons.calendar_today_rounded, isDark)),
                    const SizedBox(width: 10),
                    Expanded(child: _ballotInfoField('Voting Time', votingTime, Icons.access_time_rounded, isDark)),
                  ],
                ),
                if (allowBoycott) ...[
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _confirmBoycottAll(context, positions),
                        icon: const Icon(Icons.block_rounded, size: 14, color: Colors.deepOrange),
                        label: const Text('Boycott Entire Election'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.deepOrange,
                          side: BorderSide(color: Colors.deepOrange.withValues(alpha: 0.4)),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _ballotInfoField(String label, String value, IconData icon, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFB91C1C).withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: const Color(0xFFB91C1C).withValues(alpha: 0.7)),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: isDark ? Colors.white54 : Colors.grey.shade600, letterSpacing: 0.3)),
                Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87), overflow: TextOverflow.ellipsis),
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
      Map<String, List<String>> selections, List<PositionModel> positions, bool isDark) {
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
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Row(
              children: [
                if (_currentIndex > 0)
                  OutlinedButton.icon(
                    onPressed: _prevPage,
                    icon: const Icon(Icons.arrow_back_ios_rounded, size: 14),
                    label: const Text('Previous Contest'),
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
                    isLastStep ? 'Review & Sign Ballot (मतपत्र समीक्षा)' : 'Next Contest (अर्को पद)',
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
        ),
      ),
    );
  }
}

class _BallotPositionCard extends ConsumerWidget {
  final PositionModel position;
  final String electionId;
  final bool allowBoycott;
  const _BallotPositionCard({
    required this.position,
    required this.electionId,
    this.allowBoycott = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selections = ref.watch(ballotSelectionsProvider);
    final positionSelections = selections[position.id] ?? [];
    final isFPTP = position.seatsAvailable == 1;
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
                        position.title,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        position.isRankedChoice
                            ? 'Rank your choices in order of preference (वरियता क्रममा मतदान गर्नुहोस्)'
                            : position.isApproval
                                ? 'Select all candidates you approve of (स्वीकृत उम्मेदवारहरू छनोट गर्नुहोस्)'
                                : position.isYesNo
                                    ? 'Select Yes or No (हो वा होइन छनोट गर्नुहोस्)'
                                    : isFPTP
                                        ? 'Select 1 candidate (१ जना उम्मेदवार छनोट गर्नुहोस्)'
                                        : 'Select up to ${position.seatsAvailable} candidates (अधिकतम ${position.seatsAvailable} जना छनोट गर्नुहोस्)',
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
                            '${q.name}: ${q.seats} Seat(s)',
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
                              'Open: $openSeats',
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
                      color: AppColors.info.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      position.quotaName,
                      style: const TextStyle(color: AppColors.info, fontWeight: FontWeight.bold, fontSize: 11),
                    ),
                  ),
                ],

                // Selection Counter Badge
                if (!position.isRankedChoice && !position.isApproval && !position.isYesNo)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: positionSelections.length == position.seatsAvailable
                          ? Colors.green.withValues(alpha: 0.15)
                          : AppColors.primaryLight.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: positionSelections.length == position.seatsAvailable
                            ? Colors.green
                            : AppColors.primaryLight.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      '${positionSelections.length}/${position.seatsAvailable} Selected',
                      style: TextStyle(
                        color: positionSelections.length == position.seatsAvailable ? Colors.green : AppColors.primaryLight,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Candidates Grid
          if (position.candidates.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Text(
                  'No approved candidates listed for this position.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.all(20),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final itemWidth = constraints.maxWidth > 700
                      ? (constraints.maxWidth - 20) / 2
                      : constraints.maxWidth;

                  return Wrap(
                    spacing: 20,
                    runSpacing: 20,
                    children: position.candidates.map((candidate) {
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

          // No Vote / Boycott Option
          if (allowBoycott)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: _BoycottPositionTile(
                isBoycotted: positionSelections.contains('__BOYCOTT__'),
                onTap: () {
                  ref.read(ballotSelectionsProvider.notifier).toggleBoycott(position.id);
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _BoycottPositionTile extends StatelessWidget {
  final bool isBoycotted;
  final VoidCallback onTap;

  const _BoycottPositionTile({
    required this.isBoycotted,
    required this.onTap,
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
          color: isBoycotted
              ? Colors.red.withValues(alpha: isDark ? 0.15 : 0.08)
              : (isDark ? Colors.white.withValues(alpha: 0.03) : const Color(0xFFFAFAFA)),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isBoycotted ? Colors.red : (isDark ? Colors.white12 : Colors.grey.shade300),
            width: isBoycotted ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isBoycotted ? Colors.red : Colors.grey.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.block_rounded,
                size: 18,
                color: isBoycotted ? Colors.white : Colors.grey,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'No Vote / Boycott This Office (बहिष्कार)',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                      ),
                      if (isBoycotted) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'SELECTED',
                            style: TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'I choose to abstain from casting a vote for any candidate in this specific contest.',
                    style: TextStyle(color: isDark ? Colors.white54 : AppColors.textMuted, fontSize: 11.5),
                  ),
                ],
              ),
            ),
            Checkbox(
              value: isBoycotted,
              activeColor: Colors.red,
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

  const _CandidateTile({
    required this.candidate,
    required this.isSelected,
    this.rank,
    required this.onTap,
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
                                  'View Candidate Dossier',
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
                            rank != null ? '#$rank मत' : 'स्वस्तिक छाप',
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
