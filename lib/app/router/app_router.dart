import 'package:go_router/go_router.dart';
import 'package:intellipilot/app/session/session_bloc.dart';
import 'package:intellipilot/core/utils/listenable_stream.dart';
import 'package:intellipilot/features/activity/data/dtos/activity_dtos.dart';
import 'package:intellipilot/features/activity/presentation/entity_detail_page.dart';
import 'package:intellipilot/features/auth/presentation/forgot_password_page.dart';
import 'package:intellipilot/features/auth/presentation/login_page.dart';
import 'package:intellipilot/features/auth/presentation/register_page.dart';
import 'package:intellipilot/features/auth/presentation/reset_password_page.dart';
import 'package:intellipilot/features/backlog/presentation/backlog_page.dart';
import 'package:intellipilot/features/backlog/presentation/issues_page.dart';
import 'package:intellipilot/features/board/presentation/board_page.dart';
import 'package:intellipilot/features/home/presentation/home_page.dart';
import 'package:intellipilot/features/mfa/presentation/mfa_verify_page.dart';
import 'package:intellipilot/features/mfa/presentation/passkey_signin_page.dart';
import 'package:intellipilot/features/mfa/presentation/passkeys_page.dart';
import 'package:intellipilot/features/mfa/presentation/recovery_codes_page.dart';
import 'package:intellipilot/features/mfa/presentation/security_page.dart';
import 'package:intellipilot/features/mfa/presentation/totp_setup_page.dart';
import 'package:intellipilot/features/milestones/presentation/milestone_detail_page.dart';
import 'package:intellipilot/features/milestones/presentation/milestones_list_page.dart';
import 'package:intellipilot/features/profile/presentation/account_page.dart';
import 'package:intellipilot/features/profile/presentation/profile_page.dart';
import 'package:intellipilot/features/projects/presentation/invitation_accept_page.dart';
import 'package:intellipilot/features/projects/presentation/project_overview_page.dart';
import 'package:intellipilot/features/projects/presentation/project_settings_page.dart';
import 'package:intellipilot/features/projects/presentation/projects_list_page.dart';
import 'package:intellipilot/features/settings/presentation/settings_page.dart';

/// Stable route names used by code (do not hard-code paths at call sites).
abstract class Routes {
  static const home = '/';
  static const settings = '/me/settings';
  static const login = '/login';
  static const register = '/register';
  static const forgotPassword = '/forgot-password';
  static const resetPassword = '/reset-password';
  static const mfaVerify = '/auth/mfa';
  static const passkeySignIn = '/passkeys/sign-in';
  static const security = '/me/security';
  static const totpSetup = '/me/security/totp';
  static const recoveryCodes = '/me/security/recovery';
  static const passkeys = '/me/security/passkeys';
  static const profile = '/me/profile';
  static const account = '/me/account';
  static const projects = '/projects';
  static const acceptInvitation = '/i';

  static String projectDetailFor(String id) => '/projects/$id';
  static String projectSettingsFor(String id) => '/projects/$id/settings';
  static String projectBacklogFor(String id) => '/projects/$id/backlog';
  static String projectIssuesFor(String id) => '/projects/$id/issues';
  static String projectBoardFor(String id) => '/projects/$id/board';
  static String projectMilestonesFor(String id) => '/projects/$id/milestones';
  static String milestoneDetailFor(String projectId, String milestoneId) =>
      '/projects/$projectId/milestones/$milestoneId';
  static String entityDetailFor(
    String projectId,
    EntityKind kind,
    String entityId,
  ) =>
      '/projects/$projectId/items/${kind.slug}/$entityId';
  static String acceptInvitationFor(String token) => '/i/$token';
}

