import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/core/ui/markdown_editor.dart';
import 'package:intellipilot/features/backlog/domain/backlog_repository.dart';
import 'package:intellipilot/features/milestones/data/dtos/milestone_dtos.dart';
import 'package:intellipilot/features/milestones/domain/milestones_repository.dart';
import 'package:intellipilot/features/milestones/presentation/cubits/milestone_detail_cubit.dart';
import 'package:intellipilot/features/milestones/presentation/widgets/progress_ring.dart';
import 'package:intellipilot/features/projects/domain/permission.dart';
import 'package:intellipilot/features/projects/presentation/cubits/project_detail_cubit.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// Outcome of a sidebar session, so the list/gantt underneath knows whether it
/// has to reload and whether the milestone still exists.
class MilestoneSheetResult {
  const MilestoneSheetResult({required this.changed, required this.deleted});
  final bool changed;
  final bool deleted;

  static const none = MilestoneSheetResult(changed: false, deleted: false);
}

/// Open a milestone as a wide slide-over panel over the current screen —
/// deliberately the same gesture, width curve and transition as the issue/epic
/// detail sheet, so "click a thing, it opens on the right" holds everywhere.
///
/// Requires an ancestor [ProjectDetailCubit] for permissions.
Future<MilestoneSheetResult> showMilestoneDetailSheet(
  BuildContext context, {
  required String projectId,
  required String milestoneId,
}) async {
  final projectCubit = context.read<ProjectDetailCubit>();
  final result = await showGeneralDialog<MilestoneSheetResult>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, _, _) {
      final width = MediaQuery.sizeOf(ctx).width;
      final panelWidth = width < 640
          ? width
          : (width * 0.5).clamp(560.0, 820.0);
      return Align(
        alignment: Alignment.centerRight,
        child: Material(
          elevation: 8,
          child: SizedBox(
            width: panelWidth,
            height: double.infinity,
            child: MultiBlocProvider(
              providers: [
                BlocProvider<ProjectDetailCubit>.value(value: projectCubit),
                BlocProvider<MilestoneDetailCubit>(
                  create: (_) {
                    final c = MilestoneDetailCubit(
                      milestones: getIt<MilestonesRepository>(),
                      backlog: getIt<BacklogRepository>(),
                      projectId: projectId,
                      milestoneId: milestoneId,
                    );
                    unawaited(c.load());
                    return c;
                  },
                ),
              ],
              child: const _SheetBody(),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (ctx, anim, _, child) => SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(1, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
      child: child,
    ),
  );
  return result ?? MilestoneSheetResult.none;
}

class _SheetBody extends StatelessWidget {
  const _SheetBody();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return BlocBuilder<MilestoneDetailCubit, MilestoneDetailState>(
      builder: (context, state) {
        Widget body;
        if (state is MilestoneDetailLoading) {
          body = const Center(child: CircularProgressIndicator());
        } else if (state is MilestoneDetailFailed) {
          body = Center(child: Text(t.milestoneLoadFailed));
        } else if (state is MilestoneDetailLoaded) {
          body = _Editor(key: ValueKey(state.milestone.version), state: state);
        } else {
          body = const SizedBox.shrink();
        }
        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.close),
              tooltip: t.actionClose,
              onPressed: () => _dismiss(context),
            ),
            title: Text(
              state is MilestoneDetailLoaded
                  ? state.milestone.name
                  : t.milestoneDetailTitle,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          body: body,
        );
      },
    );
  }

  static void _dismiss(BuildContext context) {
    final cubit = context.read<MilestoneDetailCubit>();
    Navigator.of(context).pop(
      MilestoneSheetResult(changed: cubit.dirty, deleted: cubit.deleted),
    );
  }
}

/// The editable form. Rebuilt (via a `ValueKey` on the milestone version) each
/// time a save lands, so the controllers always start from stored truth rather
/// than drifting from it.
class _Editor extends StatefulWidget {
  const _Editor({required this.state, super.key});
  final MilestoneDetailLoaded state;

  @override
  State<_Editor> createState() => _EditorState();
}

class _EditorState extends State<_Editor> {
  late final TextEditingController _name = TextEditingController(
    text: widget.state.milestone.name,
  );
  late final TextEditingController _description = TextEditingController(
    text: widget.state.milestone.description,
  );
  late DateTime? _start = widget.state.milestone.startDate;
  late DateTime? _end = widget.state.milestone.endDate;
  late DateTime? _business = widget.state.milestone.businessReleaseDate;

  Milestone get _m => widget.state.milestone;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  /// Whether anything in the form differs from what is stored.
  bool get _dirty =>
      _name.text.trim() != _m.name ||
      _description.text != _m.description ||
      _start != _m.startDate ||
      _end != _m.endDate ||
      _business != _m.businessReleaseDate;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final detail = context.watch<ProjectDetailCubit>().state;
    final loaded = detail is ProjectDetailLoaded;
    final canModify = loaded && detail.has(Permission.milestoneModify);
    final canDelete = loaded && detail.has(Permission.milestoneDelete);
    final canSeeBusiness =
        loaded && detail.has(Permission.milestoneBusinessReleaseView);
    final canSetBusiness =
        loaded && detail.has(Permission.milestoneBusinessReleaseModify);
    final busy = widget.state.busy;

