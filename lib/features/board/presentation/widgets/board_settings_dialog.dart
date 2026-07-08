import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/router/app_router.dart';
import 'package:intellipilot/core/models/user_ref.dart';
import 'package:intellipilot/core/widgets/members_scope.dart';
import 'package:intellipilot/core/work_items/work_item_filter.dart';
import 'package:intellipilot/core/work_items/work_item_filter_bar.dart';
import 'package:intellipilot/features/backlog/data/dtos/backlog_dtos.dart';
import 'package:intellipilot/features/backlog/domain/backlog_repository.dart';
import 'package:intellipilot/features/board/domain/board_config.dart';
import 'package:intellipilot/features/board/presentation/boards_nav_refresh.dart';
import 'package:intellipilot/features/board/presentation/widgets/board_columns_dialog.dart';
import 'package:intellipilot/features/catalog/data/dtos/catalog_dtos.dart';
import 'package:intellipilot/features/catalog/domain/catalog_repository.dart';
import 'package:intellipilot/features/catalog/presentation/widgets/color_swatch_picker.dart';
import 'package:intellipilot/features/milestones/data/dtos/milestone_dtos.dart';
import 'package:intellipilot/features/milestones/domain/milestones_repository.dart';
import 'package:intellipilot/features/profile/domain/profile_repository.dart';
import 'package:intellipilot/features/projects/data/dtos/project_dtos.dart';
import 'package:intellipilot/features/projects/domain/permission.dart';
import 'package:intellipilot/features/projects/domain/projects_repository.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// The card fields a board may surface on each card.
const List<String> _cardFieldKeys = [
  'assignee',
  'priority',
  'size',
  'labels',
  'due',
  'release',
];

/// Opens the board create/edit dialog. [board] null → create. Performs the
/// create/update itself and returns the resulting [Board] (null if cancelled).
/// When [canDelete] is true and editing an existing board, a "Danger zone"
/// delete action is shown; deleting closes the dialog and navigates away.
Future<Board?> showBoardSettingsDialog(
  BuildContext context, {
  required String projectId,
  Board? board,
  bool canDelete = false,
}) {
  return showDialog<Board>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _BoardSettingsDialog(
      projectId: projectId,
      board: board,
      canDelete: canDelete,
    ),
  );
}

class _DialogData {
  const _DialogData({
    required this.statuses,
    required this.types,
    required this.priorities,
    required this.sizes,
    required this.epics,
    required this.labels,
    required this.components,
    required this.milestones,
    required this.members,
    required this.canShare,
  });

  final List<TaxonomyItem> statuses;
  final List<TaxonomyItem> types;
  final List<TaxonomyItem> priorities;
  final List<TaxonomyItem> sizes;
  final List<Epic> epics;
  final List<Label> labels;
  final List<Component> components;
  final List<Milestone> milestones;
  final Map<String, UserRef> members;
  final bool canShare;
}

class _BoardSettingsDialog extends StatefulWidget {
  const _BoardSettingsDialog({
    required this.projectId,
    this.board,
    this.canDelete = false,
  });
  final String projectId;
  final Board? board;
  final bool canDelete;

  @override
  State<_BoardSettingsDialog> createState() => _BoardSettingsDialogState();
}

class _BoardSettingsDialogState extends State<_BoardSettingsDialog> {
  late final Future<_DialogData> _future = _load();