const _publicRoutes = {
  Routes.login,
  Routes.register,
  Routes.forgotPassword,
  Routes.resetPassword,
  Routes.passkeySignIn,
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
        path: Routes.security,
        name: 'security',
        builder: (context, state) => const SecurityPage(),
      ),
      GoRoute(
        path: Routes.totpSetup,
        name: 'totp_setup',
        builder: (context, state) => const TotpSetupPage(),
      ),
      GoRoute(
        path: Routes.recoveryCodes,
        name: 'recovery_codes',
        builder: (context, state) => const RecoveryCodesPage(),
      ),
      GoRoute(
        path: Routes.passkeys,
        name: 'passkeys',
        builder: (context, state) => const PasskeysPage(),
      ),
      GoRoute(
        path: Routes.profile,
        name: 'profile',
        builder: (context, state) => const ProfilePage(),
      ),
      GoRoute(
        path: Routes.account,
        name: 'account',
        builder: (context, state) => const AccountPage(),
      ),
      GoRoute(
        path: Routes.projects,
        name: 'projects',
        builder: (context, state) => const ProjectsListPage(),
      ),
      GoRoute(
        path: '/projects/:id',
        name: 'project_detail',
        builder: (context, state) =>
            ProjectOverviewPage(projectId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/projects/:id/settings',
        name: 'project_settings',
        builder: (context, state) =>
            ProjectSettingsPage(projectId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/projects/:id/backlog',
        name: 'project_backlog',
        builder: (context, state) =>
            BacklogPage(projectId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/projects/:id/issues',
        name: 'project_issues',
        builder: (context, state) =>
            IssuesPage(projectId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/projects/:id/board',
        name: 'project_board',
        builder: (context, state) =>
            BoardPage(projectId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/projects/:id/milestones',
        name: 'project_milestones',
        builder: (context, state) =>
            MilestonesListPage(projectId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/projects/:projectId/milestones/:milestoneId',
        name: 'milestone_detail',
        builder: (context, state) => MilestoneDetailPage(
          projectId: state.pathParameters['projectId']!,
          milestoneId: state.pathParameters['milestoneId']!,
        ),
      ),
      GoRoute(
        path: '/projects/:projectId/items/:kind/:entityId',
        name: 'entity_detail',
        builder: (context, state) {
          final slug = state.pathParameters['kind']!;
          final kind = EntityKind.values.firstWhere(
            (k) => k.slug == slug,
            orElse: () => EntityKind.userStory,
          );
          return EntityDetailPage(
            projectId: state.pathParameters['projectId']!,
            kind: kind,
            entityId: state.pathParameters['entityId']!,
          );
        },
      ),
      GoRoute(
        path: '/i/:token',
        name: 'accept_invitation',
        builder: (context, state) =>
            InvitationAcceptPage(token: state.pathParameters['token']!),
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
      GoRoute(
        path: Routes.mfaVerify,
        name: 'mfa_verify',
        builder: (context, state) => const MfaVerifyPage(),
      ),
      GoRoute(
        path: Routes.passkeySignIn,
        name: 'passkey_sign_in',
        builder: (context, state) => const PasskeySignInPage(),
      ),
    ],
  );
}

String? _guard(SessionState session, GoRouterState routerState) {
  final loc = routerState.matchedLocation;
  final isPublic = _publicRoutes.contains(loc);

  // MFA challenge in-flight: corner the user on the verify page until they
  // complete it (or cancel — that dispatches a logout via the page UI).
  if (session is SessionMfaRequired) {
    return loc == Routes.mfaVerify ? null : Routes.mfaVerify;
  }

  // Don't redirect while cold-start session restoration is still pending.
  if (session is SessionUnknown) return null;

  final isAuthed =
      session is SessionAuthenticated || session is SessionRefreshing;

  if (!isAuthed && !isPublic) {
    final from = Uri.encodeComponent(routerState.uri.toString());
    return '${Routes.login}?from=$from';
  }
  if (isAuthed && loc == Routes.login) {
    final from = routerState.uri.queryParameters['from'];
    if (from != null && from.isNotEmpty) return Uri.decodeComponent(from);
    return Routes.projects;
  }
  // Authed users on /auth/mfa shouldn't stay there.
  if (isAuthed && loc == Routes.mfaVerify) return Routes.projects;
  return null;
}
