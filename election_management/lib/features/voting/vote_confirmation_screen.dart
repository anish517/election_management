import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import '../../core/providers/app_providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/network/api_constants.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/loading_button.dart';
import 'ballot_l10n.dart';

class VoteConfirmationScreen extends ConsumerStatefulWidget {
  final String electionId;
  const VoteConfirmationScreen({super.key, required this.electionId});

  @override
  ConsumerState<VoteConfirmationScreen> createState() => _VoteConfirmationScreenState();
}

class _VoteConfirmationScreenState extends ConsumerState<VoteConfirmationScreen> {
  bool _isSubmitting = false;
  String? _error;
  bool _hasAffirmed = true;

  Future<void> _showFinalConfirmDialog(BuildContext context) async {
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
                        SizedBox(width: 28, height: 28, child: CustomPaint(painter: _VoteSwastikPainter(color: const Color(0xFF10B981)))),
                        const Expanded(
                          child: Column(
                            children: [
                              Text('Final Confirmation', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              Text('अन्तिम पुष्टि', style: TextStyle(fontSize: 11, color: Color(0xFF10B981), fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                        SizedBox(width: 28, height: 28, child: CustomPaint(painter: _VoteSwastikPainter(color: const Color(0xFF10B981)))),
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
                    const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 32),
                    const SizedBox(height: 10),
                    const Text(
                      'Are you absolutely sure you want to cast your ballot?',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'This action is permanent and irreversible. Once submitted, your ballot is cryptographically sealed and cannot be changed or withdrawn.',
                      style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.grey.shade700, height: 1.4),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.lock_rounded, color: Colors.red, size: 16),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Your vote is secret — no one can see your selections after submission.',
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
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                        child: const Text('Go Back'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: () => Navigator.pop(ctx, true),
                        icon: const Icon(Icons.how_to_vote_rounded, size: 18),
                        label: const Text('Cast My Vote (मतदान गर्नुहोस्)', style: TextStyle(fontWeight: FontWeight.bold)),
                        style: FilledButton.styleFrom(backgroundColor: const Color(0xFF10B981), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
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
    if (confirmed == true && mounted) {
      _doSubmitVote();
    }
  }

  Future<void> _submitVote() async {
    if (!_hasAffirmed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please confirm the affirmation checkbox to cast your ballot.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Show final popup before submitting
    await _showFinalConfirmDialog(context);
  }

  Future<void> _doSubmitVote() async {
    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      final selections = ref.read(ballotSelectionsProvider);
      final votingService = ref.read(votingServiceProvider);

      // Step 1: Get session token
      final sessionToken = await votingService.startSession(widget.electionId);

      // Step 2: Cast vote with ballot data and device logging
      final receipt = await votingService.castVote(
        electionId: widget.electionId,
        sessionToken: sessionToken,
        ballotData: selections,
        deviceIdentifier: 'Client App / Web Browser',
      );

      // Step 3: Clear ballot selections (security)
      ref.read(ballotSelectionsProvider.notifier).clear();

      if (mounted) {
        context.goNamed(
          'receipt',
          pathParameters: {'electionId': widget.electionId},
          queryParameters: {'receipt': receipt},
        );
      }
    } on DioException catch (e) {
      final data = e.response?.data;
      String msg = 'Failed to submit your vote. Please try again.';
      if (data is Map) {
        if (data.containsKey('error')) {
          msg = data['error'].toString();
        } else if (data.containsKey('non_field_errors')) {
          msg = (data['non_field_errors'] as List).join('\n');
        } else {
          final errors = <String>[];
          data.forEach((key, value) {
            errors.add('$key: $value');
          });
          msg = errors.join('\n');
        }
      }
      if (msg.toLowerCase().contains('already cast') || msg.toLowerCase().contains('already voted')) {
        msg = 'Already Submitted (मतदान भइसकेको छ). Your ballot has already been cast and recorded for this election.';
      }
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _error = msg;
        });
      }
    } catch (e) {
      String msg = e.toString();
      if (msg.toLowerCase().contains('already cast') || msg.toLowerCase().contains('already voted')) {
        msg = 'Already Submitted (मतदान भइसकेको छ). Your ballot has already been cast and recorded for this election.';
      }
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _error = msg;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ballotAsync = ref.watch(ballotProvider(widget.electionId));
    final selections = ref.watch(ballotSelectionsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ballotLang = ref.watch(ballotLanguageProvider);
    final l10n = BallotL10n(ballotLang);

    return Scaffold(
      backgroundColor: isDark ? AppColors.background : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Row(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: CustomPaint(painter: _VoteSwastikPainter(color: Colors.white)),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.isEnglish ? 'Review & Confirm Ballot' : (l10n.isNepali ? 'मतपत्र समीक्षा तथा अन्तिम प्रमाणीकरण' : 'Review & Confirm Ballot'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Text(l10n.isEnglish ? 'Secure Cryptographic Submission' : 'मतपत्र समीक्षा तथा अन्तिम प्रमाणीकरण', style: TextStyle(fontSize: 11, color: (Theme.of(context).appBarTheme.foregroundColor ?? Colors.white).withValues(alpha: 0.7))),
              ],
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: ballotAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 48),
              const SizedBox(height: 16),
              Text('Error Loading Selections', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(e.toString(), style: const TextStyle(color: AppColors.textMuted)),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => context.pop(),
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('Back to Ballot'),
              ),
            ],
          ),
        ),
        data: (positions) {
          return Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 860),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildWarningBanner(context, isDark),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              const SizedBox(
                                width: 18,
                                height: 18,
                                child: CustomPaint(painter: _VoteSwastikPainter(color: Color(0xFFB91C1C))),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                l10n.isEnglish ? 'Your Verified Selections' : (l10n.isNepali ? 'तपाईंको छनोट विवरण' : 'Your Verified Selections (तपाईंको छनोट विवरण)'),
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          ...positions.map((position) => _buildPositionSummary(
                                context,
                                position,
                                selections[position.id] ?? [],
                                isDark,
                                l10n,
                              )),

                          // Affirmation Checkbox Card
                          Container(
                            margin: const EdgeInsets.only(top: 8, bottom: 16),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: isDark ? AppColors.surfaceVariant.withValues(alpha: 0.3) : const Color(0xFFFAFAFA),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: _hasAffirmed ? Colors.green.withValues(alpha: 0.4) : (isDark ? Colors.white12 : Colors.grey.shade300),
                                width: 1.2,
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Checkbox(
                                  value: _hasAffirmed,
                                  activeColor: const Color(0xFF10B981),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                  onChanged: (val) => setState(() => _hasAffirmed = val ?? false),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Electoral Affirmation & Final Authorization',
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'I confirm that I have reviewed my candidate selections and authorize cryptographic casting of this secret ballot. I understand this action is permanent and cannot be modified.',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: isDark ? Colors.white60 : Colors.grey.shade700,
                                          height: 1.4,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),

                          if (_error != null) ...[
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.red.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.error_outline_rounded, color: Colors.red, size: 22),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      _error!,
                                      style: const TextStyle(color: Colors.red, fontSize: 13, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // Bottom Action Suite
              _buildBottomBar(context, isDark),
            ],
          );
        },
      ),
    );
  }

  Widget _buildWarningBanner(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF451A03).withValues(alpha: 0.5) : const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.lock_clock_outlined, color: Color(0xFFD97706), size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Permanent & Irreversible Ballot Submission',
                  style: TextStyle(
                    color: Color(0xFFD97706),
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Once your vote is cast, it will be cryptographically anonymized and permanently sealed in the tamper-evident ballot box. Please verify your selections below before completing.',
                  style: TextStyle(
                    color: isDark ? Colors.white70 : const Color(0xFF78350F),
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPositionSummary(
    BuildContext context,
    PositionModel position,
    List<String> selectedIds,
    bool isDark,
    BallotL10n l10n,
  ) {
    final isNoVote = selectedIds.contains('__BOYCOTT__') ||
        selectedIds.contains('__NO_VOTE__') ||
        selectedIds.contains('NOTA');
    final selectedCandidates = position.candidates.where((c) => selectedIds.contains(c.id)).toList();

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
          // Contest Office Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? AppColors.surfaceVariant.withValues(alpha: 0.3) : const Color(0xFFF8FAFC),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
              border: Border(bottom: BorderSide(color: isDark ? Colors.white10 : Colors.grey.shade200)),
            ),
            child: Row(
              children: [
                const Icon(Icons.military_tech_rounded, color: AppColors.primaryLight, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.translatePositionTitle(position.title),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                  ),
                ),
                if (isNoVote)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD97706).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFD97706).withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      l10n.abstainedBadge,
                      style: const TextStyle(color: Color(0xFFD97706), fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  )
                else if (selectedCandidates.isEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'Unselected (छनोट नगरिएको)',
                      style: TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      l10n.selectedCounter(selectedCandidates.length, position.seatsAvailable),
                      style: const TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
          ),

          // Choices Content
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isNoVote)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD97706).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFD97706).withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.do_not_disturb_alt_rounded, color: Color(0xFFD97706), size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            l10n.noVoteSubtitle,
                            style: const TextStyle(color: Color(0xFFD97706), fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  )
                else if (selectedCandidates.isEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline_rounded, color: Colors.amber, size: 18),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'No candidate selected — you have chosen to abstain for this seat (कुनै उम्मेदवार छनोट गरिएको छैन)।',
                            style: TextStyle(color: Colors.amber, fontSize: 12.5, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  )

                else
                  ...selectedCandidates.map((c) {
                    final rankIndex = selectedIds.indexOf(c.id);
                    final isRanked = position.isRankedChoice && rankIndex >= 0;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.surfaceVariant.withValues(alpha: 0.2) : const Color(0xFFFAFAFA),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade200),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: const Color(0xFF4F46E5).withValues(alpha: 0.12),
                            backgroundImage: c.photoUrl != null && c.photoUrl!.isNotEmpty
                                ? NetworkImage(ApiConstants.getFullImageUrl(c.photoUrl) ?? c.photoUrl!)
                                : null,
                            child: (c.photoUrl == null || c.photoUrl!.isEmpty)
                                ? Text(
                                    c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
                                    style: const TextStyle(color: Color(0xFF4F46E5), fontSize: 14, fontWeight: FontWeight.bold),
                                  )
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  c.name,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                                if (c.quotaName != null && c.quotaName!.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    'Quota: ${c.quotaName}',
                                    style: TextStyle(fontSize: 11, color: isDark ? Colors.white54 : Colors.grey.shade600),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (isRanked)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFB91C1C).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFB91C1C), width: 1.5),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CustomPaint(painter: _VoteSwastikPainter(color: Color(0xFFB91C1C))),
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    '#${rankIndex + 1} वरियता',
                                    style: const TextStyle(color: Color(0xFFB91C1C), fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            )
                          else
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFB91C1C).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFB91C1C), width: 1.5),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFB91C1C).withValues(alpha: 0.15),
                                    blurRadius: 4,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CustomPaint(painter: _VoteSwastikPainter(color: Color(0xFFB91C1C))),
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    'स्वस्तिक छाप',
                                    style: TextStyle(
                                      color: Color(0xFFB91C1C),
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context, bool isDark) {
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
            constraints: const BoxConstraints(maxWidth: 860),
            child: Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _isSubmitting ? null : () => context.pop(),
                  icon: const Icon(Icons.arrow_back_ios_rounded, size: 14),
                  label: const Text('Back & Edit Selections'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: LoadingButton(
                    onPressed: _submitVote,
                    isLoading: _isSubmitting,
                    label: 'Cast & Submit Secret Ballot (मतदान गर्नुहोस्)',
                    icon: Icons.how_to_vote_rounded,
                    backgroundColor: const Color(0xFF10B981),
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

// ─────────────────────────────────────────────────────────────────────────────
// Traditional Hindu / Nepali Swastik CustomPainter for Vote Confirmation
// ─────────────────────────────────────────────────────────────────────────────

class _VoteSwastikPainter extends CustomPainter {
  final Color color;
  const _VoteSwastikPainter({required this.color});

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

    // Hooks (right-facing swastik)
    path.addRect(Rect.fromLTWH(w - t, 0, t, t));
    path.addRect(Rect.fromLTWH(0, h - t, t, t));

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_VoteSwastikPainter old) => old.color != color;
}
