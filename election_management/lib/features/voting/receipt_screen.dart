import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
  bool _copied = false;

  void _copyHash() {
    Clipboard.setData(ClipboardData(text: widget.receiptHash));
    setState(() => _copied = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.white),
            SizedBox(width: 10),
            Text('Cryptographic receipt fingerprint copied to clipboard!'),
          ],
        ),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _copied = false);
    });
  }

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
            constraints: const BoxConstraints(maxWidth: 680),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
              child: Column(
                children: [
                  _buildSuccessIcon(),
                  const SizedBox(height: 24),
                  _buildTitle(context, isDark),
                  const SizedBox(height: 28),
                  _buildReceiptCard(context, electionTitle, isDark),
                  const SizedBox(height: 24),
                  _buildExplainer(context, isDark),
                  const SizedBox(height: 36),
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
            BoxShadow(
              color: const Color(0xFF10B981).withValues(alpha: 0.4),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: const Icon(Icons.check_rounded, color: Colors.white, size: 50),
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
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Your ballot has been anonymized, cryptographically sealed, and submitted into the official ballot box.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white60 : Colors.grey.shade600,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReceiptCard(BuildContext context, String electionTitle, bool isDark) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? AppColors.surface : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? AppColors.surfaceVariant : Colors.grey.shade200),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Ribbon
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: isDark ? AppColors.surfaceVariant.withValues(alpha: 0.3) : const Color(0xFFF8FAFC),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(19)),
              border: Border(bottom: BorderSide(color: isDark ? Colors.white10 : Colors.grey.shade200)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.receipt_long_rounded, color: Color(0xFF10B981), size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Cryptographic Vote Receipt (प्रमाणीकरण भौचर)',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                      ),
                      Text(
                        electionTitle,
                        style: TextStyle(fontSize: 11.5, color: isDark ? Colors.white60 : Colors.grey.shade600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock_rounded, size: 12, color: Colors.green),
                      SizedBox(width: 4),
                      Text('SEALED', style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Hash Token Box
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'RECEIPT AUDIT FINGERPRINT',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                        color: isDark ? Colors.white54 : Colors.grey.shade600,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _copyHash,
                      icon: Icon(_copied ? Icons.check_rounded : Icons.copy_rounded, size: 14),
                      label: Text(_copied ? 'Copied' : 'Copy Hash', style: const TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.primaryLight,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade300),
                  ),
                  child: SelectableText(
                    widget.receiptHash,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Keep this cryptographic token safe. You can use this receipt hash to verify that your ballot is counted in the official audit tally.',
                  style: TextStyle(fontSize: 11.5, color: isDark ? Colors.white54 : Colors.grey.shade600, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExplainer(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1B4B).withValues(alpha: 0.3) : const Color(0xFFEEF2FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.verified_user_rounded, color: Color(0xFF6366F1), size: 16),
              ),
              const SizedBox(width: 10),
              const Text(
                'What does this cryptographic receipt guarantee?',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const _ExplainerItem(
            icon: Icons.shield_rounded,
            title: 'Tamper-Evident Registration',
            text: 'Your vote was successfully encrypted and appended into the verified election tally roll.',
          ),
          const _ExplainerItem(
            icon: Icons.visibility_off_rounded,
            title: 'Complete Ballot Secrecy',
            text: 'Your candidate selections are strictly disassociated from your identity — neither admins nor observers can see what you voted.',
          ),
          const _ExplainerItem(
            icon: Icons.fingerprint_rounded,
            title: 'Mathematical Verifiability',
            text: 'This hash serves as a digital receipt to independently verify ballot inclusion without compromising your privacy.',
          ),
          const _ExplainerItem(
            icon: Icons.analytics_rounded,
            title: 'Certified Results Publication',
            text: 'Election results will be officially computed and certified once the voting window closes.',
          ),
        ],
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

class _ExplainerItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  const _ExplainerItem({required this.icon, required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF6366F1), size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                  fontSize: 12.5,
                  color: isDark ? Colors.white70 : const Color(0xFF334155),
                  height: 1.35,
                  fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
                ),
                children: [
                  TextSpan(text: '$title: ', style: const TextStyle(fontWeight: FontWeight.bold)),
                  TextSpan(text: text),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
