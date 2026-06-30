import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/core/network/api_client.dart';
import 'package:intellipilot/core/network/api_config.dart';
import 'package:intellipilot/core/utils/uuid_gen.dart';
import 'package:intellipilot/features/board/data/board_repository_impl.dart';
import 'package:intellipilot/features/milestones/data/milestones_repository_impl.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);
  final Future<ResponseBody> Function(RequestOptions) respond;
  RequestOptions? lastRequest;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<dynamic>? cancelFuture,
  ) {
    lastRequest = options;
    return respond(options);
  }
}

ResponseBody _ok(String body) => ResponseBody.fromString(
  body,
  200,
  headers: {
    Headers.contentTypeHeader: ['application/json'],
  },
);

ApiClient _client(_Adapter adapter) {
  final dio = Dio()..httpClientAdapter = adapter;
  return ApiClient(
    config: const ApiConfig(baseUrl: 'http://localhost'),
    uuidGen: const DefaultUuidGen(),
    tokenProvider: () => null,
    dio: dio,
  );
}

const _milestoneJson =
    '{"id":"m1","project_id":"p1","name":"Sprint 1","slug":"sprint-1", '
    '"start_date":"2026-05-01","end_date":"2026-05-15","closed":false, '
    '"closed_at":null,"order":1.0,"version":1, '
    '"created_at":"2026-05-01T00:00:00Z","modified_at":"2026-05-01T00:00:00Z"}';

const _statusJson =
    '{"id":"s1","project_id":"p1","kind":"us_status","name":"In Progress", '
    '"slug":"in-progress","color":"#cccccc","order":2.0,"is_closed":false, '
    '"created_at":"2026-05-01T00:00:00Z"}';

const _storyJson =
    '{"id":"u1","project_id":"p1","ref":1,"subject":"Auth","description":"", '
    '"status_id":"s1","epic_id":null,"milestone_id":"m1","points_id":null, '
    '"owner_id":null,"assigned_to":"user-1","order":1.0,"version":1, '
    '"created_at":"2026-05-01T00:00:00Z","modified_at":"2026-05-01T00:00:00Z", '
    '"tasks":[]}';

void main() {
  group('MilestonesRepositoryImpl', () {
    test('list unwraps {milestones: [...]} envelope', () async {
      final repo = MilestonesRepositoryImpl(
        _client(_Adapter((_) async => _ok('{"milestones":[$_milestoneJson]}'))),
      );
      final res = await repo.list('p1');
      expect(res.valueOrNull?.single.name, 'Sprint 1');
      expect(res.valueOrNull?.single.closed, false);
    });
  });

  group('BoardRepositoryImpl', () {
    test('load returns columns with nested issues + subtasks', () async {
      final adapter = _Adapter(
        (_) async => _ok(
          '{"milestone_id":"m1","columns":[{"status":$_statusJson,'
          '"issues":[$_storyJson]}]}',
        ),
      );
      final repo = BoardRepositoryImpl(_client(adapter));
      final res = await repo.load('p1', 'm1');
      final snap = res.valueOrNull;
      expect(snap?.milestoneId, 'm1');
      expect(snap?.columns.length, 1);
      expect(snap?.columns.single.status?.name, 'In Progress');
      expect(snap?.columns.single.issues.single.issue.subject, 'Auth');
      expect(
        adapter.lastRequest?.path,
        '/api/v1/projects/p1/milestones/m1/board',
      );
    });

    test('null status column parses into BoardColumn with no status', () async {
      final repo = BoardRepositoryImpl(
        _client(
          _Adapter(
            (_) async => _ok(
              '{"milestone_id":"m1","columns":[{"status":null,'
              '"issues":[]}]}',
            ),
          ),
        ),
      );
      final res = await repo.load('p1', 'm1');
      expect(res.valueOrNull?.columns.single.status, isNull);
    });
  });
}
