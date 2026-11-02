import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_constants.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/error_helper.dart';
import '../../shared/widgets/org_logo.dart';
import '../../shared/widgets/responsive_layout.dart';
import '../../shared/widgets/theme_mode_button.dart';
import '../dashboard/platform_overview_section.dart' show electionStateColor;

class _PublicElection {
  final String title;
  final String state;
  final String stateDisplay;
  final String method;
  final DateTime? votingStartAt;
  final DateTime? votingEndAt;

  _PublicElection.fromJson(Map<String, dynamic> j)
      : title = j['title'] as String? ?? '',
        state = j['state'] as String? ?? '',
        stateDisplay = j['state_display'] as String? ?? '',
        method = j['election_method'] as String? ?? '',
        votingStartAt = DateTime.tryParse(j['voting_start_at'] as String? ?? ''),
        votingEndAt = DateTime.tryParse(j['voting_end_at'] as String? ?? '');
}

class _PublicOrg {
  final String name;
  final String prefix;
  final String orgType;
  final String address;
  final String phone;
  final String email;
  final String website;
  final String logoUrl;
  final String coverImageUrl;
  final List<_PublicElection> elections;

  _PublicOrg.fromJson(Map<String, dynamic> j)
      : name = j['name'] as String? ?? '',
        prefix = j['prefix'] as String? ?? '',
        orgType = j['org_type'] as String? ?? '',
        address = j['address'] as String? ?? '',
        phone = j['phone'] as String? ?? '',
        email = j['email'] as String? ?? '',
        website = j['website'] as String? ?? '',
        logoUrl = j['logo_url'] as String? ?? '',
        coverImageUrl = j['cover_image_url'] as String? ?? '',
        elections = (j['elections'] as List<dynamic>? ?? [])
            .map((e) => _PublicElection.fromJson(e as Map<String, dynamic>))
            .toList();
}

final _publicOrgProvider = FutureProvider.autoDispose.family<_PublicOrg, String>((ref, prefix) async {
  final dio = ref.watch(apiClientProvider);
  final response = await dio.get(ApiConstants.publicOrganization(prefix));
  return _PublicOrg.fromJson(response.data as Map<String, dynamic>);
});

/// An organization's public page, reached at `electionnepal.org/<prefix>`.
class PublicOrganizationScreen extends ConsumerWidget {
  final String prefix;
  const PublicOrganizationScreen({super.key, required this.prefix});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_publicOrgProvider(prefix));
    final loggedIn = ref.read(authProvider).isAuthenticated;

    return Scaffold(
      appBar: AppBar(
        title: Text(async.valueOrNull?.name ?? 'Election Nepal'),
        centerTitle: false,
        actions: [
          const ThemeModeButton(),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              onPressed: () => context.go(loggedIn ? '/dashboard' : '/login'),
              icon: Icon(loggedIn ? Icons.dashboard_rounded : Icons.login_rounded, size: 18),
              label: Text(loggedIn ? 'Dashboard' : 'Sign in'),
            ),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _Message(
          icon: Icons.travel_explore_rounded,
          title: e is DioException && e.response?.statusCode == 404
              ? 'No organization at this address'
              : 'Could not load this page',
          message: e is DioException && e.response?.statusCode == 404
              ? 'Check the web address, or sign in to find your organization.'
              : extractApiErrorMessage(e),
          onRetry: () => ref.invalidate(_publicOrgProvider(prefix)),
        ),
        data: (org) => CenteredScroll(
          maxWidth: 900,
          builder: (context, pad) => ListView(
            padding: pad(const EdgeInsets.fromLTRB(20, 20, 20, 60)),
            children: [
              _Hero(org: org),
              const SizedBox(height: 28),
              Row(
                children: [
                  const Icon(Icons.how_to_vote_rounded, color: AppColors.primary, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Elections',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (org.elections.isEmpty)
                const _Message(
                  icon: Icons.event_busy_rounded,
                  title: 'No elections announced yet',
                  message: 'Announced elections will appear here.',
                )
              else
                for (final e in org.elections) _ElectionCard(election: e),
            ],
          ),
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  final _PublicOrg org;
  const _Hero({required this.org});

  @override
  Widget build(BuildContext context) {
    final cover = ApiConstants.getFullImageUrl(org.coverImageUrl);
    final type = org.orgType.replaceAll('_', ' ');
    final contacts = [
      if (org.address.isNotEmpty) (Icons.location_on_outlined, org.address, null),
      if (org.phone.isNotEmpty) (Icons.phone_outlined, org.phone, 'tel:${org.phone}'),
      if (org.email.isNotEmpty) (Icons.email_outlined, org.email, 'mailto:${org.email}'),
      if (org.website.isNotEmpty) (Icons.language_rounded, org.website, org.website),
    ];
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        image: cover == null
            ? null
            : DecorationImage(
                image: NetworkImage(cover),
                fit: BoxFit.cover,
                colorFilter: ColorFilter.mode(Colors.black.withValues(alpha: 0.45), BlendMode.darken),
                onError: (_, _) {},
              ),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22)),
                child: OrgLogo(name: org.name, logoUrl: org.logoUrl, size: 72),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      org.name,
                      style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800),
                    ),
                    if (type.isNotEmpty)
                      Text(
                        type[0].toUpperCase() + type.substring(1),
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (contacts.isNotEmpty) ...[
            const SizedBox(height: 18),
            Wrap(
              spacing: 18,
              runSpacing: 8,
              children: [
                for (final (icon, text, link) in contacts)
                  InkWell(
                    onTap: link == null ? null : () => launchUrl(Uri.parse(link), webOnlyWindowName: '_blank'),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, color: Colors.white70, size: 16),
                        const SizedBox(width: 6),
                        Text(text, style: const TextStyle(color: Colors.white, fontSize: 13)),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ElectionCard extends StatelessWidget {
  final _PublicElection election;
  const _ElectionCard({required this.election});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = electionStateColor(election.state);
    final fmt = DateFormat('d MMM yyyy, h:mm a');
    final start = election.votingStartAt;
    final end = election.votingEndAt;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surface : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 44,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(election.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 4),
                Text(
                  [
                    if (start != null) 'Voting ${fmt.format(start.toLocal())}',
                    if (end != null) 'until ${fmt.format(end.toLocal())}',
                    if (election.method.isNotEmpty) election.method,
                  ].join('  ·  '),
                  style: TextStyle(color: isDark ? Colors.white60 : Colors.grey.shade600, fontSize: 12.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(20)),
            child: Text(
              election.stateDisplay,
              style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 11.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onRetry;

  const _Message({required this.icon, required this.title, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: AppColors.primaryLight),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(message, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              TextButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ],
        ),
      ),
    );
  }
}