    return Column(
      children: [
        if (widget.state.error != null)
          _ErrorBanner(error: widget.state.error!),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            children: [
              _CompletionRow(
                completed: _m.closed,
                enabled: canModify && !busy,
                onChanged: (v) => context
                    .read<MilestoneDetailCubit>()
                    .setCompleted(completed: v),
              ),
              const SizedBox(height: 16),
              _ProgressCard(state: widget.state),
              const SizedBox(height: 20),
              TextField(
                controller: _name,
                enabled: canModify,
                decoration: InputDecoration(
                  labelText: t.milestoneFieldName,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              _DateRow(
                label: t.milestoneFieldStart,
                value: _start,
                enabled: canModify,
                onPick: (d) => setState(() => _start = d),
              ),
              _DateRow(
                label: t.milestoneFieldEnd,
                helper: t.milestoneTechnicalReleaseHint,
                value: _end,
                enabled: canModify,
                onPick: (d) => setState(() {
                  _end = d;
                  // A business release with no technical release behind it is
                  // rejected by the API — drop it here so the user sees the
                  // consequence rather than an error.
                  if (d == null ||
                      (_business != null && !_business!.isAfter(d))) {
                    _business = null;
                  }
                }),
              ),
              if (canSeeBusiness)
                _DateRow(
                  label: t.milestoneFieldBusinessRelease,
                  helper: t.milestoneBusinessReleaseHint,
                  value: _business,
                  enabled: canSetBusiness && _end != null,
                  firstDate: _end?.add(const Duration(days: 1)),
                  onPick: (d) => setState(() => _business = d),
                ),
              const SizedBox(height: 20),
              Text(
                t.milestoneFieldDescription,
                style: theme.textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              if (canModify)
                MarkdownEditor(
                  controller: _description,
                  minLines: 4,
                  onSubmitShortcut: _dirty && !busy ? _save : null,
                )
              else
                Text(
                  _m.description.isEmpty ? '—' : _m.description,
                  style: theme.textTheme.bodyMedium,
                ),
              const SizedBox(height: 24),
              _EpicsSection(state: widget.state, canManage: canModify),
              if (canDelete) ...[
                const SizedBox(height: 32),
                const Divider(),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: const Icon(Icons.delete_outline),
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ),
                    onPressed: busy ? null : _confirmDelete,
                    label: Text(t.actionDelete),
                  ),
                ),
              ],
            ],
          ),
        ),
        // Save bar: only present once something actually changed, so the
        // panel stays quiet while you are just reading.
        if (canModify && _dirty)
          Material(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Row(
                children: [
                  const Spacer(),
                  TextButton(
                    onPressed: busy ? null : _revert,
                    child: Text(t.actionCancel),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: busy ? null : _save,
                    child: Text(t.actionSave),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  void _revert() {
    setState(() {
      _name.text = _m.name;
      _description.text = _m.description;
      _start = _m.startDate;
      _end = _m.endDate;
      _business = _m.businessReleaseDate;
    });
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final canSetBusiness = () {
      final d = context.read<ProjectDetailCubit>().state;
      return d is ProjectDetailLoaded &&
          d.has(Permission.milestoneBusinessReleaseModify);
    }();
    await context.read<MilestoneDetailCubit>().save(
      UpdateMilestoneRequest(
        name: name == _m.name ? null : name,
        description: _description.text == _m.description
            ? null
            : _description.text,
        startDate: _start == _m.startDate
            ? UpdateMilestoneRequest.absent
            : _start,
        endDate: _end == _m.endDate ? UpdateMilestoneRequest.absent : _end,
        // Only ever send the business date when the user may set it, so a
        // read-only holder can save the rest of the form.
        businessReleaseDate:
            canSetBusiness && _business != _m.businessReleaseDate
            ? _business
            : UpdateMilestoneRequest.absent,
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final t = AppLocalizations.of(context);
    final cubit = context.read<MilestoneDetailCubit>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.milestoneDeleteTitle),
        content: Text(t.milestoneDeleteConfirm(_m.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.actionCancel),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t.actionDelete),
          ),
        ],
      ),
    );
    if (!(ok ?? false)) return;
    final removed = await cubit.delete();
    if (removed && mounted) {
      Navigator.of(context).pop(
        const MilestoneSheetResult(changed: true, deleted: true),
      );
    }
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.error});
  final MilestoneDetailError error;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final message = switch (error) {
      MilestoneDetailError.conflict => t.milestoneSaveConflict,
      MilestoneDetailError.hasEpics => t.milestoneDeleteBlocked,
      MilestoneDetailError.generic => t.milestoneSaveFailed,
    };
    return Container(
      width: double.infinity,
      color: theme.colorScheme.errorContainer,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Icon(
            Icons.error_outline,
            size: 18,
            color: theme.colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
          if (error == MilestoneDetailError.conflict)
            TextButton(
              onPressed: () => context.read<MilestoneDetailCubit>().load(),
              child: Text(t.actionRetry),
            ),
        ],
      ),
    );
  }
}

