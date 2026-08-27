import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/router/short_links.dart';
import 'package:intellipilot/app/session/session_bloc.dart';
import 'package:intellipilot/app/shell/main_shell.dart';
import 'package:intellipilot/core/network/server_endpoint.dart';
import 'package:intellipilot/core/utils/listenable_stream.dart';
import 'package:intellipilot/features/activity/data/dtos/activity_dtos.dart';
import 'package:intellipilot/features/activity/presentation/entity_detail_page.dart';
import 'package:intellipilot/features/activity/presentation/epic_key_page.dart';
import 'package:intellipilot/features/activity/presentation/issue_key_page.dart';
import 'package:intellipilot/features/admin/presentation/admin_activity_page.dart';
import 'package:intellipilot/features/admin/presentation/admin_app_tokens_page.dart';
import 'package:intellipilot/features/admin/presentation/admin_settings_page.dart';
import 'package:intellipilot/features/admin/presentation/admin_users_page.dart';
import 'package:intellipilot/features/auth/presentation/forgot_password_page.dart';
import 'package:intellipilot/features/auth/presentation/login_page.dart';
import 'package:intellipilot/features/auth/presentation/register_page.dart';
import 'package:intellipilot/features/auth/presentation/reset_password_page.dart';
import 'package:intellipilot/features/backlog/presentation/backlog_page.dart';
import 'package:intellipilot/features/backlog/presentation/epics_page.dart';
import 'package:intellipilot/features/backlog/presentation/issues_page.dart';
import 'package:intellipilot/features/board/presentation/board_page.dart';
import 'package:intellipilot/features/board/presentation/board_resolver.dart';
import 'package:intellipilot/features/board/presentation/boards_gallery_page.dart';
import 'package:intellipilot/features/board/presentation/my_issues_page.dart';
import 'package:intellipilot/features/connect/presentation/connect_page.dart';
import 'package:intellipilot/features/docs/presentation/docs_page.dart';
import 'package:intellipilot/features/docs/presentation/wiki_overview_page.dart';
import 'package:intellipilot/features/home/presentation/home_page.dart';
import 'package:intellipilot/features/mfa/presentation/mfa_verify_page.dart';
import 'package:intellipilot/features/mfa/presentation/passkey_signin_page.dart';
import 'package:intellipilot/features/mfa/presentation/passkeys_page.dart';
import 'package:intellipilot/features/mfa/presentation/recovery_codes_page.dart';
import 'package:intellipilot/features/mfa/presentation/security_page.dart';
import 'package:intellipilot/features/mfa/presentation/totp_setup_page.dart';
import 'package:intellipilot/features/milestones/presentation/milestones_list_page.dart';
import 'package:intellipilot/features/profile/presentation/account_page.dart';
import 'package:intellipilot/features/profile/presentation/profile_page.dart';
import 'package:intellipilot/features/projects/presentation/invitation_accept_page.dart';
import 'package:intellipilot/features/projects/presentation/project_overview_page.dart';
import 'package:intellipilot/features/projects/presentation/project_settings_page.dart';
import 'package:intellipilot/features/projects/presentation/projects_list_page.dart';
import 'package:intellipilot/features/settings/presentation/settings_page.dart';
import 'package:intellipilot/features/timesheet/presentation/pages/admin_user_time_page.dart';
import 'package:intellipilot/features/timesheet/presentation/pages/project_time_page.dart';
import 'package:intellipilot/features/timesheet/presentation/pages/timesheet_page.dart';
import 'package:intellipilot/features/wiki/presentation/wiki_list_page.dart';
import 'package:intellipilot/features/wiki/presentation/wiki_page_view.dart';
import 'package:intellipilot/features/wiki/presentation/wiki_revisions_page.dart';

/// Stable route names used by code (do not hard-code paths at call sites).
abstract class Routes {
  static const home = '/';
  static const settings = '/me/settings';

  /// Step ① of the desktop/mobile sign-in wizard: which server. Never
  /// reachable on web, which is served by its own instance.
  static const connect = '/connect';

