import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/register_screen.dart';
import '../features/dashboard/presentation/dashboard_screen.dart';
import '../features/food_records/presentation/daily_record_screen.dart';
import '../features/food_records/presentation/edit_daily_record_screen.dart';
import '../features/food_records/presentation/record_history_screen.dart';
import '../features/forecast/screens/forecast_screen.dart';
import '../features/inventory/presentation/inventory_screen.dart';
import '../features/organization/presentation/organization_profile_screen.dart';
import '../features/organization/presentation/organization_setup_screen.dart';
import '../features/surplus/screens/surplus_screen.dart';
import '../features/waste/screens/waste_analysis_screen.dart';

/// FoodSense application router.
///
/// Navigation responsibilities stay in the app layer while feature screens
/// contain their own presentation logic.
///
/// Protected routes require an authenticated Firebase user.
class AppRouter {
  AppRouter._();

  static final GoRouter router = GoRouter(
    initialLocation: '/login',
    refreshListenable: _AuthChangeNotifier(
      FirebaseAuth.instance.authStateChanges(),
    ),
    redirect: (BuildContext context, GoRouterState state) {
      final User? user = FirebaseAuth.instance.currentUser;
      final bool isAuthenticated = user != null;

      final String path = state.uri.path;
      final bool isAuthRoute = path == '/login' || path == '/register';

      if (!isAuthenticated && !isAuthRoute) {
        return '/login';
      }

      if (isAuthenticated && isAuthRoute) {
        return '/dashboard';
      }

      return null;
    },
    routes: <RouteBase>[
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (BuildContext context, GoRouterState state) {
          return const LoginScreen();
        },
      ),
      GoRoute(
        path: '/register',
        name: 'register',
        builder: (BuildContext context, GoRouterState state) {
          return const RegisterScreen();
        },
      ),
      GoRoute(
        path: '/dashboard',
        name: 'dashboard',
        builder: (BuildContext context, GoRouterState state) {
          return const DashboardScreen();
        },
      ),
      GoRoute(
        path: '/organization/setup',
        name: 'organizationSetup',
        builder: (BuildContext context, GoRouterState state) {
          return const OrganizationSetupScreen();
        },
      ),
      GoRoute(
        path: '/organization/profile',
        name: 'organizationProfile',
        builder: (BuildContext context, GoRouterState state) {
          return const OrganizationProfileScreen();
        },
      ),
      GoRoute(
        path: '/inventory/:organizationId',
        name: 'inventory',
        builder: (BuildContext context, GoRouterState state) {
          final String organizationId =
              state.pathParameters['organizationId'] ?? '';

          return InventoryScreen(
            organizationId: organizationId,
          );
        },
      ),
      GoRoute(
        path: '/food-records/daily/:organizationId',
        name: 'dailyFoodRecord',
        builder: (BuildContext context, GoRouterState state) {
          final String organizationId =
              state.pathParameters['organizationId'] ?? '';

          return DailyRecordScreen(
            organizationId: organizationId,
          );
        },
      ),
      GoRoute(
        path: '/food-records/history/:organizationId',
        name: 'recordHistory',
        builder: (BuildContext context, GoRouterState state) {
          final String organizationId =
              state.pathParameters['organizationId'] ?? '';

          return RecordHistoryScreen(
            organizationId: organizationId,
          );
        },
      ),
      GoRoute(
        path: '/food-records/edit/:organizationId/:recordId',
        name: 'editDailyFoodRecord',
        builder: (BuildContext context, GoRouterState state) {
          final String organizationId =
              state.pathParameters['organizationId'] ?? '';
          final String recordId = state.pathParameters['recordId'] ?? '';

          return EditDailyRecordScreen(
            organizationId: organizationId,
            recordId: recordId,
          );
        },
      ),
      GoRoute(
        path: '/forecast/:organizationId',
        name: 'forecast',
        builder: (BuildContext context, GoRouterState state) {
          final String organizationId =
              state.pathParameters['organizationId'] ?? '';

          return ForecastScreen(
            organizationId: organizationId,
          );
        },
      ),
      GoRoute(
        path: '/surplus/:organizationId',
        name: 'surplus',
        builder: (BuildContext context, GoRouterState state) {
          final String organizationId =
              state.pathParameters['organizationId'] ?? '';

          return SurplusScreen(
            organizationId: organizationId,
          );
        },
      ),
      GoRoute(
        path: '/waste/:organizationId',
        name: 'wasteAnalysis',
        builder: (BuildContext context, GoRouterState state) {
          final String organizationId =
              state.pathParameters['organizationId'] ?? '';

          return WasteAnalysisScreen(
            organizationId: organizationId,
          );
        },
      ),
    ],
  );
}

/// Router instance used by [MaterialApp.router].
final GoRouter appRouter = AppRouter.router;

/// Converts Firebase auth-state changes into a [Listenable] so GoRouter
/// refreshes route guards after sign-in or sign-out.
class _AuthChangeNotifier extends ChangeNotifier {
  _AuthChangeNotifier(Stream<User?> authChanges) {
    _subscription = authChanges.listen((_) {
      notifyListeners();
    });
  }

  late final StreamSubscription<User?> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
