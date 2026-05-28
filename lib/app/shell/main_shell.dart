import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/router/app_router.dart';
import 'package:intellipilot/app/session/session_bloc.dart';
import 'package:intellipilot/app/theme/app_theme.dart';
import 'package:intellipilot/core/ui/breakpoints.dart';
import 'package:intellipilot/features/palette/presentation/cmd_k_dialog.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// App-wide chrome wrapping the routed page. Adds:
/// - A thin top brand strip with logo, global Create button, search trigger
///   that opens the Cmd-K palette, and an avatar with sign-out.
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
    // SessionBloc is a process-wide singleton — read it from the service
    // locator rather than the widget tree. ShellRoute's inner Navigator
    // creates a subtree where provider inheritance behaves differently from
    // direct routes, so this side-steps the scoping issue cleanly.
    // The router's redirect guard already bounces away when the session
    // ends, so we just need the *current* state at build time.
    final session = getIt<SessionBloc>().state;
    // Under a [ShellRoute] so [GoRouterState.of] is available and rebuilds
    // on every navigation.
    final route = GoRouterState.of(context).uri.toString();
    final hide = _shouldHide(session, route);
    if (hide) return child;

    final scope = _projectScopeOf(route);
    final showRail =
        scope != null && Breakpoints.of(context).isAtLeastMedium;

    return Scaffold(
      appBar: _TopBar(activeProjectId: scope),
      body: showRail
          ? Row(
              children: [
                _ProjectRail(projectId: scope, currentRoute: route),
                const VerticalDivider(width: 1),
                Expanded(child: child),
              ],
            )
          : child,
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

  /// Extract the project id from `/projects/:id/...` paths. Returns null
  /// for non-project routes (the projects list, account pages, etc.).
  String? _projectScopeOf(String location) {
    final uri = Uri.tryParse(location);
    if (uri == null) return null;
    final segments = uri.pathSegments;
    if (segments.length < 2) return null;
    if (segments[0] != 'projects') return null;
    return segments[1];
  }
}

