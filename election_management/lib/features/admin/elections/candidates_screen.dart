import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/network/api_constants.dart';
import '../../../shared/models/models.dart';
import 'create_candidate_screen.dart';
import '../../candidates/candidate_profile_sheet.dart';
import '../../shared/digital_id_card_dialog.dart';

class CandidatesScreen extends ConsumerStatefulWidget {
  final String electionId;
  const CandidatesScreen({super.key, required this.electionId});

  @override
  ConsumerState<CandidatesScreen> createState() => _CandidatesScreenState();
}

class _CandidatesScreenState extends ConsumerState<CandidatesScreen> {
  String? _selectedPositionFilter; // null = all
  String _statusFilter = 'all'; // 'all', 'approved', 'pending', 'rejected'
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Color _getStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'approved':
      case 'verified':
      case 'valid':
        return Colors.green;
      case 'rejected':
      case 'disqualified':
        return Colors.red;
      case 'withdrawn':
        return Colors.grey.shade600;
      case 'pending':
      case 'submitted':
      case 'under_review':
      default:
        return Colors.amber.shade800;
    }
  }

  String _formatStatusText(String? status) {
    if (status == null || status.isEmpty) return 'Pending Review';
    final clean = status.replaceAll('_', ' ');
    return clean[0].toUpperCase() + clean.substring(1);
  }

  Color _parseColor(String hex) {
    try {
      final h = hex.replaceAll('#', '');
      return Color(int.parse('FF$h', radix: 16));
    } catch (_) {
      return AppColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final electionAsync = ref.watch(electionProvider(widget.electionId));
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ══════════════════════════════════════════════════════════════
          // HERO BANNER
          // ══════════════════════════════════════════════════════════════
          _buildHeroHeader(context, electionAsync, isDark),
          const SizedBox(height: 24),

          // ══════════════════════════════════════════════════════════════
          // CANDIDATE ROSTER CARD
          // ══════════════════════════════════════════════════════════════
          Material(
            color: isDark ? AppColors.surface : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(
                color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.shade200,
              ),
            ),
            elevation: isDark ? 0 : 1,
            shadowColor: Colors.black.withValues(alpha: 0.04),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Toolbar: Actions, Search, Position & Status Filters
                  _buildToolbar(context, electionAsync, isDark),
                  const SizedBox(height: 20),

                  // Candidate List Body
                  electionAsync.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (err, _) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 36),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline_rounded, color: Colors.red, size: 36),
                            const SizedBox(height: 10),
                            Text('Failed to load candidate roster: $err', style: const TextStyle(color: Colors.red)),
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              onPressed: () => ref.invalidate(electionProvider(widget.electionId)),
                              icon: const Icon(Icons.refresh_rounded, size: 16),
                              label: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    data: (election) => _buildCandidateList(context, election, isDark),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // 1. HERO HEADER WITH SCRUTINY STATS
  // ════════════════════════════════════════════════════════════════════════════
  Widget _buildHeroHeader(BuildContext context, AsyncValue<ElectionModel> electionAsync, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF065F46), Color(0xFF059669), Color(0xFF10B981)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF059669).withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -25,
            top: -25,
            child: Icon(
              Icons.groups_rounded,
              size: 160,
              color: Colors.white.withValues(alpha: 0.08),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.how_to_reg_rounded, color: Colors.amberAccent, size: 14),
                      SizedBox(width: 6),
                      Text(
                        'CANDIDATE NOMINATIONS & SCRUTINY',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 0.8),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Candidate Nominations & Scrutiny',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.5,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'उम्मेदवार नामावली तथा छानबिन — Review nomination filings, scrutinize eligibility criteria, and verify publication readiness.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 20),

                // Real-time Candidate Scrutiny Stats Row
                electionAsync.maybeWhen(
                  data: (election) {
                    final allCandidates = election.positions.expand((p) => p.candidates).toList();
                    final total = allCandidates.length;
                    final approved = allCandidates.where((c) => c.status == 'approved' || c.status == 'verified').length;
                    final pending = allCandidates.where((c) => c.status == null || c.status == 'pending' || c.status == 'under_review').length;
                    final rejected = allCandidates.where((c) => c.status == 'rejected' || c.status == 'disqualified' || c.status == 'withdrawn').length;

                    return Wrap(
                      spacing: 12,
                      runSpacing: 10,
                      children: [
                        _buildStatChip('Total Nominations', '$total', Icons.groups_rounded, Colors.white),
                        _buildStatChip('Approved & Valid', '$approved', Icons.check_circle_outline_rounded, Colors.greenAccent),
                        _buildStatChip('Pending Review', '$pending', Icons.hourglass_top_rounded, Colors.amberAccent),
                        _buildStatChip('Rejected / Withdrawn', '$rejected', Icons.cancel_outlined, Colors.redAccent.shade100),
                      ],
                    );
                  },
                  orElse: () => const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ],
      ),
    )
    .animate()
    .fade(duration: 300.ms)
    .slideY(begin: -0.05, end: 0);
  }

  Widget _buildStatChip(String label, String value, IconData icon, Color accentColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: accentColor),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.7), fontWeight: FontWeight.w500)),
              Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: accentColor)),
            ],
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // 2. TOOLBAR WITH FILTERS & ADD CANDIDATE CTA
  // ════════════════════════════════════════════════════════════════════════════
  Widget _buildToolbar(BuildContext context, AsyncValue<ElectionModel> electionAsync, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 900;
            final titleCol = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Nominated Candidates Roster',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  'All candidates filed under specific designations with panel affiliations and statutory quotas.',
                  style: TextStyle(color: isDark ? Colors.white60 : Colors.grey.shade600, fontSize: 12),
                ),
              ],
            );

            final actionBtns = Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () {
                    final baseUrl = ApiConstants.baseUrl.replaceAll('/v1', '');
                    final url = '$baseUrl/v1/elections/${widget.electionId}/candidates/id_cards_bulk/';
                    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                  },
                  icon: const Icon(Icons.badge_rounded, size: 16, color: Color(0xFF6366F1)),
                  label: const Text('Batch ID Cards (PDF)'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF6366F1),
                    side: const BorderSide(color: Color(0xFF6366F1)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CreateCandidateScreen(electionId: widget.electionId),
                      ),
                    );
                  },
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                  label: const Text('Nominate Candidate'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                ),
              ],
            );

            if (isNarrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  titleCol,
                  const SizedBox(height: 12),
                  actionBtns,
                ],
              );
            }

            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: titleCol),
                const SizedBox(width: 16),
                actionBtns,
              ],
            );
          },
        ),
        const SizedBox(height: 18),

        // Filter Bar (Designation Dropdown + Status Filter + Search Box)
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // Designation Selector
            electionAsync.maybeWhen(
              data: (election) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.surfaceVariant : const Color(0xFFF4F4F5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade300),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: _selectedPositionFilter,
                    icon: const Icon(Icons.arrow_drop_down_rounded),
                    dropdownColor: isDark ? AppColors.surface : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('All Designations (सबै पदहरू)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      ),
                      ...election.positions.map(
                        (p) => DropdownMenuItem<String?>(
                          value: p.id,
                          child: Text('${p.title} (${p.candidates.length} candidates)', style: const TextStyle(fontSize: 13)),
                        ),
                      ),
                    ],
                    onChanged: (val) => setState(() => _selectedPositionFilter = val),
                  ),
                ),
              ),
              orElse: () => const SizedBox.shrink(),
            ),

            // Status Filter Segment
            Container(
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceVariant : const Color(0xFFF4F4F5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade300),
              ),
              padding: const EdgeInsets.all(3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildFilterTab('All', 'all', isDark),
                  _buildFilterTab('Approved', 'approved', isDark),
                  _buildFilterTab('Pending', 'pending', isDark),
                  _buildFilterTab('Rejected', 'rejected', isDark),
                ],
              ),
            ),

            // Search box
            SizedBox(
              width: 240,
              height: 40,
              child: TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: 'Search candidate...',
                  prefixIcon: const Icon(Icons.search_rounded, size: 18),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () => setState(() => _searchCtrl.clear()),
                        )
                      : null,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: isDark ? AppColors.surfaceVariant : const Color(0xFFF4F4F5),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade300),
                  ),
                ),
                style: const TextStyle(fontSize: 13),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFilterTab(String label, String value, bool isDark) {
    final isSelected = _statusFilter == value;
    return InkWell(
      onTap: () => setState(() => _statusFilter = value),
      borderRadius: BorderRadius.circular(9),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.grey.shade700),
          ),
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // 3. CANDIDATES LIST
  // ════════════════════════════════════════════════════════════════════════════
  Widget _buildCandidateList(BuildContext context, ElectionModel election, bool isDark) {
    // Collect all candidates across positions
    var candidateEntries = <Map<String, dynamic>>[];
    for (final pos in election.positions) {
      for (final cand in pos.candidates) {
        candidateEntries.add({
          'candidate': cand,
          'position': pos,
        });
      }
    }

    // Filter by position
    if (_selectedPositionFilter != null) {
      candidateEntries = candidateEntries
          .where((entry) => (entry['position'] as PositionModel).id == _selectedPositionFilter)
          .toList();
    }

    // Filter by status
    if (_statusFilter == 'approved') {
      candidateEntries = candidateEntries
          .where((entry) {
            final st = (entry['candidate'] as CandidateModel).status?.toLowerCase();
            return st == 'approved' || st == 'verified' || st == 'valid';
          })
          .toList();
    } else if (_statusFilter == 'pending') {
      candidateEntries = candidateEntries
          .where((entry) {
            final st = (entry['candidate'] as CandidateModel).status?.toLowerCase();
            return st == null || st == 'pending' || st == 'submitted' || st == 'under_review';
          })
          .toList();
    } else if (_statusFilter == 'rejected') {
      candidateEntries = candidateEntries
          .where((entry) {
            final st = (entry['candidate'] as CandidateModel).status?.toLowerCase();
            return st == 'rejected' || st == 'disqualified' || st == 'withdrawn';
          })
          .toList();
    }

    // Filter by search query
    final query = _searchCtrl.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      candidateEntries = candidateEntries.where((entry) {
        final c = entry['candidate'] as CandidateModel;
        final p = entry['position'] as PositionModel;
        return c.name.toLowerCase().contains(query) ||
            (c.quotaName ?? '').toLowerCase().contains(query) ||
            p.title.toLowerCase().contains(query);
      }).toList();
    }

    if (candidateEntries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.person_search_rounded, size: 48, color: AppColors.primaryLight),
              ),
              const SizedBox(height: 16),
              Text(
                election.positions.expand((p) => p.candidates).isEmpty
                    ? 'No Candidates Nominated Yet'
                    : 'No candidates match your filter criteria.',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 6),
              Text(
                'Add nomination records for qualified candidates to participate on the digital ballot.',
                style: TextStyle(color: isDark ? Colors.white60 : Colors.grey.shade600, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CreateCandidateScreen(electionId: widget.electionId),
                    ),
                  );
                },
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                label: const Text('Nominate First Candidate'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: candidateEntries.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final entry = candidateEntries[index];
        final cand = entry['candidate'] as CandidateModel;
        final pos = entry['position'] as PositionModel;
        return _buildCandidateCard(context, cand, pos, election.title, index + 1, isDark);
      },
    );
  }

  Widget _buildCandidateCard(
    BuildContext context,
    CandidateModel cand,
    PositionModel pos,
    String electionTitle,
    int index,
    bool isDark,
  ) {
    final statusColor = _getStatusColor(cand.status);
    final statusText = _formatStatusText(cand.status);
    final posColor = _parseColor(pos.bgColor);

    return Material(
      color: isDark ? AppColors.surfaceVariant.withValues(alpha: 0.4) : const Color(0xFFFAFAFA),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.shade200,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Candidate Avatar / Photo
            CircleAvatar(
              radius: 24,
              backgroundColor: posColor.withValues(alpha: 0.15),
              backgroundImage: (cand.photoUrl != null && cand.photoUrl!.isNotEmpty)
                  ? NetworkImage(cand.photoUrl!)
                  : ((cand.candidateImage != null && cand.candidateImage!.isNotEmpty)
                      ? NetworkImage(cand.candidateImage!)
                      : null),
              child: ((cand.photoUrl == null || cand.photoUrl!.isEmpty) &&
                      (cand.candidateImage == null || cand.candidateImage!.isEmpty))
                  ? Text(
                      cand.name.isNotEmpty ? cand.name.substring(0, 1).toUpperCase() : 'C',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: posColor),
                    )
                  : null,
            ),
            const SizedBox(width: 16),

            // Candidate Details Column
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    cand.name,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 6),

                  Wrap(
                    spacing: 10,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      // Designation Tag
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: posColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.military_tech_rounded, size: 12, color: posColor),
                            const SizedBox(width: 4),
                            Text(
                              pos.title,
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: posColor),
                            ),
                          ],
                        ),
                      ),

                      // Quota Tag if applicable
                      if (cand.quotaName != null && cand.quotaName!.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.purple.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.purple.withValues(alpha: 0.25)),
                          ),
                          child: Text(
                            'Quota: ${cand.quotaName}',
                            style: const TextStyle(color: Colors.purple, fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                        ),

                      if (cand.endorsements.isNotEmpty)
                        Text(
                          '${cand.endorsements.length} Endorsement(s)',
                          style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : Colors.grey.shade600),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),

            // Status Glow Pill
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: statusColor.withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    statusText,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),

            // View Profile Sheet Action
            OutlinedButton.icon(
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => CandidateProfileSheet(candidate: cand),
                );
              },
              icon: const Icon(Icons.visibility_outlined, size: 16),
              label: const Text('View Dossier'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(width: 8),

            // Candidate Digital ID Card Button
            OutlinedButton.icon(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (_) => DigitalIdCardDialog(
                    cardType: 'candidate',
                    fullName: cand.name,
                    idNumber: cand.id.length > 8 ? cand.id.substring(0, 8).toUpperCase() : cand.id,
                    positionTitle: pos.title,
                    photoUrl: cand.photoUrl ?? cand.candidateImage,
                    phone: cand.contactNumber,
                    electionTitle: electionTitle,
                    electionId: widget.electionId,
                    entityId: cand.id,
                  ),
                );
              },
              icon: const Icon(Icons.badge_outlined, size: 16, color: Color(0xFF6366F1)),
              label: const Text('ID Card'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF6366F1),
                side: const BorderSide(color: Color(0xFF6366F1)),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
