import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/providers/admin_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/responsive_layout.dart';

class QuotaSettingsScreen extends ConsumerStatefulWidget {
  final String electionId;
  const QuotaSettingsScreen({super.key, required this.electionId});

  @override
  ConsumerState<QuotaSettingsScreen> createState() => _QuotaSettingsScreenState();
}

class _QuotaSettingsScreenState extends ConsumerState<QuotaSettingsScreen> {
  String? _selectedPositionFilter; // null = all designations
  String _statusFilter = 'all'; // 'all', 'active', 'inactive'
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String _getErrorMessage(dynamic e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map) {
        final messages = <String>[];
        data.forEach((key, value) {
          if (value is List) {
            messages.add(value.join(', '));
          } else if (value is String) {
            messages.add(value);
          } else {
            messages.add('$key: $value');
          }
        });
        if (messages.isNotEmpty) return messages.join('\n');
      } else if (data is String && data.isNotEmpty) {
        return data;
      }
    }
    return e.toString();
  }

  static const List<Map<String, String>> _suggestedQuotas = [
    {'en': 'Female', 'ne': 'महिला', 'desc': 'Statutory reservation for female candidates'},
    {'en': 'Dalit', 'ne': 'दलित', 'desc': 'Reserved for marginalized Dalit community'},
    {'en': 'Janajati', 'ne': 'आदिवासी / जनजाति', 'desc': 'Indigenous / Janajati community quota'},
    {'en': 'Youth', 'ne': 'युवा (१८-४० वर्ष)', 'desc': 'Reserved for youth members'},
    {'en': 'Madhesi', 'ne': 'मधेशी', 'desc': 'Affirmative action for Madhesi community'},
    {'en': 'Muslim', 'ne': 'मुस्लिम', 'desc': 'Reserved for Muslim minority'},
    {'en': 'Khas Arya', 'ne': 'खस आर्य', 'desc': 'Khas Arya cluster reservation'},
    {'en': 'Tharu', 'ne': 'थारू', 'desc': 'Indigenous Tharu community quota'},
    {'en': 'Disability', 'ne': 'अपाङ्गता भएका', 'desc': 'Persons with disabilities reservation'},
    {'en': 'Backward Region', 'ne': 'पिछडिएको क्षेत्र', 'desc': 'Geographically remote / backward region'},
    {'en': 'Open / General', 'ne': 'खुला / सर्वसाधारण', 'desc': 'General open category seats'},
    {'en': 'Other', 'ne': 'अन्य (स्वनिर्धारित)', 'desc': 'Custom self-defined quota label'},
  ];

  static Color getCategoryColor(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('female') || lower.contains('महिला')) return const Color(0xFFE11D48);
    if (lower.contains('dalit') || lower.contains('दलित')) return const Color(0xFF7C3AED);
    if (lower.contains('janajati') || lower.contains('जनजाति') || lower.contains('indigenous')) return const Color(0xFF0D9488);
    if (lower.contains('youth') || lower.contains('युवा')) return const Color(0xFFD97706);
    if (lower.contains('madhesi') || lower.contains('मधेशी')) return const Color(0xFF2563EB);
    if (lower.contains('muslim') || lower.contains('मुस्लिम')) return const Color(0xFF059669);
    if (lower.contains('khas') || lower.contains('खस')) return const Color(0xFF4F46E5);
    if (lower.contains('tharu') || lower.contains('थारू')) return const Color(0xFF0891B2);
    if (lower.contains('disab') || lower.contains('अपाङ्गता')) return const Color(0xFFEA580C);
    if (lower.contains('backward') || lower.contains('पिछडिएको')) return const Color(0xFF78350F);
    if (lower.contains('open') || lower.contains('खुला')) return const Color(0xFF64748B);
    return AppColors.primary;
  }

  static IconData getCategoryIcon(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('female') || lower.contains('महिला')) return Icons.female_rounded;
    if (lower.contains('dalit') || lower.contains('दलित')) return Icons.accessibility_new_rounded;
    if (lower.contains('janajati') || lower.contains('जनजाति') || lower.contains('indigenous')) return Icons.nature_people_rounded;
    if (lower.contains('youth') || lower.contains('युवा')) return Icons.bolt_rounded;
    if (lower.contains('madhesi') || lower.contains('मधेशी')) return Icons.wb_sunny_rounded;
    if (lower.contains('muslim') || lower.contains('मुस्लिम')) return Icons.nights_stay_rounded;
    if (lower.contains('khas') || lower.contains('खस')) return Icons.account_balance_rounded;
    if (lower.contains('tharu') || lower.contains('थारू')) return Icons.landscape_rounded;
    if (lower.contains('disab') || lower.contains('अपाङ्गता')) return Icons.accessible_forward_rounded;
    if (lower.contains('backward') || lower.contains('पिछडिएको')) return Icons.terrain_rounded;
    if (lower.contains('open') || lower.contains('खुला')) return Icons.how_to_vote_rounded;
    return Icons.pie_chart_outline_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final electionAsync = ref.watch(electionProvider(widget.electionId));
    final quotasAsync = ref.watch(quotasProvider(widget.electionId));
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ResponsivePageWrapper(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 48),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Navigation & Hero Banner
            _buildHeroHeader(context, electionAsync, quotasAsync, isDark),
            const SizedBox(height: 24),

            // Designation Seat Distribution Cards (Interactive Visual Allocation)
            electionAsync.maybeWhen(
              data: (election) => quotasAsync.maybeWhen(
                data: (quotas) => _buildDesignationMatrix(context, election, quotas, isDark),
                orElse: () => const SizedBox.shrink(),
              ),
              orElse: () => const SizedBox.shrink(),
            ),
            const SizedBox(height: 24),

            // Quotas Management Table Card
            Material(
              color: isDark ? AppColors.surface : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.shade200),
              ),
              elevation: isDark ? 0 : 1,
              shadowColor: Colors.black.withValues(alpha: 0.04),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Toolbar: Title, Filter, Search & Add Button
                    _buildToolbar(context, electionAsync, quotasAsync, isDark),
                    const SizedBox(height: 20),

                    // Quota Roster Body
                    quotasAsync.when(
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
                              Text('Failed to load quota configuration: $err', style: const TextStyle(color: Colors.red)),
                              const SizedBox(height: 12),
                              ElevatedButton.icon(
                                onPressed: () => ref.invalidate(quotasProvider(widget.electionId)),
                                icon: const Icon(Icons.refresh_rounded, size: 16),
                                label: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      ),
                      data: (quotas) {
                        return electionAsync.maybeWhen(
                          data: (election) => _buildQuotaList(context, election, quotas, isDark),
                          orElse: () => const SizedBox.shrink(),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // 1. HERO HEADER WITH EXECUTIVE STATS
  // ════════════════════════════════════════════════════════════════════════════
  Widget _buildHeroHeader(
    BuildContext context,
    AsyncValue<ElectionModel> electionAsync,
    AsyncValue<List<PositionQuotaModel>> quotasAsync,
    bool isDark,
  ) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF312E81), Color(0xFF4338CA), Color(0xFF6366F1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4338CA).withValues(alpha: 0.35),
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
              Icons.diversity_3_rounded,
              size: 160,
              color: Colors.white.withValues(alpha: 0.08),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top breadcrumb / navigation row
                Row(
                  children: [
                    if (Navigator.canPop(context))
                      InkWell(
                        onTap: () => Navigator.pop(context),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          margin: const EdgeInsets.only(right: 12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 18),
                        ),
                      ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.pie_chart_rounded, color: Colors.amberAccent, size: 14),
                          SizedBox(width: 6),
                          Text(
                            'AFFIRMATIVE ACTION & RESERVATIONS',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 0.8),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Main Title & Subtitle
                Text(
                  'Quota & Reserved Seats Management',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.5,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'समावेशी तथा आरक्षण कोटा व्यवस्थापन — Define statutory reserved seats per designation. Quotas dynamically gate candidate nominations and ensure inclusive representation.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 20),

                // Stats Row
                electionAsync.maybeWhen(
                  data: (election) => quotasAsync.maybeWhen(
                    data: (quotas) {
                      final totalPositions = election.positions.length;
                      final totalSeats = election.positions.fold<int>(0, (sum, p) => sum + p.seatsAvailable);
                      final activeQuotas = quotas.where((q) => q.isActive).toList();
                      final totalReservedSeats = activeQuotas.fold<int>(0, (sum, q) => sum + q.seats);
                      final coveragePct = totalSeats > 0 ? ((totalReservedSeats / totalSeats) * 100).toStringAsFixed(0) : '0';

                      return Wrap(
                        spacing: 12,
                        runSpacing: 10,
                        children: [
                          _buildHeroStatChip('Designations', '$totalPositions', Icons.badge_outlined, Colors.white),
                          _buildHeroStatChip('Quota Rules', '${quotas.length}', Icons.rule_rounded, Colors.cyanAccent),
                          _buildHeroStatChip('Reserved Seats', '$totalReservedSeats / $totalSeats ($coveragePct%)', Icons.event_seat_rounded, Colors.amberAccent),
                          _buildHeroStatChip('Active Rules', '${activeQuotas.length}', Icons.check_circle_outline_rounded, Colors.greenAccent),
                        ],
                      );
                    },
                    orElse: () => const SizedBox.shrink(),
                  ),
                  orElse: () => const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ],
      ),
    )
    .animate()
    .fade(duration: 350.ms)
    .slideY(begin: -0.05, end: 0);
  }

  Widget _buildHeroStatChip(String label, String value, IconData icon, Color accentColor) {
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
  // 2. DESIGNATION SEAT ALLOCATION MATRIX
  // ════════════════════════════════════════════════════════════════════════════
  Widget _buildDesignationMatrix(
    BuildContext context,
    ElectionModel election,
    List<PositionQuotaModel> quotas,
    bool isDark,
  ) {
    if (election.positions.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(Icons.dashboard_customize_outlined, size: 18, color: AppColors.primaryLight),
                const SizedBox(width: 8),
                Text(
                  'Seat Allocation by Designation',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            Text(
              '${election.positions.length} Designation(s)',
              style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.grey.shade600),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: election.positions.map((pos) {
            final posQuotas = quotas.where((q) => q.positionId == pos.id && q.isActive).toList();
            final reservedSeats = posQuotas.fold<int>(0, (sum, q) => sum + q.seats);
            final openSeats = (pos.seatsAvailable - reservedSeats).clamp(0, pos.seatsAvailable);
            final ratio = pos.seatsAvailable > 0 ? (reservedSeats / pos.seatsAvailable).clamp(0.0, 1.0) : 0.0;
            final isFullyReserved = reservedSeats >= pos.seatsAvailable;

            return SizedBox(
              width: 380,
              child: Material(
                color: isDark ? AppColors.surface : Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.shade200,
                  ),
                ),
                elevation: isDark ? 0 : 1,
                shadowColor: Colors.black.withValues(alpha: 0.03),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.military_tech_rounded, color: AppColors.primaryLight, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  pos.title,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  'Total: ${pos.seatsAvailable} Seat(s) • ${pos.votingMethod.toUpperCase()}',
                                  style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : Colors.grey.shade600),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline_rounded, size: 20, color: AppColors.primaryLight),
                            tooltip: 'Add Quota to ${pos.title}',
                            onPressed: () => _openAddEditDialog(context, election: election, defaultPositionId: pos.id),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Progress Bar
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: ratio,
                          minHeight: 6,
                          backgroundColor: isDark ? Colors.white12 : Colors.grey.shade200,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            isFullyReserved ? Colors.amber.shade700 : AppColors.primaryLight,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Seat Summary Row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF6366F1), shape: BoxShape.circle)),
                              const SizedBox(width: 6),
                              Text('Reserved: $reservedSeats', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            ],
                          ),
                          Row(
                            children: [
                              Container(width: 8, height: 8, decoration: BoxDecoration(color: Colors.grey.shade400, shape: BoxShape.circle)),
                              const SizedBox(width: 6),
                              Text('Open: $openSeats', style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.grey.shade700)),
                            ],
                          ),
                        ],
                      ),

                      // Quota Category Badges
                      if (posQuotas.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        const Divider(height: 1),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: posQuotas.map((q) {
                            final catColor = getCategoryColor(q.name);
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: catColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: catColor.withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(getCategoryIcon(q.name), size: 12, color: catColor),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${q.name}: ${q.seats}',
                                    style: TextStyle(color: catColor, fontWeight: FontWeight.bold, fontSize: 11),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ] else ...[
                        const SizedBox(height: 8),
                        Text(
                          'No reserved quotas. All seats open to general election.',
                          style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: isDark ? Colors.white38 : Colors.grey.shade500),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // 3. TOOLBAR WITH FILTERS & ADD CTA
  // ════════════════════════════════════════════════════════════════════════════
  Widget _buildToolbar(
    BuildContext context,
    AsyncValue<ElectionModel> electionAsync,
    AsyncValue<List<PositionQuotaModel>> quotasAsync,
    bool isDark,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Configured Quota Policies',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Active quota constraints are enforced on candidate registration and ballot tabulation.',
                    style: TextStyle(color: isDark ? Colors.white60 : Colors.grey.shade600, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            electionAsync.maybeWhen(
              data: (election) => election.positions.isNotEmpty
                  ? ElevatedButton.icon(
                      onPressed: () => _openAddEditDialog(context, election: election),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Add Quota Rule'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                    )
                  : const SizedBox.shrink(),
              orElse: () => const SizedBox.shrink(),
            ),
          ],
        ),
        const SizedBox(height: 18),

        // Filter Bar (Designation Dropdown + Status Filter + Search)
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
                          child: Text('${p.title} (${p.seatsAvailable} seats)', style: const TextStyle(fontSize: 13)),
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
                  _buildFilterTab('Active', 'active', isDark),
                  _buildFilterTab('Inactive', 'inactive', isDark),
                ],
              ),
            ),

            // Search box
            SizedBox(
              width: 220,
              height: 40,
              child: TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: 'Search quota...',
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
  // 4. QUOTA LIST & TABLE
  // ════════════════════════════════════════════════════════════════════════════
  Widget _buildQuotaList(
    BuildContext context,
    ElectionModel election,
    List<PositionQuotaModel> quotas,
    bool isDark,
  ) {
    // Filter by position
    var filtered = _selectedPositionFilter == null
        ? quotas
        : quotas.where((q) => q.positionId == _selectedPositionFilter).toList();

    // Filter by status
    if (_statusFilter == 'active') {
      filtered = filtered.where((q) => q.isActive).toList();
    } else if (_statusFilter == 'inactive') {
      filtered = filtered.where((q) => !q.isActive).toList();
    }

    // Filter by search
    final query = _searchCtrl.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      filtered = filtered.where((q) {
        return q.name.toLowerCase().contains(query) ||
            q.positionTitle.toLowerCase().contains(query) ||
            q.description.toLowerCase().contains(query);
      }).toList();
    }

    if (filtered.isEmpty) {
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
                child: const Icon(Icons.pie_chart_outline_rounded, size: 48, color: AppColors.primaryLight),
              ),
              const SizedBox(height: 16),
              Text(
                _selectedPositionFilter == null
                    ? (quotas.isEmpty ? 'No Quotas Defined Yet' : 'No quotas match your filter criteria.')
                    : 'No quotas defined for this designation.',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 6),
              Text(
                'Define affirmative action rules (Female, Dalit, Youth, etc.) to enforce statutory reservation on ballots.',
                style: TextStyle(color: isDark ? Colors.white60 : Colors.grey.shade600, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              if (election.positions.isNotEmpty)
                ElevatedButton.icon(
                  onPressed: () => _openAddEditDialog(context, election: election),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Create First Quota Rule'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                )
              else
                const Text('Please add at least one designation before adding quotas.', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: filtered.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final quota = filtered[index];
        return _buildQuotaCard(context, election, quota, index + 1, isDark);
      },
    );
  }

  Widget _buildQuotaCard(
    BuildContext context,
    ElectionModel election,
    PositionQuotaModel quota,
    int index,
    bool isDark,
  ) {
    final catColor = getCategoryColor(quota.name);
    final catIcon = getCategoryIcon(quota.name);
    final pos = election.positions.where((p) => p.id == quota.positionId).firstOrNull;
    final totalPosSeats = pos?.seatsAvailable ?? quota.seats;

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
            // Category Icon Badge
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: catColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: catColor.withValues(alpha: 0.3)),
              ),
              child: Icon(catIcon, color: catColor, size: 24),
            ),
            const SizedBox(width: 16),

            // Quota Info Column
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        quota.name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: quota.isActive ? Colors.green.withValues(alpha: 0.12) : Colors.grey.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: quota.isActive ? Colors.green.withValues(alpha: 0.4) : Colors.grey.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: quota.isActive ? Colors.green : Colors.grey,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              quota.isActive ? 'Active' : 'Inactive',
                              style: TextStyle(
                                color: quota.isActive ? Colors.green : Colors.grey,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.military_tech_rounded, size: 14, color: isDark ? Colors.white60 : Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Text(
                        quota.positionTitle.isNotEmpty ? quota.positionTitle : (pos?.title ?? 'Designation'),
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: isDark ? Colors.white70 : Colors.grey.shade800),
                      ),
                      const SizedBox(width: 8),
                      Text('•', style: TextStyle(color: isDark ? Colors.white38 : Colors.grey.shade400)),
                      const SizedBox(width: 8),
                      Text(
                        'Total Designation Capacity: $totalPosSeats Seats',
                        style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.grey.shade600),
                      ),
                    ],
                  ),
                  if (quota.description.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      quota.description,
                      style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.grey.shade600),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 16),

            // Seats Badge Pill
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.event_seat_rounded, size: 16, color: AppColors.primaryLight),
                      const SizedBox(width: 6),
                      Text(
                        '${quota.seats}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.primaryLight),
                      ),
                    ],
                  ),
                  const Text('Reserved Seat(s)', style: TextStyle(fontSize: 10, color: AppColors.primaryLight, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            const SizedBox(width: 12),

            // Action Buttons
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20, color: Colors.blue),
              tooltip: 'Edit Quota Rule',
              onPressed: () => _openAddEditDialog(context, election: election, quotaToEdit: quota),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Colors.red),
              tooltip: 'Delete Quota Rule',
              onPressed: () => _confirmDelete(context, quota),
            ),
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // 5. INTERACTIVE ADD / EDIT MODAL DIALOG
  // ════════════════════════════════════════════════════════════════════════════
  void _openAddEditDialog(
    BuildContext context, {
    required ElectionModel election,
    PositionQuotaModel? quotaToEdit,
    String? defaultPositionId,
  }) {
    final isEditing = quotaToEdit != null;
    final formKey = GlobalKey<FormState>();

    String? selectedPositionId = quotaToEdit?.positionId ??
        defaultPositionId ??
        (_selectedPositionFilter ?? (election.positions.isNotEmpty ? election.positions.first.id : null));

    final nameCtrl = TextEditingController(text: quotaToEdit?.name ?? '');
    final seatsCtrl = TextEditingController(text: quotaToEdit?.seats.toString() ?? '1');
    final descCtrl = TextEditingController(text: quotaToEdit?.description ?? '');
    String status = quotaToEdit?.status ?? 'active';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final currentPosition = election.positions.where((p) => p.id == selectedPositionId).firstOrNull;
            final maxSeats = currentPosition?.seatsAvailable ?? 1;

            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              backgroundColor: isDark ? AppColors.surface : Colors.white,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 580, maxHeight: 850),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Form(
                    key: formKey,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Dialog Header
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  isEditing ? Icons.edit_note_rounded : Icons.add_circle_outline_rounded,
                                  color: AppColors.primaryLight,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      isEditing ? 'Edit Quota Policy' : 'Create New Quota Policy',
                                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'समावेशी कोटा नियम — Enforce statutory reservation per designation.',
                                      style: TextStyle(color: isDark ? Colors.white60 : Colors.grey.shade600, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close_rounded),
                                onPressed: () => Navigator.of(dialogCtx).pop(),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          const Divider(height: 1),
                          const SizedBox(height: 20),

                          // 1. Designation Selector
                          Text('1. SELECT DESIGNATION (पद छनोट)', style: _stepLabelStyle(context)),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            initialValue: selectedPositionId,
                            decoration: InputDecoration(
                              labelText: 'Target Designation *',
                              prefixIcon: const Icon(Icons.military_tech_rounded),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            items: election.positions.map((p) {
                              return DropdownMenuItem(
                                value: p.id,
                                child: Text('${p.title} (Capacity: ${p.seatsAvailable} seats)'),
                              );
                            }).toList(),
                            onChanged: isEditing ? null : (val) => setDialogState(() => selectedPositionId = val),
                            validator: (val) => val == null ? 'Please select a designation' : null,
                          ),
                          const SizedBox(height: 20),

                          // 2. Preset Category Suggestions (Bilingual Nepali / English)
                          Text('2. STATUTORY CATEGORY (आरक्षण समूह)', style: _stepLabelStyle(context)),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _suggestedQuotas.map((cat) {
                              final enName = cat['en']!;
                              final neName = cat['ne']!;
                              final currentText = nameCtrl.text.trim().toLowerCase();
                              final isOther = enName == 'Other';
                              final isStandardCat = _suggestedQuotas
                                  .where((c) => c['en'] != 'Other')
                                  .any((c) => c['en']!.toLowerCase() == currentText);

                              final isSelected = isOther ? (!isStandardCat && currentText.isNotEmpty) : (currentText == enName.toLowerCase());
                              final catColor = getCategoryColor(enName);

                              return InkWell(
                                onTap: () {
                                  if (!isOther) {
                                    setDialogState(() {
                                      nameCtrl.text = enName;
                                      if (descCtrl.text.isEmpty) {
                                        descCtrl.text = cat['desc'] ?? '';
                                      }
                                    });
                                  } else {
                                    setDialogState(() {
                                      nameCtrl.clear();
                                      descCtrl.clear();
                                    });
                                  }
                                },
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: isSelected ? catColor : (isDark ? AppColors.surfaceVariant : Colors.grey.shade100),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: isSelected ? catColor : (isDark ? Colors.white12 : Colors.grey.shade300),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        getCategoryIcon(enName),
                                        size: 14,
                                        color: isSelected ? Colors.white : catColor,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        '$enName ($neName)',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                          color: isSelected ? Colors.white : (isDark ? Colors.white : Colors.black87),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 14),

                          // Quota Name Input
                          TextFormField(
                            controller: nameCtrl,
                            decoration: InputDecoration(
                              labelText: 'Quota Category Name *',
                              hintText: 'e.g. Female, Dalit, Indigenous, Youth',
                              prefixIcon: const Icon(Icons.category_rounded),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              helperText: 'Select a preset above or type any custom criteria.',
                            ),
                            onChanged: (_) => setDialogState(() {}),
                            validator: (val) => val == null || val.trim().isEmpty ? 'Quota category name is required' : null,
                          ),
                          const SizedBox(height: 20),

                          // 3. Seats & Active Status
                          Text('3. SEAT ALLOCATION & STATUS (सिट संख्या र स्थिति)', style: _stepLabelStyle(context)),
                          const SizedBox(height: 8),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Seats Stepper
                              Expanded(
                                flex: 3,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    TextFormField(
                                      controller: seatsCtrl,
                                      decoration: InputDecoration(
                                        labelText: 'Reserved Seats *',
                                        prefixIcon: const Icon(Icons.event_seat_rounded),
                                        helperText: 'Max available: $maxSeats seat(s)',
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                      ),
                                      keyboardType: TextInputType.number,
                                      onChanged: (_) => setDialogState(() {}),
                                      validator: (val) {
                                        final n = int.tryParse(val ?? '');
                                        if (n == null || n <= 0) return 'Must be >= 1';
                                        if (n > maxSeats) return 'Cannot exceed max $maxSeats seats';
                                        return null;
                                      },
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 14),

                              // Status Switch Card
                              Expanded(
                                flex: 2,
                                child: Material(
                                  color: isDark ? AppColors.surfaceVariant : const Color(0xFFF4F4F5),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    side: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade300),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              status == 'active' ? 'Active' : 'Inactive',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: status == 'active' ? Colors.green : Colors.grey,
                                                fontSize: 13,
                                              ),
                                            ),
                                            Switch(
                                              value: status == 'active',
                                              activeThumbColor: Colors.green,
                                              onChanged: (val) => setDialogState(() => status = val ? 'active' : 'inactive'),
                                            ),
                                          ],
                                        ),
                                        Text(
                                          status == 'active' ? 'Enforced on ballots' : 'Draft / Disabled',
                                          style: TextStyle(fontSize: 10, color: isDark ? Colors.white54 : Colors.grey.shade600),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),

                          // 4. Description / Statutory criteria
                          Text('4. ELIGIBILITY CRITERIA / NOTES (विवरण)', style: _stepLabelStyle(context)),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: descCtrl,
                            decoration: InputDecoration(
                              labelText: 'Statutory Description / Criteria (Optional)',
                              hintText: 'e.g. Reserved for female members in compliance with Article 14 of Cooperative Bylaws',
                              prefixIcon: const Icon(Icons.description_outlined),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            maxLines: 2,
                          ),
                          const SizedBox(height: 24),

                          // Realtime Summary Preview Box
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.info_outline_rounded, color: AppColors.primaryLight, size: 20),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Reserving ${seatsCtrl.text.trim().isEmpty ? '1' : seatsCtrl.text.trim()} seat(s) for "${nameCtrl.text.trim().isEmpty ? 'Category' : nameCtrl.text.trim()}" under ${currentPosition?.title ?? 'selected designation'}.',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Dialog Actions
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: () => Navigator.of(dialogCtx).pop(),
                                child: const Text('Cancel'),
                              ),
                              const SizedBox(width: 12),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                onPressed: () async {
                                  if (!formKey.currentState!.validate()) return;
                                  final payload = {
                                    'position': selectedPositionId,
                                    'name': nameCtrl.text.trim(),
                                    'seats': int.parse(seatsCtrl.text.trim()),
                                    'status': status,
                                    'description': descCtrl.text.trim(),
                                  };

                                  try {
                                    if (isEditing) {
                                      await ref.read(quotaNotifierProvider.notifier).updateQuota(widget.electionId, quotaToEdit.id, payload);
                                    } else {
                                      await ref.read(quotaNotifierProvider.notifier).addQuota(widget.electionId, payload);
                                    }
                                    if (context.mounted) {
                                      Navigator.of(dialogCtx).pop();
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Row(
                                            children: [
                                              const Icon(Icons.check_circle_rounded, color: Colors.white),
                                              const SizedBox(width: 10),
                                              Text(isEditing ? 'Quota policy updated successfully!' : 'Quota policy created successfully!'),
                                            ],
                                          ),
                                          backgroundColor: Colors.green.shade700,
                                          behavior: SnackBarBehavior.floating,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                        ),
                                      );
                                    }
                                  } catch (e) {
                                    ref.invalidate(quotasProvider(widget.electionId));
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(_getErrorMessage(e)),
                                          backgroundColor: Colors.red.shade700,
                                          behavior: SnackBarBehavior.floating,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                        ),
                                      );
                                    }
                                  }
                                },
                                child: Text(isEditing ? 'Save Changes' : 'Create Quota Policy'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  TextStyle _stepLabelStyle(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.bold,
      letterSpacing: 0.8,
      color: isDark ? Colors.white70 : Colors.grey.shade700,
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // 6. DELETE CONFIRMATION MODAL
  // ════════════════════════════════════════════════════════════════════════════
  void _confirmDelete(BuildContext context, PositionQuotaModel quota) {
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
            Text('Delete Quota Rule?', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Are you sure you want to delete quota "${quota.name}" (${quota.seats} reserved seat(s)) for ${quota.positionTitle.isNotEmpty ? quota.positionTitle : "this designation"}?\n\nThis will remove the reservation constraint for candidate nominations.',
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
                await ref.read(quotaNotifierProvider.notifier).deleteQuota(widget.electionId, quota.id);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.white),
                          SizedBox(width: 10),
                          Text('Quota rule deleted successfully.'),
                        ],
                      ),
                      backgroundColor: Colors.green.shade700,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  );
                }
              } catch (e) {
                ref.invalidate(quotasProvider(widget.electionId));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Delete failed: ${_getErrorMessage(e)}'),
                      backgroundColor: Colors.red.shade700,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  );
                }
              }
            },
            child: const Text('Delete Rule'),
          ),
        ],
      ),
    );
  }
}