  /// Marks a wizard screen as belonging to an "add another account" run.
  ///
  /// Both steps need it. The guard otherwise bounces an authenticated user off
  /// `/connect` *and* `/login` — correct when someone stumbles back onto them,
  /// wrong when they deliberately asked to add a second account.
  static const addAccountFlag = 'add';

  /// Where "add another account" goes: step ① of the wizard, not step ②.
  ///
  /// The second account usually lives on a *different* server, so the flow has
  /// to start by asking which one. Jumping straight to `/login` silently
  /// assumed the current server and left no way to enter another.
  static String addAccount() => '$connect?$addAccountFlag=1';

  /// Step ② of the same run, once a server has been chosen.
  static String addAccountLogin() => '$login?$addAccountFlag=1';

  /// Whether [uri] is a wizard screen in add-account mode.
  static bool isAddAccount(Uri uri) =>
      uri.queryParameters[addAccountFlag] == '1';
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
  static const timesheet = '/me/timesheet';
  static const acceptInvitation = '/i';
  // Platform-admin (V011) — only superadmins should reach these; the
  // backend gates the API with 403, and the SPA hides the nav entry for
  // non-admins, but no router-level redirect today.
  static const adminUsers = '/admin/users';
  static const adminSettings = '/admin/settings';
  static const adminActivity = '/admin/activity';
  static const adminAppTokens = '/admin/app-tokens';

  static String projectDetailFor(String id) => '/projects/$id';
  static String projectSettingsFor(String id) => '/projects/$id/settings';
  static String projectBacklogFor(String id) => '/projects/$id/backlog';
  static String projectEpicsFor(String id) => '/projects/$id/epics';
  static String projectIssuesFor(String id) => '/projects/$id/issues';

  /// Issues list deep-linked with filters. `assignee` accepts a user id or the
  /// sentinel `'none'` for unassigned issues.
  static String projectIssuesFiltered(
    String id, {
    String? status,
    String? type,
    String? assignee,
    bool overdue = false,
  }) {
    final params = <String, String>{
      'status': ?status,
      'type': ?type,
      'assignee': ?assignee,
      if (overdue) 'overdue': 'true',
    };
    if (params.isEmpty) return '/projects/$id/issues';
    final query = params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    return '/projects/$id/issues?$query';
  }

  /// The board route. With no [boardId] this is the resolver entry that
  /// redirects to the last-opened (or first) board; with one it targets that
  /// specific board.
  static String projectBoardFor(String id, [String? boardId]) =>
      boardId == null ? '/projects/$id/board' : '/projects/$id/boards/$boardId';

  /// The My Issues board: the signed-in user's work in this project, laned by
  /// their role on each issue.
  static String projectMyIssuesFor(String id) => '/projects/$id/my-issues';

  /// The boards gallery (index) route — lists the project's boards as cards.
  /// Redirects straight to the board when the project has exactly one.
  static String projectBoardsFor(String id) => '/projects/$id/boards';

  /// Back-compat alias for callers that still link to the standalone
  /// task board. Both views now live on the unified Board page with a
  /// Stories / Tasks toggle in the app bar, so we route to the same URL.
  @Deprecated('Use projectBoardFor — Stories/Tasks toggle on the board')
  static String projectTaskBoardFor(String id) => projectBoardFor(id);
  static String projectMilestonesFor(String id) => '/projects/$id/milestones';
  static String projectTimeFor(String id) => '/projects/$id/time';
  static String adminUserTimeFor(String id) => '/admin/users/$id/time';
  static String milestoneDetailFor(String projectId, String milestoneId) =>
      '/projects/$projectId/milestones/$milestoneId';

  /// The Wiki section landing page: tiles for the internal wiki and every
  /// external documentation source.
  static String projectWikiFor(String id) => '/projects/$id/wiki';

  /// The internal wiki's own page list. Individual page URLs are deliberately
  /// left where they were (`/wiki/{pageId}`), so existing links keep working.
  static String wikiPagesFor(String id) => '/projects/$id/wiki/pages';
  static String wikiPageFor(String projectId, String pageId) =>
      '/projects/$projectId/wiki/$pageId';

