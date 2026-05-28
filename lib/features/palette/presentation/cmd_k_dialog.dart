import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/router/app_router.dart';
import 'package:intellipilot/features/backlog/domain/backlog_repository.dart';
import 'package:intellipilot/features/palette/data/dtos/palette_dtos.dart';
import 'package:intellipilot/features/palette/presentation/cubits/palette_cubit.dart';
import 'package:intellipilot/features/projects/domain/projects_repository.dart';
import 'package:intellipilot/features/wiki/domain/wiki_repository.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// Opens the Cmd-K palette modal. Caller passes the [activeProjectId] (or
/// null when no project is open).
Future<void> openCmdKDialog(
  BuildContext context, {
  String? activeProjectId,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black54,
    builder: (ctx) => BlocProvider<PaletteCubit>(
      create: (_) => PaletteCubit(
        projects: getIt<ProjectsRepository>(),
        backlog: getIt<BacklogRepository>(),
        wiki: getIt<WikiRepository>(),
        activeProjectId: activeProjectId,
      )..prime(),
      child: const _CmdK(),
    ),
  );
}

class _CmdK extends StatefulWidget {
  const _CmdK();

  @override
  State<_CmdK> createState() => _CmdKState();
}

class _CmdKState extends State<_CmdK> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  int _selected = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _move(int delta, int length) {
    if (length == 0) return;
    setState(() {
      _selected = (_selected + delta + length) % length;
    });
  }

  void _activate(BuildContext context, PaletteResult result) {
    Navigator.of(context).pop();
    switch (result) {
      case ProjectResult():
        context.go(Routes.projectDetailFor(result.projectId));
      case WikiResult():
        context.go(Routes.wikiPageFor(result.projectId, result.pageId));
      case EntityResult():
        context.go(
          Routes.entityDetailFor(
            result.projectId,
            result.kind,
            result.entityId,
          ),
        );
      case CommandResult():
        result.run();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Dialog(
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 80),
      child: BlocBuilder<PaletteCubit, PaletteState>(
        builder: (context, state) {
          final results = state.results;
          // Clamp selection when results shrink.
          if (_selected >= results.length) _selected = 0;
          return SizedBox(
            width: 640,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: KeyboardListener(
                    focusNode: FocusNode(skipTraversal: true),
                    onKeyEvent: (e) {
                      if (e is! KeyDownEvent) return;
                      if (e.logicalKey == LogicalKeyboardKey.arrowDown) {
                        _move(1, results.length);
                      } else if (e.logicalKey == LogicalKeyboardKey.arrowUp) {
                        _move(-1, results.length);
                      } else if (e.logicalKey == LogicalKeyboardKey.enter &&
                          results.isNotEmpty) {
                        _activate(context, results[_selected]);
                      } else if (e.logicalKey == LogicalKeyboardKey.escape) {
                        Navigator.of(context).pop();
                      }
                    },
                    child: TextField(
                      controller: _ctrl,
                      focusNode: _focus,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: t.paletteHint,
                        prefixIcon: const Icon(Icons.search),
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (v) {
                        setState(() => _selected = 0);
                        context.read<PaletteCubit>().setQuery(v);
                      },
                      onSubmitted: (_) {
                        if (results.isNotEmpty) {
                          _activate(context, results[_selected]);
                        }
                      },
                    ),
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: state.busy
                      ? const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      : results.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(t.paletteEmpty),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              padding: EdgeInsets.zero,
                              itemCount: results.length,
                              itemBuilder: (context, i) {
                                final r = results[i];
                                final selected = i == _selected;
                                return ListTile(
                                  selected: selected,
                                  dense: true,
                                  leading: _iconFor(r),
                                  title: Text(r.label),
                                  subtitle: Text(r.subtitle),
                                  onTap: () => _activate(context, r),
                                );
                              },
                            ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _iconFor(PaletteResult r) {
    switch (r) {
      case ProjectResult():
        return const Icon(Icons.folder_outlined);
      case WikiResult():
        return const Icon(Icons.article_outlined);
      case EntityResult():
        return const Icon(Icons.tag);
      case CommandResult():
        return const Icon(Icons.flash_on_outlined);
    }
  }
}
