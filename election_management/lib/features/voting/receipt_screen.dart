import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nepali_date_picker/nepali_date_picker.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/app_providers.dart';

class ReceiptScreen extends ConsumerStatefulWidget {
  final String electionId;
  final String receiptHash;

  const ReceiptScreen({
    super.key,
    required this.electionId,
    required this.receiptHash,
  });

  @override
  ConsumerState<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends ConsumerState<ReceiptScreen> {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final electionAsync = ref.watch(electionProvider(widget.electionId));
    final electionTitle = electionAsync.valueOrNull?.title ?? 'Official Election';

    return Scaffold(
      backgroundColor: isDark ? AppColors.background : const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
              child: Column(
                children: [
                  _buildSuccessIcon(),
                  const SizedBox(height: 24),
                  _buildTitle(context, isDark),
                  const SizedBox(height: 28),
                  _buildReceiptCard(context, electionTitle, isDark),
                  const SizedBox(height: 32),
                  _buildActions(context),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSuccessIcon() {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutBack,
      builder: (_, value, child) => Transform.scale(scale: value, child: child),
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF10B981), Color(0xFF059669)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF10B981).withValues(alpha: 0.4),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: const Icon(Icons.check_rounded, color: Colors.white, size: 54),
      ),
    );
  }

  Widget _buildTitle(BuildContext context, bool isDark) {
    return Column(
      children: [
        const Text(
          'Vote Successfully Cast!',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        const Text(
          'तपाईंको गोप्य मत सफलतापूर्वक दर्ता भयो',
          style: TextStyle(fontSize: 13, color: AppColors.primaryLight, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Thank you for exercising your democratic right. Your ballot has been cast anonymously and recorded into the official ballot box.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              color: isDark ? Colors.white60 : Colors.grey.shade600,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReceiptCard(BuildContext context, String electionTitle, bool isDark) {
    final now = DateTime.now();
    final nepaliNow = now.toNepaliDateTime();
    final formattedDate = '${NepaliDateFormat('yyyy/MM/dd').format(nepaliNow)} BS (${NepaliDateFormat('MMM d, yyyy').format(nepaliNow)})';
    final formattedTime = DateFormat('hh:mm a').format(now);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? AppColors.surface : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? AppColors.surfaceVariant : Colors.grey.shade200),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.how_to_vote_rounded, color: Color(0xFF10B981), size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        electionTitle,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Electronic Ballot Confirmation',
                        style: TextStyle(fontSize: 11.5, color: Color(0xFF10B981), fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_rounded, size: 13, color: Color(0xFF10B981)),
                      SizedBox(width: 4),
                      Text('CONFIRMED', style: TextStyle(color: Color(0xFF10B981), fontSize: 10.5, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('DATE', style: TextStyle(fontSize: 10, color: isDark ? Colors.white38 : Colors.grey.shade500, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                      const SizedBox(height: 2),
                      Text(formattedDate, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('TIME', style: TextStyle(fontSize: 10, color: isDark ? Colors.white38 : Colors.grey.shade500, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                      const SizedBox(height: 2),
                      Text(formattedTime, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('BALLOT TYPE', style: TextStyle(fontSize: 10, color: isDark ? Colors.white38 : Colors.grey.shade500, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                      const SizedBox(height: 2),
                      const Text('Secret Ballot', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF10B981))),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final electionAsync = ref.watch(electionProvider(widget.electionId));

    final isResultsAvailable = electionAsync.maybeWhen(
      data: (e) => e.hasResults || e.state == 'voting_closed' || (user?.canManageElections == true),
      orElse: () => user?.canManageElections == true,
    );

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 50,
          child: FilledButton.icon(
            onPressed: () => context.goNamed('dashboard'),
            icon: const Icon(Icons.home_rounded, size: 18),
            label: const Text('Back to Home Dashboard (गृहपृष्ठमा फर्कनुहोस्)', style: TextStyle(fontWeight: FontWeight.bold)),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        if (isResultsAvailable) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: () => context.pushNamed('results', pathParameters: {'electionId': widget.electionId}),
              icon: const Icon(Icons.bar_chart_rounded, size: 18),
              label: const Text('View Live Results & Tally (नतिजा हेर्नुहोस्)', style: TextStyle(fontWeight: FontWeight.bold)),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
