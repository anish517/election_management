import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import '../../core/providers/app_providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/network/api_constants.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/loading_button.dart';

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
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _error = msg;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ballotAsync = ref.watch(ballotProvider(widget.electionId));
    final selections = ref.watch(ballotSelectionsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.background : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Review & Confirm Ballot', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Text('मतपत्र समीक्षा तथा अन्तिम प्रमाणीकरण', style: TextStyle(fontSize: 11, color: Colors.white70)),
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
                              const Icon(Icons.checklist_rtl_rounded, color: AppColors.primaryLight, size: 22),
                              const SizedBox(width: 8),
                              Text(
                                'Your Verified Selections (तपाईंको छनोट विवरण)',
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
  ) {
    final isBoycotted = selectedIds.contains('__BOYCOTT__');
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
                    position.title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                  ),
                ),
                if (isBoycotted)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'Boycotted (बहिष्कार)',
                      style: TextStyle(color: Colors.red, fontSize: 11, fontWeight: FontWeight.bold),
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
                      'Abstained',
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
                      '${selectedCandidates.length} Selected',
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
                if (isBoycotted)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.red.withValues(alpha: 0.25)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.block_rounded, color: Colors.red, size: 18),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'No Vote / Boycott chosen for this office.',
                            style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 13),
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
                            'No candidate selected — you have chosen to abstain for this seat.',
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
                                if (c.slateName.isNotEmpty || (c.quotaName != null && c.quotaName!.isNotEmpty)) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    [
                                      if (c.quotaName != null && c.quotaName!.isNotEmpty) 'Quota: ${c.quotaName}',
                                      if (c.slateName.isNotEmpty) c.slateName,
                                    ].join(' • '),
                                    style: TextStyle(fontSize: 11, color: isDark ? Colors.white54 : Colors.grey.shade600),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (isRanked)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.primaryLight,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Preference #${rankIndex + 1}',
                                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            )
                          else
                            const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 22),
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
