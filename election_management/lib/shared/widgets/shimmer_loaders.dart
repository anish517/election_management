import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../../core/theme/app_theme.dart';

/// A base shimmer container that applies the shimmer effect to any child.
class _ShimmerBox extends StatelessWidget {
  final double width;
  final double height;
  final double radius;

  const _ShimmerBox({
    required this.width,
    required this.height,
    this.radius = 8,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Wraps children in a Shimmer animation.
Widget _shimmer({required Widget child}) {
  return Shimmer.fromColors(
    baseColor: AppColors.surfaceVariant,
    highlightColor: AppColors.surface.withValues(alpha: 0.7),
    child: child,
  );
}

/// A single shimmer row that mimics a ListTile.
class ListItemSkeleton extends StatelessWidget {
  const ListItemSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return _shimmer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const _ShimmerBox(width: 44, height: 44, radius: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ShimmerBox(width: double.infinity, height: 14),
                  const SizedBox(height: 8),
                  _ShimmerBox(width: MediaQuery.of(context).size.width * 0.5, height: 11),
                ],
              ),
            ),
            const SizedBox(width: 12),
            const _ShimmerBox(width: 24, height: 24, radius: 4),
          ],
        ),
      ),
    );
  }
}

/// A list of [ListItemSkeleton] rows separated by gaps.
class ListSkeleton extends StatelessWidget {
  final int count;
  const ListSkeleton({super.key, this.count = 6});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      physics: const NeverScrollableScrollPhysics(),
      itemCount: count,
      separatorBuilder: (_, i) => const SizedBox(height: 8),
      itemBuilder: (_, i) => const ListItemSkeleton(),
    );
  }
}

/// A single shimmer block mimicking an election/candidate card.
class CardSkeleton extends StatelessWidget {
  const CardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return _shimmer(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.surfaceVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _ShimmerBox(
                  width: MediaQuery.of(context).size.width * 0.55,
                  height: 16,
                ),
                const _ShimmerBox(width: 72, height: 22, radius: 8),
              ],
            ),
            const SizedBox(height: 10),
            _ShimmerBox(width: double.infinity, height: 12),
            const SizedBox(height: 6),
            _ShimmerBox(width: MediaQuery.of(context).size.width * 0.7, height: 12),
            const SizedBox(height: 14),
            Row(
              children: [
                const _ShimmerBox(width: 90, height: 26, radius: 6),
                const SizedBox(width: 8),
                const _ShimmerBox(width: 80, height: 26, radius: 6),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A list of [CardSkeleton]s.
class CardListSkeleton extends StatelessWidget {
  final int count;
  const CardListSkeleton({super.key, this.count = 4});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      physics: const NeverScrollableScrollPhysics(),
      itemCount: count,
      separatorBuilder: (_, i) => const SizedBox(height: 10),
      itemBuilder: (_, i) => const CardSkeleton(),
    );
  }
}

/// Shimmer skeleton for the dashboard stats row (3 stat cards).
class DashboardSkeleton extends StatelessWidget {
  const DashboardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return _shimmer(
      child: Row(
        children: List.generate(3, (i) {
          return Expanded(
            child: Container(
              margin: EdgeInsets.only(left: i == 0 ? 0 : 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.surfaceVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _ShimmerBox(width: 28, height: 28, radius: 6),
                  const SizedBox(height: 10),
                  const _ShimmerBox(width: double.infinity, height: 22),
                  const SizedBox(height: 6),
                  const _ShimmerBox(width: 50, height: 12),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// Shimmer skeleton for the User Profile screen.
class ProfileSkeleton extends StatelessWidget {
  const ProfileSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return _shimmer(
      child: Column(
        children: [
          const SizedBox(height: 40),
          const _ShimmerBox(width: 96, height: 96, radius: 48),
          const SizedBox(height: 16),
          const _ShimmerBox(width: 180, height: 18),
          const SizedBox(height: 8),
          const _ShimmerBox(width: 80, height: 24, radius: 12),
          const SizedBox(height: 32),
          _buildInfoTileSkeleton(),
          const SizedBox(height: 12),
          _buildInfoTileSkeleton(),
          const SizedBox(height: 12),
          _buildInfoTileSkeleton(),
        ],
      ),
    );
  }

  Widget _buildInfoTileSkeleton() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const _ShimmerBox(width: 36, height: 36, radius: 8),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _ShimmerBox(width: 80, height: 11),
                const SizedBox(height: 6),
                _ShimmerBox(width: double.infinity, height: 14),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
