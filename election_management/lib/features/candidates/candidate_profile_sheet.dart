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
    _tabController = TabController(length: 3, vsync: this);
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
    final sheetBg = isDark ? const Color(0xFF18181B) : Colors.white;
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
              // ── Drag Handle ──
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 6),
                width: 44,
                height: 4.5,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),

              // ── Hero Header Banner ──
              _HeroHeader(candidate: c, isDark: isDark, hasPhoto: hasPhoto, statusColor: statusColor),

              // ── Segmented Tab Bar ──
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.surfaceVariant.withValues(alpha: 0.5) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicator: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primaryLight.withValues(alpha: 0.25),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  labelColor: Colors.white,
                  unselectedLabelColor: isDark ? Colors.white60 : Colors.grey.shade600,
                  labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                  tabs: const [
                    Tab(icon: Icon(Icons.menu_book_rounded, size: 16), text: 'Platform & Manifesto'),
                    Tab(icon: Icon(Icons.person_outline_rounded, size: 16), text: 'Credentials & About'),
                    Tab(icon: Icon(Icons.draw_rounded, size: 16), text: 'Endorsements'),
                  ],
                ),
              ),

              // ── Tab Content ──
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _ManifestoTab(candidate: c, isDark: isDark),
                    _AboutTab(candidate: c, isDark: isDark),
                    _EndorsementsTab(candidate: c, isDark: isDark),
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
    switch (status?.toLowerCase()) {
      case 'approved':
        return const Color(0xFF10B981);
      case 'rejected':
        return const Color(0xFFEF4444);
      case 'withdrawn':
        return Colors.grey;
      case 'submitted':
      case 'pending':
      case 'under_review':
        return const Color(0xFFF59E0B);
      default:
        return AppColors.textMuted;
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
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          // Avatar with gradient border
          Hero(
            tag: 'candidate_avatar_${candidate.id}',
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF4F46E5).withValues(alpha: 0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(3),
              child: CircleAvatar(
                radius: 40,
                backgroundColor: isDark ? const Color(0xFF27272A) : const Color(0xFFF0F3F8),
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

          const SizedBox(width: 18),

          // Name + position + status badge
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  candidate.name,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ).animate().fadeIn(duration: 350.ms, delay: 100.ms).slideX(begin: 0.15),

                if (candidate.positionTitle != null && candidate.positionTitle!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Running for ${candidate.positionTitle}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryLight,
                      ),
                    ),
                  ).animate().fadeIn(duration: 350.ms, delay: 150.ms),
                ],

                const SizedBox(height: 8),
                Row(
                  children: [
                    if (candidate.status != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: statusColor.withValues(alpha: 0.35)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              candidate.status!.replaceAll('_', ' ').toUpperCase(),
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: statusColor,
                              ),
                            ),
                          ],
                        ),
                      ).animate().fadeIn(duration: 350.ms, delay: 250.ms),
                  ],
                ),
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

  const _ManifestoTab({required this.candidate, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final hasPersonalDesc = candidate.personalDescription.trim().isNotEmpty;
    final hasManifesto = candidate.manifesto.trim().isNotEmpty;

    if (!hasPersonalDesc && !hasManifesto) {
      return _EmptyManifesto(isDark: isDark);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Personal Description & Background Summary
          if (hasPersonalDesc) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceVariant.withValues(alpha: 0.4) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.account_box_outlined, size: 18, color: AppColors.primaryLight),
                      const SizedBox(width: 8),
                      Text(
                        'Biographical Summary & Experience',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white70 : Colors.grey.shade800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    candidate.personalDescription.trim(),
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.6,
                      color: isDark ? Colors.white70 : const Color(0xFF374151),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          // Platform & Manifesto
          if (hasManifesto) ...[
            Row(
              children: [
                const Icon(Icons.menu_book_rounded, size: 18, color: AppColors.primaryLight),
                const SizedBox(width: 8),
                Text(
                  'Election Manifesto & Platform Agenda (घोषणापत्र)',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceVariant.withValues(alpha: 0.3) : const Color(0xFFFAFAFA),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '"',
                    style: TextStyle(
                      fontSize: 48,
                      height: 0.6,
                      color: AppColors.primaryLight.withValues(alpha: 0.25),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ..._buildParagraphs(context, candidate.manifesto, isDark),
                ],
              ),
            ),
          ],
        ],
      ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.05, duration: 400.ms, curve: Curves.easeOut),
    );
  }

  List<Widget> _buildParagraphs(BuildContext context, String text, bool isDark) {
    final paragraphs = text.split('\n').where((p) => p.trim().isNotEmpty).toList();
    final textColor = isDark ? Colors.white.withValues(alpha: 0.87) : const Color(0xFF374151);

    return paragraphs.asMap().entries.map((entry) {
      final isFirst = entry.key == 0;
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          entry.value.trim(),
          style: TextStyle(
            fontSize: isFirst ? 14.5 : 13.5,
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
          Icon(
            Icons.edit_note_rounded,
            size: 64,
            color: isDark ? AppColors.textMuted : const Color(0xFFCDD5E0),
          ).animate(onPlay: (ctrl) => ctrl.repeat(reverse: true)).scaleXY(begin: 0.95, end: 1.05, duration: 1200.ms, curve: Curves.easeInOut),
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
            'The candidate has not submitted a platform statement.',
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

// ─── Tab 2: About & Credentials ──────────────────────────────────────────────

class _AboutTab extends StatelessWidget {
  final CandidateModel candidate;
  final bool isDark;

  const _AboutTab({required this.candidate, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InfoRow(
            icon: Icons.badge_rounded,
            label: 'Full Legal Name',
            value: candidate.name,
            isDark: isDark,
          ).animate().fadeIn(delay: 50.ms).slideX(begin: 0.1),

          if (candidate.email != null && candidate.email!.isNotEmpty)
            _InfoRow(
              icon: Icons.alternate_email_rounded,
              label: 'Verified Electoral Email',
              value: candidate.email!,
              isDark: isDark,
            ).animate().fadeIn(delay: 100.ms).slideX(begin: 0.1),

          if (candidate.contactNumber != null && candidate.contactNumber!.isNotEmpty)
            _InfoRow(
              icon: Icons.phone_rounded,
              label: 'Contact Phone Number',
              value: candidate.contactNumber!,
              isDark: isDark,
            ).animate().fadeIn(delay: 120.ms).slideX(begin: 0.1),

          if (candidate.positionTitle != null && candidate.positionTitle!.isNotEmpty)
            _InfoRow(
              icon: Icons.military_tech_rounded,
              label: 'Contested Office & Designation',
              value: candidate.positionTitle!,
              isDark: isDark,
            ).animate().fadeIn(delay: 150.ms).slideX(begin: 0.1),

          if (candidate.quotaName != null && candidate.quotaName!.isNotEmpty)
            _InfoRow(
              icon: Icons.category_rounded,
              label: 'Affirmative Action Quota',
              value: candidate.quotaName!,
              isDark: isDark,
              valueColor: Colors.purple,
            ).animate().fadeIn(delay: 170.ms).slideX(begin: 0.1),

          if (candidate.gender != null && candidate.gender!.isNotEmpty)
            _InfoRow(
              icon: Icons.wc_rounded,
              label: 'Gender',
              value: candidate.gender!,
              isDark: isDark,
            ).animate().fadeIn(delay: 190.ms).slideX(begin: 0.1),

          if (candidate.address != null && candidate.address!.isNotEmpty)
            _InfoRow(
              icon: Icons.location_on_rounded,
              label: 'Residential Address',
              value: candidate.address!,
              isDark: isDark,
            ).animate().fadeIn(delay: 210.ms).slideX(begin: 0.1),

          if (candidate.status != null)
            _InfoRow(
              icon: Icons.verified_rounded,
              label: 'Scrutiny Nomination Status',
              value: candidate.status!.replaceAll('_', ' ').toUpperCase(),
              isDark: isDark,
              valueColor: _statusColor(candidate.status),
            ).animate().fadeIn(delay: 250.ms).slideX(begin: 0.1),

          if (candidate.reviewNotes.isNotEmpty) ...[
            const SizedBox(height: 8),
            _InfoRow(
              icon: Icons.comment_rounded,
              label: 'Scrutiny Officer Review Notes',
              value: candidate.reviewNotes,
              isDark: isDark,
            ).animate().fadeIn(delay: 300.ms).slideX(begin: 0.1),
          ],
        ],
      ),
    );
  }

  Color _statusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'approved':
        return const Color(0xFF10B981);
      case 'rejected':
        return const Color(0xFFEF4444);
      case 'withdrawn':
        return Colors.grey;
      case 'submitted':
      case 'pending':
      case 'under_review':
        return const Color(0xFFF59E0B);
      default:
        return AppColors.textMuted;
    }
  }
}

