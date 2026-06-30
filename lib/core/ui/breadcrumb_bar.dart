import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intellipilot/app/router/app_router.dart';
import 'package:intellipilot/app/theme/app_theme.dart';
import 'package:intellipilot/features/projects/presentation/cubits/project_detail_cubit.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// One segment in a breadcrumb trail. Tappable when [onTap] is set; the
/// current page passes a null callback to render the segment as plain
/// non-interactive text.
class Crumb {
  const Crumb({
    required this.label,
    this.onTap,
    this.mono = false,
  });

  /// Display text. Keep it short — long titles get ellipsised.
  final String label;

  /// Navigation target. Null = current page (rendered as the active
  /// segment, no underline, no tap).
  final VoidCallback? onTap;

  /// Use the IntelliPilot mono typeface (JetBrains Mono) for the label —
  /// reserved for issue keys (`EPIC-12`, `US-7`, `T-3`, `ISSUE-2`).
  final bool mono;
}

/// Jira-style breadcrumb trail, designed to sit inside `AppBar.title` in
/// place of a plain page-title `Text` widget. Renders the crumbs in a
/// horizontal row with `›` separators; the active (last) segment is
/// bolder + onSurface; intermediate segments are outline-coloured and
/// tappable.
///
/// Best practice followed:
/// - First crumb is always the top-level hub (e.g. **Projects**), reachable
///   from any depth.
/// - Linear hierarchy mirrors the URL — no shortcuts, no skipped levels.
/// - Active segment is non-clickable text, distinguished by weight + colour.
/// - Long trails ellipsise the middle by switching to horizontal scroll on
///   narrow viewports rather than truncating any single segment.
class BreadcrumbBar extends StatelessWidget {
  const BreadcrumbBar({required this.crumbs, this.activeWidget, super.key});

  final List<Crumb> crumbs;

  /// When set, this widget is rendered as the trailing (active) segment in
  /// place of an active text crumb — e.g. an interactive dropdown. All
  /// [crumbs] are then rendered as non-active (linkable) segments.
  final Widget? activeWidget;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasActiveWidget = activeWidget != null;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < crumbs.length; i++) ...[
            if (i > 0) _Separator(color: theme.colorScheme.outline),
            _Segment(
              crumb: crumbs[i],
              active: !hasActiveWidget && i == crumbs.length - 1,
            ),
          ],
          if (hasActiveWidget) ...[
            _Separator(color: theme.colorScheme.outline),
            activeWidget!,
          ],
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({required this.crumb, required this.active});
  final Crumb crumb;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseStyle = crumb.mono
        ? AppTheme.mono(context, size: 13)
        : theme.textTheme.titleSmall;
    final style = baseStyle?.copyWith(
      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
      color: active ? theme.colorScheme.onSurface : theme.colorScheme.outline,
    );
    if (crumb.onTap == null || active) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Text(crumb.label, style: style),
      );
    }
    return InkWell(
      onTap: crumb.onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Text(crumb.label, style: style),
      ),
    );
  }
}

class _Separator extends StatelessWidget {
  const _Separator({required this.color});
  final Color color;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Icon(Icons.chevron_right, size: 16, color: color),
    );
  }
}

/// Pre-built breadcrumb for project sub-pages — the trail is always
/// `Projects › <ProjectName> › <Section> [› extra crumbs]`. Reads the
/// project name from the [ProjectDetailCubit] that the page already
/// provides, so the widget can drop straight into `AppBar.title`.
class ProjectSectionBreadcrumb extends StatelessWidget {
  const ProjectSectionBreadcrumb({
    required this.projectId,
    required this.currentLabel,
    this.sectionRoute,
    this.extraCrumbs = const [],
    this.activeWidget,
    super.key,
  });

  final String projectId;

  /// Section label (e.g. **Backlog**, **Board**) — becomes the active
  /// crumb when [extraCrumbs] is empty, or a linkable parent otherwise.
  final String currentLabel;

  /// Optional interactive widget rendered as the active (trailing) segment in
  /// place of [currentLabel] — e.g. the board switcher dropdown. Ignored when
  /// [extraCrumbs] is non-empty (the section becomes a linkable parent then).
  final Widget? activeWidget;

  /// Route the section crumb navigates to when tapped. Required by
  /// callers that pass [extraCrumbs] (the section is no longer the
  /// active page then); ignored otherwise.
  final String? sectionRoute;

  /// Deeper hierarchy under the section. E.g. on the wiki page detail
  /// pass `[Crumb(label: pageTitle)]`; on milestone detail pass
  /// `[Crumb(label: milestoneName)]`. The last item is rendered active.
  final List<Crumb> extraCrumbs;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    // An interactive active segment (e.g. the board switcher) only applies
    // when this is the leaf page — i.e. no deeper crumbs follow.
    final useActiveWidget = activeWidget != null && extraCrumbs.isEmpty;
    return BreadcrumbBar(
      activeWidget: useActiveWidget ? activeWidget : null,
      crumbs: [
        Crumb(
          label: t.projectsTitle,
          onTap: () => context.go(Routes.projects),
        ),
        Crumb(
          label: _projectName(context),
          onTap: () => context.go(Routes.projectDetailFor(projectId)),
        ),
        if (!useActiveWidget)
          Crumb(
            label: currentLabel,
            onTap: sectionRoute == null
                ? null
                : () => context.go(sectionRoute!),
          ),
        ...extraCrumbs,
      ],
    );
  }

  /// Reads the project name from [ProjectDetailCubit] when one is in
  /// scope, otherwise falls back to a placeholder. This keeps the
  /// breadcrumb usable on pages that don't provide the cubit (e.g. the
  /// wiki revisions page) without forcing every such page to bootstrap
  /// the cubit just for a title. Catches Object because the missing
  /// provider's exception type lives in the `provider` package which we
  /// don't directly depend on.
  String _projectName(BuildContext context) {
    try {
      final state = context.watch<ProjectDetailCubit>().state;
      if (state is ProjectDetailLoaded) return state.project.name;
    } on Object {
      // Cubit not in scope; render the placeholder.
    }
    return '…';
  }
}
