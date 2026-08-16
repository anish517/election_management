import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/providers/admin_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/models.dart';
import 'create_designation_screen.dart';
import 'quota_settings_screen.dart';

class DesignationsScreen extends ConsumerStatefulWidget {
  final String electionId;
  const DesignationsScreen({super.key, required this.electionId});

  @override
  ConsumerState<DesignationsScreen> createState() => _DesignationsScreenState();
}

class _DesignationsScreenState extends ConsumerState<DesignationsScreen> {
  final _searchCtrl = TextEditingController();
  String _sortBy = 'order'; // 'order', 'title', 'seats'

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Color _parseColor(String hex) {
    try {
      final h = hex.replaceAll('#', '');
      return Color(int.parse('FF$h', radix: 16));
    } catch (_) {
      return AppColors.primary;
    }
  }

  String _extractErrorMessage(dynamic e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map) {
        if (data['error'] is Map && data['error']['message'] != null) {
          return data['error']['message'].toString();
        }
        if (data['detail'] != null) return data['detail'].toString();
        if (data['message'] != null) return data['message'].toString();
      }
    }
    return 'Failed to delete designation: $e';
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
          // DESIGNATION MANAGEMENT CARD
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
                  // Toolbar: Actions, Search & Sorting
                  _buildToolbar(context, electionAsync, isDark),
                  const SizedBox(height: 20),

                  // Roster Body
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
                            Text('Failed to load designations: $err', style: const TextStyle(color: Colors.red)),
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
                    data: (election) => _buildDesignationList(context, election, isDark),
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
  // 1. HERO HEADER WITH STATS
  // ════════════════════════════════════════════════════════════════════════════
  Widget _buildHeroHeader(BuildContext context, AsyncValue<ElectionModel> electionAsync, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF3730A3), Color(0xFF4F46E5), Color(0xFF6366F1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4F46E5).withValues(alpha: 0.35),
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
              Icons.military_tech_rounded,
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
                      Icon(Icons.how_to_vote_rounded, color: Colors.amberAccent, size: 14),
                      SizedBox(width: 6),
                      Text(
                        'BALLOT POSITIONS & SEATS',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 0.8),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Electoral Designations & Seats',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.5,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'उम्मेदवारी पद तथा सिट संरचना — Manage positions contested on the ballot, available seat capacities, candidacy fees, and statutory reservation quotas.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 20),

                // Real-time Stats Row
                electionAsync.maybeWhen(
                  data: (election) {
                    final totalPositions = election.positions.length;
                    final totalSeats = election.positions.fold<int>(0, (sum, p) => sum + p.seatsAvailable);
                    final totalQuotas = election.positions.fold<int>(0, (sum, p) => sum + p.quotas.length);

                    return Wrap(
                      spacing: 12,
                      runSpacing: 10,
                      children: [
                        _buildStatChip('Total Designations', '$totalPositions', Icons.military_tech_rounded, Colors.white),
                        _buildStatChip('Contested Seats', '$totalSeats', Icons.event_seat_rounded, Colors.amberAccent),
                        _buildStatChip('Quota Rules', '$totalQuotas', Icons.pie_chart_rounded, Colors.cyanAccent),
                        _buildStatChip('Voting Method', 'First-Past-The-Post', Icons.ballot_outlined, Colors.greenAccent),
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
  // 2. TOOLBAR (SEARCH, SORT, ACTIONS)
  // ════════════════════════════════════════════════════════════════════════════
  Widget _buildToolbar(BuildContext context, AsyncValue<ElectionModel> electionAsync, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Configured Designations',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Order of positions directly dictates ballot presentation for voters.',
                    style: TextStyle(color: isDark ? Colors.white60 : Colors.grey.shade600, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => Scaffold(
                          appBar: AppBar(title: const Text('Quota & Reserved Seats')),
                          body: QuotaSettingsScreen(electionId: widget.electionId),
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.pie_chart_outline_rounded, size: 18),
                  label: const Text('Manage Quotas'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CreateDesignationScreen(electionId: widget.electionId),
                      ),
                    );
                  },
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add Designation'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 18),

        // Search & Sorting Controls
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 250,
              height: 40,
              child: TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: 'Search designation...',
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

            // Sorting Dropdown
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceVariant : const Color(0xFFF4F4F5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade300),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _sortBy,
                  icon: const Icon(Icons.sort_rounded, size: 18),
                  dropdownColor: isDark ? AppColors.surface : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  items: const [
                    DropdownMenuItem(value: 'order', child: Text('Sort by Ballot Order', style: TextStyle(fontSize: 13))),
                    DropdownMenuItem(value: 'title', child: Text('Sort by Title (A-Z)', style: TextStyle(fontSize: 13))),
                    DropdownMenuItem(value: 'seats', child: Text('Sort by Seat Capacity', style: TextStyle(fontSize: 13))),
                  ],
                  onChanged: (val) => setState(() => _sortBy = val ?? 'order'),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // 3. DESIGNATION LIST / CARDS
  // ════════════════════════════════════════════════════════════════════════════
  Widget _buildDesignationList(BuildContext context, ElectionModel election, bool isDark) {
    var positions = List<PositionModel>.from(election.positions);

    // Search filter
    final query = _searchCtrl.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      positions = positions.where((p) => p.title.toLowerCase().contains(query)).toList();
    }

    // Sorting
    if (_sortBy == 'order') {
      positions.sort((a, b) => a.resultOrder.compareTo(b.resultOrder));
    } else if (_sortBy == 'title') {
      positions.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    } else if (_sortBy == 'seats') {
      positions.sort((a, b) => b.seatsAvailable.compareTo(a.seatsAvailable));
    }

    if (positions.isEmpty) {
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
                child: const Icon(Icons.military_tech_rounded, size: 48, color: AppColors.primaryLight),
              ),
              const SizedBox(height: 16),
              Text(
                election.positions.isEmpty ? 'No Designations Created Yet' : 'No designations match your search.',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 6),
              Text(
                'Add executive and board offices (President, Secretary, Member) to enable candidate nominations and voter ballots.',
                style: TextStyle(color: isDark ? Colors.white60 : Colors.grey.shade600, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CreateDesignationScreen(electionId: widget.electionId),
                    ),
                  );
                },
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Create First Designation'),
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
      itemCount: positions.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final pos = positions[index];
        return _buildDesignationCard(context, pos, index + 1, isDark);
      },
    );
  }

  Widget _buildDesignationCard(BuildContext context, PositionModel pos, int index, bool isDark) {
    final bgColor = _parseColor(pos.bgColor);

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
            // Color Ring & Badge Icon
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: bgColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(color: bgColor, width: 2),
              ),
              child: Center(
                child: Icon(Icons.military_tech_rounded, color: bgColor, size: 22),
              ),
            ),
            const SizedBox(width: 16),

            // Designation Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        pos.title,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white12 : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Ballot Rank #${pos.resultOrder}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white70 : Colors.grey.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),

                  Wrap(
                    spacing: 12,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.event_seat_rounded, size: 14, color: AppColors.primaryLight),
                          const SizedBox(width: 4),
                          Text(
                            '${pos.seatsAvailable} Winning Seat(s)',
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                          ),
                        ],
                      ),
                      Text('•', style: TextStyle(color: isDark ? Colors.white38 : Colors.grey.shade400)),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.payments_outlined, size: 14, color: Colors.green),
                          const SizedBox(width: 4),
                          Text(
                            pos.nomineeCharge > 0 ? 'Fee: NPR ${pos.nomineeCharge.toStringAsFixed(2)}' : 'Free Nomination',
                            style: TextStyle(fontSize: 12, color: pos.nomineeCharge > 0 ? Colors.green.shade700 : Colors.grey.shade600),
                          ),
                        ],
                      ),
                      if (pos.candidates.isNotEmpty) ...[
                        Text('•', style: TextStyle(color: isDark ? Colors.white38 : Colors.grey.shade400)),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.people_outline_rounded, size: 14, color: Colors.amber),
                            const SizedBox(width: 4),
                            Text(
                              '${pos.candidates.length} Candidate(s)',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),

                  // Quota Pills
                  if (pos.quotas.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: pos.quotas.map((q) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: q.isActive ? AppColors.primary.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: q.isActive ? AppColors.primary.withValues(alpha: 0.3) : Colors.grey.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Text(
                            '${q.name}: ${q.seats} Seat(s)',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: q.isActive ? AppColors.primaryLight : Colors.grey.shade600,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 14),

            // Color Swatch Tag
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                pos.bgColor,
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 8),

            // Action Buttons
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20, color: Colors.blue),
              tooltip: 'Edit Designation',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CreateDesignationScreen(
                      electionId: widget.electionId,
                      positionToEdit: pos,
                    ),
                  ),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Colors.red),
              tooltip: 'Delete Designation',
              onPressed: () => _confirmDelete(context, pos),
            ),
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // 4. DELETE CONFIRMATION DIALOG
  // ════════════════════════════════════════════════════════════════════════════
  void _confirmDelete(BuildContext context, PositionModel pos) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        backgroundColor: isDark ? AppColors.surface : Colors.white,
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 24),
            SizedBox(width: 10),
            Text('Delete Designation?', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Are you sure you want to delete designation "${pos.title}" (${pos.seatsAvailable} seat(s))?\n\nThis will also remove all associated quota reservation rules and unbind registered candidates.',
          style: const TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              Navigator.of(dialogCtx).pop();
              try {
                await ref.read(publishElectionProvider.notifier).deletePosition(widget.electionId, pos.id);
                ref.invalidate(electionProvider(widget.electionId));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          const Icon(Icons.check_circle_rounded, color: Colors.white),
                          const SizedBox(width: 10),
                          Text('Designation "${pos.title}" deleted successfully.'),
                        ],
                      ),
                      backgroundColor: Colors.green.shade700,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  final errorMsg = _extractErrorMessage(e);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(errorMsg),
                      backgroundColor: Colors.red.shade700,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  );
                }
              }
            },
            child: const Text('Delete Designation'),
          ),
        ],
      ),
    );
  }
}
