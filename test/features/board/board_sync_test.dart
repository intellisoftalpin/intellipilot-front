import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/core/storage/hive_boxes.dart';
import 'package:intellipilot/features/backlog/data/dtos/backlog_dtos.dart';
import 'package:intellipilot/features/backlog/domain/backlog_repository.dart';
import 'package:intellipilot/features/board/data/board_snapshot_cache.dart';
import 'package:intellipilot/features/board/presentation/cubits/task_board_cubit.dart';
import 'package:intellipilot/features/catalog/data/dtos/catalog_dtos.dart';
import 'package:intellipilot/features/catalog/domain/catalog_repository.dart';
import 'package:intellipilot/features/milestones/data/dtos/milestone_dtos.dart';
import 'package:intellipilot/features/milestones/domain/milestones_repository.dart';

const _cursor = '2026-01-01T00:00:00Z';

TaxonomyItem _status(String id) => TaxonomyItem(
  id: id,
  projectId: 'p1',
  kind: TaxonomyKind.issueStatus,
  name: id.toUpperCase(),
  slug: id,
  color: '#cccccc',
  order: 1,
  createdAt: DateTime(2026),
);

Issue _issue(
  String id, {
  String? statusId,
  int version = 1,
  double order = 1,
  DateTime? modifiedAt,
  List<ComponentVersion> componentVersions = const [],
}) => Issue(
  id: id,
  projectId: 'p1',
  reference: 1,
  subject: 'Issue $id',
  description: '',
  labels: const [],
  components: const [],
  statusId: statusId,
  order: order,
  version: version,
  componentVersions: componentVersions,
  createdAt: DateTime(2026),
  modifiedAt: modifiedAt ?? DateTime(2026),
  etag: '"$id:$version"',
);

const _board = Board(
  id: 'b1',
  projectId: 'p1',
  visibility: 'personal',
  name: 'My board',
  color: '',
  order: 0,
  config: {
    'columns': {
      'visible': ['s1', 's2'],
      'order': ['s1', 's2'],
    },
    'column_limit': 50,
  },
);

class _FakeCatalog extends Fake implements CatalogRepository {
  _FakeCatalog(this.board, this.statuses, this.data);
  final Board board;
  final List<TaxonomyItem> statuses;
  final BoardData data;
  int boardDataFetches = 0;
  int boardGets = 0;

  @override
  Future<Result<Board, AppFailure>> getBoard(
    String projectId,
    String boardId,
  ) async {
    boardGets++;
    return Ok(board);
  }

  @override
  Future<Result<Unit, AppFailure>> setLastOpenedBoard(
    String projectId,
    String boardId,
  ) async => const Ok(Unit.instance);

  @override
  Future<Result<List<TaxonomyItem>, AppFailure>> listTaxonomy(
    String projectId,
    TaxonomyKind kind,
  ) async => Ok(kind == TaxonomyKind.issueStatus ? statuses : const []);

  @override
  Future<Result<List<Label>, AppFailure>> listLabels(String projectId) async =>
      const Ok([]);

  @override
  Future<Result<List<Component>, AppFailure>> listComponents(
    String projectId,
  ) async => const Ok([]);

  @override
  Future<Result<List<ReleaseVersionRef>, AppFailure>> listAllReleaseVersions(
    String projectId,
  ) async => const Ok([]);

  @override
  Future<Result<BoardData, AppFailure>> fetchBoardData(
    String projectId, {
    Map<String, dynamic> filter = const {},
    String? group,
    List<String>? columns,
    int columnLimit = 50,
  }) async {
    boardDataFetches++;
    return Ok(data);
  }
}

class _FakeBacklog extends Fake implements BacklogRepository {
  final List<IssuesDelta> deltaQueue = [];
  Completer<Result<Issue, AppFailure>>? pendingUpdate;
  Result<Issue, AppFailure>? updateResult;
  Issue? freshIssue;
  int updateCalls = 0;

  @override
  Future<Result<List<Epic>, AppFailure>> listEpics(String projectId) async =>
      const Ok([]);

