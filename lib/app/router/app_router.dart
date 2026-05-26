import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intellipilot/features/home/presentation/home_page.dart';
import 'package:intellipilot/features/settings/presentation/settings_page.dart';

/// Stable route names used by code (do not hard-code paths at call sites).
abstract class Routes {
  static const home = '/';
  static const settings = '/me/settings';
  static const login = '/login';
}

GoRouter buildRouter() {
  return GoRouter(
    initialLocation: Routes.home,
    routes: [
      GoRoute(
        path: Routes.home,
        name: 'home',
        builder: (context, state) => const HomePage(),
      ),
      GoRoute(
        path: Routes.settings,
        name: 'settings',
        builder: (context, state) => const SettingsPage(),
      ),
      GoRoute(
        path: Routes.login,
        name: 'login',
        builder: (context, state) => const _LoginPlaceholder(),
      ),
    ],
  );
}

/// Placeholder. Phase 2 replaces this with the real login flow.
class _LoginPlaceholder extends StatelessWidget {
  const _LoginPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('Login — coming in Phase 2')),
    );
  }
}
