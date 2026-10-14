import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/features/projects/data/dtos/project_dtos.dart';
import 'package:intellipilot/features/projects/domain/projects_repository.dart';
import 'package:intellipilot/features/projects/presentation/cubits/project_favorites_cubit.dart';
import 'package:intellipilot/features/projects/presentation/cubits/projects_list_cubit.dart';
import 'package:intellipilot/features/projects/presentation/widgets/create_project_dialog.dart';
import 'package:intellipilot/features/projects/presentation/widgets/project_card.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// Widest the card grid grows; past it the page centers.
const _maxContentWidth = 1360.0;

/// Narrowest a card gets before the grid drops a column.
const _minCardWidth = 280.0;
const _maxColumns = 4;
const _gap = 16.0;

class ProjectsListPage extends StatelessWidget {
  const ProjectsListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<ProjectsListCubit>(
          create: (_) {
            final c = ProjectsListCubit(getIt<ProjectsRepository>());
            unawaited(c.load());
            unawaited(getIt<ProjectFavoritesCubit>().load());
            return c;
          },
        ),
        BlocProvider<ProjectFavoritesCubit>.value(
          value: getIt<ProjectFavoritesCubit>(),
        ),
      ],
      child: const _ProjectsListView(),
    );
  }
}

class _ProjectsListView extends StatelessWidget {
  const _ProjectsListView();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      body: MultiBlocListener(
        listeners: [
          BlocListener<ProjectsListCubit, ProjectsListState>(
            listenWhen: (prev, next) =>
                next is ProjectsListLoaded && next.lastError != null,
            listener: (context, state) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(t.projectCreateFailed)),
              );
            },
          ),
          BlocListener<ProjectFavoritesCubit, ProjectFavoritesState>(
            listenWhen: (prev, next) => next.saveFailed > prev.saveFailed,
            listener: (context, state) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(t.projectFavoriteSaveFailed)),
              );
            },
          ),
        ],
        child: BlocBuilder<ProjectsListCubit, ProjectsListState>(
          builder: (context, state) => switch (state) {
            ProjectsListLoading() => const Center(
              child: CircularProgressIndicator(),
            ),
            ProjectsListLoadFailed() => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(t.projectsLoadFailed),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: () => context.read<ProjectsListCubit>().load(),
                    child: Text(t.actionRetry),
                  ),
                ],
              ),
            ),
            ProjectsListLoaded() => _Loaded(state: state),
          },
        ),
      ),
    );
  }
}

class _Loaded extends StatefulWidget {
  const _Loaded({required this.state});
  final ProjectsListLoaded state;

  @override
  State<_Loaded> createState() => _LoadedState();
}

class _LoadedState extends State<_Loaded> {
  late final TextEditingController _search;

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(text: widget.state.search);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _create() => unawaited(
    showCreateProjectDialog(
      context,
      create: context.read<ProjectsListCubit>().create,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final favorites = context.watch<ProjectFavoritesCubit>().state;
    final visible = widget.state.visible;
    // Starred in the order they were starred; the rest keep the server order.
    final byId = {for (final p in visible) p.id: p};
    final starred = [
      for (final id in favorites.ids) ?byId[id],
    ];
    final others = [
      for (final p in visible)
        if (!favorites.contains(p.id)) p,
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final side = width > _maxContentWidth + 48
            ? (width - _maxContentWidth) / 2
            : (width < 600 ? 16.0 : 24.0);
        final padding = EdgeInsets.symmetric(horizontal: side);
        final columns = ((width - 2 * side + _gap) ~/ (_minCardWidth + _gap))
            .clamp(1, _maxColumns);
        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: padding.copyWith(top: 28, bottom: 8),
              sliver: SliverToBoxAdapter(
                child: _Header(
                  count: widget.state.projects.length,
                  search: _search,
                  onSearch: (v) =>
                      context.read<ProjectsListCubit>().setSearch(v),
                  onCreate: _create,
                ),
              ),
            ),
            if (visible.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _Empty(
                  searching: widget.state.search.isNotEmpty,
                  onCreate: _create,
                ),
              )
            else ...[
              if (starred.isNotEmpty) ...[
                _SectionTitle(
                  padding: padding,
                  icon: Icons.star_rounded,
                  label: t.projectsStarred,
                ),
                _Grid(
                  padding: padding,
                  columns: columns,
                  projects: starred,
                  favorites: favorites,
                ),
              ],
              if (others.isNotEmpty) ...[
                if (starred.isNotEmpty)
                  _SectionTitle(
                    padding: padding,
                    icon: Icons.folder_outlined,
                    label: t.projectsAll,
                  )
                else
                  const SliverToBoxAdapter(child: SizedBox(height: 16)),
                _Grid(
                  padding: padding,
                  columns: columns,
                  projects: others,
                  favorites: favorites,
                ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          ],
        );
      },
    );
  }
}

/// Title, project count, search, and the "New project" button. Stacks on a
/// narrow window.
class _Header extends StatelessWidget {
  const _Header({
    required this.count,
    required this.search,
    required this.onSearch,
    required this.onCreate,
  });

  final int count;
  final TextEditingController search;
  final ValueChanged<String> onSearch;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          t.projectsTitle,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          t.projectsCount(count),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
    final field = TextField(
      controller: search,
      decoration: InputDecoration(
        hintText: t.projectsSearchHint,
        prefixIcon: const Icon(Icons.search, size: 20),
        filled: true,
        fillColor: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.5,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        isDense: true,
      ),
      onChanged: onSearch,
    );
    final create = FilledButton.icon(
      onPressed: onCreate,
      icon: const Icon(Icons.add, size: 18),
      label: Text(t.actionNewProject),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 640) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: title),
                  create,
                ],
              ),
              const SizedBox(height: 16),
              field,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: title),
            SizedBox(width: 300, child: field),
            const SizedBox(width: 12),
            create,
          ],
        );
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.padding,
    required this.icon,
    required this.label,
  });

  final EdgeInsets padding;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return SliverPadding(
      padding: padding.copyWith(top: 24, bottom: 12),
      sliver: SliverToBoxAdapter(
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Text(
              label.toUpperCase(),
              style: theme.textTheme.labelLarge?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({
    required this.padding,
    required this.columns,
    required this.projects,
    required this.favorites,
  });

  final EdgeInsets padding;
  final int columns;
  final List<Project> projects;
  final ProjectFavoritesState favorites;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ProjectFavoritesCubit>();
    return SliverPadding(
      padding: padding,
      sliver: SliverGrid.builder(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisExtent: projectCardHeight,
          crossAxisSpacing: _gap,
          mainAxisSpacing: _gap,
        ),
        itemCount: projects.length,
        itemBuilder: (context, i) {
          final p = projects[i];
          return ProjectCard(
            key: ValueKey(p.id),
            project: p,
            favorite: favorites.contains(p.id),
            canFavorite: !favorites.isFull,
            onToggleFavorite: () => unawaited(cubit.toggle(p.id)),
          );
        },
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.searching, required this.onCreate});
  final bool searching;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              searching ? Icons.search_off : Icons.folder_open_outlined,
              size: 56,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              searching ? t.projectsNoMatch : t.projectsEmpty,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            if (!searching) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add, size: 18),
                label: Text(t.actionNewProject),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
