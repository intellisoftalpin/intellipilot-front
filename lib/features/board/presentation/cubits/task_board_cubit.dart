// `_repo` / `_catalog` are intentionally private fields for clarity.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:intellipilot/core/work_items/work_item_filter.dart';
import 'package:intellipilot/features/backlog/data/dtos/backlog_dtos.dart';
import 'package:intellipilot/features/backlog/domain/backlog_repository.dart';
import 'package:intellipilot/features/catalog/data/dtos/catalog_dtos.dart';
import 'package:intellipilot/features/catalog/domain/catalog_repository.dart';
import 'package:intellipilot/features/milestones/data/dtos/milestone_dtos.dart';
import 'package:intellipilot/features/milestones/domain/milestones_repository.dart';

sealed class TaskBoardState extends Equatable {
  const TaskBoardState();
  @override
  List<Object?> get props => [];
}

class TaskBoardLoading extends TaskBoardState {
  const TaskBoardLoading();
}

class TaskBoardFailed extends TaskBoardState {
  const TaskBoardFailed();
}

/// Swimlane grouping dimensions for the board. `null` (the default) is the
/// flat single-board layout.
enum BoardGroupBy {
  component('component'),
  assignee('assignee'),
  epic('epic'),
  priority('priority');

  const BoardGroupBy(this.wire);
  final String wire;

  static BoardGroupBy? fromWire(String? wire) {
    if (wire == null) return null;
    for (final g in BoardGroupBy.values) {
      if (g.wire == wire) return g;
    }
    return null;
  }
}

class TaskBoardLoaded extends TaskBoardState {
  const TaskBoardLoaded({
    required this.statuses,
    required this.issues,
    required this.milestones,
    this.types = const [],
    this.priorities = const [],
    this.sizes = const [],
    this.epics = const [],
    this.labels = const [],
    this.components = const [],
    this.filter = const WorkItemFilter(),
    this.staleData = false,
    this.columnOrder = const [],
    this.hiddenColumnIds = const {},
    this.groupBy,
    this.savedViews = const [],
  });

  /// The `issue_status` taxonomy items, ordered — these are the board columns.
  final List<TaxonomyItem> statuses;

  /// All issues for the project.
  final List<Issue> issues;

  /// Project milestones / types / priorities / sizes / epics / labels /
  /// components — populate the shared filter bar.
  final List<Milestone> milestones;
  final List<TaxonomyItem> types;
  final List<TaxonomyItem> priorities;
  final List<TaxonomyItem> sizes;
  final List<Epic> epics;
  final List<Label> labels;
  final List<Component> components;

  /// Shared work-item filter (identical model to the Issues list).
  final WorkItemFilter filter;

  /// Set to true on a 409 from a move — UI surfaces a banner.
  final bool staleData;

  /// Full ordering of status ids for the board columns (a superset that may
  /// include hidden ones). Empty means "use the taxonomy default order".
  final List<String> columnOrder;

  /// Status ids hidden from the board.
  final Set<String> hiddenColumnIds;

  /// Active swimlane grouping, or null for the flat board.
  final BoardGroupBy? groupBy;

  /// The user's saved board views (server-backed).
  final List<BoardView> savedViews;

  TaskBoardLoaded copyWith({
    List<TaxonomyItem>? statuses,
    List<Issue>? issues,
    List<Milestone>? milestones,
    List<TaxonomyItem>? types,
    List<TaxonomyItem>? priorities,
    List<TaxonomyItem>? sizes,
    List<Epic>? epics,
    List<Label>? labels,
    List<Component>? components,
    WorkItemFilter? filter,
    bool? staleData,
    List<String>? columnOrder,
    Set<String>? hiddenColumnIds,
    Object? groupBy = _keepGroup,
    List<BoardView>? savedViews,
  }) => TaskBoardLoaded(
    statuses: statuses ?? this.statuses,
    issues: issues ?? this.issues,
    milestones: milestones ?? this.milestones,
    types: types ?? this.types,
    priorities: priorities ?? this.priorities,
    sizes: sizes ?? this.sizes,
    epics: epics ?? this.epics,
    labels: labels ?? this.labels,
    components: components ?? this.components,
    filter: filter ?? this.filter,
    staleData: staleData ?? this.staleData,
    columnOrder: columnOrder ?? this.columnOrder,
    hiddenColumnIds: hiddenColumnIds ?? this.hiddenColumnIds,
    groupBy: groupBy == _keepGroup ? this.groupBy : groupBy as BoardGroupBy?,
    savedViews: savedViews ?? this.savedViews,
  );

