import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/core/network/sse/project_events_service.dart';
import 'package:intellipilot/core/storage/hive_boxes.dart';
import 'package:intellipilot/core/work_items/work_item_filter.dart';
import 'package:intellipilot/features/backlog/data/dtos/backlog_dtos.dart';
import 'package:intellipilot/features/backlog/domain/backlog_repository.dart';
import 'package:intellipilot/features/board/data/board_snapshot_cache.dart';
import 'package:intellipilot/features/board/domain/board_config.dart';
import 'package:intellipilot/features/board/domain/board_source.dart';
import 'package:intellipilot/features/board/domain/my_issues_lanes.dart';
import 'package:intellipilot/features/board/presentation/board_page.dart';
import 'package:intellipilot/features/board/presentation/cubits/task_board_cubit.dart';
import 'package:intellipilot/features/catalog/data/dtos/catalog_dtos.dart';
import 'package:intellipilot/features/catalog/domain/catalog_repository.dart';
import 'package:intellipilot/features/milestones/data/dtos/milestone_dtos.dart';
import 'package:intellipilot/features/milestones/domain/milestones_repository.dart';

const _me = 'u1';

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
  String? statusId = 's1',
  String? assignedTo,
  String? qaAssigneeId,
  String? reviewerId,
  String? ownerId,
  List<String> watchers = const [],
  String description = '',
  int version = 1,
}) => Issue(
  id: id,
  projectId: 'p1',
  reference: 1,
  subject: 'Issue $id',
  description: description,
  labels: const [],
  components: const [],
  statusId: statusId,
  assignedTo: assignedTo,
  qaAssigneeId: qaAssigneeId,
  reviewerId: reviewerId,
  ownerId: ownerId,
  watchers: watchers,
  order: 1,
  version: version,
  createdAt: DateTime(2026),
  modifiedAt: DateTime(2026),
);

class _FakeCatalog extends Fake implements CatalogRepository {
  _FakeCatalog(this.statuses, this.data);
  final List<TaxonomyItem> statuses;
  BoardData data;

  Map<String, dynamic>? lastFilter;
  String? lastGroup;
  int fetches = 0;
  final List<String> watched = [];

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
  Future<Result<Unit, AppFailure>> addWatcher(
    String projectId,
    String issueId, {
    String? userId,
  }) async {
    watched.add(issueId);
    return const Ok(Unit.instance);
  }

  @override
  Future<Result<BoardData, AppFailure>> fetchBoardData(
    String projectId, {
    Map<String, dynamic> filter = const {},
    String? group,
    List<String>? columns,
    int columnLimit = 50,
  }) async {
    fetches++;
    lastFilter = filter;
    lastGroup = group;
    return Ok(data);
  }
}

class _FakeBacklog extends Fake implements BacklogRepository {
  _FakeBacklog({this.created});
  Issue? created;
  CreateIssueRequest? lastCreate;
  UpdateIssueRequest? lastUpdate;

  @override
  Future<Result<List<Epic>, AppFailure>> listEpics(String projectId) async =>
      const Ok([]);

  @override
  Future<Result<Issue, AppFailure>> createIssue(
    String projectId,
    CreateIssueRequest body,
  ) async {
    lastCreate = body;
    return Ok(created ?? _issue('new', statusId: body.statusId));
  }

  @override
  Future<Result<Issue, AppFailure>> updateIssue(
    String projectId,
    String id, {
    required UpdateIssueRequest body,
    required String etag,
  }) async {
    lastUpdate = body;
    return Ok(_issue(id, qaAssigneeId: _me, version: 2));
  }

  @override
  Future<Result<Issue, AppFailure>> getIssue(
    String projectId,
    String id,
  ) async => Ok(_issue(id, watchers: const [_me]));
}

/// Feeds hand-made live events into the cubit, the way the SSE stream would.
class _FakeEvents extends Fake implements ProjectEventsService {
  final _controller = StreamController<LiveEvent>.broadcast();

  @override
  Stream<LiveEvent> watch(String projectId) => _controller.stream;

  void issueUpdated(Issue issue) => _controller.add(
    LiveEvent.change({
      'event': 'issue.updated',
      'actor_id': 'someone-else',
      'issue': BoardSnapshotCache.issueJson(issue),
    }),
  );

  void commentCreated(String issueId) => _controller.add(
    LiveEvent.change({
      'event': 'comment.created',
      'actor_id': 'someone-else',
      'target_type': 'issue',
      'target_id': issueId,
    }),
  );

