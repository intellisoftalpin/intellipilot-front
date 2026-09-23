import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/core/network/api_client.dart';
import 'package:intellipilot/core/network/api_config.dart';
import 'package:intellipilot/core/utils/uuid_gen.dart';
import 'package:intellipilot/features/search/data/search_repository_impl.dart';

class _Adapter implements HttpClientAdapter {
  RequestOptions? lastRequest;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<dynamic>? cancelFuture,
  ) async {
    lastRequest = options;
    return ResponseBody.fromString(
      '{"results":[],"fuzzy":false}',
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }
}

const _pid = '0190f0e0-0000-7000-8000-00000000000a';

void main() {
  late _Adapter adapter;
  late SearchRepositoryImpl repo;

  setUp(() {
    adapter = _Adapter();
    repo = SearchRepositoryImpl(
      ApiClient(
        config: const ApiConfig(baseUrl: 'http://localhost'),
        uuidGen: const DefaultUuidGen(),
        tokenProvider: () => null,
        dio: Dio()..httpClientAdapter = adapter,
      ),
    );
  });

  test('sends project ids through', () async {
    await repo.search('hello', projectId: _pid, boostProjectId: _pid);

    expect(adapter.lastRequest!.queryParameters, {
      'q': 'hello',
      'project_id': _pid,
      'boost_project_id': _pid,
    });
  });

  // The server types both project parameters as ids and answers 400 to
  // anything else — rejecting the whole search, not just the ranking. A
  // caller passing the URL's short project ref (`/projects/ps/...`) used to
  // make the palette look empty inside every project; a bad value must cost
  // the boost at most.
  test('drops a project ref that is not an id', () async {
    await repo.search('hello', projectId: 'ps', boostProjectId: 'ps');

    expect(adapter.lastRequest!.queryParameters, {'q': 'hello'});
  });

  test('passes types along and omits an empty list', () async {
    await repo.search('hello', types: ['issue', 'meeting']);
    expect(adapter.lastRequest!.queryParameters['types'], 'issue,meeting');

    await repo.search('hello', types: const []);
    expect(adapter.lastRequest!.queryParameters.containsKey('types'), isFalse);
  });
}
