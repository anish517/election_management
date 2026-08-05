import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/otp_verify_screen.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/elections/election_list_screen.dart';
import '../../features/elections/election_detail_screen.dart';
import '../../features/voting/ballot_screen.dart';
import '../../features/voting/vote_confirmation_screen.dart';
import '../../features/voting/receipt_screen.dart';
import '../../features/results/results_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authProvider);

  return GoRouter(
    initialLocation: '/login',
    redirect: (context, state) {
      final isLoggedIn = authState.isAuthenticated;
      final isOnAuth = state.matchedLocation.startsWith('/login') ||
          state.matchedLocation.startsWith('/otp');

      if (!isLoggedIn && !isOnAuth) return '/login';
      if (isLoggedIn && isOnAuth) return '/dashboard';
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginScreen(),
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
        path: '/elections',
        name: 'elections',
        builder: (context, state) => const ElectionListScreen(),
        routes: [
          GoRoute(
            path: ':electionId',
            name: 'election-detail',
            builder: (context, state) => ElectionDetailScreen(
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
