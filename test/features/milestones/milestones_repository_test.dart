import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/core/network/api_client.dart';
import 'package:intellipilot/core/network/api_config.dart';
import 'package:intellipilot/core/utils/uuid_gen.dart';
import 'package:intellipilot/features/milestones/data/dtos/milestone_dtos.dart';
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

ResponseBody _ok(String body, {int status = 200}) => ResponseBody.fromString(
  body,
  status,
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

void main() {
  group('MilestonesRepositoryImpl extended', () {
    test('create posts start_date and end_date as ISO YYYY-MM-DD', () async {
      final adapter = _Adapter((_) async => _ok(_milestoneJson, status: 201));
      final repo = MilestonesRepositoryImpl(_client(adapter));
      await repo.create(
        'p1',
        CreateMilestoneRequest(
          name: 'Sprint 1',
          startDate: DateTime.utc(2026, 5, 1),
          endDate: DateTime.utc(2026, 5, 15),
        ),
      );
      expect(adapter.lastRequest?.method, 'POST');
      expect(adapter.lastRequest?.data, {
        'name': 'Sprint 1',
        'start_date': '2026-05-01',
        'end_date': '2026-05-15',
      });
    });

    test(
      'update with null start_date clears it; absent leaves it alone',
      () async {
        final adapter = _Adapter((_) async => _ok(_milestoneJson));
        final repo = MilestonesRepositoryImpl(_client(adapter));
        await repo.update(
          'p1',
          'm1',
          body: const UpdateMilestoneRequest(name: 'Renamed', startDate: null),
        );
        expect(adapter.lastRequest?.method, 'PATCH');
        expect(adapter.lastRequest?.data, {
          'name': 'Renamed',
          'start_date': null,
        });
      },
    );

    test('close posts to /close', () async {
      final adapter = _Adapter((_) async => _ok('{}'));
      final repo = MilestonesRepositoryImpl(_client(adapter));
      await repo.close('p1', 'm1');
      expect(
        adapter.lastRequest?.path,
        '/api/v1/projects/p1/milestones/m1/close',
      );
    });

    test(
      'stats unwraps the bare {total_points, completed_points, …} body',
      () async {
        final adapter = _Adapter(
          (_) async => _ok(
            '{"total_points":12.5,"completed_points":7.0,'
            '"total_tasks":20,"completed_tasks":15}',
          ),
        );
        final repo = MilestonesRepositoryImpl(_client(adapter));
        final res = await repo.stats('p1', 'm1');
        final s = res.valueOrNull;
        expect(s?.totalPoints, 12.5);
        expect(s?.completedTasks, 15);
        expect(s?.pointsFraction, closeTo(7 / 12.5, 1e-9));
      },
    );
  });
}