  @override
  Future<Result<IssuesDelta, AppFailure>> listIssuesDelta(
    String projectId, {
    required String since,
  }) async => Ok(
    deltaQueue.isEmpty
        ? const IssuesDelta(
            issues: [],
            tombstoneIds: [],
            cursor: _cursor,
            hasMore: false,
          )
        : deltaQueue.removeAt(0),
  );

  @override
  Future<Result<Issue, AppFailure>> getIssue(
    String projectId,
    String id,
  ) async =>
      freshIssue != null ? Ok(freshIssue!) : const Err(NotFoundFailure());

  @override
  Future<Result<Issue, AppFailure>> updateIssue(
    String projectId,
    String id, {
    required UpdateIssueRequest body,
    required String etag,
  }) async {
    updateCalls++;
    final pending = pendingUpdate;
    if (pending != null) return pending.future;
    return updateResult ?? const Err(NetworkFailure());
  }
}

class _FakeMilestones extends Fake implements MilestonesRepository {
  @override
  Future<Result<List<Milestone>, AppFailure>> list(String projectId) async =>
      const Ok([]);
}

TaskBoardCubit _cubit(
  _FakeCatalog catalog,
  _FakeBacklog backlog, {
  BoardSnapshotCache? cache,
}) => TaskBoardCubit(
  repo: backlog,
  catalog: catalog,
  milestones: _FakeMilestones(),
  projectId: 'p1',
  boardId: 'b1',
  cache: cache,
  currentUserId: 'u1',
);

List<Issue> _cards(TaskBoardCubit cubit, String statusId) =>
    (cubit.state as TaskBoardLoaded).flatColumns
        .firstWhere((c) => c.statusId == statusId)
        .cards;

