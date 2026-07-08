// `_repo` / `_catalog` are intentionally private fields for clarity.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:intellipilot/core/work_items/work_item_filter.dart';
import 'package:intellipilot/features/backlog/data/dtos/backlog_dtos.dart';
import 'package:intellipilot/features/backlog/domain/backlog_repository.dart';
import 'package:intellipilot/features/board/domain/board_config.dart';
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

class TaskBoardLoaded extends TaskBoardState {
  const TaskBoardLoaded({
    required this.board,
    required this.config,
    required this.statuses,
    required this.flatColumns,
    required this.lanes,
    required this.milestones,
    this.types = const [],
    this.priorities = const [],
    this.sizes = const [],
    this.epics = const [],
    this.labels = const [],
    this.components = const [],
    this.releaseVersions = const [],
    this.adhocFilter = const WorkItemFilter(),
    this.staleData = false,
  });

  /// The board being rendered (its `config` drives columns/group/filters).
  final Board board;
  final BoardConfig config;

  /// The `issue_status` taxonomy items — column headers + name resolution.
  final List<TaxonomyItem> statuses;

  /// Ordered per-column data for the flat board (includes the trailing
  /// no-status column when present). Empty when the board is grouped.
  final List<BoardColumnData> flatColumns;

  /// Ordered swimlanes for a grouped board (each lane's columns are ordered to
  /// match the visible column order). Empty when the board is flat.
  final List<BoardLaneData> lanes;

  /// Project taxonomy populating the shared filter bar + card chips.
  final List<Milestone> milestones;
  final List<TaxonomyItem> types;
  final List<TaxonomyItem> priorities;
  final List<TaxonomyItem> sizes;
  final List<Epic> epics;
  final List<Label> labels;
  final List<Component> components;

  /// Every release version in the project, enriched with its parent
  /// release's name and color — resolves each card's fix-version badge.
  final List<ReleaseVersionRef> releaseVersions;

  /// The user's transient ad-hoc filter (session-only, not persisted). The
  /// board's locked filters always win over these.
  final WorkItemFilter adhocFilter;

  /// Set when a move hit a 409 — UI surfaces a banner.
  final bool staleData;

  BoardGroupBy? get group => config.group;

  /// Locked + ad-hoc merged (locked win), with the swimlane group dimension
  /// stripped — what's effectively shown in the filter bar.
  WorkItemFilter get effectiveFilter {
    final merged = WorkItemFilter.fromJson({
      ...adhocFilter.toJson(),
      ...config.filters.toJson(),
    });
    final g = config.group;
    if (g == null) return merged;
    final j = merged.toJson()..remove(g.filterKey);
    return WorkItemFilter.fromJson(j);
  }

  TaskBoardLoaded copyWith({
    Board? board,
    BoardConfig? config,
    List<TaxonomyItem>? statuses,
    List<BoardColumnData>? flatColumns,
    List<BoardLaneData>? lanes,
    List<Milestone>? milestones,
    List<TaxonomyItem>? types,
    List<TaxonomyItem>? priorities,
    List<TaxonomyItem>? sizes,
    List<Epic>? epics,
    List<Label>? labels,
    List<Component>? components,
    List<ReleaseVersionRef>? releaseVersions,
    WorkItemFilter? adhocFilter,
    bool? staleData,
  }) => TaskBoardLoaded(
    board: board ?? this.board,
    config: config ?? this.config,
    statuses: statuses ?? this.statuses,
    flatColumns: flatColumns ?? this.flatColumns,
    lanes: lanes ?? this.lanes,
    milestones: milestones ?? this.milestones,
    types: types ?? this.types,
    priorities: priorities ?? this.priorities,
    sizes: sizes ?? this.sizes,
    epics: epics ?? this.epics,
    labels: labels ?? this.labels,
    components: components ?? this.components,
    releaseVersions: releaseVersions ?? this.releaseVersions,
    adhocFilter: adhocFilter ?? this.adhocFilter,
    staleData: staleData ?? this.staleData,
  );

  @override
  List<Object?> get props => [
    board.id,
    config.toMap(),
    statuses,
    flatColumns,
    lanes,
    milestones,
    types,
    priorities,
    sizes,
    epics,
    labels,
    components,
    releaseVersions,
    adhocFilter,
    staleData,
  ];
}

class TaskBoardCubit extends Cubit<TaskBoardState> {
  TaskBoardCubit({
    required BacklogRepository repo,
    required CatalogRepository catalog,
    required MilestonesRepository milestones,
    required this.projectId,
    required this.boardId,
  }) : _repo = repo,
       _catalog = catalog,
       _milestones = milestones,
       super(const TaskBoardLoading());