class _CompletionRow extends StatelessWidget {
  const _CompletionRow({
    required this.completed,
    required this.enabled,
    required this.onChanged,
  });
  final bool completed;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      color: completed
          ? theme.colorScheme.surfaceContainerHighest
          : theme.colorScheme.surfaceContainerLow,
      child: SwitchListTile(
        value: completed,
        onChanged: enabled ? onChanged : null,
        secondary: Icon(
          completed ? Icons.check_circle : Icons.outlined_flag,
          color: completed
              ? theme.colorScheme.tertiary
              : theme.colorScheme.primary,
        ),
        title: Text(t.milestoneCompletedLabel),
        subtitle: Text(
          completed ? t.milestoneCompletedHint : t.milestoneInProgressHint,
        ),
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.state});
  final MilestoneDetailLoaded state;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final s = state.stats;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            ProgressRing(
              value: state.epicProgress,
              size: 64,
              completed: state.milestone.closed,
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.milestoneStatTasks,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    '${s.completedTasks} / ${s.totalTasks}',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    t.milestoneStatPoints,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    '${s.completedPoints.toStringAsFixed(1)}'
                    ' / ${s.totalPoints.toStringAsFixed(1)}',
                    style: theme.textTheme.titleMedium,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateRow extends StatelessWidget {
  const _DateRow({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onPick,
    this.helper,
    this.firstDate,
  });
  final String label;
  final String? helper;
  final DateTime? value;
  final bool enabled;
  final DateTime? firstDate;
  final ValueChanged<DateTime?> onPick;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.labelLarge),
                if (helper != null)
                  Text(
                    helper!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          TextButton(
            onPressed: enabled ? () => _pick(context) : null,
            child: Text(
              value == null ? t.milestoneDateNotSet : isoDate(value!),
            ),
          ),
          IconButton(
            tooltip: t.actionClear,
            icon: const Icon(Icons.clear, size: 18),
            onPressed: enabled && value != null ? () => onPick(null) : null,
          ),
        ],
      ),
    );
  }

  Future<void> _pick(BuildContext context) async {
    final base = value ?? firstDate ?? DateTime.now();
    final lower = firstDate ?? DateTime(base.year - 5);
    final picked = await showDatePicker(
      context: context,
      initialDate: base.isBefore(lower) ? lower : base,
      firstDate: lower,
      lastDate: DateTime(base.year + 10),
    );
    if (picked != null) onPick(DateTime(picked.year, picked.month, picked.day));
  }
}

/// The epics composing this milestone, each with its readiness ring.
class _EpicsSection extends StatelessWidget {
  const _EpicsSection({required this.state, required this.canManage});
  final MilestoneDetailLoaded state;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final epics = state.epicsInMilestone;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.bookmarks_outlined, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(t.railEpics, style: theme.textTheme.titleMedium),
            ),
            if (canManage)
              TextButton.icon(
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: Text(t.milestoneManageEpics),
                onPressed: state.busy ? null : () => _manage(context),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (epics.isEmpty)
          Text(
            t.milestoneNoEpics,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          for (final e in epics)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  ProgressRing(
                    value: e.taskTotal == 0 ? null : e.taskClosed / e.taskTotal,
                    size: 40,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          e.subject,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                        Text(
                          t.milestoneEpicIssues(e.taskClosed, e.taskTotal),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }

  Future<void> _manage(BuildContext context) async {
    final t = AppLocalizations.of(context);
    final cubit = context.read<MilestoneDetailCubit>();
    final selected = {for (final e in state.epicsInMilestone) e.id};
    // Candidates: epics already here, plus every epic not claimed by another
    // milestone. An epic belongs to at most one milestone, so offering the
    // others would silently steal them.
    final candidates = state.allEpics
        .where(
          (e) => e.milestoneId == null || e.milestoneId == state.milestone.id,
        )
        .toList();
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(t.milestoneManageEpics),
          content: SizedBox(
            width: 440,
            child: candidates.isEmpty
                ? Text(t.epicsEmpty)
                : SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final e in candidates)
                          CheckboxListTile(
                            value: selected.contains(e.id),
                            controlAffinity: ListTileControlAffinity.leading,
                            title: Text(e.subject),
                            onChanged: (on) => setState(() {
                              if (on ?? false) {
                                selected.add(e.id);
                              } else {
                                selected.remove(e.id);
                              }
                            }),
                          ),
                      ],
                    ),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(t.actionCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(selected),
              child: Text(t.actionSave),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    await cubit.setEpics(result.toList());
  }
}