  /// One external documentation source, optionally at a specific document.
  static String docSourceFor(
    String projectId,
    String sourceId, {
    String? path,
  }) {
    final base = '/projects/$projectId/docs/$sourceId';
    if (path == null || path.isEmpty) return base;
    return '$base?path=${Uri.encodeQueryComponent(path)}';
  }

  static String wikiRevisionsFor(String projectId, String pageId) =>
      '/projects/$projectId/wiki/$pageId/revisions';
  static String entityDetailFor(
    String projectId,
    EntityKind kind,
    String entityId,
  ) => '/projects/$projectId/items/${kind.slug}/$entityId';

  /// Clean, human-readable full-page issue URL keyed by its issue key
  /// (e.g. `/projects/{id}/issues/PS-398`).
  static String issueByKeyFor(String projectId, String key) =>
      '/projects/$projectId/issues/$key';

  /// Clean, human-readable full-page epic URL keyed by its epic key
  /// (e.g. `/projects/{id}/epics/PS-E-7`).
  static String epicByKeyFor(String projectId, String key) =>
      '/projects/$projectId/epics/$key';

  /// The canonical short full-page route for a work item — the URL users see
  /// and share (`/projects/ps/issues/ps-398`). Prefers the project's short
  /// prefix over its UUID, falling back to the UUID when no prefix is set.
  ///
  /// Every in-app jump to an epic / issue should route through here rather
  /// than [entityDetailFor], which produces the legacy double-UUID form.
  static String entityByKeyFor({
    required String projectId,
    required String issuePrefix,
    required EntityKind kind,
    required String key,
  }) {
    final ref = issuePrefix.trim().isEmpty
        ? projectId
        : issuePrefix.trim().toLowerCase();
    final k = key.toLowerCase();
    return kind == EntityKind.epic
        ? epicByKeyFor(ref, k)
        : issueByKeyFor(ref, k);
  }

  static String acceptInvitationFor(String token) => '/i/$token';
}