// ─── Tab 3: Endorsements ──────────────────────────────────────────────────────

class _EndorsementsTab extends StatelessWidget {
  final CandidateModel candidate;
  final bool isDark;

  const _EndorsementsTab({required this.candidate, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final endorsements = candidate.endorsements.where((e) => e.name.isNotEmpty).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: endorsements.isEmpty
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 48),
                Icon(
                  Icons.group_off_rounded,
                  size: 64,
                  color: isDark ? AppColors.textMuted : const Color(0xFFCDD5E0),
                ).animate().scaleXY(begin: 0.95, end: 1.05, duration: 1200.ms, curve: Curves.easeInOut),
                const SizedBox(height: 16),
                Text(
                  'No Statutory Endorsements',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppColors.textMuted : AppColors.textSecondaryLightMode,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'No proposer or seconder endorsements are attached to this nomination.',
                  style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.grey.shade600),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.draw_rounded, size: 18, color: AppColors.primaryLight),
                    const SizedBox(width: 8),
                    Text(
                      'Statutory Nominators & Endorsements (प्रस्तावक र समर्थक)',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ],
                ).animate().fadeIn(delay: 50.ms),
                const SizedBox(height: 16),
                ...() {
                  int pCount = 0;
                  int sCount = 0;
                  return endorsements.map((e) {
                    final isP = e.endorsementType.toLowerCase() == 'proposer';
                    final idx = isP ? ++pCount : ++sCount;
                    return _buildEndorsementCard(e, idx, isDark);
                  });
                }(),
              ],
            ),
    );
  }

  Widget _buildEndorsementCard(CandidateEndorsementModel e, int index, bool isDark) {
    final isProposer = e.endorsementType.toLowerCase() == 'proposer';
    final primaryColor = isProposer ? const Color(0xFF2563EB) : const Color(0xFF059669);
    final roleTitle = isProposer ? 'PROPOSER / प्रस्तावक #$index' : 'SUPPORTER / समर्थक #$index';
    final roleIcon = isProposer ? Icons.how_to_reg_rounded : Icons.verified_user_rounded;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceVariant.withValues(alpha: 0.3) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: primaryColor.withValues(alpha: isDark ? 0.35 : 0.25),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withValues(alpha: isDark ? 0.08 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Ribbon
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: isDark ? 0.15 : 0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              border: Border(bottom: BorderSide(color: primaryColor.withValues(alpha: 0.2))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(roleIcon, size: 18, color: primaryColor),
                    const SizedBox(width: 8),
                    Text(
                      roleTitle,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        letterSpacing: 0.3,
                        color: primaryColor,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_rounded, size: 13, color: Colors.green),
                      SizedBox(width: 4),
                      Text('Verified Roll', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.green)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Body Content
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name & Avatar
                Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: primaryColor.withValues(alpha: 0.12),
                      child: Text(
                        e.name.isNotEmpty ? e.name[0].toUpperCase() : '?',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primaryColor),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e.name,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          if (e.membershipId.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.grey.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'Voter / Member ID: ${e.membershipId}',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isDark ? Colors.white70 : Colors.grey.shade700),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),
                const Divider(height: 1),
                const SizedBox(height: 12),

                // Details Grid
                Row(
                  children: [
                    if (e.phone.isNotEmpty)
                      Expanded(
                        child: Row(
                          children: [
                            Icon(Icons.phone_rounded, size: 16, color: primaryColor),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Phone Number', style: TextStyle(fontSize: 10.5, color: isDark ? Colors.white54 : Colors.grey.shade600)),
                                  Text(e.phone, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (e.citizenshipNumber.isNotEmpty)
                      Expanded(
                        child: Row(
                          children: [
                            Icon(Icons.badge_outlined, size: 16, color: primaryColor),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Citizenship / Council No', style: TextStyle(fontSize: 10.5, color: isDark ? Colors.white54 : Colors.grey.shade600)),
                                  Text(e.citizenshipNumber, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),

                // Signature Image Box
                if (e.signatureUrl.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.withValues(alpha: 0.25)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.draw_rounded, size: 14, color: isDark ? Colors.white54 : Colors.grey.shade600),
                            const SizedBox(width: 6),
                            Text(
                              'Endorsement Signature',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isDark ? Colors.white54 : Colors.grey.shade600),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Container(
                          height: 70,
                          width: 180,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.network(
                              e.signatureUrl,
                              fit: BoxFit.contain,
                              errorBuilder: (ctx, err, stack) => Center(
                                child: Text('Signature on file', style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontStyle: FontStyle.italic)),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 100.ms).slideY(begin: 0.05);
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
        color: isDark ? AppColors.surfaceVariant.withValues(alpha: 0.3) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
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
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? AppColors.textMuted : AppColors.textSecondaryLightMode,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: valueColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