  static const _keepGroup = Object();

  /// The default column ordering for [statuses]: the `is_new` status first, the
  /// `is_closed` statuses last, the rest by their taxonomy `order` in between.
  static List<String> defaultColumnOrder(List<TaxonomyItem> statuses) {
    final sorted = [...statuses]
      ..sort((a, b) {
        int rank(TaxonomyItem s) {
          if (s.isNew ?? false) return 0;
          if (s.isClosed ?? false) return 2;
          return 1;
        }

        final ra = rank(a);
        final rb = rank(b);
        if (ra != rb) return ra.compareTo(rb);
        return a.order.compareTo(b.order);
      });
    return [for (final s in sorted) s.id];
  }

  /// Visible status columns, in the configured order. Falls back to the default
  /// ordering when no order is set, and appends any statuses missing from the
  /// stored order (e.g. created after a view was saved).
  List<TaxonomyItem> get orderedVisibleStatuses {
    final byId = {for (final s in statuses) s.id: s};
    final order = columnOrder.isEmpty
        ? defaultColumnOrder(statuses)
        : [
            ...columnOrder.where(byId.containsKey),
            for (final s in statuses)
              if (!columnOrder.contains(s.id)) s.id,
          ];
    return [
      for (final id in order)
        if (byId[id] != null && !hiddenColumnIds.contains(id)) byId[id]!,
    ];
  }

  Set<String> get _closedStatusIds => {
    for (final s in statuses)
      if (s.isClosed ?? false) s.id,
  };

  /// Top-level issues passing the active filter (board cards). Sub-tasks live
  /// under their parent and are not surfaced as cards.
  List<Issue> get visibleIssues {
    final closed = _closedStatusIds;
    return [
      for (final i in issues)
        if (i.parentId == null && filter.matches(i, closedStatusIds: closed)) i,
    ];
  }

  /// Buckets [items] by `statusId`. Columns always include the visible statuses
  /// (plus the trailing null column) so empty columns still render.
  Map<String?, List<Issue>> bucketFor(List<Issue> items) {
    final out = <String?, List<Issue>>{null: []};
    for (final s in orderedVisibleStatuses) {
      out[s.id] = [];
    }
    for (final t in items) {
      out.putIfAbsent(t.statusId, () => []).add(t);
    }
    for (final list in out.values) {
      list.sort((a, b) => a.order.compareTo(b.order));
    }
    return out;
  }

  /// Issues bucketed by `statusId`, after filters (the flat board).
  Map<String?, List<Issue>> get bucketed => bucketFor(visibleIssues);

  @override
  List<Object?> get props => [
    statuses,
    issues,
    milestones,
    types,
    priorities,
    sizes,
    epics,
    labels,
    components,
    filter,
    staleData,
    columnOrder,
    hiddenColumnIds,
    groupBy,
    savedViews,
  ];
}

class TaskBoardCubit extends Cubit<TaskBoardState> {
  TaskBoardCubit({
    required BacklogRepository repo,
    required CatalogRepository catalog,
    required MilestonesRepository milestones,
    required WorkItemFilterStore filterStore,
    required this.projectId,
  }) : _repo = repo,
       _catalog = catalog,
       _milestones = milestones,
       _filterStore = filterStore,
       _filter = filterStore.load(_view, projectId),
       super(const TaskBoardLoading());

  static const _view = 'board';

  final BacklogRepository _repo;
  final CatalogRepository _catalog;
  final MilestonesRepository _milestones;
  final WorkItemFilterStore _filterStore;
  final String projectId;
  WorkItemFilter _filter;

  WorkItemFilter get filter => _filter;

  // Board layout, kept in sync with state so it survives reloads (a card move
  // triggers `load()`). Restored from the per-user "last used" board on first
  // load, or from the taxonomy defaults when none is saved.
  List<String> _columnOrder = const [];
  Set<String> _hiddenColumnIds = const {};
  BoardGroupBy? _groupBy;
  List<BoardView> _savedViews = const [];
  bool _restored = false;

