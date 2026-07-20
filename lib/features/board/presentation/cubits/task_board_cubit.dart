// `_repo` / `_catalog` are intentionally private fields for clarity.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/network/sse/project_events_service.dart';
import 'package:intellipilot/core/work_items/work_item_filter.dart';
import 'package:intellipilot/features/backlog/data/dtos/backlog_dtos.dart';
import 'package:intellipilot/features/backlog/domain/backlog_repository.dart';
import 'package:intellipilot/features/board/data/board_snapshot_cache.dart';
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
    this.highlightedIds = const {},
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

  /// Set when a move hit a conflict — UI surfaces a banner.
  final bool staleData;

  /// Cards recently changed by *another* user — rendered with a fading
  /// selection glow for a few seconds.
  final Set<String> highlightedIds;

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
    Set<String>? highlightedIds,
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
    highlightedIds: highlightedIds ?? this.highlightedIds,
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
    highlightedIds,
  ];
}

/// Board state with a three-layer sync model:
///
///  1. **Cache** — a persisted [BoardSnapshot] paints the board instantly on
///     open (no spinner, works offline);
///  2. **Delta sync** — `issues/delta` from the stored cursor reconciles the
///     cached view with the server (board open, sheet close, reconnect);
///  3. **Live events** — SSE changes apply in real time, highlighted when
///     another user made them.
///
/// All data enters the columns through one version-gated reconciler
/// ([_upsert]): stale rows never overwrite fresh ones, so duplicated delivery
/// across the three layers is harmless. Mutations (move/create) apply
/// optimistically and reconcile with the server response — the board is never
/// fully refetched behind the user's back; [fullReload] does it on demand.
class TaskBoardCubit extends Cubit<TaskBoardState> {
  TaskBoardCubit({
    required BacklogRepository repo,
    required CatalogRepository catalog,
    required MilestonesRepository milestones,
    required this.projectId,
    required this.boardId,
    BoardSnapshotCache? cache,
    ProjectEventsService? events,
    String currentUserId = '',
  }) : _repo = repo,
       _catalog = catalog,
       _milestones = milestones,
       _cache = cache,
       _events = events,
       _currentUserId = currentUserId,
       super(const TaskBoardLoading());

  final BacklogRepository _repo;
  final CatalogRepository _catalog;
  final MilestonesRepository _milestones;
  final BoardSnapshotCache? _cache;
  final ProjectEventsService? _events;
  final String _currentUserId;
  final String projectId;
  final String boardId;

  static const Duration _taxonomyTtl = Duration(minutes: 15);
  static const Duration _highlightFor = Duration(seconds: 4);
  static const Duration _snapshotDebounce = Duration(seconds: 3);
  static const int _maxDeltaPages = 5;

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

  List<BoardColumnData> _flatColumns = const [];
  List<BoardLaneData> _lanes = const [];
  bool _stale = false;
  final Set<String> _highlighted = {};
  final Map<String, Timer> _highlightTimers = {};

  String? _cursor;
  bool _syncing = false;
  Timer? _snapshotTimer;
  StreamSubscription<LiveEvent>? _liveSub;

  @override
  Future<void> close() async {
    await _liveSub?.cancel();
    _snapshotTimer?.cancel();
    for (final t in _highlightTimers.values) {
      t.cancel();
    }
    await super.close();
  }

  // ==========================================================================
  // Loading
  // ==========================================================================

  /// Load the board: instantly from the snapshot cache when possible
  /// (revalidating in the background), else the full network path.
  Future<void> load({bool useCache = true}) async {
    _ensureLiveSubscription();

    if (useCache && !_adhoc.isActive) {
      final snap = _cache?.load(_currentUserId, projectId, boardId);
      if (snap != null) {
        _restoreSnapshot(snap);
        unawaited(_catalog.setLastOpenedBoard(projectId, boardId));
        unawaited(_revalidate(snap));
        return;
      }
    }

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

    if (!await _loadTaxonomy()) {
      if (!isClosed) emit(const TaskBoardFailed());
      return;
    }
    _defaultColumnsFromTaxonomy();
    await _refetchData();
  }

  /// Manual full page reload: drop the snapshot + cursor and re-pull
  /// everything (board, taxonomy, data) from the network, with a spinner.
  Future<void> fullReload() async {
    await _cache?.clearBoard(_currentUserId, projectId, boardId);
    _cursor = null;
    _stale = false;
    await load(useCache: false);
  }

