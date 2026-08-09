import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// A polished, reusable empty-state widget.
class EmptyStateWidget extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? ctaLabel;
  final VoidCallback? onCta;

  const EmptyStateWidget({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.ctaLabel,
    this.onCta,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor = isDark ? AppColors.textMuted : AppColors.textMutedLightMode;
    final titleColor = isDark ? AppColors.textSecondary : AppColors.textSecondaryLightMode;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: AppColors.primaryLight.withValues(alpha: 0.08),
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.primaryLight.withValues(alpha: 0.15),
                  width: 1.5,
                ),
              ),
              child: Icon(icon, size: 44, color: iconColor),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: titleColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: iconColor,
                  height: 1.5,
                ),
              ),
            ],
            if (ctaLabel != null && onCta != null) ...[
              const SizedBox(height: 28),
              ElevatedButton.icon(
                onPressed: onCta,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(ctaLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
