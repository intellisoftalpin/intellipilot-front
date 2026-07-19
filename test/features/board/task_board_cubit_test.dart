import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/core/work_items/work_item_filter.dart';
import 'package:intellipilot/features/backlog/data/dtos/backlog_dtos.dart';
import 'package:intellipilot/features/backlog/domain/backlog_repository.dart';
import 'package:intellipilot/features/board/presentation/cubits/task_board_cubit.dart';
import 'package:intellipilot/features/catalog/data/dtos/catalog_dtos.dart';
import 'package:intellipilot/features/catalog/domain/catalog_repository.dart';
import 'package:intellipilot/features/milestones/data/dtos/milestone_dtos.dart';
import 'package:intellipilot/features/milestones/domain/milestones_repository.dart';

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

Issue _issue(String id, {String? statusId}) => Issue(
  id: id,
  projectId: 'p1',
  reference: 1,
  subject: 'Issue $id',
  description: '',
  labels: const [],
  components: const [],
  statusId: statusId,
  order: 1,
  version: 1,
  createdAt: DateTime(2026),
  modifiedAt: DateTime(2026),
);

class _FakeCatalog extends Fake implements CatalogRepository {
  _FakeCatalog(this.board, this.statuses, this.data);
  final Board board;
  final List<TaxonomyItem> statuses;
  final BoardData data;

  Map<String, dynamic>? lastFilter;
  String? lastGroup;
  List<String>? lastColumns;

  @override
  Future<Result<Board, AppFailure>> getBoard(
    String projectId,
    String boardId,
  ) async => Ok(board);

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
    lastFilter = filter;
    lastGroup = group;
    lastColumns = columns;
    return Ok(data);
  }
}

class _FakeBacklog extends Fake implements BacklogRepository {
  CreateIssueRequest? lastCreate;

  @override
  Future<Result<List<Epic>, AppFailure>> listEpics(String projectId) async =>
      const Ok([]);

  @override
  Future<Result<Issue, AppFailure>> createIssue(
    String projectId,
    CreateIssueRequest body,
  ) async {
    lastCreate = body;
    return Ok(_issue('created', statusId: body.statusId));
  }
}

class _FakeMilestones extends Fake implements MilestonesRepository {
  @override
  Future<Result<List<Milestone>, AppFailure>> list(String projectId) async =>
      const Ok([]);
}

TaskBoardCubit _cubit(_FakeCatalog catalog, {_FakeBacklog? backlog}) =>
    TaskBoardCubit(
      repo: backlog ?? _FakeBacklog(),
      catalog: catalog,
      milestones: _FakeMilestones(),
      projectId: 'p1',
      boardId: 'b1',
    );

void main() {
  group('TaskBoardCubit', () {
    test(
      'flat board: orders columns by config + merges locked filter',
      () async {
        const board = Board(
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
            'filters': {'type': 't1'},
            'column_limit': 50,
          },
        );
        final data = BoardData(
          columns: [
            BoardColumnData(
              statusId: 's2',
              total: 1,
              cards: [_issue('i2', statusId: 's2')],
            ),
            BoardColumnData(
              statusId: 's1',
              total: 3,
              cards: [_issue('i1', statusId: 's1')],
            ),
          ],
        );
        final catalog = _FakeCatalog(board, [
          _status('s1'),
          _status('s2'),
        ], data);
        final cubit = _cubit(catalog);
        await cubit.load();

        final state = cubit.state;
        expect(state, isA<TaskBoardLoaded>());
        state as TaskBoardLoaded;
        // Reordered to the config's visible order (s1 then s2).
        expect(state.flatColumns.map((c) => c.statusId).toList(), ['s1', 's2']);
        expect(state.flatColumns.first.total, 3);
        // Locked filter forwarded to fetchBoardData.
        expect(catalog.lastFilter?['type'], 't1');
        expect(catalog.lastGroup, isNull);
        expect(catalog.lastColumns, ['s1', 's2']);
      },
    );

    test(
      'ad-hoc filter merges with locked; group dimension is stripped',
      () async {
        const board = Board(
          id: 'b1',
          projectId: 'p1',
          visibility: 'shared',
          name: 'Grouped',
          color: '',
          order: 0,
          config: {
            'columns': {
              'visible': ['s1'],
              'order': ['s1'],
            },
            'group': 'component',
            // Locking the group dimension must NOT leak into the fetch filter.
            'filters': {'type': 't1', 'component': 'c1'},
            'column_limit': 50,
          },
        );
        const data = BoardData(
          group: 'component',
          lanes: [
            BoardLaneData(
              key: 'none',
              total: 0,
              columns: [BoardColumnData(statusId: 's1', total: 0, cards: [])],
            ),
          ],
        );
        final catalog = _FakeCatalog(board, [_status('s1')], data);
        final cubit = _cubit(catalog);
        await cubit.load();

        // Group stripped; locked type kept.
        expect(catalog.lastFilter?['type'], 't1');
        expect(catalog.lastFilter?.containsKey('component'), isFalse);
        expect(catalog.lastGroup, 'component');

        cubit.setAdhocFilter(const WorkItemFilter(search: 'foo'));
        await Future<void>.delayed(Duration.zero);
        expect(catalog.lastFilter?['search'], 'foo');
        expect(catalog.lastFilter?['type'], 't1');

        final state = cubit.state as TaskBoardLoaded;
        expect(state.lanes.single.key, 'none');
      },
    );

    test(
      'createIssueInColumn presets status + swimlane and returns the issue',
      () async {
        const board = Board(
          id: 'b1',
          projectId: 'p1',
          visibility: 'shared',
          name: 'Grouped',
          color: '',
          order: 0,
          config: {
            'columns': {
              'visible': ['s1'],
              'order': ['s1'],
            },
            'group': 'assignee',
            'column_limit': 50,
          },
        );
        const data = BoardData(
          group: 'assignee',
          lanes: [
            BoardLaneData(
              key: 'u1',
              total: 0,
              columns: [BoardColumnData(statusId: 's1', total: 0, cards: [])],
            ),
          ],
        );
        final catalog = _FakeCatalog(board, [_status('s1')], data);
        final backlog = _FakeBacklog();
        final cubit = _cubit(catalog, backlog: backlog);
        await cubit.load();

        final created = await cubit.createIssueInColumn(
          subject: 'From column',
          statusId: 's1',
          typeId: 't9',
          laneKey: 'u1',
        );

        // The created issue comes back (the caller opens its detail sheet).
        expect(created, isNotNull);
        expect(created!.id, 'created');
        // Column status + swimlane value preset on the request.
        final req = backlog.lastCreate;
        expect(req, isNotNull);
        expect(req!.subject, 'From column');
        expect(req.statusId, 's1');
        expect(req.typeId, 't9');
        expect(req.assignedTo, 'u1');

        // The 'none' lane presets nothing.
        await cubit.createIssueInColumn(
          subject: 'Unassigned lane',
          statusId: 's1',
          laneKey: 'none',
        );
        expect(backlog.lastCreate!.assignedTo, isNull);
      },
    );
  });
}