  void _restoreSnapshot(BoardSnapshot snap) {
    _board = snap.board;
    _config = BoardConfig.fromMap(snap.board.config);
    _statuses = snap.statuses;
    _types = snap.types;
    _priorities = snap.priorities;
    _sizes = snap.sizes;
    _epics = snap.epics;
    _labels = snap.labels;
    _components = snap.components;
    _releaseVersions = snap.releaseVersions;
    _milestonesList = snap.milestones;
    _cursor = snap.cursor;
    _defaultColumnsFromTaxonomy();
    _applyData(snap.data);
  }

  /// Background revalidation after a cached paint: fresh board config first
  /// (layout changes invalidate the data shape), then delta sync; taxonomy is
  /// refreshed only when the snapshot has aged past [_taxonomyTtl].
  Future<void> _revalidate(BoardSnapshot snap) async {
    final boardRes = await _catalog.getBoard(projectId, boardId);
    final board = boardRes.valueOrNull;
    if (board == null) {
      // Distinguish "gone/unauthorized" from a transient network error: the
      // cached view may keep serving offline, but must never mask a 401/403/
      // 404 — purge and fail in that case.
      final failure = boardRes.when(ok: (_) => null, err: (e) => e);
      if (failure is UnauthorizedFailure ||
          failure is ForbiddenFailure ||
          failure is NotFoundFailure) {
        await _cache?.clearBoard(_currentUserId, projectId, boardId);
        if (!isClosed) emit(const TaskBoardFailed());
      }
      return;
    }
    final configChanged =
        jsonEncode(board.config) != jsonEncode(_board?.config);
    _board = board;
    if (configChanged) {
      _config = BoardConfig.fromMap(board.config);
      _defaultColumnsFromTaxonomy();
      await _refetchData();
    } else {
      _emitLoaded();
      await _deltaSync();
    }
    if (DateTime.now().difference(snap.savedAt) > _taxonomyTtl) {
      if (await _loadTaxonomy()) {
        _defaultColumnsFromTaxonomy();
        _emitLoaded();
        await _saveSnapshot();
      }
    }
  }

  /// Pull the full taxonomy set. Statuses are required (false on failure);
  /// everything else degrades to empty lists.
  Future<bool> _loadTaxonomy() async {
    final statusRes = await _catalog.listTaxonomy(
      projectId,
      TaxonomyKind.issueStatus,
    );
    final statuses = statusRes.valueOrNull;
    if (statuses == null) return false;
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
    return true;
  }

  /// Default the visible columns to the taxonomy order when the board has none.
  void _defaultColumnsFromTaxonomy() {
    if (_config.visibleColumnIds.isEmpty && _config.columnOrder.isEmpty) {
      final order = BoardConfig.defaultColumnOrder(_statuses);
      _config = _config.copyWith(columnOrder: order, visibleColumnIds: order);
    }
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
  /// without flashing the spinner. Also refreshes the delta cursor and (when
  /// no ad-hoc filter is active) the persisted snapshot.
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
    if (data.cursor.isNotEmpty) _cursor = data.cursor;
    _applyData(data);
    await _saveSnapshot();
  }

  void _applyData(BoardData data) {
    final visible = _visibleColumnIds;
    _flatColumns = data.isGrouped
        ? const <BoardColumnData>[]
        : _orderColumns(data.columns, visible);
    _lanes = data.isGrouped
        ? [
            for (final lane in data.lanes)
              BoardLaneData(
                key: lane.key,
                total: lane.total,
                columns: _orderColumns(lane.columns, visible),
              ),
          ]
        : const <BoardLaneData>[];
    _emitLoaded();
  }