  final BacklogRepository _repo;
  final CatalogRepository _catalog;
  final MilestonesRepository _milestones;
  final String projectId;
  final String boardId;

  // Cached after the first full load so data-only refetches (filter changes,
  // card moves) don't re-pull the whole taxonomy.
  Board? _board;
  BoardConfig _config = const BoardConfig();
  List<TaxonomyItem> _statuses = const [];
  List<TaxonomyItem> _types = const [];
  List<TaxonomyItem> _priorities = const [];
  List<TaxonomyItem> _sizes = const [];
  List<Epic> _epics = const [];
  List<Label> _labels = const [];
  List<Component> _components = const [];
  List<ReleaseVersionRef> _releaseVersions = const [];
  List<Milestone> _milestonesList = const [];
  WorkItemFilter _adhoc = const WorkItemFilter();

  /// Full load: board + config + taxonomy, then board data.
  Future<void> load() async {
    if (!isClosed) emit(const TaskBoardLoading());

    final boardRes = await _catalog.getBoard(projectId, boardId);
    final board = boardRes.valueOrNull;
    if (board == null) {
      if (!isClosed) emit(const TaskBoardFailed());
      return;
    }
    _board = board;
    _config = BoardConfig.fromMap(board.config);
    unawaited(_catalog.setLastOpenedBoard(projectId, boardId));

    final statusRes = await _catalog.listTaxonomy(
      projectId,
      TaxonomyKind.issueStatus,
    );
    final statuses = statusRes.valueOrNull;
    if (statuses == null) {
      if (!isClosed) emit(const TaskBoardFailed());
      return;
    }
    _statuses = statuses;
    _types =
        (await _catalog.listTaxonomy(
          projectId,
          TaxonomyKind.issueType,
        )).valueOrNull ??
        const [];
    _priorities =
        (await _catalog.listTaxonomy(
          projectId,
          TaxonomyKind.priority,
        )).valueOrNull ??
        const [];
    _sizes =
        (await _catalog.listTaxonomy(
          projectId,
          TaxonomyKind.size,
        )).valueOrNull ??
        const [];
    _epics = (await _repo.listEpics(projectId)).valueOrNull ?? const [];
    _labels = (await _catalog.listLabels(projectId)).valueOrNull ?? const [];
    _components =
        (await _catalog.listComponents(projectId)).valueOrNull ?? const [];
    _releaseVersions =
        (await _catalog.listAllReleaseVersions(projectId)).valueOrNull ??
        const [];
    _milestonesList =
        (await _milestones.list(projectId)).valueOrNull ?? const [];

    // Default the visible columns to the taxonomy order when the board has none.
    if (_config.visibleColumnIds.isEmpty && _config.columnOrder.isEmpty) {
      final order = BoardConfig.defaultColumnOrder(statuses);
      _config = _config.copyWith(columnOrder: order, visibleColumnIds: order);
    }

    await _refetchData();
  }

  /// The visible status ids in display order, falling back to the taxonomy
  /// default and appending any statuses missing from the saved order.
  List<String> get _visibleColumnIds {
    final byId = {for (final s in _statuses) s.id: s};
    final order = _config.columnOrder.isEmpty
        ? BoardConfig.defaultColumnOrder(_statuses)
        : _config.columnOrder;
    final hidden = _config.hiddenColumnIds;
    final visible = _config.visibleColumnIds.isEmpty
        ? order
        : _config.visibleColumnIds;
    return [
      for (final id in order)
        if (byId.containsKey(id) &&
            !hidden.contains(id) &&
            visible.contains(id))
          id,
    ];
  }

  WorkItemFilter _effectiveFilter() {
    final merged = WorkItemFilter.fromJson({
      ..._adhoc.toJson(),
      ..._config.filters.toJson(),
    });
    final g = _config.group;
    if (g == null) return merged;
    final j = merged.toJson()..remove(g.filterKey);
    return WorkItemFilter.fromJson(j);
  }

  /// Data-only refetch using the cached board/taxonomy. Emits a loaded state
  /// without flashing the spinner.
  Future<void> _refetchData() async {
    final board = _board;
    if (board == null) return;
    final visible = _visibleColumnIds;
    final dataRes = await _catalog.fetchBoardData(
      projectId,
      filter: _effectiveFilter().toJson(),
      group: _config.group?.wire,
      columns: visible,
      columnLimit: _config.columnLimit,
    );
    final data = dataRes.valueOrNull;
    if (data == null) {
      if (!isClosed && state is! TaskBoardLoaded) emit(const TaskBoardFailed());
      return;
    }

    final flat = data.isGrouped
        ? const <BoardColumnData>[]
        : _orderColumns(data.columns, visible);
    final lanes = data.isGrouped
        ? [
            for (final lane in data.lanes)
              BoardLaneData(
                key: lane.key,
                total: lane.total,
                columns: _orderColumns(lane.columns, visible),
              ),
          ]
        : const <BoardLaneData>[];

    if (!isClosed) {
      emit(
        TaskBoardLoaded(
          board: board,
          config: _config,
          statuses: _statuses,
          flatColumns: flat,
          lanes: lanes,
          milestones: _milestonesList,
          types: _types,
          priorities: _priorities,
          sizes: _sizes,
          epics: _epics,
          labels: _labels,
          components: _components,
          releaseVersions: _releaseVersions,
          adhocFilter: _adhoc,
        ),
      );
    }
  }

