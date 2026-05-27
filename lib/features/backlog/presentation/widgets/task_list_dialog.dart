import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/features/backlog/domain/backlog_repository.dart';
import 'package:intellipilot/features/backlog/presentation/cubits/tasks_cubit.dart';
import 'package:intellipilot/features/catalog/domain/catalog_repository.dart';
import 'package:intellipilot/features/catalog/presentation/widgets/color_swatch_picker.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// Shows the tasks attached to a user story with quick-add + per-row
/// status menu + delete. Self-contained: it owns its own [TasksCubit] for
/// the lifetime of the modal.
Future<void> showTaskListDialog(
  BuildContext context, {
  required String projectId,
  required String userStoryId,
  required String userStorySubject,
  required bool canEdit,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => BlocProvider<TasksCubit>(
      create: (_) => TasksCubit(
        repo: getIt<BacklogRepository>(),
        catalog: getIt<CatalogRepository>(),
        projectId: projectId,
        userStoryId: userStoryId,
      )..load(),
      child: _TaskListView(
        userStorySubject: userStorySubject,
        canEdit: canEdit,
      ),
    ),
  );
}

class _TaskListView extends StatefulWidget {
  const _TaskListView({
    required this.userStorySubject,
    required this.canEdit,
  });

  final String userStorySubject;
  final bool canEdit;

  @override
  State<_TaskListView> createState() => _TaskListViewState();
}

class _TaskListViewState extends State<_TaskListView> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(t.tasksDialogTitle(widget.userStorySubject)),
      content: SizedBox(
        width: 480,
        height: 420,
        child: BlocBuilder<TasksCubit, TasksState>(
          builder: (context, state) {
            if (state is TasksLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state is TasksFailed) {
              return Center(child: Text(t.tasksLoadFailed));
            }
            if (state is! TasksLoaded) return const SizedBox.shrink();
            return Column(
              children: [
                if (widget.canEdit)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _ctrl,
                            decoration: InputDecoration(
                              hintText: t.tasksAddHint,
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                            onSubmitted: (v) {
                              context.read<TasksCubit>().create(v);
                              _ctrl.clear();
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          icon: const Icon(Icons.add),
                          onPressed: () {
                            context.read<TasksCubit>().create(_ctrl.text);
                            _ctrl.clear();
                          },
                          label: Text(t.actionAdd),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: state.tasks.isEmpty
                      ? Center(child: Text(t.tasksEmpty))
                      : ListView.builder(
                          itemCount: state.tasks.length,
                          itemBuilder: (context, i) {
                            final task = state.tasks[i];
                            final matches = state.statuses
                                .where((s) => s.id == task.statusId)
                                .toList();
                            final status =
                                matches.isEmpty ? null : matches.first;
                            final closed = status?.isClosed ?? false;
                            return CheckboxListTile(
                              dense: true,
                              value: closed,
                              onChanged: !widget.canEdit
                                  ? null
                                  : (v) {
                                      String? targetStatus;
                                      if (v ?? false) {
                                        targetStatus = state.statuses
                                            .firstWhere(
                                              (s) =>
                                                  s.isClosed ?? false,
                                              orElse: () =>
                                                  state.statuses.first,
                                            )
                                            .id;
                                      } else {
                                        targetStatus = state.statuses
                                            .firstWhere(
                                              (s) =>
                                                  !(s.isClosed ?? false),
                                              orElse: () =>
                                                  state.statuses.first,
                                            )
                                            .id;
                                      }
                                      context
                                          .read<TasksCubit>()
                                          .setStatus(task.id, targetStatus);
                                    },
                              title: Text(
                                task.subject,
                                style: closed
                                    ? TextStyle(
                                        decoration:
                                            TextDecoration.lineThrough,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .outline,
                                      )
                                    : null,
                              ),
                              subtitle: Row(
                                children: [
                                  Text('T-${task.reference}'),
                                  if (status != null) ...[
                                    const SizedBox(width: 8),
                                    HexColorDot(
                                      hex: status.color,
                                      size: 10,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(status.name),
                                  ],
                                ],
                              ),
                              secondary: widget.canEdit
                                  ? IconButton(
                                      icon:
                                          const Icon(Icons.delete_outline),
                                      onPressed: () => context
                                          .read<TasksCubit>()
                                          .delete(task.id),
                                    )
                                  : null,
                              controlAffinity:
                                  ListTileControlAffinity.leading,
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.actionDone),
        ),
      ],
    );
  }
}