  void _emitLoaded() {
    final board = _board;
    if (board == null || isClosed) return;
    emit(
      TaskBoardLoaded(
        board: board,
        config: _config,
        statuses: _statuses,
        flatColumns: _flatColumns,
        lanes: _lanes,
        milestones: _milestonesList,
        types: _types,
        priorities: _priorities,
        sizes: _sizes,
        epics: _epics,
        labels: _labels,
        components: _components,
        releaseVersions: _releaseVersions,
        adhocFilter: _adhoc,
        staleData: _stale,
        highlightedIds: Set.unmodifiable(_highlighted),
      ),
    );
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

  // ==========================================================================
  // Delta sync + live events
  // ==========================================================================

  void _ensureLiveSubscription() {
    _liveSub ??= _events?.watch(projectId).listen(_onLiveEvent);
  }

  void _onLiveEvent(LiveEvent e) {
    if (e.isControl) {
      // `connected` after any (re)connect and `resync` after event loss both
      // mean the same thing: close the gap via delta.
      unawaited(_deltaSync());
      return;
    }
    final payload = e.payload;
    final actor = payload['actor_id'] as String?;
    final remote =
        _currentUserId.isNotEmpty && actor != null && actor != _currentUserId;
    switch (payload['event']) {
      case 'issue.created' || 'issue.updated':
        final raw = payload['issue'];
        if (raw is Map<String, dynamic>) {
          if (_upsert(Issue.fromJson(raw), highlight: remote)) {
            _scheduleSnapshotSave();
          }
        }
      case 'issue.deleted':
        final id = payload['issue_id'] as String?;
        if (id != null && _removeById(id)) _scheduleSnapshotSave();
      case 'board.changed':
        if (payload['board_id'] == boardId) unawaited(_onBoardChanged());
      default:
        break;
    }
  }

  /// Someone edited this board's definition: refresh config, then data.
  Future<void> _onBoardChanged() async {
    final board = (await _catalog.getBoard(projectId, boardId)).valueOrNull;
    if (board == null) return;
    _board = board;
    _config = BoardConfig.fromMap(board.config);
    _defaultColumnsFromTaxonomy();
    await _refetchData();
  }

  /// Catch up from the stored cursor. Any failure (including a 410 over-age
  /// cursor) degrades to a full data refetch — delta must never be able to
  /// wedge the board.
  Future<void> _deltaSync() async {
    if (_syncing) return;
    _syncing = true;
    try {
      var since = _cursor;
      if (since == null || since.isEmpty) {
        await _refetchData();
        return;
      }
      for (var page = 0; page < _maxDeltaPages; page++) {
        final res = await _repo.listIssuesDelta(projectId, since: since!);
        final delta = res.valueOrNull;
        if (delta == null) {
          await _refetchData();
          return;
        }
        delta.issues.forEach(_upsert);
        delta.tombstoneIds.forEach(_removeById);
        if (delta.cursor.isNotEmpty) _cursor = delta.cursor;
        since = delta.cursor;
        if (!delta.hasMore || since.isEmpty) break;
      }
      await _saveSnapshot();
    } finally {
      _syncing = false;
    }
  }

  // ==========================================================================
  // Reconciler
  // ==========================================================================

  /// Locate an issue among the currently visible cards.
  Issue? findIssue(String id) {
    for (final c in _flatColumns) {
      for (final card in c.cards) {
        if (card.id == id) return card;
      }
    }
    for (final lane in _lanes) {
      for (final c in lane.columns) {
        for (final card in c.cards) {
          if (card.id == id) return card;
        }
      }
    }
    return null;
  }

  /// The version gate: strictly-newer data only. Reorders keep the version
  /// but bump `modified_at`, hence the tiebreaker.
  static bool _isNewer(Issue incoming, Issue existing) =>
      incoming.version > existing.version ||
      (incoming.version == existing.version &&
          incoming.modifiedAt.isAfter(existing.modifiedAt));

  /// Apply one issue to the visible board. Every data source (delta, SSE,
  /// mutation responses) funnels through here; [force] is reserved for local
  /// optimistic writes, which don't carry a bumped version yet.
  ///
  /// Returns true when the board changed.
  bool _upsert(Issue issue, {bool highlight = false, bool force = false}) {
    if (state is! TaskBoardLoaded && _board == null) return false;
    final existing = findIssue(issue.id);
    if (existing != null && !force && !_isNewer(issue, existing)) return false;
    final belongs = _belongsOnBoard(issue);
    if (existing == null && !belongs) return false;

    if (_config.group == null) {
      _flatColumns = _upsertIntoColumns(
        _flatColumns,
        issue,
        belongs: belongs,
        targetStatus: _targetStatusId(issue),
      );
    } else {
      _lanes = _upsertIntoLanes(_lanes, issue, belongs: belongs);
    }
    if (highlight) _flashHighlight(issue.id);
    _emitLoaded();
    return true;
  }

  bool _removeById(String id) {
    final existing = findIssue(id);
    if (existing == null) return false;
    if (_config.group == null) {
      _flatColumns = _stripFromColumns(_flatColumns, id).columns;
    } else {
      _lanes = [
        for (final lane in _lanes)
          () {
            final stripped = _stripFromColumns(lane.columns, id);
            return stripped.removed
                ? BoardLaneData(
                    key: lane.key,
                    total: lane.total > 0 ? lane.total - 1 : 0,
                    columns: stripped.columns,
                  )
                : lane;
          }(),
      ];
    }
    _emitLoaded();
    return true;
  }

  /// Whether [issue] matches this board's visible columns + effective filter.
  bool _belongsOnBoard(Issue issue) {
    final status = issue.statusId;
    if (status != null && !_visibleColumnIds.contains(status)) return false;
    final f = _effectiveFilter();
    final closed = {
      for (final s in _statuses)
        if (s.isClosed ?? false) s.id,
    };
    if (!f.matches(issue, closedStatusIds: closed)) return false;
    // `matches` has no release predicate (server-side there): resolve via the
    // cached release-version list.
    final releaseFilter = f.releaseId;
    if (releaseFilter != null) {
      if (releaseFilter == 'none') {
        if (issue.releaseVersionId != null) return false;
      } else {
        final rv = _releaseVersions
            .where((v) => v.id == issue.releaseVersionId)
            .firstOrNull;
        if (rv == null || rv.releaseId != releaseFilter) return false;
      }
    }
    return true;
  }

  /// The column an issue belongs to (null = the trailing no-status column).
  String? _targetStatusId(Issue issue) => issue.statusId;

  /// Swimlane keys for an issue under the active grouping. Component-grouped
  /// boards can place one issue in several lanes.
  Set<String> _laneKeysFor(Issue issue) {
    final g = _config.group;
    return switch (g) {
      null => const {},
      BoardGroupBy.assignee => {issue.assignedTo ?? 'none'},
      BoardGroupBy.epic => {issue.epicId ?? 'none'},
      BoardGroupBy.priority => {issue.priorityId ?? 'none'},
      BoardGroupBy.component =>
        issue.components.isEmpty ? const {'none'} : issue.components.toSet(),
    };
  }

  ({List<BoardColumnData> columns, bool removed}) _stripFromColumns(
    List<BoardColumnData> cols,
    String id,
  ) {
    var removed = false;
    final out = <BoardColumnData>[];
    for (final c in cols) {
      if (c.cards.any((x) => x.id == id)) {
        removed = true;
        out.add(
          BoardColumnData(
            statusId: c.statusId,
            total: c.total > 0 ? c.total - 1 : 0,
            cards: [
              for (final x in c.cards)
                if (x.id != id) x,
            ],
          ),
        );
      } else {
        out.add(c);
      }
    }
    return (columns: out, removed: removed);
  }

  /// Remove-then-insert with per-column total bookkeeping. Totals for cards
  /// living in the unloaded tail of a capped column can drift by one — that's
  /// accepted and healed by the next full data fetch.
  List<BoardColumnData> _upsertIntoColumns(
    List<BoardColumnData> cols,
    Issue issue, {
    required bool belongs,
    required String? targetStatus,
  }) {
    var wasVisibleInTarget = false;
    var out = <BoardColumnData>[];
    for (final c in cols) {
      final has = c.cards.any((x) => x.id == issue.id);
      if (!has) {
        out.add(c);
        continue;
      }
      if (c.statusId == targetStatus) wasVisibleInTarget = true;
      out.add(
        BoardColumnData(
          statusId: c.statusId,
          // Leaving the column entirely vs. moving within it.
          total: c.statusId == targetStatus && belongs
              ? c.total
              : (c.total > 0 ? c.total - 1 : 0),
          cards: [
            for (final x in c.cards)
              if (x.id != issue.id) x,
          ],
        ),
      );
    }
    if (!belongs) return out;

    var found = false;
    out = [
      for (final c in out)
        if (c.statusId == targetStatus)
          () {
            found = true;
            return _insertCard(
              c,
              issue,
              keepVisible: wasVisibleInTarget,
              bumpTotal: !wasVisibleInTarget,
            );
          }()
        else
          c,
    ];
    if (!found) {
      // No such column yet (e.g. the first no-status card): append one, like
      // the server-ordered payload would.
      out.add(
        BoardColumnData(statusId: targetStatus, total: 1, cards: [issue]),
      );
    }
    return out;
  }

  List<BoardLaneData> _upsertIntoLanes(
    List<BoardLaneData> lanes,
    Issue issue, {
    required bool belongs,
  }) {
    final keys = _laneKeysFor(issue);
    final target = _targetStatusId(issue);
    final out = <BoardLaneData>[];
    final seenKeys = <String>{};
    for (final lane in lanes) {
      seenKeys.add(lane.key);
      final inLane = belongs && keys.contains(lane.key);
      final hadCard = lane.columns.any(
        (c) => c.cards.any((x) => x.id == issue.id),
      );
      if (!inLane && !hadCard) {
        out.add(lane);
        continue;
      }
      final columns = _upsertIntoColumns(
        lane.columns,
        issue,
        belongs: inLane,
        targetStatus: target,
      );
      var total = lane.total;
      if (inLane && !hadCard) total += 1;
      if (!inLane && hadCard) total = total > 0 ? total - 1 : 0;
      out.add(BoardLaneData(key: lane.key, total: total, columns: columns));
    }
    // Lanes that don't exist yet (first card for an assignee/epic/…): append
    // a skeleton; the server-ordered layout returns on the next full fetch.
    if (belongs) {
      for (final key in keys.difference(seenKeys)) {
        final skeleton = _orderColumns(const [], _visibleColumnIds);
        out.add(
          BoardLaneData(
            key: key,
            total: 1,
            columns: _upsertIntoColumns(
              skeleton,
              issue,
              belongs: true,
              targetStatus: target,
            ),
          ),
        );
      }
    }
    return out;
  }

  /// Insert [issue] into [col] by `(order, id)` rank. When the card would
  /// land past the visible slice of a capped column (and wasn't visible
  /// before), it stays in the unloaded tail: only the total moves.
  BoardColumnData _insertCard(
    BoardColumnData col,
    Issue issue, {
    required bool keepVisible,
    required bool bumpTotal,
  }) {
    final total = bumpTotal ? col.total + 1 : col.total;
    var idx = col.cards.length;
    for (var i = 0; i < col.cards.length; i++) {
      final c = col.cards[i];
      if (c.order > issue.order ||
          (c.order == issue.order && c.id.compareTo(issue.id) > 0)) {
        idx = i;
        break;
      }
    }
    final tailHidden =
        !keepVisible && idx >= col.cards.length && total > col.cards.length + 1;
    if (tailHidden) {
      return BoardColumnData(
        statusId: col.statusId,
        total: total,
        cards: col.cards,
      );
    }
    return BoardColumnData(
      statusId: col.statusId,
      total: total,
      cards: [...col.cards.take(idx), issue, ...col.cards.skip(idx)],
    );
  }

  void _flashHighlight(String id) {
    _highlighted.add(id);
    _highlightTimers.remove(id)?.cancel();
    _highlightTimers[id] = Timer(_highlightFor, () {
      _highlightTimers.remove(id);
      if (_highlighted.remove(id)) _emitLoaded();
    });
  }

  // ==========================================================================
  // Snapshot persistence
  // ==========================================================================

  void _scheduleSnapshotSave() {
    _snapshotTimer?.cancel();
    _snapshotTimer = Timer(_snapshotDebounce, () => unawaited(_saveSnapshot()));
  }

  /// Persist the current view — only the unfiltered baseline (an active
  /// ad-hoc filter shows a server-filtered subset that must not overwrite
  /// the cached board).
  Future<void> _saveSnapshot() async {
    final board = _board;
    final cursor = _cursor;
    final cache = _cache;
    if (cache == null || board == null || cursor == null || cursor.isEmpty) {
      return;
    }
    if (_adhoc.isActive) return;
    await cache.save(
      _currentUserId,
      projectId,
      boardId,
      BoardSnapshot(
        cursor: cursor,
        savedAt: DateTime.now(),
        board: board,
        data: BoardData(
          group: _config.group?.wire,
          columns: _flatColumns,
          lanes: _lanes,
        ),
        statuses: _statuses,
        types: _types,
        priorities: _priorities,
        sizes: _sizes,
        epics: _epics,
        labels: _labels,
        components: _components,
        releaseVersions: _releaseVersions,
        milestones: _milestonesList,
      ),
    );
  }

  // ==========================================================================
  // User actions
  // ==========================================================================

  /// Cheap catch-up (no full reload) — used after a detail sheet closes so
  /// any edits are reflected.
  Future<void> refresh() => _deltaSync();

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
    if (state is! TaskBoardLoaded) return;
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
      _flatColumns = [
        for (final c in _flatColumns)
          if (c.statusId == statusId) appendTo(c) else c,
      ];
    } else {
      _lanes = [
        for (final lane in _lanes)
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
    }
    _emitLoaded();
  }

