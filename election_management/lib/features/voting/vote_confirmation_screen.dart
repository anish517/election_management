import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import '../../core/providers/app_providers.dart';
import '../../core/theme/app_theme.dart';
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

  Future<void> _submitVote() async {
    setState(() { _isSubmitting = true; _error = null; });
    try {
      final selections = ref.read(ballotSelectionsProvider);
      final votingService = ref.read(votingServiceProvider);

      // Step 1: Get session token
      final sessionToken = await votingService.startSession(widget.electionId);

      // Step 2: Cast vote with ballot data
      final receipt = await votingService.castVote(
        electionId: widget.electionId,
        sessionToken: sessionToken,
        ballotData: selections,
      );

      // Step 3: Clear ballot selections (security)
      ref.read(ballotSelectionsProvider.notifier).clear();

      if (mounted) {
        context.goNamed('receipt',
            pathParameters: {'electionId': widget.electionId},
            queryParameters: {'receipt': receipt});
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
          // Flatten all other validation errors
          final errors = <String>[];
          data.forEach((key, value) {
            errors.add('$key: $value');
          });
          msg = errors.join('\n');
        }
      }
      if (mounted) setState(() { _isSubmitting = false; _error = msg; });
    } catch (e) {
      if (mounted) setState(() { _isSubmitting = false; _error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ballotAsync = ref.watch(ballotProvider(widget.electionId));
    final selections = ref.watch(ballotSelectionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Confirm Your Vote'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: ballotAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (positions) {
          return Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildWarningBanner(context),
                      const SizedBox(height: 20),
                      Text('Your Selections', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 16),
                      ...positions.map((position) => _buildPositionSummary(
                            context, position, selections[position.id] ?? [])),
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.error.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 18),
                              const SizedBox(width: 8),
                              Expanded(child: Text(_error!,
                                  style: const TextStyle(color: AppColors.error))),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              _buildBottomBar(context),
            ],
          );
        },
      ),
    );
  }

  Widget _buildWarningBanner(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('This action is irreversible',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: AppColors.warning, fontSize: 15)),
                const SizedBox(height: 4),
                Text(
                  'Once submitted, your vote cannot be changed or recalled. Please verify your selections carefully.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPositionSummary(BuildContext context, PositionModel position, List<String> selectedIds) {
    final selectedCandidates = position.candidates.where((c) => selectedIds.contains(c.id)).toList();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surface : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? AppColors.surfaceVariant : Colors.black.withValues(alpha: 0.05)),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.star_rounded, color: AppColors.accent, size: 16),
              const SizedBox(width: 6),
              Text(position.title, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 10),
          if (selectedCandidates.isEmpty)
            const Text('⚠️ No candidate selected for this position',
                style: TextStyle(color: AppColors.warning))
          else
            ...selectedCandidates.map((c) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: AppColors.primaryLight,
                        backgroundImage: c.photoUrl != null && c.photoUrl!.isNotEmpty
                            ? NetworkImage(c.photoUrl!)
                            : null,
                        child: (c.photoUrl == null || c.photoUrl!.isEmpty)
                            ? Text(c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
                                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))
                            : null,
                      ),
                      const SizedBox(width: 10),
                      Text(c.name, style: Theme.of(context).textTheme.bodyLarge),
                      const Spacer(),
                      const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 18),
                    ],
                  ),
                )),
        ],
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surface : Colors.white,
        border: Border(top: BorderSide(color: isDark ? AppColors.surfaceVariant : Colors.black.withValues(alpha: 0.05))),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            LoadingButton(
              onPressed: _submitVote,
              isLoading: _isSubmitting,
              label: 'Submit My Vote',
              icon: Icons.how_to_vote_rounded,
              backgroundColor: AppColors.stateVoting,
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: _isSubmitting ? null : () => context.pop(),
              child: const Text('Go Back & Edit'),
            ),
          ],
        ),
      ),
    );
  }
}
