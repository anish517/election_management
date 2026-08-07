import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers/app_providers.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/models.dart';

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
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.surfaceVariant)),
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

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Position header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.surfaceVariant)),
            ),
            child: Row(
              children: [
                const Icon(Icons.star_rounded, color: AppColors.accent, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(position.title, style: Theme.of(context).textTheme.titleMedium),
                      Text(
                        isFPTP ? 'Select 1 candidate' : 'Select up to ${position.seatsAvailable} candidates',
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
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
            ...position.candidates.map((candidate) {
              final isSelected = positionSelections.contains(candidate.id);
              return _CandidateTile(
                candidate: candidate,
                isSelected: isSelected,
                onTap: () => ref.read(ballotSelectionsProvider.notifier).toggleCandidate(
                  positionId: position.id,
                  candidateId: candidate.id,
                  maxSeats: position.seatsAvailable,
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _CandidateTile extends StatelessWidget {
  final CandidateModel candidate;
  final bool isSelected;
  final VoidCallback onTap;

  const _CandidateTile({
    required this.candidate,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryLight.withValues(alpha: 0.1) : AppColors.surfaceVariant.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.primaryLight : AppColors.surfaceVariant,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            // Avatar / photo
            CircleAvatar(
              radius: 22,
              backgroundColor: AppColors.primary,
              backgroundImage: candidate.photoUrl != null && candidate.photoUrl!.isNotEmpty
                  ? NetworkImage(candidate.photoUrl!)
                  : null,
              child: (candidate.photoUrl == null || candidate.photoUrl!.isEmpty)
                  ? Text(
                      candidate.name.isNotEmpty ? candidate.name[0].toUpperCase() : '?',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                    )
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(candidate.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: isSelected ? AppColors.primaryLight : AppColors.textPrimary,
                          )),
                  if (candidate.slateName.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(candidate.slateName,
                        style: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w600),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 24, height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? AppColors.primaryLight : Colors.transparent,
                border: Border.all(
                  color: isSelected ? AppColors.primaryLight : AppColors.textMuted,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check_rounded, color: Colors.white, size: 16)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