  /// Create an issue directly in a board column: the column's status is
  /// preset so the new card lands where the user clicked "+". On a grouped
  /// board the swimlane value is preset too ('none' lanes preset nothing).
  /// The created card is inserted locally — no board reload. Returns the
  /// created issue (null on failure) so the caller can open its detail sheet
  /// and show the confirmation toast.
  Future<Issue?> createIssueInColumn({
    required String subject,
    required String? statusId,
    String? typeId,
    String? laneKey,
  }) async {
    String? assignedTo;
    String? epicId;
    String? priorityId;
    var components = const <String>[];
    final g = _config.group;
    if (g != null && laneKey != null && laneKey != 'none') {
      switch (g) {
        case BoardGroupBy.component:
          components = [laneKey];
        case BoardGroupBy.assignee:
          assignedTo = laneKey;
        case BoardGroupBy.epic:
          epicId = laneKey;
        case BoardGroupBy.priority:
          priorityId = laneKey;
      }
    }
    final res = await _repo.createIssue(
      projectId,
      CreateIssueRequest(
        subject: subject,
        statusId: statusId,
        typeId: typeId,
        assignedTo: assignedTo,
        epicId: epicId,
        priorityId: priorityId,
        components: components,
      ),
    );
    final created = res.valueOrNull;
    if (created == null) return null;
    _upsert(created, force: true);
    _scheduleSnapshotSave();
    return created;
  }