  Future<void> load() async {
    if (!isClosed) emit(const TaskBoardLoading());

    // On the very first load, restore the per-user last-used board + view list.
    if (!_restored) {
      _restored = true;
      final viewsRes = await _catalog.listBoardViews(projectId);
      _savedViews = viewsRes.valueOrNull ?? const [];
      final lastRes = await _catalog.getLastUsedBoard(projectId);
      final last = lastRes.valueOrNull;
      if (last != null) _readConfig(last);
    }

    final statusRes = await _catalog.listTaxonomy(
      projectId,
      TaxonomyKind.issueStatus,
    );
    final issueRes = await _repo.listIssues(projectId);
    final msRes = await _milestones.list(projectId);
    final epicRes = await _repo.listEpics(projectId);
    final labelRes = await _catalog.listLabels(projectId);
    final compRes = await _catalog.listComponents(projectId);
    final typeRes = await _catalog.listTaxonomy(
      projectId,
      TaxonomyKind.issueType,
    );
    final prioRes = await _catalog.listTaxonomy(
      projectId,
      TaxonomyKind.priority,
    );
    final sizeRes = await _catalog.listTaxonomy(projectId, TaxonomyKind.size);
    final statuses = statusRes.valueOrNull;
    final issues = issueRes.valueOrNull;
    if (statuses == null || issues == null) {
      if (!isClosed) emit(const TaskBoardFailed());
      return;
    }
    // Default the order to the taxonomy ordering when nothing was restored.
    if (_columnOrder.isEmpty) {
      _columnOrder = TaskBoardLoaded.defaultColumnOrder(statuses);
    }
    if (!isClosed) {
      emit(
        TaskBoardLoaded(
          statuses: statuses,
          issues: issues,
          milestones: msRes.valueOrNull ?? const [],
          types: typeRes.valueOrNull ?? const [],
          priorities: prioRes.valueOrNull ?? const [],
          sizes: sizeRes.valueOrNull ?? const [],
          epics: epicRes.valueOrNull ?? const [],
          labels: labelRes.valueOrNull ?? const [],
          components: compRes.valueOrNull ?? const [],
          filter: _filter,
          columnOrder: _columnOrder,
          hiddenColumnIds: _hiddenColumnIds,
          groupBy: _groupBy,
          savedViews: _savedViews,
        ),
      );
    }
  }

  void setFilter(WorkItemFilter f) {
    _filter = f;
    unawaited(_filterStore.save(_view, projectId, f));
    final s = state;
    if (s is TaskBoardLoaded) emit(s.copyWith(filter: f));
    unawaited(_persistLastUsed());
  }

  /// Show/hide and reorder the board columns. [order] is the full ordering of
  /// status ids; [hidden] the subset that should not render.
  void setColumns({required List<String> order, required Set<String> hidden}) {
    _columnOrder = order;
    _hiddenColumnIds = hidden;
    final s = state;
    if (s is TaskBoardLoaded) {
      emit(s.copyWith(columnOrder: order, hiddenColumnIds: hidden));
    }
    unawaited(_persistLastUsed());
  }

  /// Set (or clear, with null) the active swimlane grouping.
  void setGrouping(BoardGroupBy? groupBy) {
    _groupBy = groupBy;
    final s = state;
    if (s is TaskBoardLoaded) emit(s.copyWith(groupBy: groupBy));
    unawaited(_persistLastUsed());
  }

  /// Persist the current layout as a named, server-backed board view.
  Future<void> saveView(String name) async {
    final res = await _catalog.createBoardView(
      projectId,
      name,
      _currentConfig(),
    );
    final created = res.valueOrNull;
    if (created == null) return;
    _savedViews = [..._savedViews, created];
    final s = state;
    if (s is TaskBoardLoaded) emit(s.copyWith(savedViews: _savedViews));
  }

