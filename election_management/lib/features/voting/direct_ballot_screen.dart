import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers/app_providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/network/api_constants.dart';
import '../candidates/candidate_profile_sheet.dart';

class DirectBallotScreen extends ConsumerStatefulWidget {
  final String directToken;
  const DirectBallotScreen({super.key, required this.directToken});

  @override
  ConsumerState<DirectBallotScreen> createState() => _DirectBallotScreenState();
}

class _DirectBallotScreenState extends ConsumerState<DirectBallotScreen> {
  bool _isCasting = false;
  String? _castError;

  Color _hexToColor(String hex) {
    try {
      final buffer = StringBuffer();
      if (hex.length == 6 || hex.length == 7) buffer.write('ff');
      buffer.write(hex.replaceFirst('#', ''));
      return Color(int.parse(buffer.toString(), radix: 16));
    } catch (_) {
      return AppColors.primary;
    }
  }

  Future<void> _submitBallot(DirectBallotData data) async {
    final selections = ref.read(ballotSelectionsProvider);

    // Validate that all positions have at least one selection or boycott
    final unvotedPositions = <String>[];
    for (final pos in data.positions) {
      final chosen = selections[pos.id] ?? [];
      if (chosen.isEmpty) {
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
              Text('Incomplete Ballot'),
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

    // Confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.lock_outline_rounded, color: AppColors.primary, size: 24),
            SizedBox(width: 10),
            Text('Confirm Vote Submission'),
          ],
        ),
        content: const Text(
          'Once submitted, your ballot will be cryptographically decoupled from your identity and recorded permanently. This single-use link will be deactivated.\n\nAre you sure you want to cast your vote?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.how_to_vote_rounded, size: 18),
            label: const Text('Yes, Cast My Vote'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
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
          _castError = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ballotAsync = ref.watch(directBallotProvider(widget.directToken));
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.background : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Official Secret Ballot'),
        centerTitle: true,
        automaticallyImplyLeading: false,
        elevation: 0,
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
          final isUsedOrExpired = err.toString().contains('410') ||
              err.toString().toLowerCase().contains('used') ||
              err.toString().toLowerCase().contains('expired');

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
                          color: isUsedOrExpired
                              ? Colors.amber.withValues(alpha: 0.12)
                              : Colors.red.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isUsedOrExpired ? Icons.lock_clock_rounded : Icons.error_outline_rounded,
                          color: isUsedOrExpired ? Colors.amber.shade800 : Colors.red,
                          size: 48,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        isUsedOrExpired ? 'Single-Use Link Deactivated' : 'Unable to Open Ballot',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        isUsedOrExpired
                            ? 'This single-use ballot link has already been used or has expired. To maintain electoral integrity, each ballot token can only be cast once.'
                            : err.toString().replaceAll('Exception: ', ''),
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
                        onPressed: () => context.go('/'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
        data: (data) {
          final primary = _hexToColor(data.primaryColor);
          final selections = ref.watch(ballotSelectionsProvider);

          return Column(
            children: [
              // Top Banner
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [primary, _hexToColor(data.secondaryColor)],
                  ),
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 860),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.how_to_vote_rounded, color: Colors.white, size: 22),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                data.electionTitle,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Voter:  (ID: ) • Single-Use Direct Ballot',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.shield_rounded, color: Colors.white, size: 14),
                              SizedBox(width: 4),
                              Text(
                                'Secret Ballot',
                                style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              if (_castError != null)
                Container(
                  width: double.infinity,
                  color: Colors.red.shade700,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _castError!,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),

              // Ballot List
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 860),
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
                      itemCount: data.positions.length,
                      itemBuilder: (context, posIdx) {
                        final pos = data.positions[posIdx];
                        final chosenCandIds = selections[pos.id] ?? [];
                        final isBoycott = ref.read(ballotSelectionsProvider.notifier).isBoycotted(pos.id);

                        return Card(
                          margin: const EdgeInsets.only(bottom: 24),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(
                              color: isDark ? Colors.white12 : Colors.grey.shade200,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Position Header
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: primary.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        'Position ',
                                        style: TextStyle(
                                          color: primary,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        pos.title,
                                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: isDark ? Colors.white10 : Colors.grey.shade100,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        'Max Choices: ',
                                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                const Divider(height: 1),
                                const SizedBox(height: 14),

                                // Candidate Cards
                                ...pos.candidates.map((cand) {
                                  final isSelected = chosenCandIds.contains(cand.id);

                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: InkWell(
                                      onTap: () {
                                        ref.read(ballotSelectionsProvider.notifier).toggleCandidate(
                                              positionId: pos.id,
                                              candidateId: cand.id,
                                              maxSeats: pos.maxVotesPerVoter,
                                            );
                                      },
                                      borderRadius: BorderRadius.circular(12),
                                      child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 150),
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? primary.withValues(alpha: 0.12)
                                              : (isDark ? Colors.white.withValues(alpha: 0.04) : Colors.white),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: isSelected ? primary : (isDark ? Colors.white12 : Colors.grey.shade300),
                                            width: isSelected ? 2 : 1,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            CircleAvatar(
                                              radius: 22,
                                              backgroundColor: primary.withValues(alpha: 0.2),
                                              backgroundImage: (cand.photoUrl != null && cand.photoUrl!.isNotEmpty)
                                                  ? NetworkImage(ApiConstants.getFullImageUrl(cand.photoUrl!) ?? cand.photoUrl!)
                                                  : null,
                                              child: (cand.photoUrl == null || cand.photoUrl!.isEmpty)
                                                  ? Text(
                                                      cand.name.isNotEmpty ? cand.name[0] : '?',
                                                      style: TextStyle(fontWeight: FontWeight.bold, color: primary),
                                                    )
                                                  : null,
                                            ),
                                            const SizedBox(width: 14),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    cand.name,
                                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                                                  ),
                                                  if (cand.quotaName != null && cand.quotaName!.isNotEmpty) ...[
                                                    const SizedBox(height: 4),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: Colors.blue.withValues(alpha: 0.15),
                                                        borderRadius: BorderRadius.circular(4),
                                                      ),
                                                      child: Text(
                                                        cand.quotaName!,
                                                        style: const TextStyle(
                                                          fontSize: 10.5,
                                                          color: Colors.blue,
                                                          fontWeight: FontWeight.w600,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                            if (cand.manifesto.isNotEmpty)
                                              IconButton(
                                                icon: const Icon(Icons.info_outline_rounded, size: 20),
                                                tooltip: 'View Manifesto',
                                                onPressed: () {
                                                  showModalBottomSheet(
                                                    context: context,
                                                    isScrollControlled: true,
                                                    backgroundColor: Colors.transparent,
                                                    builder: (_) => CandidateProfileSheet(candidate: cand),
                                                  );
                                                },
                                              ),
                                            Checkbox(
                                              value: isSelected,
                                              activeColor: primary,
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                              onChanged: (_) {
                                                ref.read(ballotSelectionsProvider.notifier).toggleCandidate(
                                                      positionId: pos.id,
                                                      candidateId: cand.id,
                                                      maxSeats: pos.maxVotesPerVoter,
                                                    );
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                }),

                                // None of the Above / Boycott Option
                                if (data.allowBoycott) ...[
                                  const SizedBox(height: 4),
                                  InkWell(
                                    onTap: () {
                                      ref.read(ballotSelectionsProvider.notifier).toggleBoycott(pos.id);
                                    },
                                    borderRadius: BorderRadius.circular(12),
                                    child: Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: isBoycott
                                            ? Colors.amber.withValues(alpha: 0.15)
                                            : (isDark ? Colors.white.withValues(alpha: 0.03) : Colors.grey.shade50),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: isBoycott ? Colors.amber.shade700 : (isDark ? Colors.white12 : Colors.grey.shade300),
                                          width: isBoycott ? 2 : 1,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.do_not_disturb_on_rounded,
                                            color: isBoycott ? Colors.amber.shade800 : Colors.grey,
                                            size: 22,
                                          ),
                                          const SizedBox(width: 12),
                                          const Expanded(
                                            child: Text(
                                              'No Vote / Boycott This Position (बहिष्कार)',
                                              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                            ),
                                          ),
                                          Checkbox(
                                            value: isBoycott,
                                            activeColor: Colors.amber.shade800,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                            onChanged: (_) {
                                              ref.read(ballotSelectionsProvider.notifier).toggleBoycott(pos.id);
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),

              // Bottom Sticky Cast Button
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.surface : Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 10,
                      offset: const Offset(0, -3),
                    ),
                  ],
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 860),
                    child: SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        icon: _isCasting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.how_to_vote_rounded, size: 20),
                        label: Text(
                          _isCasting ? 'Casting Secret Ballot...' : 'Submit & Cast Ballot (गोप्य मतदान गर्नुहोस्)',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.success,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _isCasting ? null : () => _submitBallot(data),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