const _publicRoutes = {
  Routes.connect,
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
      // Authenticated routes share the app shell (top bar + project rail).
      // Public + auth routes (login, register, password reset, MFA, accept
      // invitation) sit outside this ShellRoute so they keep the
      // chrome-free auth layout.
      ShellRoute(
        builder: (context, state, child) => MainShell(child: child),
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
            path: Routes.timesheet,
            name: 'timesheet',
            builder: (context, state) => const TimesheetPage(),
          ),
          GoRoute(
            path: '/projects/:id/time',
            name: 'project_time',
            builder: (context, state) => ShortLinkGate(
              state: state,
              builder: (_, pid, _) => ProjectTimePage(projectId: pid),
            ),
          ),
          GoRoute(
            path: '/admin/users/:id/time',
            name: 'admin_user_time',
            builder: (context, state) =>
                AdminUserTimePage(userId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/projects/:id',
            name: 'project_detail',
            builder: (context, state) => ShortLinkGate(
              state: state,
              builder: (_, pid, _) => ProjectOverviewPage(projectId: pid),
            ),
          ),
          GoRoute(
            path: '/projects/:id/settings',
            name: 'project_settings',
            builder: (context, state) => ShortLinkGate(
              state: state,
              builder: (_, pid, _) => ProjectSettingsPage(projectId: pid),
            ),
          ),
          GoRoute(
            path: '/projects/:id/backlog',
            name: 'project_backlog',
            builder: (context, state) => ShortLinkGate(
              state: state,
              builder: (_, pid, _) => BacklogPage(projectId: pid),
            ),
          ),
          GoRoute(
            path: '/projects/:id/epics',
            name: 'project_epics',
            builder: (context, state) => ShortLinkGate(
              state: state,
              builder: (_, pid, _) => EpicsPage(projectId: pid),
            ),
          ),
          GoRoute(
            path: '/projects/:id/issues',
            name: 'project_issues',
            builder: (context, state) {
              final q = state.uri.queryParameters;
              final overdue = q['overdue'] == 'true';
              return ShortLinkGate(
                state: state,
                builder: (_, pid, _) => IssuesPage(
                  projectId: pid,
                  initialStatusFilter: q['status'],
                  initialTypeFilter: q['type'],
                  initialAssigneeFilter: q['assignee'],
                  initialOverdueOnly: overdue,
                ),
              );
            },
          ),
          GoRoute(
            path: '/projects/:id/my-issues',
            name: 'project_my_issues',
            builder: (context, state) => ShortLinkGate(
              state: state,
              builder: (_, pid, _) => MyIssuesPage(projectId: pid),
            ),
          ),
          GoRoute(
            path: '/projects/:id/board',
            name: 'project_board',
            builder: (context, state) => ShortLinkGate(
              state: state,
              builder: (_, pid, _) => BoardResolverPage(projectId: pid),
            ),
          ),
          GoRoute(
            path: '/projects/:id/boards',
            name: 'project_boards_gallery',
            builder: (context, state) => ShortLinkGate(
              state: state,
              builder: (_, pid, _) => BoardsGalleryPage(projectId: pid),
            ),
          ),
          GoRoute(
            path: '/projects/:id/boards/:boardId',
            name: 'project_board_detail',
            builder: (context, state) => ShortLinkGate(
              state: state,
              boardRef: state.pathParameters['boardId'],
              builder: (_, pid, boardId) =>
                  BoardPage(projectId: pid, boardId: boardId!),
            ),
          ),
          GoRoute(
            // Back-compat: the standalone task board collapsed into the
            // unified Board page with a Stories ⇄ Tasks toggle. Anyone
            // visiting an old `/task-board` link lands on the board, where
            // their last-chosen mode (persisted per project) is honoured.
            path: '/projects/:id/task-board',
            name: 'project_task_board_legacy',
            redirect: (context, state) =>
                Routes.projectBoardFor(state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/projects/:id/milestones',
            name: 'project_milestones',
            builder: (context, state) => ShortLinkGate(
              state: state,
              builder: (_, pid, _) => MilestonesListPage(projectId: pid),
            ),
          ),
          // A milestone has no screen of its own: this URL renders the
          // milestones page in whichever view the user last used, with the
          // detail sidebar already open on the milestone. Keeps every existing
          // deep link (and the milestone chip on an issue) working.
          GoRoute(
            path: '/projects/:projectId/milestones/:milestoneId',
            name: 'milestone_detail',
            builder: (context, state) => ShortLinkGate(
              state: state,
              builder: (_, pid, _) => MilestonesListPage(
                projectId: pid,
                openMilestoneId: state.pathParameters['milestoneId'],
              ),
            ),
          ),
          GoRoute(
            path: '/projects/:id/wiki',
            name: 'project_wiki',
            builder: (context, state) => ShortLinkGate(
              state: state,
              builder: (_, pid, _) => WikiOverviewPage(projectId: pid),
            ),
          ),
          // Declared BEFORE `/wiki/:pageId` so the literal segment wins. Page
          // ids are UUIDs, so "pages" can never be one.
          GoRoute(
            path: '/projects/:id/wiki/pages',
            name: 'wiki_pages',
            builder: (context, state) => ShortLinkGate(
              state: state,
              builder: (_, pid, _) => WikiListPage(projectId: pid),
            ),
          ),
          GoRoute(
            path: '/projects/:projectId/docs/:sourceId',
            name: 'doc_source',
            builder: (context, state) => ShortLinkGate(
              state: state,
              builder: (_, pid, _) => DocsPage(
                projectId: pid,
                sourceId: state.pathParameters['sourceId']!,
                path: state.uri.queryParameters['path'],
              ),
            ),
          ),
          GoRoute(
            path: '/projects/:projectId/wiki/:pageId',
            name: 'wiki_page',
            builder: (context, state) => ShortLinkGate(
              state: state,
              builder: (_, pid, _) => WikiPageView(
                projectId: pid,
                pageId: state.pathParameters['pageId']!,
              ),
            ),
          ),
          GoRoute(
            path: '/projects/:projectId/wiki/:pageId/revisions',
            name: 'wiki_revisions',
            builder: (context, state) => ShortLinkGate(
              state: state,
              builder: (_, pid, _) => WikiRevisionsPage(
                projectId: pid,
                pageId: state.pathParameters['pageId']!,
              ),
            ),
          ),
          GoRoute(
            path: '/projects/:projectId/items/:kind/:entityId',
            name: 'entity_detail',
            builder: (context, state) {
              final slug = state.pathParameters['kind']!;
              final kind = EntityKind.values.firstWhere(
                (k) => k.slug == slug,
                orElse: () => EntityKind.issue,
              );
              return ShortLinkGate(
                state: state,
                builder: (_, pid, _) => EntityDetailPage(
                  projectId: pid,
                  kind: kind,
                  entityId: state.pathParameters['entityId']!,
                ),
              );
            },
          ),
          GoRoute(
            // Clean, human-readable full-page issue view keyed by issue key.
            path: '/projects/:projectId/issues/:key',
            name: 'issue_by_key',
            builder: (context, state) => ShortLinkGate(
              state: state,
              lowercaseTail: true,
              builder: (_, pid, _) => IssueKeyPage(
                projectId: pid,
                issueKey: state.pathParameters['key']!,
              ),
            ),
          ),
          GoRoute(
            // Clean, human-readable full-page epic view keyed by epic key.
            path: '/projects/:projectId/epics/:key',
            name: 'epic_by_key',
            builder: (context, state) => ShortLinkGate(
              state: state,
              lowercaseTail: true,
              builder: (_, pid, _) => EpicKeyPage(
                projectId: pid,
                epicKey: state.pathParameters['key']!,
              ),
            ),
          ),
          GoRoute(
            path: Routes.adminUsers,
            name: 'admin_users',
            builder: (context, state) => const AdminUsersPage(),
          ),
          GoRoute(
            path: Routes.adminSettings,
            name: 'admin_settings',
            builder: (context, state) => const AdminSettingsPage(),
          ),
          GoRoute(
            path: Routes.adminActivity,
            name: 'admin_activity',
            builder: (context, state) => const AdminActivityPage(),
          ),
          GoRoute(
            path: Routes.adminAppTokens,
            name: 'admin_app_tokens',
            builder: (context, state) => const AdminAppTokensPage(),
          ),
        ],
      ),
      GoRoute(
        path: '/i/:token',
        name: 'accept_invitation',
        builder: (context, state) =>
            InvitationAcceptPage(token: state.pathParameters['token']!),
      ),
      // Desktop/mobile only: on web `kIsWeb` keeps the guard from ever
      // targeting this, and the app's own origin is the server.
      GoRoute(
        path: Routes.connect,
        name: 'connect',
        builder: (context, state) => const ConnectPage(),
      ),
      GoRoute(
        path: Routes.login,
        name: 'login',
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: Routes.register,
        name: 'register',
        builder: (context, state) =>
            RegisterPage(invitationToken: state.uri.queryParameters['token']),
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

  // A deliberate "add another account" run: the user is signed in and is
  // *supposed* to see the wizard. Desktop/mobile only — web holds a single
  // cookie-backed session, so there is no second account to add.
  final addingAccount = !kIsWeb && Routes.isAddAccount(routerState.uri);

  // Step ①. Desktop/mobile with no server chosen yet has nowhere to send a
  // request, so nothing else can be attempted first. Web is exempt: it is
  // served by its instance and its base URL is intentionally empty.
  if (getIt<ServerEndpoint>().needsServerChoice) {
    return loc == Routes.connect ? null : Routes.connect;
  }
  // Conversely, once a server IS configured the connect screen is only
  // reachable deliberately (via "change server"), never as a landing page for
  // an authenticated user.
  // Step ① of an add-account run is the exception: reaching the server picker
  // while signed in is the entire point there.
  if (loc == Routes.connect && session is SessionAuthenticated) {
    if (!addingAccount) return Routes.projects;
  }

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
    // Step ② of the same run.
    if (addingAccount) return null;
    final from = routerState.uri.queryParameters['from'];
    if (from != null && from.isNotEmpty) return Uri.decodeComponent(from);
    return Routes.projects;
  }
  // Authed users on /auth/mfa shouldn't stay there.
  if (isAuthed && loc == Routes.mfaVerify) return Routes.projects;
  return null;
}