  /// Apply a saved view's config to the live board.
  void applyView(BoardView view) {
    _readConfig(view.config);
    final s = state;
    if (s is TaskBoardLoaded) {
      emit(
        s.copyWith(
          filter: _filter,
          columnOrder: _columnOrder,
          hiddenColumnIds: _hiddenColumnIds,
          groupBy: _groupBy,
        ),
      );
    }
    unawaited(_filterStore.save(_view, projectId, _filter));
    unawaited(_persistLastUsed());
  }

  /// Delete a saved view.
  Future<void> deleteView(String viewId) async {
    final res = await _catalog.deleteBoardView(projectId, viewId);
    if (res.isErr) return;
    _savedViews = [
      for (final v in _savedViews)
        if (v.id != viewId) v,
    ];
    final s = state;
    if (s is TaskBoardLoaded) emit(s.copyWith(savedViews: _savedViews));
  }

  /// The current board layout serialized for persistence. Round-trips via
  /// [_readConfig].
  Map<String, dynamic> _currentConfig() {
    final order = _columnOrder;
    final visible = [
      for (final id in order)
        if (!_hiddenColumnIds.contains(id)) id,
    ];
    return {
      'visible': visible,
      'order': order,
      'group': _groupBy?.wire,
      'filter': _filter.toJson(),
    };
  }

  /// Restore layout fields from a persisted config blob (best-effort).
  void _readConfig(Map<String, dynamic> config) {
    final order = (config['order'] as List<dynamic>?)
        ?.map((e) => e as String)
        .toList();
    final visible = (config['visible'] as List<dynamic>?)
        ?.map((e) => e as String)
        .toSet();
    if (order != null) _columnOrder = order;
    if (visible != null && order != null) {
      _hiddenColumnIds = {
        for (final id in order)
          if (!visible.contains(id)) id,
      };
    }
    _groupBy = BoardGroupBy.fromWire(config['group'] as String?);
    final filterJson = config['filter'];
    if (filterJson is Map<String, dynamic>) {
      _filter = WorkItemFilter.fromJson(filterJson);
    }
  }

  Future<void> _persistLastUsed() async {
    await _catalog.setLastUsedBoard(projectId, _currentConfig());
  }

  /// Optimistic move of an issue to a different `statusId`. On 409 we set
  /// `staleData = true` and reload to reconcile with the server.
  Future<void> moveTask({
    required String taskId,
    required String? targetStatusId,
  }) async {
    final s = state;
    if (s is! TaskBoardLoaded) return;
    final i = s.issues.indexWhere((t) => t.id == taskId);
    if (i < 0) return;
    final cur = s.issues[i];
    if (cur.statusId == targetStatusId) return;

    // Optimistic local swap.
    final optimistic = [...s.issues];
    optimistic[i] = Issue(
      id: cur.id,
      projectId: cur.projectId,
      reference: cur.reference,
      subject: cur.subject,
      description: cur.description,
      labels: cur.labels,
      components: cur.components,
      statusId: targetStatusId,
      typeId: cur.typeId,
      priorityId: cur.priorityId,
      sizeId: cur.sizeId,
      epicId: cur.epicId,
      parentId: cur.parentId,
      milestoneId: cur.milestoneId,
      ownerId: cur.ownerId,
      assignedTo: cur.assignedTo,
      order: cur.order,
      version: cur.version,
      createdAt: cur.createdAt,
      modifiedAt: cur.modifiedAt,
      etag: cur.etag,
    );
    emit(s.copyWith(issues: optimistic, staleData: false));

    // Fetch fresh issue to get a current ETag before PATCH.
    final freshRes = await _repo.getIssue(projectId, taskId);
    final fresh = freshRes.valueOrNull;
    if (fresh == null || fresh.etag == null) {
      await load();
      return;
    }
    final patch = await _repo.updateIssue(
      projectId,
      taskId,
      body: UpdateIssueRequest(statusId: targetStatusId),
      etag: fresh.etag!,
    );
    final updated = patch.valueOrNull;
    if (updated == null) {
      if (!isClosed) emit(s.copyWith(staleData: true));
      await load();
      return;
    }
    final cur2 = state;
    if (cur2 is! TaskBoardLoaded) return;
    final j = cur2.issues.indexWhere((t) => t.id == taskId);
    if (j < 0) return;
    final next = [...cur2.issues];
    next[j] = updated;
    emit(cur2.copyWith(issues: next));
  }
}
