import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/core/io/file_picker.dart';
import 'package:intellipilot/core/io/url_opener.dart';
import 'package:intellipilot/core/ui/markdown_text.dart';
import 'package:intellipilot/core/ui/timestamps.dart';
import 'package:intellipilot/core/widgets/user_avatar.dart';
import 'package:intellipilot/features/activity/data/dtos/activity_dtos.dart';
import 'package:intellipilot/features/activity/domain/activity_repository.dart';
import 'package:intellipilot/features/activity/presentation/cubits/activity_stream_cubit.dart';
import 'package:intellipilot/features/activity/presentation/widgets/comment_composer.dart';
import 'package:intellipilot/features/projects/domain/permission.dart';
import 'package:intellipilot/features/projects/presentation/cubits/project_detail_cubit.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// Activity tab: filter chips + merged comments/history list + composer.
///
/// Set [shrinkWrap] to true when embedding inside a `SingleChildScrollView`
/// (e.g. the Jira-style entity detail page). In that mode entries render as
/// a `Column` of rows that sizes to content rather than the default
/// `Expanded(ListView)` fill-parent layout.
class ActivityStreamView extends StatelessWidget {
  const ActivityStreamView({
    required this.draftKey,
    this.shrinkWrap = false,
    super.key,
  });

  /// Unique key per (entity kind + entity id) used by [CommentComposer] for
  /// draft autosave.
  final String draftKey;
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return BlocBuilder<ActivityStreamCubit, ActivityStreamState>(
      builder: (context, state) {
        if (state is ActivityStreamLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state is ActivityStreamFailed) {
          return Center(child: Text(t.activityLoadFailed));
        }
        if (state is! ActivityStreamLoaded) return const SizedBox.shrink();
        if (shrinkWrap) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _FilterBar(filter: state.filter),
              const Divider(height: 1),
              if (state.entries.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text(t.activityEmpty)),
                )
              else
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final entry in state.entries)
                        if (entry.isComment)
                          _CommentRow(comment: entry.comment!)
                        else
                          _HistoryRow(event: entry.history!),
                    ],
                  ),
                ),
              _ComposerGate(draftKey: draftKey, busy: state.busy),
            ],
          );
        }
        return Column(
          children: [
            _FilterBar(filter: state.filter),
            const Divider(height: 1),
            Expanded(
              child: state.entries.isEmpty
                  ? Center(child: Text(t.activityEmpty))
                  : _Stream(entries: state.entries),
            ),
            _ComposerGate(draftKey: draftKey, busy: state.busy),
          ],
        );
      },
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.filter});
  final ActivityFilter filter;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SegmentedButton<ActivityFilter>(
        segments: [
          ButtonSegment(
            value: ActivityFilter.all,
            label: Text(t.activityFilterAll),
          ),
          ButtonSegment(
            value: ActivityFilter.comments,
            label: Text(t.activityFilterComments),
          ),
          ButtonSegment(
            value: ActivityFilter.history,
            label: Text(t.activityFilterHistory),
          ),
        ],
        selected: {filter},
        onSelectionChanged: (s) =>
            context.read<ActivityStreamCubit>().setFilter(s.first),
      ),
    );
  }
}

class _Stream extends StatelessWidget {
  const _Stream({required this.entries});
  final List<ActivityEntry> entries;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final entry = entries[i];
        if (entry.isComment) {
          return _CommentRow(comment: entry.comment!);
        }
        return _HistoryRow(event: entry.history!);
      },
    );
  }
}

