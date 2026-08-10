import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/models.dart';

/// Opens a rich candidate profile as a full-screen modal bottom sheet.
void showCandidateProfile(BuildContext context, CandidateModel candidate) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => CandidateProfileSheet(candidate: candidate),
  );
}

class CandidateProfileSheet extends StatefulWidget {
  final CandidateModel candidate;
  const CandidateProfileSheet({super.key, required this.candidate});

  @override
  State<CandidateProfileSheet> createState() => _CandidateProfileSheetState();
}

class _CandidateProfileSheetState extends State<CandidateProfileSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = widget.candidate;
    final hasPhoto = c.photoUrl != null && c.photoUrl!.isNotEmpty;
    final sheetBg = isDark ? AppColors.surface : Colors.white;
    final statusColor = _statusColor(c.status);

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, scrollController) {
        return Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: sheetBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              // ── Drag handle ──
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 4),
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? AppColors.surfaceVariant : const Color(0xFFCDD5E0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // ── Hero header ──
              _HeroHeader(candidate: c, isDark: isDark, hasPhoto: hasPhoto, statusColor: statusColor),

              // ── Tab bar ──
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.background : const Color(0xFFF0F3F8),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicator: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  labelColor: Colors.white,
                  unselectedLabelColor: isDark ? AppColors.textMuted : AppColors.textSecondaryLightMode,
                  labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  tabs: const [
                    Tab(text: 'Platform / Manifesto'),
                    Tab(text: 'About'),
                  ],
                ),
              ),

              // ── Tab content ──
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _ManifestoTab(candidate: c, isDark: isDark, scrollController: scrollController),
                    _AboutTab(candidate: c, isDark: isDark, scrollController: scrollController),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'approved': return AppColors.success;
      case 'rejected': return AppColors.error;
      case 'submitted': return Colors.blue;
      case 'under_review': return AppColors.warning;
      default: return AppColors.textMuted;
    }
  }
}

// ─── Hero Header ─────────────────────────────────────────────────────────────

class _HeroHeader extends StatelessWidget {
  final CandidateModel candidate;
  final bool isDark;
  final bool hasPhoto;
  final Color statusColor;

  const _HeroHeader({
    required this.candidate,
    required this.isDark,
    required this.hasPhoto,
    required this.statusColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          // Avatar with animated border
          Hero(
            tag: 'candidate_avatar_${candidate.id}',
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    AppColors.primaryLight.withValues(alpha: 0.8),
                    AppColors.primary.withValues(alpha: 0.4),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              padding: const EdgeInsets.all(3),
              child: CircleAvatar(
                radius: 40,
                backgroundColor: isDark ? AppColors.background : const Color(0xFFF0F3F8),
                backgroundImage: hasPhoto ? NetworkImage(candidate.photoUrl!) : null,
                child: !hasPhoto
                    ? Text(
                        _initials(candidate.name),
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primaryLight,
                        ),
                      )
                    : null,
              ),
            ),
          )
              .animate()
              .scale(begin: const Offset(0.7, 0.7), duration: 400.ms, curve: Curves.easeOutBack),

          const SizedBox(width: 16),

          // Name + position + status badge
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  candidate.name,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ).animate().fadeIn(duration: 350.ms, delay: 100.ms).slideX(begin: 0.15),

                if (candidate.positionTitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    'Running for ${candidate.positionTitle}',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? AppColors.textMuted : AppColors.textSecondaryLightMode,
                    ),
                  ).animate().fadeIn(duration: 350.ms, delay: 150.ms),
                ],

                if (candidate.slateName.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(children: [
                    const Icon(Icons.groups_rounded, size: 13, color: AppColors.primaryLight),
                    const SizedBox(width: 4),
                    Text(
                      candidate.slateName,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.primaryLight,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ]).animate().fadeIn(duration: 350.ms, delay: 200.ms),
                ],

                const SizedBox(height: 8),
                if (candidate.status != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: statusColor.withValues(alpha: 0.35)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        width: 6, height: 6,
                        decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        candidate.status!.replaceAll('_', ' ').toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: statusColor,
                        ),
                      ),
                    ]),
                  ).animate().fadeIn(duration: 350.ms, delay: 250.ms),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }
}

// ─── Tab 1: Manifesto / Platform ─────────────────────────────────────────────

class _ManifestoTab extends StatelessWidget {
  final CandidateModel candidate;
  final bool isDark;
  final ScrollController scrollController;

  const _ManifestoTab({required this.candidate, required this.isDark, required this.scrollController});

