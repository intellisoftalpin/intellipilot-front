import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/core/network/api_client.dart';
import 'package:intellipilot/core/network/api_config.dart';
import 'package:intellipilot/core/utils/uuid_gen.dart';
import 'package:intellipilot/features/wiki/data/dtos/wiki_dtos.dart';
import 'package:intellipilot/features/wiki/data/wiki_repository_impl.dart';

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
  Map<String, List<String>>? extra,
}) => ResponseBody.fromString(
  body,
  status,
  headers: {
    Headers.contentTypeHeader: ['application/json'],
    ...?extra,
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

const _pageJson =
    '{"id":"w1","project_id":"p1","slug":"hello","title":"Hello", '
    '"body":"hi","body_html":"<p>hi</p>","version":3,"editor_id":"u1", '
    '"created_at":"2026-05-01T00:00:00Z","modified_at":"2026-05-28T00:00:00Z"}';

const _revisionJson =
    '{"id":"r1","page_id":"w1","rev":1,"title":"Hello","body":"first", '
    '"editor_id":"u1","created_at":"2026-05-01T00:00:00Z"}';

void main() {
  group('WikiRepositoryImpl', () {
    test('list unwraps the {pages: [...]} envelope', () async {
      final repo = WikiRepositoryImpl(
        _client(_Adapter((_) async => _ok('{"pages":[$_pageJson]}'))),
      );
      final res = await repo.list('p1');
      expect(res.valueOrNull?.single.title, 'Hello');
    });

    test('get captures the ETag header', () async {
      final adapter = _Adapter(
        (_) async => _ok(
          _pageJson,
          extra: {
            'etag': ['"w1:3"'],
          },
        ),
      );
      final repo = WikiRepositoryImpl(_client(adapter));
      final res = await repo.get('p1', 'w1');
      expect(res.valueOrNull?.etag, '"w1:3"');
    });

    test('update sends If-Match from the supplied etag', () async {
      final adapter = _Adapter((_) async => _ok(_pageJson));
      final repo = WikiRepositoryImpl(_client(adapter));
      await repo.update(
        'p1',
        'w1',
        body: const UpdateWikiPageRequest(body: 'new'),
        etag: '"w1:3"',
      );
      expect(adapter.lastRequest?.method, 'PATCH');
      expect(adapter.lastRequest?.headers['If-Match'], '"w1:3"');
      expect(adapter.lastRequest?.data, {'body': 'new'});
    });

    test('listRevisions unwraps {revisions: [...]} envelope', () async {
      final adapter = _Adapter(
        (_) async => _ok('{"revisions":[$_revisionJson]}'),
      );
      final repo = WikiRepositoryImpl(_client(adapter));
      final res = await repo.listRevisions('p1', 'w1');
      expect(res.valueOrNull?.single.rev, 1);
    });

    test('diff returns the {from, to, diff} envelope', () async {
      final adapter = _Adapter(
        (_) async => _ok(
          r'{"from":2,"to":3,"diff":"@@ -1 +1 @@\n-old\n+new"}',
        ),
      );
      final repo = WikiRepositoryImpl(_client(adapter));
      final res = await repo.diff('p1', 'w1', 2, to: 3);
      final d = res.valueOrNull;
      expect(d?.from, 2);
      expect(d?.to, 3);
      expect(d?.diff.contains('@@'), true);
      expect(adapter.lastRequest?.queryParameters, {'to': '3'});
    });

    test('restore posts to /revisions/:rev/restore', () async {
      final adapter = _Adapter((_) async => _ok(_pageJson));
      final repo = WikiRepositoryImpl(_client(adapter));
      await repo.restore('p1', 'w1', 1);
      expect(
        adapter.lastRequest?.path,
        '/api/v1/projects/p1/wiki/w1/revisions/1/restore',
      );
    });
  });
}