  Future<void> dispose() => _controller.close();
}

class _FakeMilestones extends Fake implements MilestonesRepository {
  @override
  Future<Result<List<Milestone>, AppFailure>> list(String projectId) async =>
      const Ok([]);
}

BoardData _grouped(Map<String, List<Issue>> lanes) => BoardData(
  group: 'my_role',
  columns: const [],
  lanes: [
    for (final e in lanes.entries)
      BoardLaneData(
        key: e.key,
        total: e.value.length,
        columns: [
          BoardColumnData(
            statusId: 's1',
            total: e.value.length,
            cards: e.value,
          ),
        ],
      ),
  ],
);

TaskBoardCubit _cubit(
  _FakeCatalog catalog, {
  _FakeBacklog? backlog,
  KeyValueStorage? storage,
  _FakeEvents? events,
  String username = 'ada',
}) {
  final store = storage ?? InMemoryKeyValueStorage();
  return TaskBoardCubit(
    repo: backlog ?? _FakeBacklog(),
    catalog: catalog,
    milestones: _FakeMilestones(),
    projectId: 'p1',
    boardId: LocalBoardSource.myIssuesBoardId,
    events: events,
    currentUserId: _me,
    currentUsername: username,
    source: LocalBoardSource(
      storage: store,
      projectId: 'p1',
      userId: _me,
      name: 'My Issues',
    ),
  );
}