  Future<_DialogData> _load() async {
    final catalog = getIt<CatalogRepository>();
    final backlog = getIt<BacklogRepository>();
    final milestones = getIt<MilestonesRepository>();
    final projects = getIt<ProjectsRepository>();
    final pid = widget.projectId;

    final statuses =
        (await catalog.listTaxonomy(
          pid,
          TaxonomyKind.issueStatus,
        )).valueOrNull ??
        const [];
    final types =
        (await catalog.listTaxonomy(pid, TaxonomyKind.issueType)).valueOrNull ??
        const [];
    final priorities =
        (await catalog.listTaxonomy(pid, TaxonomyKind.priority)).valueOrNull ??
        const [];
    final sizes =
        (await catalog.listTaxonomy(pid, TaxonomyKind.size)).valueOrNull ??
        const [];
    final epics = (await backlog.listEpics(pid)).valueOrNull ?? const [];
    final labels = (await catalog.listLabels(pid)).valueOrNull ?? const [];
    final components =
        (await catalog.listComponents(pid)).valueOrNull ?? const [];
    final ms = (await milestones.list(pid)).valueOrNull ?? const [];
    final memberList =
        (await projects.listMembers(pid)).valueOrNull ?? const [];
    final members = {for (final m in memberList) m.userId: m.toRef()};

    // Visibility is fixed at creation; only resolve the shared-create
    // permission when creating a new board.
    var canShare = false;
    if (widget.board == null) {
      final profile =
          (await getIt<ProfileRepository>().getProfile()).valueOrNull;
      final roles = (await projects.listRoles(pid)).valueOrNull ?? const [];
      Membership? mine;
      for (final m in memberList) {
        if (m.userId == profile?.id) {
          mine = m;
          break;
        }
      }
      if (mine != null) {
        for (final r in roles) {
          if (r.id == mine.roleId) {
            canShare =
                r.isAdmin ||
                r.permissions.contains(Permission.boardSharedCreate);
            break;
          }
        }
      }
    }

    return _DialogData(
      statuses: statuses,
      types: types,
      priorities: priorities,
      sizes: sizes,
      epics: epics,
      labels: labels,
      components: components,
      milestones: ms,
      members: members,
      canShare: canShare,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_DialogData>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Dialog(
            child: SizedBox(
              width: 520,
              height: 200,
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        final data = snap.data;
        if (data == null) {
          return AlertDialog(
            content: Text(AppLocalizations.of(context).errUnknown),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(AppLocalizations.of(context).actionCancel),
              ),
            ],
          );
        }
        return _BoardSettingsForm(
          projectId: widget.projectId,
          board: widget.board,
          data: data,
          canDelete: widget.canDelete,
        );
      },
    );
  }
}

class _BoardSettingsForm extends StatefulWidget {
  const _BoardSettingsForm({
    required this.projectId,
    required this.board,
    required this.data,
    this.canDelete = false,
  });
  final String projectId;
  final Board? board;
  final _DialogData data;
  final bool canDelete;

  @override
  State<_BoardSettingsForm> createState() => _BoardSettingsFormState();
}

class _BoardSettingsFormState extends State<_BoardSettingsForm> {
  late final TextEditingController _name;
  late final TextEditingController _closedWithin;
  late String _color;
  late bool _shared;
  late List<String> _columnOrder;
  late Set<String> _hidden;
  late BoardGroupBy? _group;
  late WorkItemFilter _lockedFilter;
  late Set<String> _cardFields;
  late int _columnLimit;
  bool _saving = false;

  bool get _isCreate => widget.board == null;

  @override
  void initState() {
    super.initState();
    final board = widget.board;
    final cfg = board == null
        ? BoardConfig.defaults(widget.data.statuses)
        : BoardConfig.fromMap(board.config);
    _name = TextEditingController(text: board?.name ?? '');
    _closedWithin = TextEditingController(
      text: cfg.closedWithinDays?.toString() ?? '',
    );
    _color = board?.color ?? '';
    _shared = false;
    _columnOrder = cfg.columnOrder.isEmpty
        ? BoardConfig.defaultColumnOrder(widget.data.statuses)
        : [...cfg.columnOrder];
    _hidden = {...cfg.hiddenColumnIds};
    _group = cfg.group;
    _lockedFilter = cfg.filters;
    _cardFields = {
      ...(cfg.cardFields ?? const ['assignee']),
    };
    _columnLimit = cfg.columnLimit;
  }

  @override
  void dispose() {
    _name.dispose();
    _closedWithin.dispose();
    super.dispose();
  }