  @override
  Widget build(BuildContext context) {
    final hasManifesto = candidate.manifesto.trim().isNotEmpty;

    return SingleChildScrollView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      child: hasManifesto
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Decorative quote mark
                Text(
                  '"',
                  style: TextStyle(
                    fontSize: 72,
                    height: 0.8,
                    color: AppColors.primaryLight.withValues(alpha: 0.18),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                // Manifesto text rendered as styled paragraphs
                ..._buildParagraphs(context, candidate.manifesto, isDark),
                const SizedBox(height: 20),
                // Decorative bottom bar
                Row(children: [
                  Expanded(
                    child: Container(
                      height: 2,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [AppColors.primaryLight.withValues(alpha: 0.5), Colors.transparent],
                        ),
                      ),
                    ),
                  ),
                ]),
              ],
            )
            .animate()
            .fadeIn(duration: 400.ms)
            .slideY(begin: 0.05, duration: 400.ms, curve: Curves.easeOut)
          : _EmptyManifesto(isDark: isDark),
    );
  }

  List<Widget> _buildParagraphs(BuildContext context, String text, bool isDark) {
    final paragraphs = text.split('\n').where((p) => p.trim().isNotEmpty).toList();
    final textColor = isDark ? Colors.white.withValues(alpha: 0.87) : const Color(0xFF374151);

    return paragraphs.asMap().entries.map((entry) {
      final isFirst = entry.key == 0;
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Text(
          entry.value.trim(),
          style: TextStyle(
            fontSize: isFirst ? 16 : 14.5,
            height: 1.65,
            color: textColor,
            fontWeight: isFirst ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      );
    }).toList();
  }
}

class _EmptyManifesto extends StatelessWidget {
  final bool isDark;
  const _EmptyManifesto({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 220,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Animated pencil icon
          Icon(
            Icons.edit_note_rounded,
            size: 64,
            color: isDark ? AppColors.textMuted : const Color(0xFFCDD5E0),
          )
              .animate(onPlay: (ctrl) => ctrl.repeat(reverse: true))
              .scaleXY(begin: 0.95, end: 1.05, duration: 1200.ms, curve: Curves.easeInOut),
          const SizedBox(height: 16),
          Text(
            'No manifesto submitted yet',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: isDark ? AppColors.textMuted : AppColors.textSecondaryLightMode,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'The candidate has not written a platform statement.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? AppColors.textMuted : AppColors.textSecondaryLightMode,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Tab 2: About ─────────────────────────────────────────────────────────────

class _AboutTab extends StatelessWidget {
  final CandidateModel candidate;
  final bool isDark;
  final ScrollController scrollController;

  const _AboutTab({required this.candidate, required this.isDark, required this.scrollController});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InfoRow(
            icon: Icons.badge_rounded,
            label: 'Full Name',
            value: candidate.name,
            isDark: isDark,
          ).animate().fadeIn(delay: 50.ms).slideX(begin: 0.1),

          if (candidate.memberEmail != null && candidate.memberEmail!.isNotEmpty)
            _InfoRow(
              icon: Icons.alternate_email_rounded,
              label: 'Email',
              value: candidate.memberEmail!,
              isDark: isDark,
            ).animate().fadeIn(delay: 100.ms).slideX(begin: 0.1),

          if (candidate.positionTitle != null)
            _InfoRow(
              icon: Icons.work_outline_rounded,
              label: 'Running For',
              value: candidate.positionTitle!,
              isDark: isDark,
            ).animate().fadeIn(delay: 150.ms).slideX(begin: 0.1),

          if (candidate.slateName.isNotEmpty)
            _InfoRow(
              icon: Icons.groups_rounded,
              label: 'Slate / Party',
              value: candidate.slateName,
              isDark: isDark,
            ).animate().fadeIn(delay: 200.ms).slideX(begin: 0.1),

          if (candidate.status != null)
            _InfoRow(
              icon: Icons.verified_rounded,
              label: 'Nomination Status',
              value: candidate.status!.replaceAll('_', ' ').toUpperCase(),
              isDark: isDark,
              valueColor: _statusColor(candidate.status),
            ).animate().fadeIn(delay: 250.ms).slideX(begin: 0.1),

          if (candidate.reviewNotes.isNotEmpty) ...[
            const SizedBox(height: 8),
            _InfoRow(
              icon: Icons.comment_rounded,
              label: 'Review Notes',
              value: candidate.reviewNotes,
              isDark: isDark,
            ).animate().fadeIn(delay: 300.ms).slideX(begin: 0.1),
          ],
        ],
      ),
    );
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'approved': return AppColors.success;
      case 'rejected': return AppColors.error;
      case 'submitted': return Colors.blue;
      case 'under_review': return AppColors.warning;
      default: return AppColors.textMuted;
    }
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool isDark;
  final Color? valueColor;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.isDark,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.background : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppColors.surfaceVariant : Colors.black.withValues(alpha: 0.05),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primaryLight.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 18, color: AppColors.primaryLight),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? AppColors.textMuted : AppColors.textSecondaryLightMode,
                      fontWeight: FontWeight.w500,
                    )),
                const SizedBox(height: 3),
                Text(value,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: valueColor,
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
