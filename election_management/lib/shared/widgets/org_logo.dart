import 'package:flutter/material.dart';
import '../../core/network/api_constants.dart';
import '../../core/theme/app_theme.dart';

/// An organization's logo in a rounded square, falling back to its initials.
class OrgLogo extends StatelessWidget {
  final String name;
  final String logoUrl;
  final double size;

  const OrgLogo({super.key, required this.name, required this.logoUrl, this.size = 44});

  String get _initials {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '?';
    return words.take(2).map((w) => w[0].toUpperCase()).join();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final url = ApiConstants.getFullImageUrl(logoUrl);
    final fallback = Center(
      child: Text(
        _initials,
        style: TextStyle(
          color: isDark ? AppColors.primaryLight : AppColors.primary,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.34,
        ),
      ),
    );
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: isDark ? AppColors.primary.withValues(alpha: 0.18) : AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(size * 0.28),
        border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.shade200),
      ),
      child: url == null
          ? fallback
          : Image.network(url, fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback),
    );
  }
}
