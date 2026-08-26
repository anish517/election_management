import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/models.dart';
import '../../../core/providers/payment_providers.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/network/api_constants.dart';
import '../../../shared/widgets/admin_drawer.dart';
import '../../../shared/widgets/shimmer_loaders.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/responsive_layout.dart';

class PaymentManagementScreen extends ConsumerStatefulWidget {
  const PaymentManagementScreen({super.key});

  @override
  ConsumerState<PaymentManagementScreen> createState() => _PaymentManagementScreenState();
}

class _PaymentManagementScreenState extends ConsumerState<PaymentManagementScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchCtrl = TextEditingController();

  static const _tabs = [
    Tab(icon: Icon(Icons.all_inbox_rounded, size: 18), text: 'All (सबै)'),
    Tab(icon: Icon(Icons.pending_actions_rounded, size: 18), text: 'Pending (बाँकी)'),
    Tab(icon: Icon(Icons.verified_rounded, size: 18), text: 'Verified (स्वीकृत)'),
    Tab(icon: Icon(Icons.cancel_outlined, size: 18), text: 'Rejected (अस्वीकृत)'),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    String status = 'all';
    switch (_tabController.index) {
      case 1:
        status = 'pending';
        break;
      case 2:
        status = 'verified';
        break;
      case 3:
        status = 'rejected';
        break;
      default:
        status = 'all';
    }
    ref.read(paymentFilterProvider.notifier).update(
          (s) => s.copyWith(status: status),
        );
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleVerify(PaymentModel payment) async {
    final noteCtrl = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.green),
            SizedBox(width: 10),
            Text('Verify & Approve Payment?'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to approve the nomination payment of Rs. ${payment.amount.toStringAsFixed(0)} for candidate ${payment.candidateName ?? payment.userName ?? "Nominee"}?',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Txn Reference: ${payment.transactionReference.isNotEmpty ? payment.transactionReference : "N/A"}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: noteCtrl,
              decoration: const InputDecoration(
                labelText: 'Officer Verification Note (Optional)',
                hintText: 'e.g. Bank credit confirmed on passbook...',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.check_rounded, size: 16),
            label: const Text('Confirm Verification'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await ref.read(paymentActionsProvider.notifier).verifyPayment(
            payment.id,
            notes: noteCtrl.text.trim(),
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Payment #${payment.transactionReference} verified successfully!'),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Verification failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _handleReject(PaymentModel payment) async {
    final reasonCtrl = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.cancel_rounded, color: AppColors.error),
            SizedBox(width: 10),
            Text('Reject Payment Proof?'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Reject payment submission for ${payment.candidateName ?? payment.userName ?? "Nominee"}? Candidate will be notified to re-submit proof.',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(
                labelText: 'Rejection Reason *',
                hintText: 'e.g. Invalid Transaction ID, Unclear voucher screenshot...',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
            onPressed: () {
              if (reasonCtrl.text.trim().isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Please provide a rejection reason.')),
                );
                return;
              }
              Navigator.pop(ctx, true);
            },
            icon: const Icon(Icons.close_rounded, size: 16),
            label: const Text('Reject Payment'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await ref.read(paymentActionsProvider.notifier).rejectPayment(
            payment.id,
            reason: reasonCtrl.text.trim(),
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment rejected. Candidate notified.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Rejection failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showReceiptLightbox(PaymentModel payment) {
    final fullUrl = ApiConstants.getFullImageUrl(payment.receiptImageUrl);
    if (fullUrl == null) return;

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              constraints: const BoxConstraints(maxWidth: 600, maxHeight: 750),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(16),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: InteractiveViewer(
                  maxScale: 4.0,
                  child: Image.network(
                    fullUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => const Center(
                      child: Text('Failed to load image preview', style: TextStyle(color: Colors.white)),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: CircleAvatar(
                backgroundColor: Colors.black54,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final paymentsAsync = ref.watch(paymentsListProvider);
    final statsAsync = ref.watch(paymentStatsProvider);
    final electionsAsync = ref.watch(electionsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      drawer: const AdminDrawer(),
      appBar: AppBar(
        title: const Text('Payment History & Verifications (भुक्तानी इतिहास)'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          tooltip: 'Back',
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/dashboard');
            }
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Ledger',
            onPressed: () {
              ref.invalidate(paymentsListProvider);
              ref.invalidate(paymentStatsProvider);
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primary,
          indicatorWeight: 3,
          labelColor: AppColors.primary,
          unselectedLabelColor: isDark ? Colors.white70 : Colors.grey.shade700,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: _tabs,
        ),
      ),
      body: ResponsivePageWrapper(
        child: Column(
          children: [
            // ══════════════════════════════════════════════════════════
            // TOP METRICS CARDS
            // ══════════════════════════════════════════════════════════
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: statsAsync.when(
                loading: () => const SizedBox(height: 80, child: Center(child: CircularProgressIndicator())),
                error: (err, _) => const SizedBox.shrink(),
                data: (stats) => Row(
                  children: [
                    _buildStatCard(
                      title: 'Total Verified',
                      value: 'Rs. ${stats.totalCollected.toStringAsFixed(0)}',
                      subtitle: '${stats.verifiedCount} Approved',
                      icon: Icons.account_balance_wallet_rounded,
                      color: const Color(0xFF10B981),
                      isDark: isDark,
                    ),
                    const SizedBox(width: 12),
                    _buildStatCard(
                      title: 'Pending Review',
                      value: '${stats.pendingCount}',
                      subtitle: 'Rs. ${stats.pendingAmount.toStringAsFixed(0)}',
                      icon: Icons.pending_actions_rounded,
                      color: const Color(0xFFF59E0B),
                      isDark: isDark,
                    ),
                    const SizedBox(width: 12),
                    _buildStatCard(
                      title: 'Rejected',
                      value: '${stats.rejectedCount}',
                      subtitle: 'Returned',
                      icon: Icons.cancel_presentation_rounded,
                      color: AppColors.error,
                      isDark: isDark,
                    ),
                  ],
                ),
              ),
            ),

            // ══════════════════════════════════════════════════════════
            // FILTER & SEARCH TOOLBAR
            // ══════════════════════════════════════════════════════════
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _searchCtrl,
                      decoration: InputDecoration(
                        hintText: 'Search by Txn ID, Candidate Name, Email...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon: _searchCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  ref.read(paymentFilterProvider.notifier).update(
                                        (s) => s.copyWith(searchQuery: ''),
                                      );
                                },
                              )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onChanged: (val) {
                        ref.read(paymentFilterProvider.notifier).update(
                              (s) => s.copyWith(searchQuery: val),
                            );
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: electionsAsync.when(
                      loading: () => const SizedBox.shrink(),
                      error: (err, stack) => const SizedBox.shrink(),
                      data: (elections) {
                        final currentElection = ref.watch(paymentFilterProvider).electionId;
                        return DropdownButtonFormField<String>(
                          initialValue: currentElection.isEmpty ? null : currentElection,
                          decoration: InputDecoration(
                            hintText: 'All Elections',
                            prefixIcon: const Icon(Icons.how_to_vote_outlined, size: 18),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          items: [
                            const DropdownMenuItem(value: null, child: Text('All Elections')),
                            ...elections.map((e) => DropdownMenuItem(
                                  value: e.id,
                                  child: Text(e.title, overflow: TextOverflow.ellipsis),
                                )),
                          ],
                          onChanged: (val) {
                            ref.read(paymentFilterProvider.notifier).update(
                                  (s) => s.copyWith(electionId: val ?? ''),
                                );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // ══════════════════════════════════════════════════════════
            // TRANSACTION LEDGER LIST
            // ══════════════════════════════════════════════════════════
            Expanded(
              child: paymentsAsync.when(
                loading: () => const ListSkeleton(count: 5),
                error: (err, _) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 36),
                      const SizedBox(height: 8),
                      Text('Failed to load payments: $err'),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: () => ref.invalidate(paymentsListProvider),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
                data: (payments) {
                  if (payments.isEmpty) {
                    return EmptyStateWidget(
                      icon: Icons.receipt_long_outlined,
                      title: 'No Payment Records Found',
                      subtitle: 'Candidate Static QR payment submissions will appear here for verification.',
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: payments.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 14),
                    itemBuilder: (ctx, i) {
                      final p = payments[i];
                      return _buildPaymentCard(p, isDark, i);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    required bool isDark,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surface : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : Colors.grey.shade600, fontWeight: FontWeight.w600)),
                  Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
                  Text(subtitle, style: TextStyle(fontSize: 10, color: isDark ? Colors.white38 : Colors.grey.shade500)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentCard(PaymentModel p, bool isDark, int index) {
    final statusColor = _getStatusColor(p.status);
    final hasReceipt = p.receiptImageUrl.isNotEmpty;
    final receiptUrl = hasReceipt ? ApiConstants.getFullImageUrl(p.receiptImageUrl) : null;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surface : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.shade200,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Candidate name, Election, and Status badge
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (p.candidateImage != null && p.candidateImage!.isNotEmpty)
                CircleAvatar(
                  radius: 24,
                  backgroundImage: NetworkImage(p.candidateImage!),
                )
              else
                CircleAvatar(
                  radius: 24,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                  child: Text(
                    (p.candidateName?.isNotEmpty == true)
                        ? p.candidateName![0].toUpperCase()
                        : (p.userName?.isNotEmpty == true ? p.userName![0].toUpperCase() : '?'),
                    style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary, fontSize: 18),
                  ),
                ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (p.positionTitle != null) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              p.positionTitle!,
                              style: const TextStyle(
                                color: AppColors.primaryLight,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                          ),
                          child: Text(
                            p.statusDisplay.toUpperCase(),
                            style: TextStyle(
                              color: statusColor,
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      p.candidateName ?? p.userName ?? p.userEmail ?? 'Candidate Nominee',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    if (p.electionTitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Election: ${p.electionTitle}',
                        style: TextStyle(color: isDark ? Colors.white60 : Colors.grey.shade600, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 14),

          // Details Row: Amount, Txn Reference, Payment Method, Date
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('FEE AMOUNT', style: TextStyle(fontSize: 10, color: isDark ? Colors.white38 : Colors.grey.shade500, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text('Rs. ${p.amount.toStringAsFixed(0)} ${p.currency}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF10B981))),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('TXN REFERENCE / ID', style: TextStyle(fontSize: 10, color: isDark ? Colors.white38 : Colors.grey.shade500, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          p.transactionReference.isNotEmpty ? p.transactionReference : 'None Provided',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        if (p.transactionReference.isNotEmpty) ...[
                          const SizedBox(width: 4),
                          InkWell(
                            onTap: () {
                              Clipboard.setData(ClipboardData(text: p.transactionReference));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Transaction reference copied!')),
                              );
                            },
                            child: const Padding(
                              padding: EdgeInsets.all(4),
                              child: Icon(Icons.copy_rounded, size: 14, color: AppColors.primaryLight),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('PAYMENT TYPE', style: TextStyle(fontSize: 10, color: isDark ? Colors.white38 : Colors.grey.shade500, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(p.paymentMethodDisplay, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),

          // Rejection reason notice if rejected
          if (p.isRejected && p.rejectionReason.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, size: 16, color: AppColors.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Rejection Reason: ${p.rejectionReason}',
                      style: const TextStyle(color: AppColors.error, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Footer: Voucher Thumbnail + Action buttons
          const SizedBox(height: 14),
          Row(
            children: [
              if (receiptUrl != null)
                GestureDetector(
                  onTap: () => _showReceiptLightbox(p),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.receipt_rounded, size: 16, color: AppColors.primary),
                        SizedBox(width: 6),
                        Text('View Receipt Voucher', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary)),
                      ],
                    ),
                  ),
                )
              else
                const Text('No voucher uploaded', style: TextStyle(fontSize: 11, color: Colors.grey)),
              const Spacer(),

              // Verification Actions
              if (p.isPending) ...[
                OutlinedButton.icon(
                  onPressed: () => _handleReject(p),
                  icon: const Icon(Icons.close_rounded, size: 16, color: AppColors.error),
                  label: const Text('Reject', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: AppColors.error.withValues(alpha: 0.4)),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () => _handleVerify(p),
                  icon: const Icon(Icons.check_rounded, size: 16),
                  label: const Text('Verify & Approve', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                  ),
                ),
              ] else if (p.isVerified) ...[
                Row(
                  children: [
                    const Icon(Icons.verified_user_rounded, size: 16, color: Colors.green),
                    const SizedBox(width: 4),
                    Text('Verified by ${p.reviewedByEmail ?? "Officer"}', style: const TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ],
          ),
        ],
      ),
    )
    .animate()
    .fade(delay: Duration(milliseconds: 25 * index))
    .slideY(begin: 0.05, end: 0);
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'verified':
      case 'completed':
        return Colors.green;
      case 'rejected':
      case 'failed':
        return AppColors.error;
      case 'pending':
      default:
        return const Color(0xFFF59E0B);
    }
  }
}
