import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/router/app_router.dart';
import 'package:intellipilot/core/ui/empty_state.dart';
import 'package:intellipilot/features/board/presentation/boards_nav_refresh.dart';
import 'package:intellipilot/features/board/presentation/widgets/board_settings_dialog.dart';
import 'package:intellipilot/features/catalog/data/dtos/catalog_dtos.dart';
import 'package:intellipilot/features/catalog/domain/catalog_repository.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// Resolves `/projects/:id/board` to a concrete board: the user's last-opened
/// board, or the first board, redirecting there. When the project has no
/// boards yet it shows a create-a-board empty state.
class BoardResolverPage extends StatefulWidget {
  const BoardResolverPage({required this.projectId, super.key});
  final String projectId;

  @override
  State<BoardResolverPage> createState() => _BoardResolverPageState();
}

class _BoardResolverPageState extends State<BoardResolverPage> {
  late final Future<List<Board>> _future = _resolve();

  Future<List<Board>> _resolve() async {
    final catalog = getIt<CatalogRepository>();
    final boards =
        (await catalog.listBoards(widget.projectId)).valueOrNull ??
        const <Board>[];
    if (boards.isEmpty) return boards;

    final lastId = (await catalog.getLastOpenedBoard(
      widget.projectId,
    )).valueOrNull;
    final target =
        boards.where((b) => b.id == lastId).firstOrNull ?? boards.first;
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.go(Routes.projectBoardFor(widget.projectId, target.id));
        }
      });
    }
    return boards;
  }

  Future<void> _create() async {
    final created = await showBoardSettingsDialog(
      context,
      projectId: widget.projectId,
    );
    if (created == null || !mounted) return;
    bumpBoardsNav();
    context.go(Routes.projectBoardFor(widget.projectId, created.id));
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      body: FutureBuilder<List<Board>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final boards = snap.data ?? const <Board>[];
          if (boards.isEmpty) {
            return Center(
              child: EmptyState(
                icon: Icons.view_kanban_outlined,
                title: t.boardsEmptyTitle,
                body: t.boardsEmptyBody,
                action: FilledButton.icon(
                  onPressed: _create,
                  icon: const Icon(Icons.add),
                  label: Text(t.boardNewAction),
                ),
              ),
            );
          }
          // A board was found — the post-frame redirect is in flight.
          return const Center(child: CircularProgressIndicator());
        },
      ),
    );
  }
}
