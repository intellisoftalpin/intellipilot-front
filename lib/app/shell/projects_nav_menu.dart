import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/router/app_router.dart';
import 'package:intellipilot/features/projects/data/dtos/project_dtos.dart';
import 'package:intellipilot/features/projects/domain/projects_repository.dart';
import 'package:intellipilot/features/projects/presentation/cubits/project_favorites_cubit.dart';
import 'package:intellipilot/features/projects/presentation/widgets/create_project_dialog.dart';
import 'package:intellipilot/features/projects/presentation/widgets/project_avatar.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// Top-bar "Projects" link. A click opens the projects screen; hovering opens
/// a dropdown with the starred projects first, then every other project, then
/// "View all projects" and "New project".
///
/// The list is fetched when the menu opens, so it is never older than the
/// last hover; the previous answer shows meanwhile.
class ProjectsNavMenu extends StatefulWidget {
  const ProjectsNavMenu({required this.label, super.key});
  final String label;

  @override
  State<ProjectsNavMenu> createState() => _ProjectsNavMenuState();
}

class _ProjectsNavMenuState extends State<ProjectsNavMenu> {
  /// Grace period for the pointer to travel between the link and the menu.
  static const _closeDelay = Duration(milliseconds: 220);

  final _menu = MenuController();
  Timer? _closeTimer;
  List<Project>? _projects;
  bool _failed = false;

  @override
  void dispose() {
    _closeTimer?.cancel();
    super.dispose();
  }

  void _hoverIn() {
    _closeTimer?.cancel();
    if (_menu.isOpen) return;
    _menu.open();
    unawaited(_load());
  }

  void _hoverOut() {
    _closeTimer?.cancel();
    _closeTimer = Timer(_closeDelay, () {
      if (mounted && _menu.isOpen) _menu.close();
    });
  }

  Future<void> _load() async {
    unawaited(getIt<ProjectFavoritesCubit>().load());
    final res = await getIt<ProjectsRepository>().listProjects();
    if (!mounted) return;
    res.when(
      ok: (list) => setState(() {
        _projects = list;
        _failed = false;
      }),
      err: (_) => setState(() => _failed = true),
    );
  }

  void _go(String location) {
    _menu.close();
    context.go(location);
  }

  void _create() {
    _menu.close();
    final repo = getIt<ProjectsRepository>();
    final messenger = ScaffoldMessenger.of(context);
    final failed = AppLocalizations.of(context).projectCreateFailed;
    unawaited(
      showCreateProjectDialog(
        context,
        create: (body) async {
          final res = await repo.createProject(body);
          return res.when(
            ok: (p) => p,
            err: (_) {
              messenger.showSnackBar(SnackBar(content: Text(failed)));
              return null;
            },
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      controller: _menu,
      alignmentOffset: const Offset(0, 4),
      style: MenuStyle(
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        side: WidgetStatePropertyAll(
          BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
      ),
      menuChildren: [
        MouseRegion(
          onEnter: (_) => _closeTimer?.cancel(),
          onExit: (_) => _hoverOut(),
          child: BlocBuilder<ProjectFavoritesCubit, ProjectFavoritesState>(
            bloc: getIt<ProjectFavoritesCubit>(),
            builder: (context, favorites) => _Panel(
              projects: _projects,
              failed: _failed,
              favorites: favorites.ids,
              onOpen: (p) => _go(Routes.projectDetailFor(p.id)),
              onViewAll: () => _go(Routes.projects),
              onCreate: _create,
            ),
          ),
        ),
      ],
      builder: (context, controller, child) => MouseRegion(
        onEnter: (_) => _hoverIn(),
        onExit: (_) => _hoverOut(),
        child: TextButton(
          onPressed: () => _go(Routes.projects),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
            foregroundColor: Theme.of(context).colorScheme.onSurface,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.label),
              const SizedBox(width: 2),
              const Icon(Icons.expand_more, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.projects,
    required this.failed,
    required this.favorites,
    required this.onOpen,
    required this.onViewAll,
    required this.onCreate,
  });

  final List<Project>? projects;
  final bool failed;
  final List<String> favorites;
  final ValueChanged<Project> onOpen;
  final VoidCallback onViewAll;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final all = projects;
    final byId = {for (final p in all ?? const <Project>[]) p.id: p};
    final starred = [
      for (final id in favorites) ?byId[id],
    ];
    final others = [
      for (final p in all ?? const <Project>[])
        if (!favorites.contains(p.id)) p,
    ];

    final Widget list;
    if (all == null) {
      list = failed
          ? _Note(text: t.projectsLoadFailed)
          : const Padding(
              padding: EdgeInsets.all(20),
              child: Center(
                child: SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
    } else if (all.isEmpty) {
      list = _Note(text: t.projectsMenuEmpty);
    } else {
      list = Flexible(
        child: SingleChildScrollView(
          // The menu wraps its children in a scroll view of its own; this one
          // must not claim the primary controller too.
          primary: false,
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (starred.isNotEmpty) ...[
                _Heading(icon: Icons.star_rounded, label: t.projectsStarred),
                for (final p in starred) _Row(project: p, onTap: onOpen),
                if (others.isNotEmpty) const Divider(height: 12),
              ],
              if (others.isNotEmpty) ...[
                _Heading(icon: Icons.folder_outlined, label: t.projectsAll),
                for (final p in others) _Row(project: p, onTap: onOpen),
              ],
            ],
          ),
        ),
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: 300,
        maxWidth: 300,
        maxHeight: 480,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          list,
          const Divider(height: 1),
          MenuItemButton(
            leadingIcon: const Icon(Icons.grid_view_rounded, size: 18),
            onPressed: onViewAll,
            child: Text(t.projectsMenuViewAll),
          ),
          MenuItemButton(
            leadingIcon: const Icon(Icons.add, size: 18),
            onPressed: onCreate,
            child: Text(t.actionNewProject),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.project, required this.onTap});
  final Project project;
  final ValueChanged<Project> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = project;
    final key = p.issuePrefix.isEmpty ? p.slug : p.issuePrefix;
    return MenuItemButton(
      leadingIcon: ProjectAvatar(project: p, size: 24),
      trailingIcon: Text(
        key,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      onPressed: () => onTap(p),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 190),
        child: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}
