import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/register_screen.dart';
import '../../features/auth/otp_verify_screen.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/elections/election_list_screen.dart';
import '../../features/admin/elections/election_dashboard_screen.dart';
import '../../features/elections/election_detail_screen.dart';
import '../../features/voting/ballot_screen.dart';
import '../../features/voting/vote_confirmation_screen.dart';
import '../../features/voting/receipt_screen.dart';
import '../../features/admin/elections/create_election_screen.dart';
import '../../features/admin/elections/voter_turnout_screen.dart';
import '../../features/voting/voting_history_screen.dart';
import '../../features/candidates/nomination_screen.dart';
import '../../features/candidates/nomination_list_screen.dart';
import '../../features/admin/organization/org_settings_screen.dart';
import '../../features/admin/payment_settings/payment_settings_screen.dart';
import '../../features/results/results_screen.dart';
import '../../features/profile/user_profile_screen.dart';
import '../../features/analytics/analytics_screen.dart';

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

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = ref.watch(_routerNotifierProvider);
  final authState = ref.watch(authProvider);

  return GoRouter(
    initialLocation: '/login',
    refreshListenable: notifier,
    redirect: (context, state) {
      final isLoggedIn = authState.isAuthenticated;
      final user = authState.user;
      final loc = state.matchedLocation;

      final isOnAuth = loc.startsWith('/login') ||
          loc.startsWith('/otp') ||
          loc.startsWith('/register');

      // Not logged in → always go to login
      if (!isLoggedIn && !isOnAuth) return '/login';

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

      // Prevent voters/candidates from accessing the admin dashboard
      if (isLoggedIn && user != null) {
        final role = user.role;
        final isAdminRoute = loc.startsWith('/dashboard') ||
            loc.startsWith('/org-settings') ||
            loc.startsWith('/payment-settings');
        final isAdminRole = role == 'org_admin' || role == 'super_admin';
        if (isAdminRoute && !isAdminRole) return '/elections';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginScreen(),
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
        builder: (context, state) {
          final tab = int.tryParse(state.uri.queryParameters['tab'] ?? '0') ?? 0;
          return OrgSettingsScreen(initialTab: tab);
        },
      ),
      GoRoute(
        path: '/election-rules',
        name: 'election-rules',
        redirect: (_, __) => '/org-settings?tab=1',
      ),
      GoRoute(
        path: '/payment-settings',
        name: 'payment-settings',
        builder: (context, state) => const PaymentSettingsScreen(),
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
            builder: (context, state) => const CreateElectionScreen(),
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
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Text('Page not found: ${state.uri}'),
      ),
    ),
  );
});