  /// Move an issue to a different `statusId` — optimistically: the card moves
  /// at once, the PATCH runs behind it, and a conflict either auto-resolves
  /// (disjoint edit → one retry with the fresh ETag) or rolls the card back
  /// to server truth with the stale banner. Returns the moved issue on
  /// success (for the confirmation toast), null otherwise.
  Future<Issue?> moveTask({
    required String taskId,
    required String? targetStatusId,
  }) async {
    var current = findIssue(taskId);
    if (current == null || current.etag == null) {
      // Card not visible locally (unloaded tail) — fetch, then patch.
      current = (await _repo.getIssue(projectId, taskId)).valueOrNull;
      if (current == null || current.etag == null) {
        await _refetchData();
        return null;
      }
    }
    if (current.statusId == targetStatusId) return null;

    // Optimistic move (same version — forced past the gate).
    _upsert(_withStatus(current, targetStatusId), force: true);

    final res = await _repo.updateIssue(
      projectId,
      taskId,
      body: UpdateIssueRequest(statusId: targetStatusId),
      etag: current.etag!,
    );
    var updated = res.valueOrNull;
    if (updated == null) {
      final fresh = (await _repo.getIssue(projectId, taskId)).valueOrNull;
      if (fresh == null) {
        // Unreachable/deleted: put the card back and flag staleness.
        _upsert(current, force: true);
        _setStale();
        return null;
      }
      if (fresh.statusId == targetStatusId) {
        // Someone else already moved it — that's success.
        _upsert(fresh, force: true);
        _scheduleSnapshotSave();
        return fresh;
      }
      // Disjoint conflict (another field changed): retry once on fresh state.
      final retry = await _repo.updateIssue(
        projectId,
        taskId,
        body: UpdateIssueRequest(statusId: targetStatusId),
        etag: fresh.etag ?? '',
      );
      updated = retry.valueOrNull;
      if (updated == null) {
        // Genuine conflict: roll back to server truth.
        _upsert(fresh, force: true);
        _setStale();
        return null;
      }
    }
    _upsert(updated, force: true);
    _scheduleSnapshotSave();
    return updated;
  }

  void _setStale() {
    _stale = true;
    _emitLoaded();
  }

  /// Clone [issue] with a different status (wire round-trip keeps every other
  /// field and the reconstructed ETag intact).
  static Issue _withStatus(Issue issue, String? statusId) {
    final j = BoardSnapshotCache.issueJson(issue)..['status_id'] = statusId;
    return Issue.fromJson(j);
  }
}
