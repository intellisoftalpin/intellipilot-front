import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/core/network/api_client.dart';
import 'package:intellipilot/core/network/api_config.dart';
import 'package:intellipilot/core/utils/uuid_gen.dart';
import 'package:intellipilot/features/catalog/data/catalog_repository_impl.dart';
import 'package:intellipilot/features/catalog/data/dtos/catalog_dtos.dart';

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

void main() {
  group('CatalogRepositoryImpl', () {
    test('listTaxonomy URL embeds the kind wire string', () async {
      final adapter = _Adapter((_) async => _ok('{"items":[]}'));
      final repo = CatalogRepositoryImpl(_client(adapter));
      await repo.listTaxonomy('p1', TaxonomyKind.issueStatus);
      expect(
        adapter.lastRequest?.path,
        '/api/v1/projects/p1/taxonomy/issue_status',
      );
    });

    test('createTaxonomyItem sends is_closed for status kinds only', () async {
      final adapter = _Adapter(
        (_) async => _ok(
          '{"id":"i1","project_id":"p1","kind":"us_status","name":"Done",'
          '"slug":"done","color":"#669900","order":1.0,"is_closed":true,'
          '"created_at":"2026-05-27T00:00:00Z"}',
          status: 201,
        ),
      );
      final repo = CatalogRepositoryImpl(_client(adapter));
      await repo.createTaxonomyItem(
        'p1',
        TaxonomyKind.issueStatus,
        const CreateTaxonomyItemRequest(
          name: 'Done',
          slug: 'done',
          color: '#669900',
          isClosed: true,
        ),
      );
      expect(adapter.lastRequest?.data, {
        'name': 'Done',
        'slug': 'done',
        'color': '#669900',
        'emoji': '',
        'is_closed': true,
      });
    });

    test('moveTaxonomyItem posts to /move with before/after ids', () async {
      final adapter = _Adapter((_) async => _ok('{}'));
      final repo = CatalogRepositoryImpl(_client(adapter));
      await repo.moveTaxonomyItem(
        'p1',
        TaxonomyKind.priority,
        'item-id',
        const MoveTaxonomyItemRequest(beforeId: 'b1', afterId: 'a1'),
      );
      expect(
        adapter.lastRequest?.path,
        '/api/v1/projects/p1/taxonomy/priority/item-id/move',
      );
      expect(adapter.lastRequest?.data, {
        'before_id': 'b1',
        'after_id': 'a1',
      });
    });

    test('listLabels unwraps the {labels: [...]} envelope', () async {
      final adapter = _Adapter(
        (_) async => _ok(
          '{"labels":[{"id":"l1","project_id":"p1","name":"bug","color":"#cc0000",'
          '"created_at":"2026-05-27T00:00:00Z"}]}',
        ),
      );
      final repo = CatalogRepositoryImpl(_client(adapter));
      final res = await repo.listLabels('p1');
      expect(res.valueOrNull?.single.name, 'bug');
      expect(res.valueOrNull?.single.color, '#cc0000');
    });

    test('listComponents unwraps the {components: [...]} envelope', () async {
      final adapter = _Adapter(
        (_) async => _ok(
          '{"components":[{"id":"c1","project_id":"p1","name":"api",'
          '"color":"#0079bc",'
          '"created_at":"2026-05-27T00:00:00Z"}]}',
        ),
      );
      final repo = CatalogRepositoryImpl(_client(adapter));
      final res = await repo.listComponents('p1');
      expect(res.valueOrNull?.single.name, 'api');
      expect(res.valueOrNull?.single.color, '#0079bc');
    });

    test('TaxonomyKind.hasClosed only true for status kinds', () {
      expect(TaxonomyKind.issueStatus.hasClosed, isTrue);
      expect(TaxonomyKind.issueStatus.hasClosed, isTrue);
      expect(TaxonomyKind.issueStatus.hasClosed, isTrue);
      expect(TaxonomyKind.issueType.hasClosed, isFalse);
      expect(TaxonomyKind.priority.hasClosed, isFalse);
      expect(TaxonomyKind.size.hasClosed, isFalse);
    });

    test('TaxonomyKind.hasValue only true for size kind', () {
      expect(TaxonomyKind.size.hasValue, isTrue);
      for (final k in TaxonomyKind.values.where(
        (k) => k != TaxonomyKind.size,
      )) {
        expect(k.hasValue, isFalse, reason: '${k.wire} should not carry value');
      }
    });
  });

  group('considered-completed status flag', () {
    test('parses independently of is_closed and defaults to null off-kind', () {
      // A status that finishes the work without closing the issue — the case
      // the flag exists for.
      final staging = TaxonomyItem.fromJson({
        'id': 's1',
        'project_id': 'p1',
        'kind': 'issue_status',
        'name': 'In staging',
        'slug': 'in-staging',
        'order': 4.0,
        'is_closed': false,
        'counts_as_done': true,
        'created_at': '2026-05-27T00:00:00Z',
      });
      expect(staging.isClosed, isFalse);
      expect(staging.countsAsDone, isTrue);

      // And the reverse: closed, but the project has chosen not to count it.
      final archived = TaxonomyItem.fromJson({
        'id': 's2',
        'project_id': 'p1',
        'kind': 'issue_status',
        'name': 'Archived',
        'slug': 'archived',
        'order': 6.0,
        'is_closed': true,
        'counts_as_done': false,
        'created_at': '2026-05-27T00:00:00Z',
      });
      expect(archived.isClosed, isTrue);
      expect(archived.countsAsDone, isFalse);

      // Kinds without the flag report null rather than a misleading false.
      final priority = TaxonomyItem.fromJson({
        'id': 'p9',
        'project_id': 'p1',
        'kind': 'priority',
        'name': 'Low',
        'slug': 'low',
        'order': 1.0,
        'created_at': '2026-05-27T00:00:00Z',
      });
      expect(priority.countsAsDone, isNull);
      expect(priority.kind.hasCountsAsDone, isFalse);
    });

    test('only the status kind advertises the flag', () {
      expect(TaxonomyKind.issueStatus.hasCountsAsDone, isTrue);
      for (final k in TaxonomyKind.values.where(
        (k) => k != TaxonomyKind.issueStatus,
      )) {
        expect(k.hasCountsAsDone, isFalse, reason: r'$k');
      }
    });

    test('create and update send the flag only when set', () {
      expect(
        const CreateTaxonomyItemRequest(
          name: 'In staging',
          slug: 'in-staging',
          countsAsDone: true,
        ).toJson(),
        {
          'name': 'In staging',
          'slug': 'in-staging',
          'color': '',
          'emoji': '',
          'counts_as_done': true,
        },
      );
      // Toggling the done flag must not smuggle an is_closed change with it.
      final patch = const UpdateTaxonomyItemRequest(
        countsAsDone: true,
      ).toJson();
      expect(patch, {'counts_as_done': true});
      expect(patch.containsKey('is_closed'), isFalse);
    });
  });
}
