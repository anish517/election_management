import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/error_helper.dart';

/// A production-grade, state-aware error view widget that replaces raw
/// browser/Dio exceptions with plain, human-friendly recovery actions.
class AppErrorView extends StatelessWidget {
  final dynamic error;
  final VoidCallback? onRetry;
  final String? title;
  final String? message;
  final IconData? icon;
  final bool isCompact;

  const AppErrorView({
    super.key,
    required this.error,
    this.onRetry,
    this.title,
    this.message,
    this.icon,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cleanMsg = message ?? extractApiErrorMessage(error);
    final isNetwork = cleanMsg.toLowerCase().contains('network') ||
        cleanMsg.toLowerCase().contains('reach the election server') ||
        cleanMsg.toLowerCase().contains('timed out');
    final isSession = isSessionExpiredError(error) || cleanMsg.toLowerCase().contains('session expired');

    final displayIcon = icon ??
        (isNetwork
            ? Icons.wifi_off_rounded
            : (isSession ? Icons.lock_clock_outlined : Icons.error_outline_rounded));

    final displayTitle = title ??
        (isNetwork
            ? 'Connection Interrupted'
            : (isSession ? 'Session Expired' : 'Unable to Load Data'));

    if (isCompact) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        margin: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: isDark ? 0.15 : 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.error.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Icon(displayIcon, size: 20, color: AppColors.error),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                cleanMsg,
                style: TextStyle(
                  color: isDark ? Colors.white70 : Colors.grey.shade800,
                  fontSize: 12.5,
                ),
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 18),
                tooltip: 'Try Again',
                color: AppColors.primaryLight,
                onPressed: onRetry,
              ),
            ],
          ],
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.error.withValues(alpha: isDark ? 0.18 : 0.09),
                  border: Border.all(
                    color: AppColors.error.withValues(alpha: 0.25),
                    width: 1.5,
                  ),
                ),
                child: Icon(displayIcon, size: 40, color: AppColors.error),
              ),
              const SizedBox(height: 20),
              Text(
                displayTitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                cleanMsg,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark ? Colors.white60 : Colors.grey.shade600,
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Try Again', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

