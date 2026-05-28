import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/core/storage/hive_boxes.dart';
import 'package:intellipilot/features/board/presentation/cubits/board_cubit.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// Opens a modal that lets the user save the current filter / milestone as a
/// named view, list existing ones, and apply or delete them. Storage is
/// per-project under `views:<projectId>` in [HiveBoxes.boards].
Future<void> openSavedViewsMenu(
  BuildContext context,
  BoardLoaded state,
) async {
  final cubit = context.read<BoardCubit>();
  await showDialog<void>(
    context: context,
    builder: (ctx) => _SavedViewsDialog(state: state, parentCubit: cubit),
  );
}

class SavedView {
  const SavedView({
    required this.name,
    required this.milestoneId,
    required this.search,
    this.assignee,
  });

  factory SavedView.fromJson(Map<dynamic, dynamic> json) => SavedView(
    name: (json['name'] as String?) ?? '',
    milestoneId: (json['milestone_id'] as String?) ?? '',
    search: (json['search'] as String?) ?? '',
    assignee: json['assignee'] as String?,
  );

  final String name;
  final String milestoneId;
  final String search;
  final String? assignee;

  Map<String, dynamic> toJson() => {
    'name': name,
    'milestone_id': milestoneId,
    'search': search,
    if (assignee != null) 'assignee': assignee,
  };
}

class _SavedViewsDialog extends StatefulWidget {
  const _SavedViewsDialog({required this.state, required this.parentCubit});
  final BoardLoaded state;
  final BoardCubit parentCubit;

  @override
  State<_SavedViewsDialog> createState() => _SavedViewsDialogState();
}

class _SavedViewsDialogState extends State<_SavedViewsDialog> {
  late final KeyValueStorage _store;
  late String _key;
  late List<SavedView> _views;
  final _nameCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _store = getIt<KeyValueStorage>(instanceName: HiveBoxes.boards);
    _key = 'views:${widget.parentCubit.projectId}';
    _views = _read();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  List<SavedView> _read() {
    final raw = _store.get<List<dynamic>>(_key);
    if (raw == null) return [];
    return raw
        .whereType<Map<dynamic, dynamic>>()
        .map(SavedView.fromJson)
        .toList();
  }

  Future<void> _write(List<SavedView> next) async {
    await _store.set<List<dynamic>>(
      _key,
      next.map((v) => v.toJson()).toList(),
    );
    setState(() => _views = next);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(t.boardSavedViewsTitle),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _nameCtrl,
                    decoration: InputDecoration(
                      hintText: t.boardSavedViewNameHint,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  icon: const Icon(Icons.save_outlined),
                  onPressed: () async {
                    final name = _nameCtrl.text.trim();
                    if (name.isEmpty) return;
                    final view = SavedView(
                      name: name,
                      milestoneId: widget.state.milestoneId,
                      search: widget.state.filter.search,
                      assignee: widget.state.filter.assignee,
                    );
                    final next = _views.where((v) => v.name != name).toList()
                      ..add(view);
                    await _write(next);
                    _nameCtrl.clear();
                  },
                  label: Text(t.actionSave),
                ),
              ],
            ),
            const Divider(height: 16),
            if (_views.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  t.boardSavedViewsEmpty,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ),
            for (final v in _views)
              ListTile(
                dense: true,
                title: Text(v.name),
                subtitle: Text(
                  [
                    if (v.search.isNotEmpty) '"${v.search}"',
                    if (v.assignee != null) v.assignee!,
                  ].join(' · '),
                ),
                leading: const Icon(Icons.bookmark_outline),
                onTap: () {
                  Navigator.of(context).pop();
                  widget.parentCubit.setFilter(
                    BoardFilter(
                      search: v.search,
                      assignee: v.assignee,
                    ),
                  );
                  unawaited(
                    widget.parentCubit.switchMilestone(v.milestoneId),
                  );
                },
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: AppLocalizations.of(context).actionDelete,
                  onPressed: () async {
                    final next =
                        _views.where((x) => x.name != v.name).toList();
                    await _write(next);
                  },
                ),
              ),
          ],
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
