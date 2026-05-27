import 'package:go_router/go_router.dart';
import 'package:intellipilot/app/session/session_bloc.dart';
import 'package:intellipilot/core/utils/listenable_stream.dart';
import 'package:intellipilot/features/auth/presentation/forgot_password_page.dart';
import 'package:intellipilot/features/auth/presentation/login_page.dart';
import 'package:intellipilot/features/auth/presentation/register_page.dart';
import 'package:intellipilot/features/auth/presentation/reset_password_page.dart';
import 'package:intellipilot/features/home/presentation/home_page.dart';
import 'package:intellipilot/features/settings/presentation/settings_page.dart';

/// Stable route names used by code (do not hard-code paths at call sites).
abstract class Routes {
  static const home = '/';
  static const settings = '/me/settings';
  static const login = '/login';
  static const register = '/register';
  static const forgotPassword = '/forgot-password';
  static const resetPassword = '/reset-password';
}

const _publicRoutes = {
  Routes.login,
  Routes.register,
  Routes.forgotPassword,
  Routes.resetPassword,
};

/// Build the app router. [session] drives the redirect guard so authentication
/// state changes immediately bounce the user to/from the auth screens.
GoRouter buildRouter({required SessionBloc session}) {
  return GoRouter(
    initialLocation: Routes.home,
    refreshListenable: GoRouterRefreshStream(session.stream),
    redirect: (context, state) => _guard(session.state, state),
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
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: Routes.register,
        name: 'register',
        builder: (context, state) => const RegisterPage(),
      ),
      GoRoute(
        path: Routes.forgotPassword,
        name: 'forgot_password',
        builder: (context, state) => const ForgotPasswordPage(),
      ),
      GoRoute(
        path: Routes.resetPassword,
        name: 'reset_password',
        builder: (context, state) =>
            ResetPasswordPage(initialToken: state.uri.queryParameters['token']),
      ),
    ],
  );
}

String? _guard(SessionState session, GoRouterState routerState) {
  final loc = routerState.matchedLocation;
  final isPublic = _publicRoutes.contains(loc);

  // Don't redirect while we haven't resolved cold-start session restoration.
  if (session is SessionUnknown) {
    return null;
  }

  final isAuthed =
      session is SessionAuthenticated || session is SessionRefreshing;

  if (!isAuthed && !isPublic) {
    final from = Uri.encodeComponent(routerState.uri.toString());
    return '${Routes.login}?from=$from';
  }
  if (isAuthed && loc == Routes.login) {
    final from = routerState.uri.queryParameters['from'];
    if (from != null && from.isNotEmpty) return Uri.decodeComponent(from);
    return Routes.home;
  }
  return null;
}
