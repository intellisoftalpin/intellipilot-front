import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/router/app_router.dart';
import 'package:intellipilot/core/ui/breadcrumb_bar.dart';
import 'package:intellipilot/core/ui/empty_state.dart';
import 'package:intellipilot/features/board/domain/board_config.dart';
import 'package:intellipilot/features/board/presentation/boards_nav_refresh.dart';
import 'package:intellipilot/features/board/presentation/widgets/board_settings_dialog.dart';
import 'package:intellipilot/features/catalog/data/dtos/catalog_dtos.dart';
import 'package:intellipilot/features/catalog/domain/catalog_repository.dart';
import 'package:intellipilot/features/profile/data/dtos/profile_dtos.dart';
import 'package:intellipilot/features/profile/domain/profile_repository.dart';
import 'package:intellipilot/features/projects/domain/projects_repository.dart';
import 'package:intellipilot/features/projects/presentation/cubits/project_detail_cubit.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// The boards gallery (index). Shows the project's boards as cards plus a
/// "New board" card. When the project has exactly one board it redirects
/// straight to that board (skipping the gallery); with none it shows a
/// create-a-board empty state.
class BoardsGalleryPage extends StatefulWidget {
  const BoardsGalleryPage({required this.projectId, super.key});
  final String projectId;

  @override
  State<BoardsGalleryPage> createState() => _BoardsGalleryPageState();
}

class _BoardsGalleryPageState extends State<BoardsGalleryPage> {
  late Future<(UserProfile?, List<Board>)> _future = _load();

  @override
  void initState() {
    super.initState();
    boardsNavRevision.addListener(_reload);
  }

  @override
  void dispose() {
    boardsNavRevision.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    if (mounted) setState(() => _future = _load());
  }

  Future<(UserProfile?, List<Board>)> _load() async {
    final profile = (await getIt<ProfileRepository>().getProfile()).valueOrNull;
    final boards =
        (await getIt<CatalogRepository>().listBoards(
          widget.projectId,
        )).valueOrNull ??
        const <Board>[];
    return (profile, boards);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(UserProfile?, List<Board>)>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final (profile, boards) = snap.data ?? (null, const <Board>[]);

        // Exactly one board → skip the gallery, open it directly.
        if (boards.length == 1) {
          final id = boards.first.id;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              context.go(Routes.projectBoardFor(widget.projectId, id));
            }
          });
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return BlocProvider<ProjectDetailCubit>(
          create: (_) {
            final c = ProjectDetailCubit(
              repo: getIt<ProjectsRepository>(),
              projectId: widget.projectId,
              currentUserId: profile?.id ?? '',
            );
            unawaited(c.load());
            return c;
          },
          child: _GalleryView(projectId: widget.projectId, boards: boards),
        );
      },
    );
  }
}

class _GalleryView extends StatelessWidget {
  const _GalleryView({required this.projectId, required this.boards});
  final String projectId;
  final List<Board> boards;

  Future<void> _create(BuildContext context) async {
    final created = await showBoardSettingsDialog(
      context,
      projectId: projectId,
    );
    if (created == null || !context.mounted) return;
    bumpBoardsNav();
    context.go(Routes.projectBoardFor(projectId, created.id));
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: ProjectSectionBreadcrumb(
          projectId: projectId,
          currentLabel: t.railBoards,
        ),
      ),
      body: boards.isEmpty
          ? Center(
              child: EmptyState(
                icon: Icons.view_kanban_outlined,
                title: t.boardsEmptyTitle,
                body: t.boardsEmptyBody,
                action: FilledButton.icon(
                  onPressed: () => _create(context),
                  icon: const Icon(Icons.add),
                  label: Text(t.boardNewAction),
                ),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  for (final b in boards)
                    _BoardCard(
                      board: b,
                      onTap: () => context.go(
                        Routes.projectBoardFor(projectId, b.id),
                      ),
                    ),
                  _NewBoardCard(onTap: () => _create(context)),
                ],
              ),
            ),
    );
  }
}

class _BoardCard extends StatelessWidget {
  const _BoardCard({required this.board, required this.onTap});
  final Board board;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final accent = _hex(board.color) ?? theme.colorScheme.primary;
    final cfg = BoardConfig.fromMap(board.config);
    final visibleCount = cfg.visibleColumnIds.isEmpty
        ? cfg.columnOrder.length
        : cfg.visibleColumnIds.length;
    return SizedBox(
      width: 260,
      child: Card(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(height: 6, color: accent),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      board.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _Tag(
                          icon: board.isShared
                              ? Icons.group_outlined
                              : Icons.person_outline,
                          label: board.isShared
                              ? t.boardVisibilityShared
                              : t.boardVisibilityPersonal,
                        ),
                        if (visibleCount > 0)
                          _Tag(
                            icon: Icons.view_column_outlined,
                            label: t.boardColumnsVisible(visibleCount),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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

class _Tag extends StatelessWidget {
  const _Tag({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(label, style: theme.textTheme.labelSmall),
        ],
      ),
    );
  }
}

class _NewBoardCard extends StatelessWidget {
  const _NewBoardCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return SizedBox(
      width: 260,
      height: 96,
      child: Card(
        clipBehavior: Clip.antiAlias,
        color: theme.colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: InkWell(
          onTap: onTap,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  t.boardNewAction,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