class _TopBar extends StatelessWidget implements PreferredSizeWidget {
  const _TopBar({this.activeProjectId});
  final String? activeProjectId;

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
            // Tight threshold — the full bar (brand + nav links + search
            // chip + Create button + avatar) only fits comfortably above
            // ~900px. Below that, brand collapses to its icon, nav links
            // hide (still reachable via the avatar menu), the search chip
            // becomes an icon, and Create becomes an icon-only filled
            // button.
            final compact = constraints.maxWidth < 900;
            return Row(
              children: [
                const SizedBox(width: 12),
                _BrandMark(
                  compact: compact,
                  onTap: () => context.go(Routes.projects),
                ),
                if (!compact) ...[
                  const SizedBox(width: 24),
                  _NavLink(
                    label: AppLocalizations.of(context).topNavProjects,
                    onTap: () => context.go(Routes.projects),
                  ),
                  const SizedBox(width: 4),
                  _NavLink(
                    label: AppLocalizations.of(context).topNavSettings,
                    onTap: () => context.go(Routes.settings),
                  ),
                ],
                const Spacer(),
                _SearchButton(
                  compact: compact,
                  activeProjectId: activeProjectId,
                ),
                const SizedBox(width: 8),
                _CreateMenu(
                  compact: compact,
                  activeProjectId: activeProjectId,
                ),
                const SizedBox(width: 8),
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
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(
                Icons.flight_takeoff,
                size: 16,
                color: theme.colorScheme.onPrimary,
              ),
            ),
            if (!compact) ...[
              const SizedBox(width: 8),
              Text(
                'IntelliPilot',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
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
  const _SearchButton({this.activeProjectId, this.compact = false});
  final String? activeProjectId;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (compact) {
      return IconButton(
        onPressed: () => openCmdKDialog(
          context,
          activeProjectId: activeProjectId,
        ),
        icon: const Icon(Icons.search),
        tooltip: AppLocalizations.of(context).topNavSearchPlaceholder,
      );
    }
    return InkWell(
      onTap: () => openCmdKDialog(
        context,
        activeProjectId: activeProjectId,
      ),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
              padding: const EdgeInsets.symmetric(
                horizontal: 4,
                vertical: 1,
              ),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '⌘K',
                style: AppTheme.mono(context, size: 11).copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CreateMenu extends StatelessWidget {
  const _CreateMenu({this.activeProjectId, this.compact = false});
  final String? activeProjectId;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return MenuAnchor(
      menuChildren: [
        if (activeProjectId != null) ...[
          MenuItemButton(
            leadingIcon: const Icon(Icons.bookmark_outlined),
            onPressed: () =>
                context.go(Routes.projectBacklogFor(activeProjectId!)),
            child: Text(t.topCreateUserStory),
          ),
          MenuItemButton(
            leadingIcon: const Icon(Icons.bug_report_outlined),
            onPressed: () =>
                context.go(Routes.projectIssuesFor(activeProjectId!)),
            child: Text(t.topCreateIssue),
          ),
          MenuItemButton(
            leadingIcon: const Icon(Icons.article_outlined),
            onPressed: () =>
                context.go(Routes.projectWikiFor(activeProjectId!)),
            child: Text(t.topCreateWikiPage),
          ),
          const Divider(height: 1),
        ],
        MenuItemButton(
          leadingIcon: const Icon(Icons.folder_outlined),
          onPressed: () => context.go(Routes.projects),
          child: Text(t.topCreateProject),
        ),
      ],
      builder: (context, controller, _) => compact
          ? IconButton.filled(
              icon: const Icon(Icons.add, size: 18),
              tooltip: t.topCreateAction,
              onPressed: () =>
                  controller.isOpen ? controller.close() : controller.open(),
            )
          : FilledButton.icon(
              icon: const Icon(Icons.add, size: 18),
              onPressed: () =>
                  controller.isOpen ? controller.close() : controller.open(),
              label: Text(t.topCreateAction),
              style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
    );
  }
}

class _AvatarMenu extends StatelessWidget {
  const _AvatarMenu();

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
        const Divider(height: 1),
        MenuItemButton(
          leadingIcon: const Icon(Icons.logout),
          onPressed: () =>
              getIt<SessionBloc>().add(const SessionLogoutRequested()),
          child: Text(t.topMenuSignOut),
        ),
      ],
      builder: (context, controller, _) => IconButton(
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        icon: CircleAvatar(
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

class _ProjectRail extends StatelessWidget {
  const _ProjectRail({required this.projectId, required this.currentRoute});
  final String projectId;
  final String currentRoute;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final items = [
      _RailItem(
        icon: Icons.dashboard_outlined,
        label: t.railOverview,
        path: Routes.projectDetailFor(projectId),
      ),
      _RailItem(
        icon: Icons.bookmark_outlined,
        label: t.railBacklog,
        path: Routes.projectBacklogFor(projectId),
      ),
      _RailItem(
        icon: Icons.view_kanban_outlined,
        label: t.railBoard,
        path: Routes.projectBoardFor(projectId),
      ),
      _RailItem(
        icon: Icons.bug_report_outlined,
        label: t.railIssues,
        path: Routes.projectIssuesFor(projectId),
      ),
      _RailItem(
        icon: Icons.flag_outlined,
        label: t.railMilestones,
        path: Routes.projectMilestonesFor(projectId),
      ),
      _RailItem(
        icon: Icons.menu_book_outlined,
        label: t.railWiki,
        path: Routes.projectWikiFor(projectId),
      ),
      _RailItem(
        icon: Icons.settings_outlined,
        label: t.railSettings,
        path: Routes.projectSettingsFor(projectId),
      ),
    ];

    final selectedIndex = _selectedIndexFor(currentRoute, items);

    return NavigationRail(
      extended: Breakpoints.of(context).isExpanded,
      selectedIndex: selectedIndex,
      onDestinationSelected: (i) => context.go(items[i].path),
      labelType: Breakpoints.of(context).isExpanded
          ? NavigationRailLabelType.none
          : NavigationRailLabelType.all,
      destinations: [
        for (final i in items)
          NavigationRailDestination(
            icon: Icon(i.icon),
            label: Text(i.label),
          ),
      ],
    );
  }

  int _selectedIndexFor(String route, List<_RailItem> items) {
    // Walk longest path first so /projects/:id/settings doesn't match /:id.
    final sorted = [...items]..sort(
      (a, b) => b.path.length.compareTo(a.path.length),
    );
    for (final item in sorted) {
      if (route == item.path || route.startsWith('${item.path}/')) {
        return items.indexOf(item);
      }
    }
    return 0;
  }
}

class _RailItem {
  const _RailItem({
    required this.icon,
    required this.label,
    required this.path,
  });
  final IconData icon;
  final String label;
  final String path;
}
