import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers/app_providers.dart';
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

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
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
    final ballotAsync = ref.watch(ballotProvider(widget.electionId));
    final selections = ref.watch(ballotSelectionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Ballot'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: ballotAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 40),
              const SizedBox(height: 12),
              Text('Cannot load ballot', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(e.toString(),
                  style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.center),
            ],
          ),
        ),
        data: (positions) {
          if (positions.isEmpty) {
            return const Center(
              child: Text('No positions available on this ballot.'),
            );
          }
          
          return Column(
            children: [
              // Progress Bar
              LinearProgressIndicator(
                value: (_currentIndex + 1) / positions.length,
                backgroundColor: AppColors.surfaceVariant,
                valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Text('Step ${_currentIndex + 1} of ${positions.length}', 
                  style: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.bold)),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(), // Force using buttons
                  onPageChanged: (idx) => setState(() => _currentIndex = idx),
                  itemCount: positions.length,
                  itemBuilder: (context, i) {
                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          if (i == 0) _buildBallotHeader(context),
                          _BallotPositionCard(
                            position: positions[i],
                            electionId: widget.electionId,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              _buildWizardControls(context, ref, selections, positions),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBallotHeader(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primaryDark.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primaryLight.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: AppColors.primaryLight, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Your selections are saved locally and only submitted when you tap "Review & Submit" at the end.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWizardControls(BuildContext context, WidgetRef ref,
      Map<String, List<String>> selections, List<PositionModel> positions) {
    final hasSelections = selections.values.any((l) => l.isNotEmpty);
    final isLastStep = _currentIndex == positions.length - 1;
    
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surface : Colors.white,
        border: Border(top: BorderSide(color: isDark ? AppColors.surfaceVariant : Colors.black.withValues(alpha: 0.05))),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            if (_currentIndex > 0)
              Expanded(
                flex: 1,
                child: OutlinedButton(
                  onPressed: _prevPage,
                  child: const Text('Back'),
                ),
              )
            else
              const Spacer(flex: 1),
            
            const SizedBox(width: 16),
            
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: isLastStep
                    ? (hasSelections
                        ? () => context.pushNamed('vote-confirm',
                            pathParameters: {'electionId': widget.electionId})
                        : null)
                    : () => _nextPage(positions.length),
                child: Text(isLastStep ? 'Review & Submit' : 'Next Position'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BallotPositionCard extends ConsumerWidget {
  final PositionModel position;
  final String electionId;
  const _BallotPositionCard({required this.position, required this.electionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selections = ref.watch(ballotSelectionsProvider);
    final positionSelections = selections[position.id] ?? [];
    final isFPTP = position.seatsAvailable == 1;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surface : Colors.white,
        borderRadius: BorderRadius.circular(16),
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
          // Position header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: position.bgColor.isNotEmpty
                  ? Color(int.parse(position.bgColor.replaceAll('#', 'FF'), radix: 16)).withValues(alpha: 0.1)
                  : Colors.transparent,
              border: Border(bottom: BorderSide(color: isDark ? AppColors.surfaceVariant : Colors.black.withValues(alpha: 0.05))),
            ),
            child: Row(
              children: [
                Icon(Icons.star_rounded, 
                  color: position.bgColor.isNotEmpty 
                      ? Color(int.parse(position.bgColor.replaceAll('#', 'FF'), radix: 16))
                      : AppColors.accent, 
                  size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(position.title, style: Theme.of(context).textTheme.titleMedium),
                      Text(
                        position.isRankedChoice 
                            ? 'Rank your choices in order of preference' 
                            : position.isApproval 
                                ? 'Select all candidates you approve of' 
                                : position.isYesNo
                                    ? 'Select Yes or No'
                                    : isFPTP 
                                        ? 'Select 1 candidate' 
                                        : 'Select up to ${position.seatsAvailable} candidates',
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                if (position.quotaName.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.info.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      position.quotaName,
                      style: const TextStyle(color: AppColors.info, fontWeight: FontWeight.w600, fontSize: 11),
                    ),
                  ),
                if (!position.isRankedChoice && !position.isApproval && !position.isYesNo)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${positionSelections.length}/${position.seatsAvailable}',
                      style: const TextStyle(color: AppColors.primaryLight, fontWeight: FontWeight.w700, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
          // Candidates
          if (position.candidates.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(
                child: Text('No approved candidates for this position.',
                    style: TextStyle(color: AppColors.textMuted)),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              child: SizedBox(
                width: double.infinity,
                child: Wrap(
                  spacing: 20,
                  runSpacing: 20,
                  alignment: WrapAlignment.center,
                  children: position.candidates.map((candidate) {
                    final isSelected = positionSelections.contains(candidate.id);
                    final rank = position.isRankedChoice 
                        ? ref.read(ballotSelectionsProvider.notifier).getRank(position.id, candidate.id) 
                        : null;
                        
                    return SizedBox(
                      width: 280,
                      height: 340,
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
                          
                          // If length didn't change and wasn't deselected, it means max seats hit
                          if (!isSelected && prevLength == position.seatsAvailable && prevLength == newLength && position.seatsAvailable > 1) {
                            ScaffoldMessenger.of(context).clearSnackBars();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('You can only select up to ${position.seatsAvailable} candidates for this position.')),
                            );
                          }
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
        ],
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryLight.withValues(alpha: 0.1) : AppColors.surfaceVariant.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.primaryLight : AppColors.surfaceVariant,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                    child: ApiConstants.getFullImageUrl(candidate.photoUrl) != null
                        ? Image.network(
                            ApiConstants.getFullImageUrl(candidate.photoUrl)!, 
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => _buildPlaceholder(),
                          )
                        : _buildPlaceholder(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        candidate.name,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: isSelected ? AppColors.primaryLight : AppColors.textPrimary,
                              fontSize: 14,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (candidate.slateName.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          candidate.slateName,
                          style: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      // Manifesto snippet
                      if (candidate.manifesto.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          candidate.manifesto,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted, height: 1.35),
                        ),
                      ],
                      const SizedBox(height: 6),
                      // "Read more" info button
                      GestureDetector(
                        onTap: () => showCandidateProfile(context, candidate),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.info_outline_rounded, size: 12,
                                color: isSelected ? AppColors.primaryLight : AppColors.textMuted),
                            const SizedBox(width: 3),
                            Text(
                              'View full manifesto',
                              style: TextStyle(
                                fontSize: 10,
                                color: isSelected ? AppColors.primaryLight : AppColors.textMuted,
                                fontWeight: FontWeight.w500,
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
            if (isSelected)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: AppColors.primaryLight,
                    shape: BoxShape.circle,
                  ),
                  child: rank != null 
                    ? SizedBox(
                        width: 16, 
                        height: 16, 
                        child: Center(
                          child: Text(
                            '$rank', 
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)
                          )
                        )
                      )
                    : const Icon(Icons.check_rounded, color: Colors.white, size: 16),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: AppColors.primary,
      child: Center(
        child: Text(
          candidate.name.isNotEmpty ? candidate.name[0].toUpperCase() : '?',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 36),
        ),
      ),
    );
  }
}
