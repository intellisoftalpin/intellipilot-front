import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intellipilot/app/branding/brand_logo.dart';
import 'package:intellipilot/app/branding/branding_cubit.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/router/app_router.dart';
import 'package:intellipilot/app/router/short_links.dart';
import 'package:intellipilot/app/session/session_bloc.dart';
import 'package:intellipilot/app/theme/app_theme.dart';
import 'package:intellipilot/core/network/sse/project_events_service.dart';
import 'package:intellipilot/core/storage/hive_boxes.dart';
import 'package:intellipilot/core/ui/breakpoints.dart';
import 'package:intellipilot/core/widgets/user_avatar.dart';
import 'package:intellipilot/features/accounts/domain/account_switcher.dart';
import 'package:intellipilot/features/accounts/presentation/account_switcher_menu.dart';
import 'package:intellipilot/features/backlog/presentation/global_issue_create.dart';
import 'package:intellipilot/features/board/presentation/boards_nav_refresh.dart';
import 'package:intellipilot/features/board/presentation/widgets/board_settings_dialog.dart';
import 'package:intellipilot/features/catalog/data/dtos/catalog_dtos.dart';
import 'package:intellipilot/features/catalog/domain/catalog_repository.dart';
import 'package:intellipilot/features/docs/data/dtos/doc_dtos.dart';
import 'package:intellipilot/features/docs/domain/docs_repository.dart';
import 'package:intellipilot/features/meetings/domain/project_access_cache.dart';
import 'package:intellipilot/features/palette/presentation/cmd_k_dialog.dart';
import 'package:intellipilot/features/profile/data/dtos/profile_dtos.dart';
import 'package:intellipilot/features/profile/domain/profile_repository.dart';
import 'package:intellipilot/features/projects/data/dtos/project_dtos.dart';
import 'package:intellipilot/features/projects/domain/permission.dart';
import 'package:intellipilot/features/projects/domain/projects_repository.dart';
import 'package:intellipilot/features/projects/presentation/cubits/project_counts_cubit.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// App-wide chrome wrapping the routed page. Adds:
/// - A thin top brand strip with logo, a global "+ Create" issue button (any
///   project the caller can create in, the current one preselected; also on
///   the `c` shortcut), a search trigger that opens the Cmd-K palette, and an
///   avatar with sign-out.
/// - A left navigation rail on **project-scoped** routes (medium / expanded
///   breakpoints only — compact stays single-column).
/// - Hides itself entirely on auth routes (login, register, password reset,
///   MFA verify, passkey sign-in, accept invitation) so the auth UX stays
///   uncluttered.
///
/// Pages keep their own [Scaffold] + [AppBar] for page-specific concerns
/// (page title, contextual actions) — the shell's bar is global.
class MainShell extends StatelessWidget {
  const MainShell({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // SessionBloc is a process-wide singleton — drive the shell off the bloc
    // instance directly rather than the widget tree. ShellRoute's inner
    // Navigator creates a subtree where provider inheritance behaves
    // differently from direct routes, so passing the instance side-steps the
    // scoping issue cleanly.
    //
    // We must *subscribe* (BlocBuilder), not just snapshot the current state:
    // on a hard page load of an authenticated deep link, the session is still
    // SessionUnknown while the startup cookie-refresh runs. A snapshot would
    // build chrome-less and never recover (nothing re-triggers a build until
    // the next navigation). Subscribing rebuilds the shell when the session
    // settles to SessionAuthenticated.
    return BlocBuilder<SessionBloc, SessionState>(
      bloc: getIt<SessionBloc>(),
      builder: (context, session) {
        // Under a [ShellRoute] so [GoRouterState.of] is available and rebuilds
        // on every navigation.
        final route = GoRouterState.of(context).uri.toString();
        // Remember where each account was, so switching back returns here.
        // This builder already runs on every navigation, which makes it the
        // cheapest correct hook; the switcher de-duplicates repeats.
        if (!kIsWeb && session is SessionAuthenticated) {
          unawaited(getIt<AccountSwitcher>().rememberRoute(route));
        }
        final hide = _shouldHide(session, route);
        if (hide) return child;

        final scope = _projectScopeOf(route);
        final showRail =
            scope != null && Breakpoints.of(context).isAtLeastMedium;

        if (scope == null) {
          return Scaffold(appBar: const _TopBar(), body: child);
        }

        // The URL carries the project's *prefix* (`/projects/ps/issues`), not
        // its id — [ShortLinkGate] rewrites every project URL to that short
        // form. Everything below that talks to the API is addressed by id, so
        // resolve once here and hand both down: the ref builds links, the id
        // makes requests.
        return _ProjectScope(
          projectRef: scope,
          builder: (context, projectId) {
            // Project-scoped layout: full-height rail on the left (toggle
            // pinned at the top), and the top bar shows the current project's
            // icon + name first — matching Jira's project sidebar.
            if (showRail) {
              return Scaffold(
                body: Row(
                  children: [
                    // Keyed by project so switching projects starts a fresh
                    // count fetch and SSE subscription rather than showing the
                    // previous project's badges. Keyed by the *id* too, so the
                    // cubit is rebuilt (and finally fetches) once the ref
                    // resolves.
                    BlocProvider<ProjectCountsCubit>(
                      key: ValueKey('$scope/$projectId'),
                      create: (_) => ProjectCountsCubit(
                        repo: getIt<ProjectsRepository>(),
                        projectId: projectId,
                        events: getIt<ProjectEventsService>(),
                      ),
                      child: _ProjectRail(
                        projectRef: scope,
                        projectId: projectId,
                        currentRoute: route,
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: Column(
                        children: [
                          _TopBar(
                            activeProjectRef: scope,
                            showBrandMark: false,
                          ),
                          Expanded(child: child),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }

            // Project routes on a phone-width window: single column with the
            // brand mark on the top bar, no rail — the rail's entries move
            // into a drawer behind a menu button.
            return Scaffold(
              appBar: _TopBar(activeProjectRef: scope, showProjectMenu: true),
              drawer: _ProjectDrawer(
                projectRef: scope,
                projectId: projectId,
                currentRoute: route,
              ),
              body: child,
            );
          },
        );
      },
    );
  }

  bool _shouldHide(SessionState session, String location) {
    if (session is! SessionAuthenticated && session is! SessionRefreshing) {
      return true;
    }
    if (location.startsWith(Routes.login) ||
        location.startsWith(Routes.register) ||
        location.startsWith(Routes.forgotPassword) ||
        location.startsWith(Routes.resetPassword) ||
        location.startsWith(Routes.mfaVerify) ||
        location.startsWith(Routes.passkeySignIn) ||
        location.startsWith('/i/')) {
      return true;
    }
    return false;
  }

  /// Extract the project ref from `/projects/:ref/...` paths. Returns null
  /// for non-project routes (the projects list, account pages, etc.).
  ///
  /// The segment is whatever the URL holds: the project's issue prefix in the
  /// canonical short form, or a UUID on a legacy deep link. It names the
  /// project for link building; [_ProjectScope] turns it into the id that
  /// the API needs.
  String? _projectScopeOf(String location) {
    final uri = Uri.tryParse(location);
    if (uri == null) return null;
    final segments = uri.pathSegments;
    if (segments.length < 2) return null;
    if (segments[0] != 'projects') return null;
    return segments[1];
  }
}

/// Turns the URL's project ref into the project id the API is addressed by,
/// and rebuilds when it lands.
///
/// The shell lives outside the routes, so unlike a page (which gets its id
/// from [ShortLinkGate]) it only ever sees the raw segment. Passing that
/// segment on as an id is silent breakage: the counts endpoint and the event
/// feed 404, and the search endpoint rejects the request outright.
///
/// [builder] is called with null for the frames before the answer arrives —
/// callers skip their API work then rather than ask with a ref.
class _ProjectScope extends StatefulWidget {
  const _ProjectScope({required this.projectRef, required this.builder});

  final String projectRef;
  final Widget Function(BuildContext context, String? projectId) builder;

  @override
  State<_ProjectScope> createState() => _ProjectScopeState();
}

class _ProjectScopeState extends State<_ProjectScope> {
  String? _projectId;

  /// Guards against a slow answer for a project the user has already left.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _adopt();
  }

  @override
  void didUpdateWidget(covariant _ProjectScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.projectRef != widget.projectRef) _adopt();
  }

  /// Take the cached answer synchronously when there is one — a UUID ref, or
  /// a prefix seen earlier this session — so switching between projects
  /// doesn't blank the badges for a frame. Otherwise resolve.
  void _adopt() {
    final generation = ++_generation;
    if (!getIt.isRegistered<ShortLinkResolver>()) {
      _projectId = looksLikeUuid(widget.projectRef) ? widget.projectRef : null;
      return;
    }
    final resolver = getIt<ShortLinkResolver>();
    _projectId = resolver.cachedProjectId(widget.projectRef);
    if (_projectId != null) return;
    unawaited(_resolve(resolver, widget.projectRef, generation));
  }

  Future<void> _resolve(
    ShortLinkResolver resolver,
    String ref,
    int generation,
  ) async {
    final id = await resolver.projectId(ref);
    if (!mounted || generation != _generation || id == null) return;
    setState(() => _projectId = id);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _projectId);
}

class _TopBar extends StatelessWidget implements PreferredSizeWidget {
  const _TopBar({
    this.activeProjectRef,
    this.showBrandMark = true,
    this.showProjectMenu = false,
  });

  /// The URL's project segment (prefix or UUID), or null outside a project.
  /// Search and Create resolve it to an id themselves.
  final String? activeProjectRef;

  /// Leading button opening the project drawer — for project routes on a
  /// phone-width window, which have no rail.
  final bool showProjectMenu;

  /// On non-project routes the brand mark renders at the start of the
  /// bar. On project-scoped routes (where the rail already owns the
  /// project identity) the brand is hidden so the top bar only carries
  /// global actions (nav, search, create, avatar).
  final bool showBrandMark;

  @override
  Size get preferredSize => const Size.fromHeight(52);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      shape: Border(
        bottom: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: SizedBox(
        height: 52,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final t = AppLocalizations.of(context);
            final layout = _TopBarLayout.forWidth(constraints.maxWidth);
            return Row(
              children: [
                SizedBox(width: showProjectMenu ? 4 : 12),
                if (showProjectMenu)
                  IconButton(
                    onPressed: () => Scaffold.of(context).openDrawer(),
                    icon: const Icon(Icons.menu),
                    tooltip: t.railOpenProjectMenu,
                  ),
                if (showBrandMark)
                  _BrandMark(
                    compact: !layout.brandName,
                    onTap: () => context.go(Routes.home),
                  ),
                // Takes all the free space, so it doubles as the spacer that
                // pushes the actions to the right. The links scroll rather
                // than overflow if a long translation still doesn't fit.
                Expanded(
                  child: layout.navLinks
                      ? Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                if (showBrandMark) const SizedBox(width: 16),
                                _NavLink(
                                  label: t.navDashboard,
                                  onTap: () => context.go(Routes.home),
                                ),
                                const SizedBox(width: 4),
                                _NavLink(
                                  label: t.topNavProjects,
                                  onTap: () => context.go(Routes.projects),
                                ),
                                const SizedBox(width: 4),
                                _NavLink(
                                  label: t.ttNavTimesheet,
                                  onTap: () => context.go(Routes.timesheet),
                                ),
                                const SizedBox(width: 4),
                                _NavLink(
                                  label: t.topNavSettings,
                                  onTap: () => context.go(Routes.settings),
                                ),
                              ],
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                const SizedBox(width: 8),
                _SearchButton(
                  compact: !layout.searchChip,
                  activeProjectRef: activeProjectRef,
                ),
                const SizedBox(width: 8),
                _CreateButton(
                  compact: !layout.createLabel,
                  activeProjectRef: activeProjectRef,
                ),
                const SizedBox(width: 8),
                // Account switching is a main-screen affordance, not a menu
                // entry: with two instances open you need to see which one you
                // are on. Renders nothing on web or with a single account, and
                // fits inside the bar's fixed 52px.
                AccountSwitcherMenu(compact: !layout.searchChip),
                const SizedBox(width: 4),
                const _AvatarMenu(),
                const SizedBox(width: 12),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Which top-bar pieces get their full form at a given bar width.
///
/// Pieces collapse in order of how much they cost and how reachable they are
/// elsewhere: the nav links first (all four are also in the avatar menu),
/// then the search chip shrinks to an icon (Cmd-K still works), and last the
/// brand name and the Create label. The thresholds leave headroom for the
/// longest shipped translations; the nav links additionally scroll inside
/// their slot, so no width can make the bar overflow.
class _TopBarLayout {
  const _TopBarLayout({
    required this.navLinks,
    required this.searchChip,
    required this.brandName,
    required this.createLabel,
  });

  factory _TopBarLayout.forWidth(double width) => _TopBarLayout(
    navLinks: width >= 1100,
    searchChip: width >= 960,
    brandName: width >= 640,
    createLabel: width >= 640,
  );

  final bool navLinks;
  final bool searchChip;
  final bool brandName;
  final bool createLabel;
}

/// Top-bar "+ Create": a new issue in any project the caller can create in,
/// the current one preselected. Same flow as the `c` shortcut.
class _CreateButton extends StatelessWidget {
  const _CreateButton({this.activeProjectRef, this.compact = false});
  final String? activeProjectRef;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    void open() => unawaited(
      openGlobalIssueCreate(context, activeProjectRef: activeProjectRef),
    );
    if (compact) {
      return IconButton.filled(
        key: const ValueKey('top-create'),
        onPressed: open,
        icon: const Icon(Icons.add),
        tooltip: t.topCreateTooltip,
      );
    }
    return Tooltip(
      message: t.topCreateTooltip,
      child: FilledButton.icon(
        key: const ValueKey('top-create'),
        onPressed: open,
        icon: const Icon(Icons.add, size: 18),
        label: Text(t.topCreateAction),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.onTap, this.compact = false});
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            const BrandLogo(size: 24),
            if (!compact) ...[
              const SizedBox(width: 8),
              BlocBuilder<BrandingCubit, Branding>(
                bloc: getIt<BrandingCubit>(),
                builder: (context, branding) => Text(
                  branding.appName ?? 'IntelliPilot',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NavLink extends StatelessWidget {
  const _NavLink({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        foregroundColor: Theme.of(context).colorScheme.onSurface,
      ),
      child: Text(label),
    );
  }
}

class _SearchButton extends StatelessWidget {
  const _SearchButton({this.activeProjectRef, this.compact = false});
  final String? activeProjectRef;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (compact) {
      return IconButton(
        onPressed: () =>
            openCmdKDialog(context, activeProjectRef: activeProjectRef),
        icon: const Icon(Icons.search),
        tooltip: AppLocalizations.of(context).topNavSearchPlaceholder,
      );
    }
    return InkWell(
      onTap: () => openCmdKDialog(context, activeProjectRef: activeProjectRef),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              AppLocalizations.of(context).topNavSearchPlaceholder,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '⌘K',
                style: AppTheme.mono(
                  context,
                  size: 11,
                ).copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AvatarMenu extends StatefulWidget {
  const _AvatarMenu();

  @override
  State<_AvatarMenu> createState() => _AvatarMenuState();
}

class _AvatarMenuState extends State<_AvatarMenu> {
  UserProfile? _me;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final res = await getIt<ProfileRepository>().getProfile();
      if (mounted) setState(() => _me = res.valueOrNull);
    } on Object {
      // Top bar falls back to the generic icon.
    }
  }

  /// Log the active account out; land on whichever account remains, or the
  /// login screen when none do.
  Future<void> _signOutAndSwitch(BuildContext context) async {
    final router = GoRouter.of(context);
    final next = await getIt<AccountSwitcher>().logoutActive();
    if (next == null) {
      getIt<SessionBloc>().add(const SessionLogoutRequested());
      return;
    }
    final restored = await getIt<AccountSwitcher>().restoredRouteFor(next);
    router.go(restored ?? Routes.projects);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = AppLocalizations.of(context);
    return MenuAnchor(
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.person_outline),
          onPressed: () => context.go(Routes.profile),
          child: Text(t.topMenuProfile),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.security_outlined),
          onPressed: () => context.go(Routes.security),
          child: Text(t.topMenuSecurity),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.settings_outlined),
          onPressed: () => context.go(Routes.settings),
          child: Text(t.topMenuSettings),
        ),
        // Platform admin — only shown to superadmins (user management now also
        // hosts invite-by-email, so there's no separate invitations entry).
        if (_me?.isSuperadmin ?? false) ...[
          const Divider(height: 1),
          MenuItemButton(
            leadingIcon: const Icon(Icons.admin_panel_settings_outlined),
            onPressed: () => context.go(Routes.adminUsers),
            child: Text(t.adminNavUsers),
          ),
          MenuItemButton(
            leadingIcon: const Icon(Icons.tune),
            onPressed: () => context.go(Routes.adminSettings),
            child: Text(t.adminNavSettings),
          ),
          MenuItemButton(
            leadingIcon: const Icon(Icons.key_outlined),
            onPressed: () => context.go(Routes.adminAppTokens),
            child: Text(t.adminNavAppTokens),
          ),
        ],
        const Divider(height: 1),
        // "Add another account" lives here, not only in the switcher: the
        // switcher appears once there are two accounts, so with one signed in
        // this is the only route to a second.
        if (!kIsWeb)
          MenuItemButton(
            leadingIcon: const Icon(Icons.person_add_alt),
            onPressed: () => context.go(Routes.addAccount()),
            child: Text(t.accountsAddAnother),
          ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.logout),
          onPressed: () {
            if (kIsWeb) {
              getIt<SessionBloc>().add(const SessionLogoutRequested());
              return;
            }
            // Signing out of one account activates the next signed-in one
            // rather than dumping the user on a login screen they don't need.
            unawaited(_signOutAndSwitch(context));
          },
          child: Text(t.topMenuSignOut),
        ),
      ],
      builder: (context, controller, _) => IconButton(
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        icon: _me != null
            ? UserAvatar(user: _me!.toRef(), size: 28, enableHover: false)
            : CircleAvatar(
                radius: 14,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Icon(
                  Icons.person,
                  size: 16,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
      ),
    );
  }
}

/// Project navigation rail. The expanded/collapsed state is initialised
/// from the viewport (wide → expanded, narrow → collapsed) and can then
/// be flipped by the user via the toggle button in the rail's `leading`
/// slot — the preference is persisted in the UI Hive box keyed by
/// `project_rail.expanded` so the layout sticks across reloads.
class _ProjectRail extends StatefulWidget {
  const _ProjectRail({
    required this.projectRef,
    required this.projectId,
    required this.currentRoute,
  });

  /// The URL's project segment — what links are built from.
  final String projectRef;

  /// The resolved project id, or null until it resolves — what the API is
  /// asked with.
  final String? projectId;
  final String currentRoute;

  @override
  State<_ProjectRail> createState() => _ProjectRailState();
}

class _ProjectRailState extends State<_ProjectRail> {
  static const _prefsKey = 'project_rail.expanded';

  /// `null` while we await the saved preference; falls back to the
  /// viewport default on the first build.
  bool? _userExpanded;

  late final KeyValueStorage _storage = getIt<KeyValueStorage>(
    instanceName: HiveBoxes.ui,
  );

  @override
  void initState() {
    super.initState();
    _userExpanded = _storage.get<bool>(_prefsKey);
  }

  Future<void> _toggle() async {
    final next = !_currentExpanded;
    setState(() => _userExpanded = next);
    await _storage.set<bool>(_prefsKey, next);
  }

  bool get _currentExpanded =>
      _userExpanded ?? Breakpoints.of(context).isExpanded;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final expanded = _currentExpanded;
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surface,
      child: SizedBox(
        width: expanded ? 240 : 64,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header lives in its own Material with the SAME bottom
            // border shape + 52px SizedBox the top bar uses. That's
            // the only way to guarantee both horizontal dividers land
            // on exactly the same pixel row — Material.shape draws the
            // border on the box's inner edge, which a separate
            // `Divider` widget can't replicate without 1-pixel drift.
            Material(
              color: theme.colorScheme.surface,
              shape: Border(
                bottom: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
              child: SizedBox(
                height: 52,
                child: _RailHeader(
                  expanded: expanded,
                  projectRef: widget.projectRef,
                  collapseTooltip: t.railCollapse,
                  expandTooltip: t.railExpand,
                  onToggle: _toggle,
                ),
              ),
            ),
            // The rows scroll; the header does not.
            Expanded(
              child: _ProjectNavList(
                projectRef: widget.projectRef,
                projectId: widget.projectId,
                currentRoute: widget.currentRoute,
                expanded: expanded,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One entry of the project navigation: a flat [_RailItem] row, or one of the
/// expandable sections that load their own children.
sealed class _NavEntry {
  const _NavEntry();
}

/// The Boards section — the project's boards plus "New board".
class _BoardsEntry extends _NavEntry {
  const _BoardsEntry();
}

/// The Wiki section — the internal wiki plus external documentation sources.
class _WikiEntry extends _NavEntry {
  const _WikiEntry();
}

/// The project's navigation, in display order.
///
/// The single definition shared by the rail and the narrow-screen drawer: a new
/// project section is added here and nowhere else.
List<_NavEntry> _projectNavEntries(
  AppLocalizations t,
  String projectId,
  ProjectCounts? counts, {
  bool showMeetings = false,
}) => [
  _RailItem(
    icon: Icons.dashboard_outlined,
    label: t.railOverview,
    path: Routes.projectDetailFor(projectId),
  ),
  _RailItem(
    icon: Icons.assignment_ind_outlined,
    label: t.railMyIssues,
    path: Routes.projectMyIssuesFor(projectId),
    count: counts?.myIssues,
  ),
  const _BoardsEntry(),
  _RailItem(
    icon: Icons.bug_report_outlined,
    label: t.railIssues,
    path: Routes.projectIssuesFor(projectId),
    count: counts?.issues,
  ),
  _RailItem(
    icon: Icons.bookmarks_outlined,
    label: t.railEpics,
    path: Routes.projectEpicsFor(projectId),
    count: counts?.epics,
  ),
  _RailItem(
    icon: Icons.flag_outlined,
    label: t.railMilestones,
    path: Routes.projectMilestonesFor(projectId),
    count: counts?.milestones,
  ),
  // Only for roles with `meeting.view` — stakeholders don't get it.
  if (showMeetings)
    _RailItem(
      icon: Icons.groups_outlined,
      label: t.railMeetings,
      path: Routes.projectMeetingsFor(projectId),
    ),
  _RailItem(
    icon: Icons.schedule_outlined,
    label: t.ttTimeTracking,
    path: Routes.projectTimeFor(projectId),
  ),
  const _WikiEntry(),
  _RailItem(
    icon: Icons.settings_outlined,
    label: t.railSettings,
    path: Routes.projectSettingsFor(projectId),
  ),
];

/// The scrolling list of project navigation rows, rendered by both the rail
/// and the drawer. Needs a [ProjectCountsCubit] above it for the badges.
///
/// Every row is a fixed 48px and the Boards and Wiki sections expand to list
/// however many boards and doc sources a project has, so the total routinely
/// exceeds a short window. The list therefore scrolls, and shows its scrollbar
/// whenever it overflows — without one nothing hints that more rows sit below.
class _ProjectNavList extends StatefulWidget {
  const _ProjectNavList({
    required this.projectRef,
    required this.projectId,
    required this.currentRoute,
    required this.expanded,
    this.onNavigate,
  });

  /// The URL's project segment — what the rows' links are built from.
  final String projectRef;

  /// The resolved project id, or null until it resolves — what the
  /// permission lookup behind the Meetings row is asked with.
  final String? projectId;
  final String currentRoute;

  /// Labels shown; `false` is the icon-only collapsed rail.
  final bool expanded;

  /// Replaces plain `context.go` for the flat rows — the drawer uses it to
  /// close itself on the way.
  final ValueChanged<String>? onNavigate;

  @override
  State<_ProjectNavList> createState() => _ProjectNavListState();
}

class _ProjectNavListState extends State<_ProjectNavList> {
  final _scroll = ScrollController();

  /// Whether the Meetings row shows; resolved per project, off until known.
  bool _showMeetings = false;

  @override
  void initState() {
    super.initState();
    unawaited(_resolveAccess());
  }

  @override
  void didUpdateWidget(covariant _ProjectNavList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.projectId != widget.projectId) {
      _showMeetings = false;
      unawaited(_resolveAccess());
    }
  }

  Future<void> _resolveAccess() async {
    final projectId = widget.projectId;
    // Nothing to ask with until the shell has resolved the ref; a rebuild
    // with the id arrives and brings us back here.
    if (projectId == null) return;
    if (!getIt.isRegistered<ProjectAccessCache>()) return;
    final access = await getIt<ProjectAccessCache>().access(projectId);
    if (!mounted || widget.projectId != projectId) return;
    final show = access.has(Permission.meetingView);
    if (show != _showMeetings) setState(() => _showMeetings = show);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _go(String path) {
    final navigate = widget.onNavigate;
    if (navigate != null) {
      navigate(path);
    } else {
      context.go(path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final counts = context.watch<ProjectCountsCubit>().state.counts;
    final entries = _projectNavEntries(
      t,
      widget.projectRef,
      counts,
      showMeetings: _showMeetings,
    );
    final route = widget.currentRoute;

    // The Boards section owns its own selection; when the user is on any board
    // route we suppress generic-row highlighting so Overview (a prefix of every
    // project path) doesn't also light up.
    final onBoard = route.startsWith(Routes.projectBoardFor(widget.projectRef));
    // The Wiki section owns its own selection too, for the same reason.
    final onWiki =
        route.startsWith(Routes.projectWikiFor(widget.projectRef)) ||
        route.startsWith('/projects/${widget.projectRef}/docs/');
    final selected = onBoard || onWiki
        ? null
        : _selectedItemFor(route, entries.whereType<_RailItem>().toList());
    final expanded = widget.expanded;

    return ScrollConfiguration(
      // The platform's automatic scrollbar would double up with ours.
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: Scrollbar(
        controller: _scroll,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _scroll,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              for (final entry in entries)
                switch (entry) {
                  _RailItem() => _RailRow(
                    icon: entry.icon,
                    label: expanded ? Text(entry.label) : null,
                    tooltip: entry.label,
                    selected: identical(entry, selected),
                    count: entry.count,
                    onTap: () => _go(entry.path),
                  ),
                  _BoardsEntry() => _BoardsRailSection(
                    projectId: widget.projectRef,
                    currentRoute: route,
                    railExpanded: expanded,
                    active: onBoard,
                  ),
                  _WikiEntry() => _WikiRailSection(
                    projectId: widget.projectRef,
                    currentRoute: route,
                    railExpanded: expanded,
                  ),
                },
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  _RailItem _selectedItemFor(String route, List<_RailItem> items) {
    // Walk longest path first so /projects/:id/settings doesn't match /:id.
    final sorted = [...items]
      ..sort((a, b) => b.path.length.compareTo(a.path.length));
    for (final item in sorted) {
      if (route == item.path || route.startsWith('${item.path}/')) {
        return item;
      }
    }
    return items.first;
  }
}

/// Project navigation for phone-width windows, where there is no room for the
/// rail: the same entries in a drawer opened from the top bar.
///
/// It closes whenever the route changes, which covers the flat rows and the
/// Boards/Wiki children alike — those navigate on their own.
class _ProjectDrawer extends StatefulWidget {
  const _ProjectDrawer({
    required this.projectRef,
    required this.projectId,
    required this.currentRoute,
  });

  /// The URL's project segment — what links are built from.
  final String projectRef;

  /// The resolved project id, or null until it resolves — what the API is
  /// asked with.
  final String? projectId;
  final String currentRoute;

  @override
  State<_ProjectDrawer> createState() => _ProjectDrawerState();
}

class _ProjectDrawerState extends State<_ProjectDrawer> {
  @override
  void didUpdateWidget(covariant _ProjectDrawer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentRoute != widget.currentRoute) {
      // Not during build: closing starts the drawer's animation.
      WidgetsBinding.instance.addPostFrameCallback((_) => _close());
    }
  }

  void _close() {
    if (mounted) Scaffold.maybeOf(context)?.closeDrawer();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Built only while the drawer is open, so the counts are fetched on
    // opening rather than kept live in the background.
    return BlocProvider<ProjectCountsCubit>(
      key: ValueKey(widget.projectId),
      create: (_) => ProjectCountsCubit(
        repo: getIt<ProjectsRepository>(),
        projectId: widget.projectId,
        events: getIt<ProjectEventsService>(),
      ),
      child: Drawer(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Material(
                color: theme.colorScheme.surface,
                shape: Border(
                  bottom: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
                child: SizedBox(
                  height: 52,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: DefaultTextStyle.merge(
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        child: _ProjectName(projectRef: widget.projectRef),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: _ProjectNavList(
                  projectRef: widget.projectRef,
                  projectId: widget.projectId,
                  currentRoute: widget.currentRoute,
                  expanded: true,
                  onNavigate: (path) {
                    _close();
                    context.go(path);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RailItem extends _NavEntry {
  const _RailItem({
    required this.icon,
    required this.label,
    required this.path,
    this.count,
  });
  final IconData icon;
  final String label;
  final String path;

  /// Active-object count for the badge, or null for no badge.
  final int? count;
}

/// Rail header tap target — a single tile that toggles the rail and,
/// when expanded, displays the current project name as its label.
/// Lives inside a 52px Material shared shape with the top bar so the
/// two bottom borders land on the same pixel row.
class _RailHeader extends StatelessWidget {
  const _RailHeader({
    required this.expanded,
    required this.projectRef,
    required this.collapseTooltip,
    required this.expandTooltip,
    required this.onToggle,
  });

  final bool expanded;

  /// The URL's project segment; [_ProjectName] resolves it either way.
  final String projectRef;
  final String collapseTooltip;
  final String expandTooltip;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = theme.colorScheme.onSurfaceVariant;
    // Match the destination row's icon column exactly: outer
    // Padding(horizontal: 12) + inner padding(horizontal: 8) puts the
    // 20px icon's centre at x=30 — same as the _RailRow rows below.
    final tile = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            Icon(expanded ? Icons.menu_open : Icons.menu, size: 20, color: fg),
            if (expanded) ...[
              const SizedBox(width: 12),
              Expanded(child: _ProjectName(projectRef: projectRef)),
            ],
          ],
        ),
      ),
    );
    return Tooltip(
      message: expanded ? collapseTooltip : expandTooltip,
      child: InkWell(onTap: onToggle, child: tile),
    );
  }
}

/// A single row in the project rail. The icon sits at a fixed left line
/// (column-x = 20 + icon centre) for every row — header included — so
/// the vertical rhythm reads as one consistent column. Selected rows
/// get a pill-shaped primary-container background like Material 3
/// NavigationRail destinations.
class _RailRow extends StatelessWidget {
  const _RailRow({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.selected,
    required this.onTap,
    this.count,
  });

  final IconData icon;

  /// Optional trailing label widget. `null` collapses the row to icon-only.
  final Widget? label;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;

  /// Active-object count for this section. `null` renders no badge — which is
  /// also what a caller without the section's view permission gets, so a
  /// hidden count never masquerades as an empty one.
  final int? count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = selected
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurfaceVariant;
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? theme.colorScheme.primaryContainer : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            // Collapsed rail: the count rides the icon as a compact badge,
            // since there is no room for a pill.
            if (label == null && count != null)
              Badge.count(
                count: count!,
                backgroundColor: theme.colorScheme.secondaryContainer,
                textColor: theme.colorScheme.onSecondaryContainer,
                child: Icon(icon, size: 20, color: fg),
              )
            else
              Icon(icon, size: 20, color: fg),
            if (label != null) ...[
              const SizedBox(width: 12),
              Expanded(
                child: DefaultTextStyle.merge(
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: fg,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                  child: label!,
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 6),
                _RailBadge(count: count!, selected: selected),
              ],
            ],
          ],
        ),
      ),
    );
    final tappable = InkWell(onTap: onTap, child: row);
    return label == null
        ? Tooltip(message: tooltip, child: tappable)
        : tappable;
  }
}

/// The count badge on a project rail row: a tonal stadium pill.
///
/// Digits use tabular figures so the pill doesn't twitch as counts change, and
/// the number cross-fades rather than snapping. On the selected row it borrows
/// the highlight's own container colour so it reads as part of it.
class _RailBadge extends StatelessWidget {
  const _RailBadge({required this.count, required this.selected});

  final int count;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bg = selected
        ? scheme.secondaryContainer
        : scheme.surfaceContainerHighest;
    final fg = selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant;
    final label = count > 999 ? '999+' : '$count';
    return Tooltip(
      message: AppLocalizations.of(context).railCountTooltip(count),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        constraints: const BoxConstraints(minWidth: 24),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.85, end: 1).animate(animation),
              child: child,
            ),
          ),
          child: Text(
            label,
            key: ValueKey(label),
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
  }
}

/// Expandable "Boards" rail entry. Lists the project's boards as children
/// (each linking to its board route) plus a "New board" action. The
/// expanded/collapsed state is persisted in the UI Hive box. When the rail
/// itself is collapsed (icon-only) this renders as a single icon row that
/// navigates to the board resolver.
class _BoardsRailSection extends StatefulWidget {
  const _BoardsRailSection({
    required this.projectId,
    required this.currentRoute,
    required this.railExpanded,
    required this.active,
  });

  final String projectId;
  final String currentRoute;
  final bool railExpanded;
  final bool active;

  @override
  State<_BoardsRailSection> createState() => _BoardsRailSectionState();
}

class _BoardsRailSectionState extends State<_BoardsRailSection> {
  static const _prefsKey = 'project_rail.boards_expanded';

  late final KeyValueStorage _storage = getIt<KeyValueStorage>(
    instanceName: HiveBoxes.ui,
  );

  List<Board> _boards = const [];
  late bool _expanded = _storage.get<bool>(_prefsKey) ?? true;
  String? _resolvedProjectId;

  @override
  void initState() {
    super.initState();
    boardsNavRevision.addListener(_fetch);
    unawaited(_fetch());
  }

  @override
  void didUpdateWidget(covariant _BoardsRailSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.projectId != widget.projectId) {
      // Genuine project switch: the old list no longer applies.
      _resolvedProjectId = null;
      setState(() => _boards = const []);
      unawaited(_fetch());
    }
  }

  @override
  void dispose() {
    boardsNavRevision.removeListener(_fetch);
    super.dispose();
  }

  /// The rail sits outside the routes, so unlike pages (which go through
  /// [ShortLinkGate]) its [widget.projectId] is the raw URL segment — since
  /// short links that may be the project *prefix*, which the API rejects.
  /// Resolve it to the UUID once (session-cached in [ShortLinkResolver]).
  Future<String?> _projectUuid() async {
    if (looksLikeUuid(widget.projectId)) return widget.projectId;
    final cached = _resolvedProjectId;
    if (cached != null) return cached;
    final resolved = await getIt<ShortLinkResolver>().project(widget.projectId);
    return _resolvedProjectId = resolved?.$1;
  }

  Future<void> _fetch() async {
    final pid = await _projectUuid();
    if (pid == null) return;
    final res = await getIt<CatalogRepository>().listBoards(pid);
    if (!mounted) return;
    final boards = res.valueOrNull;
    // Keep the last known list on transient failures (e.g. a 401 during
    // token refresh) — blanking it made the menu flicker in and out.
    if (boards != null) setState(() => _boards = boards);
  }

  Future<void> _toggle() async {
    setState(() => _expanded = !_expanded);
    await _storage.set<bool>(_prefsKey, _expanded);
  }

  Future<void> _createBoard() async {
    final pid = await _projectUuid();
    if (pid == null || !mounted) return;
    final created = await showBoardSettingsDialog(context, projectId: pid);
    if (created == null || !mounted) return;
    bumpBoardsNav();
    if (mounted) {
      context.go(Routes.projectBoardFor(widget.projectId, created.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);

    // Collapsed rail: a single icon row leading to the board resolver.
    if (!widget.railExpanded) {
      return _RailRow(
        icon: Icons.view_kanban_outlined,
        label: null,
        tooltip: t.railBoards,
        selected: widget.active,
        onTap: () => context.go(Routes.projectBoardsFor(widget.projectId)),
      );
    }

    final theme = Theme.of(context);
    final activeBoardId = _activeBoardId();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionParentRow(
          icon: Icons.view_kanban_outlined,
          label: t.railBoards,
          expanded: _expanded,
          // Highlight the parent only when on the gallery/resolver (no board).
          selected: widget.active && activeBoardId == null,
          onTap: () => context.go(Routes.projectBoardsFor(widget.projectId)),
          onToggle: _toggle,
        ),
        if (_expanded) ...[
          for (final b in _boards)
            _BoardChildRow(
              label: b.name,
              color: b.color,
              shared: b.isShared,
              selected: b.id == activeBoardId,
              onTap: () => context.go(
                Routes.projectBoardFor(widget.projectId, b.id),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(left: 36, right: 12, bottom: 4),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: _createBoard,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.add,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      t.boardNewAction,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// The board id in the current route, or null on the resolver route.
  String? _activeBoardId() {
    if (!widget.active) return null;
    final segs = Uri.tryParse(widget.currentRoute)?.pathSegments ?? const [];
    final i = segs.indexOf('boards');
    if (i >= 0 && i + 1 < segs.length) return segs[i + 1];
    return null;
  }
}

/// Parent row of an expandable rail section (Boards, Wiki). Carries the
/// section's own icon and label so one row widget serves every section.
class _SectionParentRow extends StatelessWidget {
  const _SectionParentRow({
    required this.icon,
    required this.label,
    required this.expanded,
    required this.selected,
    required this.onTap,
    required this.onToggle,
  });

  final IconData icon;
  final String label;
  final bool expanded;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = selected
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? theme.colorScheme.primaryContainer : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: onTap,
                child: Row(
                  children: [
                    Icon(icon, size: 20, color: fg),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        label,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: fg,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            InkWell(
              onTap: onToggle,
              borderRadius: BorderRadius.circular(4),
              child: Icon(
                expanded ? Icons.expand_less : Icons.expand_more,
                size: 18,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BoardChildRow extends StatelessWidget {
  const _BoardChildRow({
    required this.label,
    required this.color,
    required this.shared,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String color;
  final bool shared;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = selected
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(left: 24, right: 12, top: 2, bottom: 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: selected ? theme.colorScheme.primaryContainer : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              _BoardDot(color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: fg,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ),
              if (shared) Icon(Icons.group_outlined, size: 14, color: fg),
            ],
          ),
        ),
      ),
    );
  }
}

class _BoardDot extends StatelessWidget {
  const _BoardDot({required this.color});
  final String color;

  @override
  Widget build(BuildContext context) {
    final parsed = _hex(color);
    final theme = Theme.of(context);
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: parsed ?? theme.colorScheme.outlineVariant,
        shape: BoxShape.circle,
      ),
    );
  }

  Color? _hex(String hex) {
    var s = hex.trim();
    if (s.isEmpty) return null;
    if (s.startsWith('#')) s = s.substring(1);
    if (s.length == 6) s = 'ff$s';
    if (s.length != 8) return null;
    final v = int.tryParse(s, radix: 16);
    return v == null ? null : Color(v);
  }
}

/// Lightweight project-name resolver that drives the rail header label.
/// Reuses the same process-wide cache as the previous _ProjectHeader so
/// navigating across the same project's sub-pages doesn't refetch.
class _ProjectName extends StatefulWidget {
  const _ProjectName({required this.projectRef});

  /// A UUID or a project prefix — whichever the URL carried.
  final String projectRef;

  @override
  State<_ProjectName> createState() => _ProjectNameState();
}

class _ProjectNameState extends State<_ProjectName> {
  static final Map<String, Future<Project?>> _cache = {};

  late Future<Project?> _future;

  @override
  void initState() {
    super.initState();
    _future = _resolve(widget.projectRef);
  }

  @override
  void didUpdateWidget(covariant _ProjectName oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.projectRef != widget.projectRef) {
      _future = _resolve(widget.projectRef);
    }
  }

  static Future<Project?> _resolve(String ref) {
    return _cache.putIfAbsent(ref, () {
      // The shell receives the raw URL segment — a UUID or, with short
      // links, the project prefix. Pick the matching lookup.
      final repo = getIt<ProjectsRepository>();
      final res = looksLikeUuid(ref)
          ? repo.getProject(ref)
          : repo.getProjectByPrefix(ref);
      return res.then((r) => r.valueOrNull);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Project?>(
      future: _future,
      builder: (context, snap) {
        return Text(
          snap.data?.name ?? '…',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }
}

/// Expandable "Wiki" rail entry.
///
/// Lists the internal wiki (when the project has it enabled) and every
/// external documentation source. The whole section disappears when a project
/// has turned the internal wiki off *and* registered no sources — there is
/// then nothing behind it, and an empty entry is worse than none.
///
/// Like the boards section, the expanded/collapsed state lives in the UI Hive
/// box so it survives navigation.
class _WikiRailSection extends StatefulWidget {
  const _WikiRailSection({
    required this.projectId,
    required this.currentRoute,
    required this.railExpanded,
  });

  final String projectId;
  final String currentRoute;
  final bool railExpanded;

  @override
  State<_WikiRailSection> createState() => _WikiRailSectionState();
}

class _WikiRailSectionState extends State<_WikiRailSection> {
  static const _prefsKey = 'project_rail.wiki_expanded';

  late final KeyValueStorage _storage = getIt<KeyValueStorage>(
    instanceName: HiveBoxes.ui,
  );

  List<DocSource> _sources = const [];
  bool _wikiEnabled = true;
  bool _loaded = false;
  late bool _expanded = _storage.get<bool>(_prefsKey) ?? true;
  String? _resolvedProjectId;

  @override
  void initState() {
    super.initState();
    unawaited(_fetch());
  }

  @override
  void didUpdateWidget(covariant _WikiRailSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.projectId != widget.projectId) {
      _resolvedProjectId = null;
      setState(() {
        _sources = const [];
        _loaded = false;
      });
      unawaited(_fetch());
    }
  }

  /// Same short-link resolution the boards section needs: the rail sits
  /// outside the routes, so its projectId may be a project *prefix* rather
  /// than a UUID.
  Future<String?> _projectUuid() async {
    if (looksLikeUuid(widget.projectId)) return widget.projectId;
    final cached = _resolvedProjectId;
    if (cached != null) return cached;
    final resolved = await getIt<ShortLinkResolver>().project(widget.projectId);
    return _resolvedProjectId = resolved?.$1;
  }

  Future<void> _fetch() async {
    final pid = await _projectUuid();
    if (pid == null) return;
    final sources = await getIt<DocsRepository>().listSources(pid);
    final project = await getIt<ProjectsRepository>().getProject(pid);
    if (!mounted) return;
    setState(() {
      // Keep the last known list on a transient failure, exactly as the
      // boards section does — blanking it makes the menu flicker.
      //
      // Hidden sources are filtered here rather than server-side: a manager
      // still receives them (so settings can list them), but hiding must
      // withdraw a source from navigation for everyone, managers included.
      _sources =
          sources.valueOrNull?.where((s) => !s.hidden).toList() ?? _sources;
      _wikiEnabled = project.valueOrNull?.wikiEnabled ?? _wikiEnabled;
      _loaded = true;
    });
  }

  Future<void> _toggle() async {
    setState(() => _expanded = !_expanded);
    await _storage.set<bool>(_prefsKey, _expanded);
  }

  bool get _onWiki {
    final base = Routes.projectWikiFor(widget.projectId);
    return widget.currentRoute == base ||
        widget.currentRoute.startsWith('$base/') ||
        widget.currentRoute.startsWith('/projects/${widget.projectId}/docs/');
  }

  /// The documentation source in the current route, if any.
  String? _activeSourceId() {
    final segs = Uri.tryParse(widget.currentRoute)?.pathSegments ?? const [];
    final i = segs.indexOf('docs');
    if (i >= 0 && i + 1 < segs.length) return segs[i + 1];
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);

    // Nothing to show: no internal wiki and no sources. Until the first fetch
    // lands we keep the entry visible, so it does not blink on every
    // navigation.
    if (_loaded && !_wikiEnabled && _sources.isEmpty) {
      return const SizedBox.shrink();
    }

    if (!widget.railExpanded) {
      return _RailRow(
        icon: Icons.menu_book_outlined,
        label: null,
        tooltip: t.railWiki,
        selected: _onWiki,
        onTap: () => context.go(Routes.projectWikiFor(widget.projectId)),
      );
    }

    final activeSource = _activeSourceId();
    final onPages =
        widget.currentRoute == Routes.wikiPagesFor(widget.projectId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionParentRow(
          icon: Icons.menu_book_outlined,
          label: t.railWiki,
          expanded: _expanded,
          // The parent is the overview, so highlight it only there.
          selected: _onWiki && activeSource == null && !onPages,
          onTap: () => context.go(Routes.projectWikiFor(widget.projectId)),
          onToggle: _toggle,
        ),
        if (_expanded) ...[
          if (_wikiEnabled)
            _DocChildRow(
              label: t.docsInternalWiki,
              icon: Icons.article_outlined,
              selected: onPages,
              onTap: () => context.go(Routes.wikiPagesFor(widget.projectId)),
            ),
          for (final s in _sources)
            _DocChildRow(
              label: s.name,
              icon: s.kind.isWeb
                  ? Icons.language
                  : Icons.folder_shared_outlined,
              emoji: s.emoji,
              color: s.color,
              selected: s.id == activeSource,
              onTap: () => context.go(
                Routes.docSourceFor(widget.projectId, s.id),
              ),
            ),
        ],
      ],
    );
  }
}

/// A child row of the Wiki section: the internal wiki, or one documentation
/// source shown with its own emoji or colour.
class _DocChildRow extends StatelessWidget {
  const _DocChildRow({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.emoji = '',
    this.color = '',
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final String emoji;
  final String color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = selected
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(left: 24, right: 12, top: 2, bottom: 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: selected ? theme.colorScheme.primaryContainer : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              if (emoji.isNotEmpty)
                SizedBox(
                  width: 18,
                  child: Text(emoji, style: const TextStyle(fontSize: 14)),
                )
              else if (color.isNotEmpty)
                SizedBox(
                  width: 18,
                  child: Center(child: _BoardDot(color: color)),
                )
              else
                Icon(icon, size: 16, color: fg),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: fg,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