void main() {
  group('delta reconciler', () {
    test('applies changes/tombstones and gates out stale rows', () async {
      final data = BoardData(
        cursor: _cursor,
        columns: [
          BoardColumnData(
            statusId: 's1',
            total: 1,
            cards: [_issue('i1', statusId: 's1')],
          ),
          const BoardColumnData(statusId: 's2', total: 0, cards: []),
        ],
      );
      final catalog = _FakeCatalog(_board, [
        _status('s1'),
        _status('s2'),
      ], data);
      final backlog = _FakeBacklog();
      final cubit = _cubit(catalog, backlog);
      await cubit.load();

      // i1 moved to s2 (v2) elsewhere; i3 is brand new in s1.
      backlog.deltaQueue.add(
        IssuesDelta(
          issues: [
            _issue('i1', statusId: 's2', version: 2, order: 1),
            _issue('i3', statusId: 's1', version: 1, order: 2),
          ],
          tombstoneIds: const [],
          cursor: _cursor,
          hasMore: false,
        ),
      );
      await cubit.refresh();
      expect(_cards(cubit, 's2').map((c) => c.id), ['i1']);
      expect(_cards(cubit, 's1').map((c) => c.id), ['i3']);
      expect(
        (cubit.state as TaskBoardLoaded).flatColumns
            .firstWhere((c) => c.statusId == 's2')
            .total,
        1,
      );

      // A stale replay of i1 (v1, back in s1) must be ignored.
      backlog.deltaQueue.add(
        IssuesDelta(
          issues: [_issue('i1', statusId: 's1')],
          tombstoneIds: const [],
          cursor: _cursor,
          hasMore: false,
        ),
      );
      await cubit.refresh();
      expect(_cards(cubit, 's2').map((c) => c.id), ['i1']);
      expect(_cards(cubit, 's1').map((c) => c.id), ['i3']);

      // Same version but newer modified_at (a reorder) IS applied.
      backlog.deltaQueue.add(
        IssuesDelta(
          issues: [
            _issue(
              'i1',
              statusId: 's2',
              version: 2,
              order: 99,
              modifiedAt: DateTime(2026, 2),
            ),
          ],
          tombstoneIds: const [],
          cursor: _cursor,
          hasMore: false,
        ),
      );
      await cubit.refresh();
      expect(_cards(cubit, 's2').single.order, 99);

      // Tombstone removes the card and fixes the count.
      backlog.deltaQueue.add(
        const IssuesDelta(
          issues: [],
          tombstoneIds: ['i3'],
          cursor: _cursor,
          hasMore: false,
        ),
      );
      await cubit.refresh();
      expect(_cards(cubit, 's1'), isEmpty);
      expect(
        (cubit.state as TaskBoardLoaded).flatColumns
            .firstWhere((c) => c.statusId == 's1')
            .total,
        0,
      );
      await cubit.close();
    });
  });

  group('optimistic move', () {
    BoardData data() => BoardData(
      cursor: _cursor,
      columns: [
        BoardColumnData(
          statusId: 's1',
          total: 1,
          cards: [_issue('i1', statusId: 's1')],
        ),
        const BoardColumnData(statusId: 's2', total: 0, cards: []),
      ],
    );

    test('card moves before the server responds, then reconciles', () async {
      final catalog = _FakeCatalog(_board, [
        _status('s1'),
        _status('s2'),
      ], data());
      final backlog = _FakeBacklog()
        ..pendingUpdate = Completer<Result<Issue, AppFailure>>();
      final cubit = _cubit(catalog, backlog);
      await cubit.load();

      final move = cubit.moveTask(taskId: 'i1', targetStatusId: 's2');
      await Future<void>.delayed(Duration.zero);
      // Optimistic: already in s2 while the PATCH is in flight (v1).
      expect(_cards(cubit, 's2').single.version, 1);
      expect(_cards(cubit, 's1'), isEmpty);

      backlog.pendingUpdate!.complete(
        Ok(_issue('i1', statusId: 's2', version: 2)),
      );
      final moved = await move;
      expect(moved?.version, 2);
      expect(_cards(cubit, 's2').single.version, 2);
      expect((cubit.state as TaskBoardLoaded).staleData, isFalse);
      await cubit.close();
    });

    test('failed move rolls back to server truth and flags stale', () async {
      final catalog = _FakeCatalog(_board, [
        _status('s1'),
        _status('s2'),
      ], data());
      final backlog = _FakeBacklog()
        ..updateResult = const Err(NetworkFailure())
        ..freshIssue = _issue('i1', statusId: 's1', version: 3);
      final cubit = _cubit(catalog, backlog);
      await cubit.load();

      final moved = await cubit.moveTask(taskId: 'i1', targetStatusId: 's2');
      expect(moved, isNull);
      // Rolled back to the fresh server copy in s1, banner raised, and both
      // the initial PATCH and the one retry were attempted.
      expect(_cards(cubit, 's1').single.version, 3);
      expect(_cards(cubit, 's2'), isEmpty);
      expect((cubit.state as TaskBoardLoaded).staleData, isTrue);
      expect(backlog.updateCalls, 2);
      await cubit.close();
    });

    test('concurrent identical move is accepted as success', () async {
      final catalog = _FakeCatalog(_board, [
        _status('s1'),
        _status('s2'),
      ], data());
      final backlog = _FakeBacklog()
        ..updateResult = const Err(ConflictFailure())
        ..freshIssue = _issue('i1', statusId: 's2', version: 5);
      final cubit = _cubit(catalog, backlog);
      await cubit.load();

      final moved = await cubit.moveTask(taskId: 'i1', targetStatusId: 's2');
      expect(moved?.version, 5);
      expect(_cards(cubit, 's2').single.version, 5);
      expect((cubit.state as TaskBoardLoaded).staleData, isFalse);
      expect(backlog.updateCalls, 1);
      await cubit.close();
    });
  });

  group('snapshot cache', () {
    BoardSnapshot snap() => BoardSnapshot(
      cursor: _cursor,
      savedAt: DateTime(2026),
      board: _board,
      data: BoardData(
        columns: [
          BoardColumnData(
            statusId: 's1',
            total: 1,
            cards: [_issue('i1', statusId: 's1')],
          ),
        ],
      ),
      statuses: [_status('s1'), _status('s2')],
      types: const [],
      priorities: const [],
      sizes: const [],
      epics: const [],
      labels: const [],
      components: const [],
      releaseVersions: const [],
      milestones: const [],
    );

    test('round-trips through the wire serializers', () async {
      final cache = BoardSnapshotCache(InMemoryKeyValueStorage());
      await cache.save('u1', 'p1', 'b1', snap());
      final loaded = cache.load('u1', 'p1', 'b1');
      expect(loaded, isNotNull);
      expect(loaded!.cursor, _cursor);
      expect(loaded.board.name, 'My board');
      final col = loaded.data.columns.single;
      expect(col.total, 1);
      final card = col.cards.single;
      expect(card.id, 'i1');
      expect(card.statusId, 's1');
      // The ETag reconstructs from id+version, so cached cards stay movable.
      expect(card.etag, '"i1:1"');
      expect(loaded.statuses.length, 2);
    });

    test('per-component fix versions survive the cache', () async {
      // The card renders one pill per version, so a cached board that dropped
      // them would repaint instantly but under-report what an issue ships in.
      final cache = BoardSnapshotCache(InMemoryKeyValueStorage());
      final withVersions = BoardSnapshot(
        cursor: _cursor,
        savedAt: DateTime(2026),
        board: _board,
        data: BoardData(
          columns: [
            BoardColumnData(
              statusId: 's1',
              total: 1,
              cards: [
                _issue(
                  'i1',
                  statusId: 's1',
                  componentVersions: const [
                    ComponentVersion(componentId: 'c1', releaseVersionId: 'v1'),
                    ComponentVersion(componentId: 'c2', releaseVersionId: 'v2'),
                  ],
                ),
              ],
            ),
          ],
        ),
        statuses: [_status('s1')],
        types: const [],
        priorities: const [],
        sizes: const [],
        epics: const [],
        labels: const [],
        components: const [],
        releaseVersions: const [],
        milestones: const [],
      );
      await cache.save('u1', 'p1', 'b1', withVersions);
      final card = cache
          .load('u1', 'p1', 'b1')!
          .data
          .columns
          .single
          .cards
          .single;
      expect(card.componentVersions, hasLength(2));
      expect(card.versionFor('c1'), 'v1');
      expect(card.versionFor('c2'), 'v2');
    });

    test('is user-scoped, corruption-tolerant and clearable', () async {
      final storage = InMemoryKeyValueStorage();
      final cache = BoardSnapshotCache(storage);
      await cache.save('u1', 'p1', 'b1', snap());
      // Another user never sees it.
      expect(cache.load('u2', 'p1', 'b1'), isNull);
      // Corruption falls back to null instead of throwing.
      await storage.set<String>('snap:u1:p1:b1', '{not json');
      expect(cache.load('u1', 'p1', 'b1'), isNull);
      // clearAll leaves nothing behind.
      await cache.save('u1', 'p1', 'b1', snap());
      await cache.clearAll();
      expect(cache.load('u1', 'p1', 'b1'), isNull);
    });

    test('paints instantly from cache and revalidates via delta', () async {
      final cache = BoardSnapshotCache(InMemoryKeyValueStorage());
      await cache.save('u1', 'p1', 'b1', snap());
      final catalog = _FakeCatalog(
        _board,
        [_status('s1'), _status('s2')],
        const BoardData(cursor: _cursor),
      );
      final backlog = _FakeBacklog()
        ..deltaQueue.add(
          IssuesDelta(
            issues: [_issue('i9', statusId: 's1', version: 1, order: 9)],
            tombstoneIds: const [],
            cursor: _cursor,
            hasMore: false,
          ),
        );
      final cubit = _cubit(catalog, backlog, cache: cache);
      await cubit.load();

      // Painted from the snapshot: loaded state with the cached card.
      expect(cubit.state, isA<TaskBoardLoaded>());
      expect(_cards(cubit, 's1').map((c) => c.id), contains('i1'));

      // Let background revalidation (config check + delta) settle: the new
      // issue arrives via delta — no full board-data fetch happened.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(_cards(cubit, 's1').map((c) => c.id), containsAll(['i1', 'i9']));
      expect(catalog.boardDataFetches, 0);
      expect(catalog.boardGets, 1);
      await cubit.close();
    });
  });
}
