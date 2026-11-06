import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/register_screen.dart';
import '../../features/auth/otp_verify_screen.dart';
import '../../features/auth/forgot_password_screen.dart';
import '../../features/auth/reset_password_screen.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/elections/election_list_screen.dart';
import '../../features/admin/elections/election_dashboard_screen.dart';
import '../../features/elections/election_detail_screen.dart';
import '../../features/voting/ballot_screen.dart';
import '../../features/voting/direct_ballot_screen.dart';
import '../../features/voting/vote_confirmation_screen.dart';
import '../../features/voting/receipt_screen.dart';
import '../../features/voting/verify_vote_screen.dart';
import '../../features/admin/elections/create_election_screen.dart';
import '../../features/admin/elections/voter_turnout_screen.dart';
import '../../features/voting/voting_history_screen.dart';
import '../../features/candidates/nomination_screen.dart';
import '../../features/candidates/nomination_list_screen.dart';
import '../../features/candidates/nomination_inbox_screen.dart';
import '../../features/admin/organization/org_settings_screen.dart';
import '../../features/admin/election_rules/election_rules_screen.dart';
import '../../features/admin/payment_settings/payment_settings_screen.dart';
import '../../features/admin/payments/payment_management_screen.dart';
import '../../features/admin/platform/platform_organizations_screen.dart';
import '../../features/admin/platform/platform_election_detail_screen.dart';
import '../../features/results/results_screen.dart';
import '../../features/profile/user_profile_screen.dart';
import '../../features/analytics/analytics_screen.dart';
import '../../features/venue_kiosk/venue_kiosk_screen.dart';
import '../../features/public/public_organization_screen.dart';

/// Bridges Riverpod auth state into a ChangeNotifier so GoRouter
/// can call [refreshListenable] and re-run the redirect logic whenever
/// the logged-in user changes.
class _RouterNotifier extends ChangeNotifier {
  _RouterNotifier(this._ref) {
    _ref.listen<AuthState>(authProvider, (_, next) => notifyListeners());
  }
  final Ref _ref;
}

final _routerNotifierProvider = ChangeNotifierProvider(
  (ref) => _RouterNotifier(ref),
);

String? _detectSubdomain() {
  if (!kIsWeb) return null;
  final host = Uri.base.host.toLowerCase();
  if (host == 'localhost' ||
      host == '127.0.0.1' ||
      RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(host) ||
      host == 'electionnepal.org' ||
      host == 'www.electionnepal.org' ||
      host == 'election.omwaytechnologies.com' ||
      host == 'admin.electionnepal.org') {
    return null;
  }
  final parts = host.split('.');
  if (parts.length >= 3) {
    final sub = parts.first;
    if (sub != 'www' &&
        sub != 'admin' &&
        sub != 'api' &&
        RegExp(r'^[a-z0-9-]+$').hasMatch(sub)) {
      return sub;
    }
  }
  return null;
}

/// Routes public URLs and branded portals on initial web load:
/// - electionnepal.org/$prefix -> /o/$prefix (public page)
/// - electionnepal.org/$prefix/login -> /login?org=$prefix (branded login)
/// - $prefix.electionnepal.org -> /login?org=$prefix (subdomain branded login)
String _initialLocation() {
  if (!kIsWeb) return '/login';
  final sub = _detectSubdomain();
  if (Uri.base.fragment.isNotEmpty) {
    var frag = Uri.base.fragment;
    if (!frag.startsWith('/')) frag = '/$frag';
    if (frag == '/login' && sub != null) {
      return '/login?org=$sub';
    }
    return frag;
  }
  final segments = Uri.base.pathSegments.where((s) => s.isNotEmpty).toList();
  // Case 1: /<token>/<prefix>/login (CEO format: sldfe21324vfbgf/nesog/login)
  if (segments.length == 3 && segments[2].toLowerCase() == 'login') {
    return '/${segments[0]}/${segments[1]}/login';
  }
  // Case 2: /o/<token>/<prefix>/login
  if (segments.length == 4 && segments[0].toLowerCase() == 'o' && segments[3].toLowerCase() == 'login') {
    return '/${segments[1]}/${segments[2]}/login';
  }
  if (segments.length == 1 && RegExp(r'^[A-Za-z0-9][A-Za-z0-9-]*$').hasMatch(segments.first)) {
    final seg = segments.first;
    if (seg.toLowerCase() == 'login') {
      return sub != null ? '/login?org=$sub' : '/login';
    }
    return '/o/$seg';
  }
  if (segments.length == 2 &&
      RegExp(r'^[A-Za-z0-9][A-Za-z0-9-]*$').hasMatch(segments.first) &&
      segments[1].toLowerCase() == 'login') {
    return '/login?org=${segments.first}';
  }
  if (sub != null) {
    return '/login?org=$sub';
  }
  return '/login';
}

