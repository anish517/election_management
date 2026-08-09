import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';

class ReceiptScreen extends StatefulWidget {
  final String electionId;
  final String receiptHash;

  const ReceiptScreen({
    super.key,
    required this.electionId,
    required this.receiptHash,
  });

  @override
  State<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen> {
  @override
  void initState() {
    super.initState();
    // Automatically redirect to Live Results after 4 seconds
    Future.delayed(const Duration(seconds: 4), () {
      if (!mounted) return;
      try {
        context.go('/elections/${widget.electionId}/results');
      } catch (_) {
        // Navigation may have already happened; ignore
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 40),
              _buildSuccessIcon(),
              const SizedBox(height: 32),
              _buildTitle(context),
              const SizedBox(height: 32),
              _buildReceiptCard(context),
              const SizedBox(height: 24),
              _buildExplainer(context),
              const SizedBox(height: 40),
              _buildActions(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuccessIcon() {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 600),
      builder: (_, value, child) => Transform.scale(scale: value, child: child),
      child: Container(
        width: 100, height: 100,
        decoration: BoxDecoration(
          gradient: const RadialGradient(
            colors: [AppColors.success, Color(0xFF059669)],
          ),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.success.withValues(alpha: 0.4),
              blurRadius: 30,
              spreadRadius: 5,
            ),
          ],
        ),
        child: const Icon(Icons.check_rounded, color: Colors.white, size: 54),
      ),
    );
  }

  Widget _buildTitle(BuildContext context) {
    return Column(
      children: [
        Text('Vote Submitted!', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(
          'Your vote has been recorded anonymously and securely.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }

  Widget _buildReceiptCard(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
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
          Row(
            children: [
              const Icon(Icons.receipt_long_rounded, color: AppColors.primaryLight, size: 20),
              const SizedBox(width: 8),
              Text('Your Vote Receipt', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              IconButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: widget.receiptHash));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Receipt hash copied to clipboard!')),
                  );
                },
                icon: const Icon(Icons.copy_rounded, size: 18),
                color: AppColors.primaryLight,
                tooltip: 'Copy Hash',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? AppColors.background : Colors.black.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              widget.receiptHash,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: AppColors.textSecondary,
                letterSpacing: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExplainer(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primaryDark.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primaryLight.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.help_outline_rounded, color: AppColors.primaryLight, size: 18),
              const SizedBox(width: 8),
              Text('What does this receipt prove?',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 14)),
            ],
          ),
          const SizedBox(height: 10),
          const _ExplainerItem(
            icon: Icons.security_rounded,
            text: 'Your ballot was successfully recorded on the system.',
          ),
          const _ExplainerItem(
            icon: Icons.visibility_off_rounded,
            text: 'Your specific choices remain permanently anonymous — not even admins can see what you voted.',
          ),
          const _ExplainerItem(
            icon: Icons.fingerprint_rounded,
            text: 'This hash is a cryptographic fingerprint that uniquely identifies your ballot without revealing its contents.',
          ),
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton.icon(
            onPressed: () => context.goNamed('dashboard'),
            icon: const Icon(Icons.home_rounded),
            label: const Text('Back to Home'),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => context.pushNamed('results',
                pathParameters: {'electionId': widget.electionId}),
            icon: const Icon(Icons.bar_chart_rounded),
            label: const Text('View Live Tally'),
          ),
        ),
      ],
    );
  }
}

class _ExplainerItem extends StatelessWidget {
  final IconData icon;
  final String text;
  const _ExplainerItem({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primaryLight, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