  BoardConfig _buildConfig() {
    final visible = [
      for (final id in _columnOrder)
        if (!_hidden.contains(id)) id,
    ];
    final days = int.tryParse(_closedWithin.text.trim());
    return BoardConfig(
      columnOrder: _columnOrder,
      visibleColumnIds: visible,
      group: _group,
      filters: _lockedFilter,
      columnLimit: _columnLimit,
      closedWithinDays: days,
      cardFields: _cardFields.toList(),
    );
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);
    final catalog = getIt<CatalogRepository>();
    final config = _buildConfig().toMap();
    final res = _isCreate
        ? await catalog.createBoard(
            widget.projectId,
            name: name,
            color: _color,
            shared: _shared,
            config: config,
          )
        : await catalog.updateBoard(
            widget.projectId,
            widget.board!.id,
            name: name,
            color: _color,
            config: config,
          );
    if (!mounted) return;
    final saved = res.valueOrNull;
    if (saved == null) {
      setState(() => _saving = false);
      final t = AppLocalizations.of(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(t.errUnknown)));
      return;
    }
    Navigator.of(context).pop(saved);
  }

  Future<void> _delete() async {
    final t = AppLocalizations.of(context);
    final board = widget.board;
    if (board == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.boardDeleteTitle),
        content: Text(t.boardDeleteConfirm(board.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t.actionDelete),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _saving = true);
    final res = await getIt<CatalogRepository>().deleteBoard(
      widget.projectId,
      board.id,
    );
    if (!mounted) return;
    if (res.isErr) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(t.errUnknown)));
      return;
    }
    bumpBoardsNav();
    // Capture the router before popping; navigate the underlying page to the
    // board resolver, which redirects to another board (or the empty state).
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.go(Routes.projectBoardFor(widget.projectId));
  }

  Future<void> _editColumns() async {
    final res = await showBoardColumnsDialog(
      context,
      statuses: widget.data.statuses,
      order: _columnOrder,
      hidden: _hidden,
    );
    if (res != null) {
      setState(() {
        _columnOrder = res.order;
        _hidden = res.hidden;
      });
    }
  }

  String _groupLabel(BoardGroupBy? g, AppLocalizations t) => switch (g) {
    null => t.boardGroupNone,
    BoardGroupBy.component => t.issueFieldComponents,
    BoardGroupBy.assignee => t.issueFieldAssignee,
    BoardGroupBy.epic => t.detailFieldEpic,
    BoardGroupBy.priority => t.issueFieldPriority,
  };

  String _cardFieldLabel(String key, AppLocalizations t) => switch (key) {
    'assignee' => t.issueFieldAssignee,
    'priority' => t.issueFieldPriority,
    'size' => t.detailFieldPoints,
    'labels' => t.issueFieldLabels,
    'due' => t.boardCardFieldDue,
    'release' => 'Release',
    _ => key,
  };

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final visibleCount = _columnOrder
        .where((id) => !_hidden.contains(id))
        .length;

    return AlertDialog(
      title: Text(_isCreate ? t.boardCreateTitle : t.boardEditTitle),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _name,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: t.boardFieldName,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Text(t.boardFieldColor, style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              ColorSwatchPicker(
                selectedHex: _color,
                onChanged: (hex) => setState(() => _color = hex),
              ),
              if (_isCreate && widget.data.canShare) ...[
                const SizedBox(height: 8),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _shared,
                  onChanged: (v) => setState(() => _shared = v ?? false),
                  title: Text(t.boardFieldShared),
                  subtitle: Text(t.boardFieldSharedHint),
                ),
              ],
              const Divider(height: 24),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.view_column_outlined),
                title: Text(t.boardColumnsLabel),
                subtitle: Text(t.boardColumnsVisible(visibleCount)),
                trailing: TextButton(
                  onPressed: _editColumns,
                  child: Text(t.actionConfigure),
                ),
              ),
              const SizedBox(height: 8),
              Text(t.boardFieldSwimlane, style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final g in <BoardGroupBy?>[null, ...BoardGroupBy.values])
                    ChoiceChip(
                      label: Text(_groupLabel(g, t)),
                      selected: _group == g,
                      onSelected: (_) => setState(() => _group = g),
                    ),
                ],
              ),
              const Divider(height: 24),
              Text(
                t.boardFieldLockedFilters,
                style: theme.textTheme.labelLarge,
              ),
              Text(
                t.boardFieldLockedFiltersHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
              const SizedBox(height: 4),
              MembersScope(
                membersById: widget.data.members,
                child: WorkItemFilterBar(
                  filter: _lockedFilter,
                  onChanged: (f) => setState(() => _lockedFilter = f),
                  statuses: widget.data.statuses,
                  types: widget.data.types,
                  priorities: widget.data.priorities,
                  sizes: widget.data.sizes,
                  epics: widget.data.epics,
                  milestones: widget.data.milestones,
                  labels: widget.data.labels,
                  components: widget.data.components,
                  showStatus: false,
                  hiddenDimensions: {?_group?.filterKey},
                ),
              ),
              const Divider(height: 24),
              Text(t.boardFieldCardFields, style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final key in _cardFieldKeys)
                    FilterChip(
                      label: Text(_cardFieldLabel(key, t)),
                      selected: _cardFields.contains(key),
                      onSelected: (v) => setState(() {
                        if (v) {
                          _cardFields.add(key);
                        } else {
                          _cardFields.remove(key);
                        }
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _closedWithin,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: t.boardFieldClosedWithin,
                  helperText: t.boardFieldClosedWithinHint,
                  border: const OutlineInputBorder(),
                ),
              ),
              if (!_isCreate && widget.canDelete) ...[
                const Divider(height: 24),
                Text(
                  t.boardDangerZone,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
                Text(
                  t.boardDangerZoneHint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _saving ? null : _delete,
                    icon: const Icon(Icons.delete_outline),
                    label: Text(t.boardDeleteTitle),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                      side: BorderSide(color: theme.colorScheme.error),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(t.actionCancel),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_isCreate ? t.actionCreate : t.actionSave),
        ),
      ],
    );
  }
}