class _CommentRow extends StatelessWidget {
  const _CommentRow({required this.comment});
  final Comment comment;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final detailState = context.watch<ProjectDetailCubit>().state;
    final canModerate = detailState is ProjectDetailLoaded &&
        detailState.has(Permission.commentModerate);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (comment.author != null)
                  UserAvatar(user: comment.author!, size: 24)
                else
                  Icon(
                    Icons.account_circle_outlined,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    comment.author != null
                        ? '${comment.author!.displayName} · '
                              '${formatTimestamp(context, comment.createdAt)}'
                        : formatTimestamp(context, comment.createdAt),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                if (comment.editedAt != null)
                  Text(
                    t.commentEditedSuffix,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                if (canModerate) ...[
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _edit(context),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _delete(context),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            MarkdownText(comment.body),
            const SizedBox(height: 6),
            _CommentAttachments(
              projectId: context.read<ActivityStreamCubit>().projectId,
              commentId: comment.id,
              canEdit: canModerate,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context) async {
    final t = AppLocalizations.of(context);
    final cubit = context.read<ActivityStreamCubit>();
    final ctrl = TextEditingController(text: comment.body);
    final updated = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.commentEditTitle),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 6,
          minLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(t.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text),
            child: Text(t.actionSave),
          ),
        ],
      ),
    );
    if (updated == null) return;
    await cubit.editComment(comment.id, updated);
  }

  Future<void> _delete(BuildContext context) async {
    final t = AppLocalizations.of(context);
    final cubit = context.read<ActivityStreamCubit>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.commentDeleteTitle),
        content: Text(t.commentDeleteConfirm),
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
    if (ok ?? false) {
      await cubit.removeComment(comment.id);
    }
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.event});
  final HistoryEvent event;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final fields = event.diff.keys.toList();
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.history_toggle_off,
                  size: 18,
                  color: theme.colorScheme.outline,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    formatTimestamp(context, event.createdAt),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              t.historyEntryHeader(fields.length),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            for (final f in fields) _DiffRow(field: f, change: event.diff[f]),
          ],
        ),
      ),
    );
  }
}

class _DiffRow extends StatelessWidget {
  const _DiffRow({required this.field, required this.change});
  final String field;
  final Object? change;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final raw = change;
    final pair = raw is List<dynamic> && raw.length == 2 ? raw : null;
    final from = pair?[0]?.toString() ?? '—';
    final to = pair?[1]?.toString() ?? '—';
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('$field: ', style: theme.textTheme.bodySmall),
          Text(
            from,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
              decoration: TextDecoration.lineThrough,
            ),
          ),
          Text(
            '  →  ',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          Text(to, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _ComposerGate extends StatelessWidget {
  const _ComposerGate({required this.draftKey, required this.busy});
  final String draftKey;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ProjectDetailCubit>().state;
    final canComment =
        state is ProjectDetailLoaded && state.has(Permission.commentCreate);
    if (!canComment) return const SizedBox.shrink();
    return CommentComposer(draftKey: draftKey, busy: busy);
  }
}

/// Compact comment-level attachment strip. Reuses the attachment endpoints
/// pointed at the `comments/{id}/attachments` path. Lists existing files,
/// uploads via the file picker, and opens a signed download URL on tap.
class _CommentAttachments extends StatefulWidget {
  const _CommentAttachments({
    required this.projectId,
    required this.commentId,
    required this.canEdit,
  });

  final String projectId;
  final String commentId;
  final bool canEdit;

  @override
  State<_CommentAttachments> createState() => _CommentAttachmentsState();
}

class _CommentAttachmentsState extends State<_CommentAttachments> {
  late Future<List<Attachment>> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Attachment>> _load() async {
    final res = await getIt<ActivityRepository>()
        .listCommentAttachments(widget.projectId, widget.commentId);
    return res.valueOrNull ?? <Attachment>[];
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _open(Attachment a) async {
    final res = await getIt<ActivityRepository>()
        .signAttachmentUrl(widget.projectId, a.id);
    final signed = res.valueOrNull;
    if (signed != null) openExternalUrl(signed.url);
  }

  Future<void> _upload() async {
    final picked = await getIt<FilePicker>().pickSingleFile();
    if (picked == null) return;
    setState(() => _busy = true);
    await getIt<ActivityRepository>().uploadCommentAttachment(
      widget.projectId,
      widget.commentId,
      filename: picked.name,
      bytes: picked.bytes,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    _reload();
  }

  Future<void> _delete(Attachment a) async {
    await getIt<ActivityRepository>().deleteAttachment(widget.projectId, a.id);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<List<Attachment>>(
      future: _future,
      builder: (context, snap) {
        final items = snap.data ?? const <Attachment>[];
        if (items.isEmpty && !widget.canEdit) return const SizedBox.shrink();
        return Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final a in items)
              InputChip(
                avatar: const Icon(Icons.attach_file, size: 14),
                label: Text(a.filename),
                onPressed: () => _open(a),
                onDeleted: widget.canEdit ? () => _delete(a) : null,
                deleteIcon:
                    widget.canEdit ? const Icon(Icons.close, size: 14) : null,
                visualDensity: VisualDensity.compact,
              ),
            if (widget.canEdit)
              TextButton.icon(
                icon: _busy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.attach_file, size: 16),
                label: Text(
                  'Attach',
                  style: theme.textTheme.bodySmall,
                ),
                onPressed: _busy ? null : _upload,
              ),
          ],
        );
      },
    );
  }
}