  /// Order [cols] to match [visibleIds]; append the no-status column and any
  /// extra returned statuses at the end. Missing visible columns render empty.
  List<BoardColumnData> _orderColumns(
    List<BoardColumnData> cols,
    List<String> visibleIds,
  ) {
    final byId = <String, BoardColumnData>{
      for (final c in cols)
        if (c.statusId != null) c.statusId!: c,
    };
    final out = <BoardColumnData>[
      for (final id in visibleIds)
        byId[id] ?? BoardColumnData(statusId: id, total: 0, cards: const []),
    ];
    // Extra statuses returned but not in the visible set (e.g. just created).
    for (final c in cols) {
      if (c.statusId != null && !visibleIds.contains(c.statusId)) out.add(c);
    }
    final noStatus = cols.where((c) => c.statusId == null).firstOrNull;
    if (noStatus != null) out.add(noStatus);
    return out;
  }

  /// Silently refetch the board data (no spinner) — used after a detail sheet
  /// closes so any status/assignee edits are reflected.
  Future<void> refresh() => _refetchData();

  /// Replace the user's ad-hoc filter. Locked + group dimensions are stripped
  /// so the ad-hoc layer stays purely additive.
  void setAdhocFilter(WorkItemFilter f) {
    final j = f.toJson()
      ..removeWhere((k, _) => _config.lockedDimensions.contains(k));
    final g = _config.group;
    if (g != null) j.remove(g.filterKey);
    _adhoc = WorkItemFilter.fromJson(j);
    unawaited(_refetchData());
  }

  /// Append the next page of cards to one column (the "Load more" affordance).
  Future<void> loadMoreColumn({
    required String? statusId,
    required int offset,
    String? laneKey,
  }) async {
    final s = state;
    if (s is! TaskBoardLoaded) return;
    final filterMap = _effectiveFilter().toJson();
    filterMap['status'] = statusId ?? 'none';
    final g = _config.group;
    if (g != null && laneKey != null) filterMap[g.filterKey] = laneKey;

    final res = await _repo.listIssuesPaged(
      projectId,
      filter: filterMap,
      limit: _config.columnLimit,
      offset: offset,
    );
    final page = res.valueOrNull;
    if (page == null) return;

    final cur = state;
    if (cur is! TaskBoardLoaded) return;

    BoardColumnData appendTo(BoardColumnData col) {
      final seen = {for (final c in col.cards) c.id};
      final merged = [
        ...col.cards,
        for (final i in page.items)
          if (!seen.contains(i.id)) i,
      ];
      return BoardColumnData(
        statusId: col.statusId,
        total: col.total,
        cards: merged,
      );
    }

    if (g == null) {
      final next = [
        for (final c in cur.flatColumns)
          if (c.statusId == statusId) appendTo(c) else c,
      ];
      if (!isClosed) emit(cur.copyWith(flatColumns: next));
    } else {
      final next = [
        for (final lane in cur.lanes)
          if (lane.key == laneKey)
            BoardLaneData(
              key: lane.key,
              total: lane.total,
              columns: [
                for (final c in lane.columns)
                  if (c.statusId == statusId) appendTo(c) else c,
              ],
            )
          else
            lane,
      ];
      if (!isClosed) emit(cur.copyWith(lanes: next));
    }
  }

  /// Move an issue to a different `statusId`, then refetch the board data.
  Future<void> moveTask({
    required String taskId,
    required String? targetStatusId,
  }) async {
    final freshRes = await _repo.getIssue(projectId, taskId);
    final fresh = freshRes.valueOrNull;
    if (fresh == null || fresh.etag == null) {
      await _refetchData();
      return;
    }
    if (fresh.statusId == targetStatusId) return;
    final patch = await _repo.updateIssue(
      projectId,
      taskId,
      body: UpdateIssueRequest(statusId: targetStatusId),
      etag: fresh.etag!,
    );
    if (patch.valueOrNull == null) {
      final s = state;
      if (s is TaskBoardLoaded && !isClosed) emit(s.copyWith(staleData: true));
    }
    await _refetchData();
  }
}
