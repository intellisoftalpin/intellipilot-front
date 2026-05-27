import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/core/network/api_client.dart';
import 'package:intellipilot/core/network/api_config.dart';
import 'package:intellipilot/core/utils/uuid_gen.dart';
import 'package:intellipilot/features/backlog/data/backlog_repository_impl.dart';
import 'package:intellipilot/features/backlog/data/dtos/backlog_dtos.dart';

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

ResponseBody _ok(
  String body, {
  int status = 200,
  Map<String, List<String>>? extraHeaders,
}) =>
    ResponseBody.fromString(
      body,
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
        ...?extraHeaders,
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

const _epicJson =
    '{"id":"e1","project_id":"p1","ref":1,"subject":"Auth","description":"",'
    '"status_id":null,"color":"#cc0000","owner_id":null,"assigned_to":null,'
    '"order":1.0,"version":3,"created_at":"2026-05-27T00:00:00Z",'
    '"modified_at":"2026-05-27T00:00:00Z"}';

const _usJson =
    '{"id":"u1","project_id":"p1","ref":42,"subject":"Sign in","description":"",'
    '"status_id":"s1","epic_id":"e1","milestone_id":null,"points_id":null,'
    '"owner_id":null,"assigned_to":null,"order":2.5,"version":1,'
    '"created_at":"2026-05-27T00:00:00Z","modified_at":"2026-05-27T00:00:00Z"}';

void main() {
  group('BacklogRepositoryImpl', () {
    test('listEpics unwraps the {epics: [...]} envelope', () async {
      final repo = BacklogRepositoryImpl(
        _client(_Adapter((_) async => _ok('{"epics":[$_epicJson]}'))),
      );
      final res = await repo.listEpics('p1');
      expect(res.valueOrNull?.single.reference, 1);
      expect(res.valueOrNull?.single.color, '#cc0000');
    });

    test('listUserStories unwraps the {user_stories: [...]} envelope',
        () async {
      final repo = BacklogRepositoryImpl(
        _client(_Adapter((_) async => _ok('{"user_stories":[$_usJson]}'))),
      );
      final res = await repo.listUserStories('p1');
      expect(res.valueOrNull?.single.reference, 42);
      expect(res.valueOrNull?.single.epicId, 'e1');
    });

    test('getEpic captures the ETag header for round-trip', () async {
      final adapter = _Adapter(
        (_) async => _ok(
          _epicJson,
          extraHeaders: {
            'etag': ['"v3"'],
          },
        ),
      );
      final repo = BacklogRepositoryImpl(_client(adapter));
      final res = await repo.getEpic('p1', 'e1');
      expect(res.valueOrNull?.etag, '"v3"');
    });

    test('updateEpic sends If-Match from the supplied ETag', () async {
      final adapter = _Adapter((_) async => _ok(_epicJson));
      final repo = BacklogRepositoryImpl(_client(adapter));
      await repo.updateEpic(
        'p1',
        'e1',
        body: const UpdateEpicRequest(subject: 'Renamed'),
        etag: '"v3"',
      );
      expect(adapter.lastRequest?.method, 'PATCH');
      expect(adapter.lastRequest?.headers['If-Match'], '"v3"');
    });

    test('moveUserStory posts before/after to /move', () async {
      final adapter = _Adapter((_) async => _ok('{}'));
      final repo = BacklogRepositoryImpl(_client(adapter));
      await repo.moveUserStory(
        'p1',
        'u1',
        const ReorderRequest(beforeId: 'b1', afterId: 'a1'),
      );
      expect(
        adapter.lastRequest?.path,
        '/api/v1/projects/p1/userstories/u1/move',
      );
      expect(adapter.lastRequest?.data, {
        'before_id': 'b1',
        'after_id': 'a1',
      });
    });

    test('bulkCreateUserStories serialises {items: [...]}', () async {
      final adapter = _Adapter(
        (_) async => _ok('{"user_stories":[$_usJson]}', status: 201),
      );
      final repo = BacklogRepositoryImpl(_client(adapter));
      await repo.bulkCreateUserStories(
        'p1',
        const BulkCreateUserStoriesRequest([
          BulkCreateUserStoryItem(subject: 'A'),
          BulkCreateUserStoryItem(subject: 'B', epicId: 'e1'),
        ]),
      );
      expect(adapter.lastRequest?.data, {
        'items': [
          {'subject': 'A'},
          {'subject': 'B', 'epic_id': 'e1'},
        ],
      });
    });
  });
}
