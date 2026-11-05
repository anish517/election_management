import 'package:election_management/core/network/api_constants.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/org_providers.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/admin_drawer.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/responsive_layout.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dashboard_quick_actions.dart';
import 'platform_overview_section.dart';
import '../../core/providers/platform_providers.dart';
import '../../shared/widgets/live_clock.dart';
import '../../shared/widgets/theme_mode_button.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final isDesktop = ResponsiveLayout.isDesktop(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      drawer: (!isDesktop && user != null && user.canManageElections)
          ? const AdminDrawer()
          : null,
      body: Row(
        children: [
          if (isDesktop && user != null && user.canManageElections)
            const SizedBox(width: 250, child: AdminDrawer(isPersistent: true)),
          Expanded(
            child: Column(
              children: [
                _buildAppBar(context, ref, user, isDesktop, isDark),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () async {
                      ref.invalidate(electionsProvider);
                      ref.invalidate(orgStatsProvider);
                      if (user?.isSuperAdmin == true) ref.invalidate(platformOverviewProvider);
                    },
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(24, 20, 24, 100),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Executive Greeting & Organization Hero Banner
                          _buildGreetingBanner(context, user, isDark),
                          const SizedBox(height: 24),

                          // Admin Analytics Grid
                          if (user != null && user.role == 'org_admin') ...[
                            _buildPremiumOverviewSection(context, ref, isDark),
                            const SizedBox(height: 28),
                          ],

                          // Platform totals (super admin)
                          if (user?.isSuperAdmin == true) ...[
                            const PlatformStatCards(),
                            const SizedBox(height: 28),
                          ],

                          // Quick Actions Row/Grid
                          if (user != null) DashboardQuickActions(user: user),
                          const SizedBox(height: 32),

                          // Running / past elections and organizations (super admin)
                          if (user?.isSuperAdmin == true) const PlatformLists(),

                          // Elections Feed Section (super admins belong to no organization)
                          if (user?.isSuperAdmin != true) ...[
                            _buildSectionHeader(
                              context,
                              'Your Elections (निर्वाचनहरू)',
                              Icons.how_to_vote_rounded,
                              onTap: () => context.pushNamed('elections'),
                            ),
                            const SizedBox(height: 16),
                            _buildElectionsSection(context, ref, user, isDark),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: (user != null && user.isOrgAdmin)
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/elections/new'),
              icon: const Icon(Icons.add_rounded),
              label: const Text('New Election', style: TextStyle(fontWeight: FontWeight.bold)),
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 4,
            )
          : null,
    );
  }

  Widget _buildAppBar(
    BuildContext context,
    WidgetRef ref,
    UserModel? user,
    bool isDesktop,
    bool isDark,
  ) {
    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.shade200,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          if (!isDesktop && user != null && user.canManageElections)
            IconButton(
              icon: const Icon(Icons.menu_rounded),
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
          if (user?.organizationLogoUrl.isNotEmpty == true) ...[
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isDark ? Colors.white24 : Colors.grey.shade300,
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(2),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  ApiConstants.getFullImageUrl(user!.organizationLogoUrl)!,
                  fit: BoxFit.contain,
                  errorBuilder: (ctx, err, stack) => const Icon(Icons.corporate_fare_rounded, size: 18, color: AppColors.primary),
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Text(
              user?.isSuperAdmin == true
                  ? 'Platform Administration'
                  : (user?.organizationName.isNotEmpty == true
                      ? user!.organizationName
                      : 'Election Management Portal'),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          const LiveClockWidget(),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Refresh Data',
            icon: const Icon(Icons.refresh_rounded, size: 20),
            onPressed: () {
              ref.invalidate(electionsProvider);
              ref.invalidate(orgStatsProvider);
            },
          ).animate().fade().scale(delay: 200.ms),
          const ThemeModeButton(),
          const SizedBox(width: 4),
          _buildUserMenu(context, ref, user, isDark),
        ],
      ),
    );
  }

  Widget _buildGreetingBanner(BuildContext context, UserModel? user, bool isDark) {
    final rawName = user?.fullName.trim().isNotEmpty == true
        ? user!.fullName.trim()
        : (user?.email.split('@').first ?? 'Member');
    final name = rawName.isNotEmpty
        ? (rawName[0].toUpperCase() + rawName.substring(1))
        : 'Member';

    final roleLabel = user?.role == 'super_admin'
        ? 'Super Admin'
        : user?.role == 'org_admin'
        ? 'Organization Admin'
        : (user?.role == 'election_officer'
            ? 'Election Officer'
            : (user?.role == 'auditor'
                ? 'Auditor'
                : (user?.role == 'observer' ? 'Observer' : 'Verified Elector')));

    final hasCover = user != null && user.organizationCoverImageUrl.isNotEmpty;
    final isWideBanner = MediaQuery.sizeOf(context).width >= 600;
    final Widget? orgPill = user?.organizationName.isNotEmpty == true
        ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFF10B981),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Color(0xFF10B981),
                        blurRadius: 4,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    user!.organizationName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),
          )
        : null;
    final coverUrl = hasCover ? ApiConstants.getFullImageUrl(user.organizationCoverImageUrl) : null;

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 124),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF1E1B4B), const Color(0xFF312E81)]
              : [const Color(0xFF3730A3), const Color(0xFF4F46E5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        image: coverUrl != null
            ? DecorationImage(
                image: NetworkImage(coverUrl),
                fit: BoxFit.cover,
                colorFilter: ColorFilter.mode(
                  Colors.black.withValues(alpha: 0.82),
                  BlendMode.darken,
                ),
              )
            : null,
        boxShadow: [
          BoxShadow(
            color: (isDark ? Colors.black : const Color(0xFF4338CA)).withValues(alpha: 0.22),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Strong progressive scrim layer when a cover photo is present so background
          // noise/text never interferes with foreground text legibility.
          if (coverUrl != null)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      (isDark ? const Color(0xFF0F172A) : const Color(0xFF1E1B4B)).withValues(alpha: 0.94),
                      (isDark ? const Color(0xFF1E1B4B) : const Color(0xFF312E81)).withValues(alpha: 0.86),
                      (isDark ? const Color(0xFF0F172A) : const Color(0xFF1E1B4B)).withValues(alpha: 0.76),
                    ],
                  ),
                ),
              ),
            ),
          if (coverUrl == null)
            Positioned(
              right: -20,
              top: -30,
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.05),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Executive Emblem Frame (Squircle with clean backing)
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(4),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: (user?.organizationLogoUrl.isNotEmpty == true)
                            ? Image.network(
                                ApiConstants.getFullImageUrl(user!.organizationLogoUrl)!,
                                fit: BoxFit.contain,
                                errorBuilder: (ctx, err, stack) => (user.photoUrl.isNotEmpty == true)
                                    ? Image.network(
                                        ApiConstants.getFullImageUrl(user.photoUrl)!,
                                        fit: BoxFit.cover,
                                        errorBuilder: (ctx2, err2, stack2) => Center(
                                          child: Text(
                                            name.isNotEmpty ? name[0].toUpperCase() : 'U',
                                            style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 22),
                                          ),
                                        ),
                                      )
                                    : const Icon(Icons.corporate_fare_rounded, color: AppColors.primary, size: 28),
                              )
                            : (user?.photoUrl.isNotEmpty == true)
                                ? Image.network(
                                    ApiConstants.getFullImageUrl(user!.photoUrl)!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (ctx, err, stack) => Center(
                                      child: Text(
                                        name.isNotEmpty ? name[0].toUpperCase() : 'U',
                                        style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 22),
                                      ),
                                    ),
                                  )
                                : Center(
                                    child: Text(
                                      name.isNotEmpty ? name[0].toUpperCase() : 'U',
                                      style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 22),
                                    ),
                                  ),
                      ),
                    ),
                    // Small user photo badge if user has distinct photo and org logo is displayed
                    if (user?.photoUrl.isNotEmpty == true && user?.organizationLogoUrl.isNotEmpty == true)
                      Positioned(
                        bottom: -3,
                        right: -3,
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1.5),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.15),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          child: ClipOval(
                            child: Image.network(
                              ApiConstants.getFullImageUrl(user!.photoUrl)!,
                              fit: BoxFit.cover,
                              errorBuilder: (ctx, err, stack) => const Icon(Icons.person, size: 12, color: AppColors.primary),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 10,
                        runSpacing: 4,
                        children: [
                          Text(
                            'Welcome back, $name',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 19,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.3,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.verified_user_outlined, size: 12, color: Colors.white),
                                const SizedBox(width: 4),
                                Text(
                                  roleLabel,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Manage elections, monitor live ballots, and oversee electoral verifiability securely.',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                      if (orgPill != null && !isWideBanner) ...[
                        const SizedBox(height: 12),
                        orgPill,
                      ],
                    ],
                  ),
                ),
                if (orgPill != null && isWideBanner) ...[
                  const SizedBox(width: 16),
                  orgPill,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserMenu(
    BuildContext context,
    WidgetRef ref,
    UserModel? user,
    bool isDark,
  ) {
    return PopupMenuButton(
      offset: const Offset(0, 48),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.grey.shade200,
        ),
      ),
      color: isDark ? AppColors.surface : Colors.white,
      elevation: 6,
      icon: CircleAvatar(
        radius: 17,
        backgroundColor: AppColors.primary,
        backgroundImage: user?.photoUrl.isNotEmpty == true ? NetworkImage(user!.photoUrl) : null,
        child: user?.photoUrl.isNotEmpty == true
            ? null
            : Text(
                ((user?.fullName.isNotEmpty == true)
                        ? user!.fullName
                        : ((user?.email.isNotEmpty == true) ? user!.email : '?'))
                    .substring(0, 1)
                    .toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
      ),
      itemBuilder: (_) => <PopupMenuEntry<dynamic>>[
        PopupMenuItem(
          child: Row(
            children: [
              Icon(Icons.history_rounded, size: 18, color: Theme.of(context).iconTheme.color),
              const SizedBox(width: 10),
              const Text('My Voting History'),
            ],
          ),
          onTap: () => context.pushNamed('voting-history'),
        ),
        PopupMenuItem(
          child: Row(
            children: [
              Icon(Icons.person_rounded, size: 18, color: Theme.of(context).iconTheme.color),
              const SizedBox(width: 10),
              const Text('My Profile'),
            ],
          ),
          onTap: () => context.pushNamed('profile'),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          child: const Row(
            children: [
              Icon(Icons.logout_rounded, size: 18, color: AppColors.error),
              SizedBox(width: 10),
              Text('Logout', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w600)),
            ],
          ),
          onTap: () async => await ref.read(authProvider.notifier).logout(),
        ),
      ],
    ).animate().fade().scale(delay: 300.ms);
  }

  Widget _buildPremiumOverviewSection(BuildContext context, WidgetRef ref, bool isDark) {
    final statsAsync = ref.watch(orgStatsProvider);
    return statsAsync.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (e, _) => Text('Error loading stats: $e'),
      data: (stats) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 800;
              final crossAxisCount = isWide ? 5 : (constraints.maxWidth > 500 ? 3 : 2);
              return GridView.count(
                crossAxisCount: crossAxisCount,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
                childAspectRatio: 1.65,
                children: [
                  _buildPremiumStatCard(
                    context,
                    'Total Elections',
                    stats.totalElections.toString(),
                    Icons.inventory_2_rounded,
                    Colors.blue,
                    isDark,
                  ),
                  _buildPremiumStatCard(
                    context,
                    'Active Elections',
                    stats.activeElections.toString(),
                    Icons.how_to_vote_rounded,
                    Colors.green,
                    isDark,
                  ),
                  _buildPremiumStatCard(
                    context,
                    'Registered Voters',
                    _formatNumber(stats.totalMembers),
                    Icons.people_alt_rounded,
                    Colors.orange,
                    isDark,
                  ),
                  _buildPremiumStatCard(
                    context,
                    'Votes Cast',
                    _formatNumber(stats.totalBallotsCast),
                    Icons.check_circle_outline_rounded,
                    Colors.teal,
                    isDark,
                  ),
                  _buildPremiumStatCard(
                    context,
                    'Turnout %',
                    '${stats.turnoutPercentage.toStringAsFixed(1)}%',
                    Icons.pie_chart_outline_rounded,
                    Colors.purple,
                    isDark,
                  ),
                ],
              );
            },
          )
          .animate()
          .fade(duration: 400.ms, delay: 100.ms)
          .slideY(begin: 0.1, end: 0, curve: Curves.easeOutQuad),
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 800;
              return Flex(
                direction: isWide ? Axis.horizontal : Axis.vertical,
                children: [
                  Expanded(
                    flex: isWide ? 2 : 0,
                    child: _buildChartCard(
                      context,
                      'Real-time Voting Progress',
                      _buildVotingProgressChart(stats.votingProgress),
                      isDark,
                    ),
                  ),
                  if (isWide) const SizedBox(width: 16),
                  if (!isWide) const SizedBox(height: 16),
                  Expanded(
                    flex: isWide ? 3 : 0,
                    child: _buildChartCard(
                      context,
                      'Results Overview',
                      _buildResultsOverviewChart(stats.resultsOverview),
                      isDark,
                    ),
                  ),
                ],
              );
            },
          )
          .animate()
          .fade(duration: 500.ms, delay: 200.ms)
          .slideY(begin: 0.1, end: 0, curve: Curves.easeOutQuad),
        ],
      ),
    );
  }

  String _formatNumber(int number) {
    if (number >= 1000000) return '${(number / 1000000).toStringAsFixed(1)}M';
    if (number >= 1000) return '${(number / 1000).toStringAsFixed(1)}K';
    return number.toString();
  }

  Widget _buildPremiumStatCard(
    BuildContext context,
    String title,
    String value,
    IconData icon,
    MaterialColor color,
    bool isDark,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surface : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.shade200,
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color.shade600, size: 20),
              ),
              const Spacer(),
              Text(
                value,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            title,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: isDark ? Colors.white60 : Colors.grey.shade600,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartCard(
    BuildContext context,
    String title,
    Widget chartWidget,
    bool isDark,
  ) {
    return Container(
      height: 300,
      decoration: BoxDecoration(
        color: isDark ? AppColors.surface : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.shade200,
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
          ),
          const SizedBox(height: 20),
          Expanded(child: chartWidget),
        ],
      ),
    );
  }

  Widget _buildVotingProgressChart(List<Map<String, dynamic>> data) {
    if (data.isEmpty) {
      return const Center(
        child: Text('No active voting progress data yet.', style: TextStyle(color: Colors.grey)),
      );
    }

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: 100,
        barTouchData: BarTouchData(enabled: false),
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= data.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    data[index]['label'],
                    style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                  ),
                );
              },
            ),
          ),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        barGroups: List.generate(data.length, (index) {
          return BarChartGroupData(
            x: index,
            barRods: [
              BarChartRodData(
                toY: (data[index]['value'] as num).toDouble(),
                color: AppColors.primary,
                width: 16,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildResultsOverviewChart(List<Map<String, dynamic>> data) {
    if (data.isEmpty) {
      return const Center(
        child: Text('No election results overview available yet.', style: TextStyle(color: Colors.grey)),
      );
    }

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: 100,
        barTouchData: BarTouchData(enabled: false),
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= data.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    data[index]['label'],
                    style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                  ),
                );
              },
            ),
          ),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) => FlLine(
            color: Colors.grey.withValues(alpha: 0.15),
            strokeWidth: 1,
            dashArray: [4, 4],
          ),
        ),
        borderData: FlBorderData(show: false),
        barGroups: List.generate(data.length, (index) {
          final item = data[index];
          return BarChartGroupData(
            x: index,
            groupVertically: true,
            barRods: [
              BarChartRodData(
                toY: (item['valueA'] as num).toDouble(),
                color: Colors.blue.shade600,
                width: 28,
                borderRadius: BorderRadius.zero,
              ),
              BarChartRodData(
                fromY: (item['valueA'] as num).toDouble(),
                toY: (item['valueA'] as num).toDouble() + (item['valueB'] as num).toDouble(),
                color: Colors.green.shade600,
                width: 28,
                borderRadius: BorderRadius.zero,
              ),
              BarChartRodData(
                fromY: (item['valueA'] as num).toDouble() + (item['valueB'] as num).toDouble(),
                toY: (item['valueA'] as num).toDouble() + (item['valueB'] as num).toDouble() + (item['valueC'] as num).toDouble(),
                color: Colors.orange.shade600,
                width: 28,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildSectionHeader(
    BuildContext context,
    String title,
    IconData icon, {
    VoidCallback? onTap,
  }) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primary, size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const Spacer(),
        if (onTap != null)
          TextButton.icon(
            onPressed: onTap,
            icon: const Icon(Icons.arrow_forward_rounded, size: 14),
            label: const Text('See All'),
          ),
      ],
    );
  }

  Widget _buildElectionsSection(
    BuildContext context,
    WidgetRef ref,
    UserModel? user,
    bool isDark,
  ) {
    final electionsAsync = ref.watch(electionsProvider);
    return electionsAsync.when(
      loading: () => _buildShimmerList(),
      error: (e, _) => _buildError(e.toString(), () => ref.invalidate(electionsProvider)),
      data: (elections) => _buildElectionList(context, elections, user, isDark),
    );
  }

  Widget _buildElectionList(
    BuildContext context,
    List<ElectionModel> elections,
    UserModel? user,
    bool isDark,
  ) {
    if (elections.isEmpty) {
      return GlassCard(
        padding: const EdgeInsets.all(36),
        child: Column(
          children: [
            const Icon(Icons.ballot_outlined, size: 48, color: AppColors.textMuted),
            const SizedBox(height: 16),
            Text(
              'No elections yet',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              user?.canManageElections == true
                  ? 'Create your first election to get started.'
                  : 'No elections have been created for your organization yet.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey),
            ),
          ],
        ),
      ).animate().fade().scale(curve: Curves.easeOutBack);
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: elections.length > 5 ? 5 : elections.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, i) => _ElectionCard(election: elections[i], isDark: isDark)
          .animate()
          .fade(delay: Duration(milliseconds: 60 * i))
          .slideY(begin: 0.1, end: 0, curve: Curves.easeOutQuad),
    );
  }

  Widget _buildShimmerList() {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 3,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, _) => const GlassCard(
        padding: EdgeInsets.all(16),
        child: SizedBox(height: 80),
      ),
    );
  }

  Widget _buildError(String message, VoidCallback onRetry) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 32),
          const SizedBox(height: 8),
          const Text('Failed to load elections', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: onRetry,
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class _ElectionCard extends StatelessWidget {
  final ElectionModel election;
  final bool isDark;

  const _ElectionCard({required this.election, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final stateColor = _stateColor(election.state);

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
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => context.pushNamed(
            'election-detail',
            pathParameters: {'electionId': election.id},
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: stateColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _stateIcon(election.state),
                    color: stateColor,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        election.title,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: stateColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: stateColor.withValues(alpha: 0.3)),
                            ),
                            child: Text(
                              _stateLabel(election.state),
                              style: TextStyle(
                                color: stateColor,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '${election.positions.length} position(s)',
                            style: TextStyle(
                              color: isDark ? Colors.white60 : Colors.grey.shade600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (election.state == 'voting_open')
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppColors.stateVoting, Colors.green.shade700],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.how_to_vote, size: 13, color: Colors.white),
                        SizedBox(width: 4),
                        Text(
                          'VOTE NOW',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  )
                  .animate(onPlay: (controller) => controller.repeat(reverse: true))
                  .fade(begin: 0.8, end: 1.0)
                  .scaleXY(begin: 0.98, end: 1.02),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 14,
                  color: isDark ? Colors.white30 : Colors.grey.shade400,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _stateColor(String state) {
    switch (state) {
      case 'draft':
        return AppColors.stateDraft;
      case 'published':
        return AppColors.statePublished;
      case 'nominations_open':
      case 'nominations_closed':
        return AppColors.stateNominations;
      case 'voting_open':
        return AppColors.stateVoting;
      case 'voting_closed':
        return AppColors.stateClosed;
      case 'results_provisional':
      case 'results_final':
        return AppColors.stateResults;
      default:
        return AppColors.textMuted;
    }
  }

  IconData _stateIcon(String state) {
    switch (state) {
      case 'draft':
        return Icons.edit_outlined;
      case 'published':
        return Icons.public_rounded;
      case 'nominations_open':
      case 'nominations_closed':
        return Icons.person_add_alt_1_outlined;
      case 'voting_open':
        return Icons.how_to_vote_rounded;
      case 'voting_closed':
        return Icons.lock_outline_rounded;
      case 'results_provisional':
      case 'results_final':
        return Icons.emoji_events_outlined;
      default:
        return Icons.circle_outlined;
    }
  }

  String _stateLabel(String state) {
    return state.replaceAll('_', ' ').toUpperCase();
  }
}