/// Let the broadcast event reach the cubit and its emit settle.
Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  group('LocalBoardSource', () {
    test('synthesises a my_role board with no server call', () async {
      final source = LocalBoardSource(
        storage: InMemoryKeyValueStorage(),
        projectId: 'p1',
        userId: _me,
        name: 'My Issues',
      );
      final board = (await source.load()).valueOrNull!;
      expect(board.id, 'my-issues');
      expect(BoardConfig.fromMap(board.config).group, BoardGroupBy.myRole);
      expect(source.isRemote, isFalse);
    });

    test('persists the column layout and keeps the grouping forced', () async {
      final storage = InMemoryKeyValueStorage();
      final source = LocalBoardSource(
        storage: storage,
        projectId: 'p1',
        userId: _me,
        name: 'My Issues',
      );
      // Even if a caller tries to change the group, it stays my_role: the
      // lanes are what this board IS.
      await source.saveConfig(
        const BoardConfig(
          columnOrder: ['s2', 's1'],
          visibleColumnIds: ['s2'],
          group: BoardGroupBy.assignee,
        ),
      );
      final reloaded = BoardConfig.fromMap(
        (await source.load()).valueOrNull!.config,
      );
      expect(reloaded.group, BoardGroupBy.myRole);
      expect(reloaded.columnOrder, ['s2', 's1']);
      expect(reloaded.visibleColumnIds, ['s2']);
    });

    test('layout is scoped per user and per project', () async {
      final storage = InMemoryKeyValueStorage();
      LocalBoardSource src(String user, String project) => LocalBoardSource(
        storage: storage,
        projectId: project,
        userId: user,
        name: 'My Issues',
      );
      await src(_me, 'p1').saveConfig(
        const BoardConfig(columnOrder: ['s2'], visibleColumnIds: ['s2']),
      );
      final other = BoardConfig.fromMap(
        (await src('u2', 'p1').load()).valueOrNull!.config,
      );
      final otherProject = BoardConfig.fromMap(
        (await src(_me, 'p2').load()).valueOrNull!.config,
      );
      expect(other.columnOrder, isEmpty);
      expect(otherProject.columnOrder, isEmpty);
    });
  });

  group('MyIssuesLane.structuralKeysFor', () {
    test('derives every role the user holds, and only those', () {
      expect(
        MyIssuesLane.structuralKeysFor(_issue('a', assignedTo: _me), _me),
        {'assignee'},
      );
      expect(
        MyIssuesLane.structuralKeysFor(
          _issue('b', watchers: const [_me]),
          _me,
        ),
        {'watching'},
      );
      expect(
        MyIssuesLane.structuralKeysFor(_issue('c', qaAssigneeId: _me), _me),
        {'qa'},
      );
      expect(
        MyIssuesLane.structuralKeysFor(_issue('d', reviewerId: _me), _me),
        {'reviewer'},
      );
      expect(
        MyIssuesLane.structuralKeysFor(_issue('e', ownerId: _me), _me),
        {'reporter'},
      );
      expect(
        MyIssuesLane.structuralKeysFor(
          _issue('f', assignedTo: 'someone-else'),
          _me,
        ),
        isEmpty,
      );
    });

    test('an issue with several roles lands in every one of them', () {
      expect(
        MyIssuesLane.structuralKeysFor(
          _issue(
            'a',
            assignedTo: _me,
            qaAssigneeId: _me,
            watchers: const [_me],
          ),
          _me,
        ),
        {'watching', 'assignee', 'qa'},
      );
    });

    test('lane order is fixed and matches the server', () {
      expect(MyIssuesLane.wireKeys, [
        'watching',
        'assignee',
        'qa',
        'reviewer',
        'reporter',
        'mentioned',
      ]);
    });
  });

  group('TaskBoardCubit on a my_role board', () {
    test(
      'renders all six lanes in order, synthesising the empty ones',
      () async {
        final catalog = _FakeCatalog(
          [
            _status('s1'),
          ],
          _grouped({
            'assignee': [_issue('a', assignedTo: _me)],
          }),
        );
        final cubit = _cubit(catalog);
        await cubit.load();

        final state = cubit.state as TaskBoardLoaded;
        expect(catalog.lastGroup, 'my_role');
        expect([for (final l in state.lanes) l.key], MyIssuesLane.wireKeys);
        expect(state.lanes.firstWhere((l) => l.key == 'assignee').total, 1);
        // Every other lane renders empty rather than vanishing.
        expect(state.lanes.firstWhere((l) => l.key == 'qa').total, 0);
        expect(
          state.lanes
              .firstWhere((l) => l.key == 'mentioned')
              .columns
              .first
              .cards,
          isEmpty,
        );
        expect(state.lanesAreFixed, isTrue);
        await cubit.close();
      },
    );

    test('a live update re-lanes the card by its new role', () async {
      final catalog = _FakeCatalog(
        [
          _status('s1'),
        ],
        _grouped({
          'assignee': [_issue('a', assignedTo: _me)],
        }),
      );
      final events = _FakeEvents();
      final cubit = _cubit(catalog, events: events);
      await cubit.load();

      // Reassigned away, but the user is now its QA.
      events.issueUpdated(_issue('a', qaAssigneeId: _me, version: 2));
      await _settle();
      final state = cubit.state as TaskBoardLoaded;
      expect(
        state.lanes.firstWhere((l) => l.key == 'assignee').columns.first.cards,
        isEmpty,
      );
      expect(
        [
          for (final c
              in state.lanes
                  .firstWhere((l) => l.key == 'qa')
                  .columns
                  .first
                  .cards)
            c.id,
        ],
        ['a'],
      );
      await events.dispose();
      await cubit.close();
    });

    test('an issue that loses every role leaves the board', () async {
      final catalog = _FakeCatalog(
        [
          _status('s1'),
        ],
        _grouped({
          'assignee': [_issue('a', assignedTo: _me)],
        }),
      );
      final events = _FakeEvents();
      final cubit = _cubit(catalog, events: events);
      await cubit.load();

      events.issueUpdated(_issue('a', assignedTo: 'somebody', version: 2));
      await _settle();
      final state = cubit.state as TaskBoardLoaded;
      for (final lane in state.lanes) {
        for (final col in lane.columns) {
          expect(col.cards, isEmpty, reason: 'still present in ${lane.key}');
        }
      }
      await events.dispose();
      await cubit.close();
    });

    test('a description @handle puts the card in the mentioned lane', () async {
      final catalog = _FakeCatalog([_status('s1')], _grouped({}));
      final events = _FakeEvents();
      final cubit = _cubit(catalog, events: events);
      await cubit.load();

      events.issueUpdated(
        _issue('a', ownerId: 'other', description: 'ping @Ada please'),
      );
      await _settle();
      final state = cubit.state as TaskBoardLoaded;
      expect(
        [
          for (final c
              in state.lanes
                  .firstWhere((l) => l.key == 'mentioned')
                  .columns
                  .first
                  .cards)
            c.id,
        ],
        ['a'],
      );
      await events.dispose();
      await cubit.close();
    });

    test('mentioned membership is sticky across updates', () async {
      // The server put it in `mentioned` (a comment mention the client cannot
      // see). A later update must not silently drop it out of the lane.
      final catalog = _FakeCatalog(
        [
          _status('s1'),
        ],
        _grouped({
          'mentioned': [_issue('a', ownerId: 'other')],
        }),
      );
      final events = _FakeEvents();
      final cubit = _cubit(catalog, events: events);
      await cubit.load();

      events.issueUpdated(_issue('a', ownerId: 'other', version: 2));
      await _settle();
      final state = cubit.state as TaskBoardLoaded;
      expect(
        [
          for (final c
              in state.lanes
                  .firstWhere((l) => l.key == 'mentioned')
                  .columns
                  .first
                  .cards)
            c.id,
        ],
        ['a'],
        reason: 'comment mentions are invisible to the client, so stay put',
      );
      await events.dispose();
      await cubit.close();
    });

    test('creating in the QA lane makes the user its QA', () async {
      final catalog = _FakeCatalog([_status('s1')], _grouped({}));
      final backlog = _FakeBacklog();
      final cubit = _cubit(catalog, backlog: backlog);
      await cubit.load();

      await cubit.createIssueInColumn(
        subject: 'x',
        statusId: 's1',
        laneKey: 'qa',
      );
      // CreateIssueRequest cannot carry qa_assignee_id, so it is a follow-up
      // write on the created issue.
      expect(backlog.lastCreate?.assignedTo, isNull);
      expect(backlog.lastUpdate?.qaAssigneeId, _me);
      await cubit.close();
    });

    test('creating in the assignee lane presets the assignee inline', () async {
      final catalog = _FakeCatalog([_status('s1')], _grouped({}));
      final backlog = _FakeBacklog();
      final cubit = _cubit(catalog, backlog: backlog);
      await cubit.load();

      await cubit.createIssueInColumn(
        subject: 'x',
        statusId: 's1',
        laneKey: 'assignee',
      );
      expect(backlog.lastCreate?.assignedTo, _me);
      expect(backlog.lastUpdate, isNull);
      await cubit.close();
    });

    test('creating in the watching lane adds the user as a watcher', () async {
      final catalog = _FakeCatalog([_status('s1')], _grouped({}));
      final cubit = _cubit(catalog);
      await cubit.load();

      final created = await cubit.createIssueInColumn(
        subject: 'x',
        statusId: 's1',
        laneKey: 'watching',
      );
      expect(catalog.watched, ['new']);
      expect(created?.watchers, contains(_me));
      await cubit.close();
    });

    test('saving columns persists locally and refetches', () async {
      final catalog = _FakeCatalog([
        _status('s1'),
        _status('s2'),
      ], _grouped({}));
      final storage = InMemoryKeyValueStorage();
      final cubit = _cubit(catalog, storage: storage);
      await cubit.load();
      final before = catalog.fetches;

      await cubit.saveColumns(order: ['s2', 's1'], visible: ['s2']);
      expect(catalog.fetches, greaterThan(before));
      expect((cubit.state as TaskBoardLoaded).config.visibleColumnIds, ['s2']);
      await cubit.close();
    });
  });

  group('WorkItemFilter.myRole', () {
    test('round-trips as my_role on the wire', () {
      const f = WorkItemFilter(myRole: 'qa');
      expect(f.toJson()['my_role'], 'qa');
      expect(WorkItemFilter.fromJson(f.toJson()).myRole, 'qa');
    });

    test('does not count as a user-applied filter', () {
      // `isActive` gates snapshot persistence; the My Issues board must still
      // cache, because my_role is its baseline rather than a narrowing.
      expect(const WorkItemFilter(myRole: 'any').isActive, isFalse);
      expect(const WorkItemFilter(assigneeId: 'u1').isActive, isTrue);
    });
  });

  group('boardAcceptsDrop', () {
    const inWatching = BoardDragData(issueId: 'a', laneKey: 'watching');

    test('a role board refuses a drop from another lane', () {
      // Accepting it would patch only the status, leaving the card in a lane
      // that no longer describes it.
      expect(
        boardAcceptsDrop(
          drag: inWatching,
          laneKey: 'assignee',
          lanesAreFixed: true,
        ),
        isFalse,
      );
    });

    test('a role board accepts a drop within the same lane', () {
      expect(
        boardAcceptsDrop(
          drag: inWatching,
          laneKey: 'watching',
          lanesAreFixed: true,
        ),
        isTrue,
      );
    });

    test('ordinary boards accept cross-lane drops as before', () {
      // Dragging across an assignee/epic/priority lane is a legitimate move
      // there, so nothing changes for them.
      expect(
        boardAcceptsDrop(
          drag: inWatching,
          laneKey: 'anything-else',
          lanesAreFixed: false,
        ),
        isTrue,
      );
      expect(
        boardAcceptsDrop(
          drag: const BoardDragData(issueId: 'a'),
          laneKey: null,
          lanesAreFixed: false,
        ),
        isTrue,
      );
    });
  });
}