final routerProvider = Provider<GoRouter>((ref) {
  // Read, don't watch: watching rebuilt the GoRouter on every auth change
  // (even "loading"), which reset navigation to /login, so e.g. a wrong OTP
  // bounced the user back to the login screen. The notifier re-runs redirect.
  final notifier = ref.read(_routerNotifierProvider);

  return GoRouter(
    initialLocation: _initialLocation(),
    refreshListenable: notifier,
    redirect: (context, state) {
      final authState = ref.read(authProvider);
      final isLoggedIn = authState.isAuthenticated;
      final user = authState.user;
      final loc = state.matchedLocation;

      final isOnAuth = loc.startsWith('/login') ||
          loc.startsWith('/otp') ||
          loc.startsWith('/forgot-password') ||
          loc.startsWith('/reset-password') ||
          loc.endsWith('/login');

      final isDirectVoteRoute = loc.startsWith('/vote/direct') ||
          loc.startsWith('/vote/receipt') ||
          loc.startsWith('/verify-vote') ||
          loc.startsWith('/o/');

      // Unauthenticated users are allowed on auth pages and direct ballot link pages
      if (!isLoggedIn && !isOnAuth && !isDirectVoteRoute) {
        final lastOrg = authState.lastOrgPrefix;
        final lastToken = authState.lastPortalToken;
        if (lastToken != null && lastToken.trim().isNotEmpty && lastOrg != null && lastOrg.trim().isNotEmpty) {
          return '/${lastToken.trim()}/${lastOrg.trim()}/login';
        }
        if (lastOrg != null && lastOrg.trim().isNotEmpty) {
          return '/login?org=${lastOrg.trim()}';
        }
        final sub = _detectSubdomain();
        if (sub != null && sub.isNotEmpty) {
          return '/login?org=$sub';
        }
        return '/login';
      }

      // Already logged in and on an auth page → route by role
      if (isLoggedIn && isOnAuth && user != null) {
        final role = user.role;
        if (role == 'org_admin' || role == 'super_admin') {
          return '/dashboard';
        }
        // election_officer, observer, auditor → election list
        if (role == 'election_officer' ||
            role == 'observer' ||
            role == 'auditor') {
          return '/elections';
        }
        // voter, candidate → election list (voter-facing)
        return '/elections';
      }

      // Prevent voters/candidates from accessing admin restricted routes
      if (isLoggedIn && user != null) {
        final role = user.role;
        final isAdminRoute = loc.startsWith('/dashboard') ||
            loc.startsWith('/org-settings') ||
            loc.startsWith('/payment-settings');
        final isAdminRole = role == 'org_admin' || role == 'super_admin';
        if (isAdminRoute && !isAdminRole) return '/elections';

        // Creating and managing organizations is reserved for the platform super admin
        if ((loc.startsWith('/register') || loc.startsWith('/platform')) &&
            role != 'super_admin') {
          return '/dashboard';
        }

        final isOfficerRoute = loc.startsWith('/admin/payments') || loc == '/nominations';
        final isOfficerOrAdmin = isAdminRole || role == 'election_officer';
        if (isOfficerRoute && !isOfficerOrAdmin) return '/elections';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) {
          final org = state.uri.queryParameters['org'] ??
              _detectSubdomain() ??
              ref.read(authProvider).lastOrgPrefix;
          return LoginScreen(orgPrefix: org);
        },
      ),
      GoRoute(
        path: '/:token/:prefix/login',
        name: 'token-org-login',
        builder: (context, state) => LoginScreen(
          orgPrefix: state.pathParameters['prefix'],
          portalToken: state.pathParameters['token'],
        ),
      ),
      GoRoute(
        path: '/o/:token/:prefix/login',
        builder: (context, state) => LoginScreen(
          orgPrefix: state.pathParameters['prefix'],
          portalToken: state.pathParameters['token'],
        ),
      ),
      GoRoute(
        path: '/o/:prefix/login',
        name: 'public-org-login',
        builder: (context, state) => LoginScreen(
          orgPrefix: state.pathParameters['prefix'] ?? _detectSubdomain(),
        ),
      ),
      GoRoute(
        path: '/o/:prefix',
        name: 'public-org',
        builder: (context, state) => PublicOrganizationScreen(
          prefix: state.pathParameters['prefix']!,
        ),
      ),
      GoRoute(
        path: '/forgot-password',
        name: 'forgot-password',
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/reset-password/:email',
        name: 'reset-password',
        builder: (context, state) => ResetPasswordScreen(
          email: state.pathParameters['email']!,
        ),
      ),
      GoRoute(
        path: '/register',
        name: 'register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/otp/:identifier',
        name: 'otp',
        builder: (context, state) => OtpVerifyScreen(
          identifier: state.pathParameters['identifier']!,
        ),
      ),
      GoRoute(
        path: '/dashboard',
        name: 'dashboard',
        builder: (context, state) => const DashboardScreen(),
      ),
      GoRoute(
        path: '/org-settings',
        name: 'org-settings',
        builder: (context, state) => const OrgSettingsScreen(),
      ),
      GoRoute(
        path: '/election-rules',
        name: 'election-rules',
        builder: (context, state) => const ElectionRulesScreen(),
      ),
      GoRoute(
        path: '/payment-settings',
        name: 'payment-settings',
        builder: (context, state) => const PaymentSettingsScreen(),
      ),
      GoRoute(
        path: '/nominations',
        name: 'nominations',
        builder: (context, state) => const NominationInboxScreen(),
      ),
      GoRoute(
        path: '/platform/organizations',
        name: 'platform-organizations',
        builder: (context, state) => const PlatformOrganizationsScreen(),
      ),
      GoRoute(
        path: '/platform/elections/:id',
        name: 'platform-election',
        builder: (context, state) => PlatformElectionDetailScreen(
          electionId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/platform/organizations/:id',
        name: 'platform-organization',
        builder: (context, state) => PlatformOrganizationDetailScreen(
          orgId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/admin/payments',
        name: 'admin-payments',
        builder: (context, state) => const PaymentManagementScreen(),
      ),
      GoRoute(
        path: '/profile',
        name: 'profile',
        builder: (context, state) => const UserProfileScreen(),
      ),

      GoRoute(
        path: '/voting-history',
        name: 'voting-history',
        builder: (context, state) => const VotingHistoryScreen(),
      ),
      GoRoute(
        path: '/elections',
        name: 'elections',
        builder: (context, state) => const ElectionListScreen(),
        routes: [
          GoRoute(
            path: 'new',
            name: 'create-election',
            builder: (context, state) => CreateElectionScreen(
              initialOrgId: state.uri.queryParameters['orgId'] ?? state.uri.queryParameters['org_id'],
            ),
          ),
          GoRoute(
            path: ':electionId',
            name: 'election-detail',
            builder: (context, state) {
              final electionId = state.pathParameters['electionId']!;
              // Read auth state directly from the container
              // canManageElections covers org_admin + election_officer
              return Consumer(
                builder: (ctx, ref, _) {
                  final user = ref.watch(currentUserProvider);
                  if (user != null && user.canManageElections) {
                    return ElectionDashboardScreen(electionId: electionId);
                  }
                  // voter, candidate, observer, auditor → public view
                  return ElectionDetailScreen(electionId: electionId);
                },
              );
            },
          ),
          GoRoute(
            path: ':electionId/turnout',
            name: 'election-turnout',
            builder: (context, state) => VoterTurnoutScreen(
              electionId: state.pathParameters['electionId']!,
            ),
          ),
          GoRoute(
            path: ':electionId/ballot',
            name: 'ballot',
            builder: (context, state) => BallotScreen(
              electionId: state.pathParameters['electionId']!,
            ),
          ),
          GoRoute(
            path: ':electionId/kiosk',
            name: 'venue-kiosk',
            builder: (context, state) => VenueKioskScreen(
              electionId: state.pathParameters['electionId']!,
            ),
          ),
          GoRoute(
            path: ':electionId/confirm',
            name: 'vote-confirm',
            builder: (context, state) => VoteConfirmationScreen(
              electionId: state.pathParameters['electionId']!,
            ),
          ),
          GoRoute(
            path: ':electionId/receipt',
            name: 'receipt',
            builder: (context, state) => ReceiptScreen(
              electionId: state.pathParameters['electionId']!,
              receiptHash: state.uri.queryParameters['receipt'] ?? '',
            ),
          ),
          GoRoute(
            path: ':electionId/results',
            name: 'results',
            builder: (context, state) => ResultsScreen(
              electionId: state.pathParameters['electionId']!,
            ),
          ),
          GoRoute(
            path: ':electionId/nominate',
            name: 'nominate',
            builder: (context, state) => NominationScreen(
              electionId: state.pathParameters['electionId']!,
            ),
          ),
          GoRoute(
            path: ':electionId/nominations',
            name: 'review_nominations',
            builder: (context, state) => NominationListScreen(
              electionId: state.pathParameters['electionId']!,
            ),
          ),
          GoRoute(
            path: ':electionId/analytics',
            name: 'analytics',
            builder: (context, state) => AnalyticsScreen(
              electionId: state.pathParameters['electionId']!,
            ),
          ),
        ],
      ),

      // ─── Direct Tokenized Voting Routes (Method 1 Type 2) ──────────────────
      GoRoute(
        path: '/vote/direct/:token',
        name: 'direct-ballot',
        builder: (context, state) => DirectBallotScreen(
          directToken: state.pathParameters['token']!,
        ),
      ),
      GoRoute(
        path: '/vote/receipt',
        name: 'direct-receipt',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return ReceiptScreen(
            electionId: extra['election_id'] ?? '',
            receiptHash: extra['receipt_hash'] ?? state.uri.queryParameters['receipt'] ?? '',
          );
        },
      ),
      GoRoute(
        path: '/verify-vote',
        name: 'verify-vote',
        builder: (context, state) {
          final sig = state.uri.queryParameters['signature'] ??
              state.uri.queryParameters['receipt_hash'];
          return VerifyVoteScreen(initialSignature: sig);
        },
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Text('Page not found: ${state.uri}'),
      ),
    ),
  );
});
