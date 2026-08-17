import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/core/network/api_client.dart';
import 'package:intellipilot/core/network/api_config.dart';
import 'package:intellipilot/core/utils/uuid_gen.dart';
import 'package:intellipilot/features/docs/data/docs_repository_impl.dart';
import 'package:intellipilot/features/docs/data/dtos/doc_dtos.dart';
import 'package:intellipilot/features/docs/presentation/widgets/doc_sources_tab.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);
  final Future<ResponseBody> Function(RequestOptions) respond;
  final List<RequestOptions> requests = [];

  RequestOptions get last => requests.last;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<dynamic>? cancelFuture,
  ) {
    requests.add(options);
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

const _sourceJson =
    '{"id":"s1","project_id":"p1","name":"Handbook","kind":"git", '
    '"ssh_url":"git@github.com:acme/docs.git", '
    '"web_url":"https://github.com/acme/docs","branch":"main", '
    '"doc_path":"docs","read_only":false,"order":1.0,"color":"#3F8CFF", '
    '"emoji":"📘","cache_status":"ready","head_commit":"abc123", '
    '"cache_bytes":4096,"last_synced_at":"2026-08-01T10:00:00Z", '
    '"version":3,"created_at":"2026-07-01T00:00:00Z", '
    '"modified_at":"2026-08-01T00:00:00Z"}';

void main() {
  group('DocsRepositoryImpl', () {
    test('listSources unwraps the {doc_sources: [...]} body', () async {
      final adapter = _Adapter(
        (_) async => _ok('{"doc_sources":[$_sourceJson]}'),
      );
      final repo = DocsRepositoryImpl(_client(adapter));
      final sources = (await repo.listSources('p1')).valueOrNull;
      expect(adapter.last.path, '/api/v1/projects/p1/doc-sources');
      expect(sources, hasLength(1));
      expect(sources!.single.name, 'Handbook');
      expect(sources.single.docPath, 'docs');
      expect(sources.single.cacheStatus, DocCacheStatus.ready);
      // Derived from id + version, so a PATCH can guard on it.
      expect(sources.single.etag, '"s1:3"');
      expect(sources.single.hasContent, isTrue);
    });

    test('a source with no head commit reports no content yet', () async {
      final adapter = _Adapter(
        (_) async => _ok(
          '{"id":"s2","project_id":"p1","name":"New", '
          '"ssh_url":"git@h:a/b.git","web_url":"https://h/a/b", '
          '"branch":"main","doc_path":"","read_only":false,"order":1.0, '
          '"color":"","emoji":"","cache_status":"pending","cache_bytes":0, '
          '"version":1,"created_at":"2026-08-01T00:00:00Z", '
          '"modified_at":"2026-08-01T00:00:00Z"}',
        ),
      );
      final repo = DocsRepositoryImpl(_client(adapter));
      final source = (await repo.getSource('p1', 's2')).valueOrNull;
      expect(source?.hasContent, isFalse);
      expect(source?.cacheStatus, DocCacheStatus.pending);
      expect(source?.lastSyncedAt, isNull);
    });

    test('updateSource carries the ETag as If-Match', () async {
      final adapter = _Adapter((_) async => _ok(_sourceJson));
      final repo = DocsRepositoryImpl(_client(adapter));
      await repo.updateSource(
        'p1',
        's1',
        body: const UpdateDocSourceRequest(name: 'Renamed'),
        etag: '"s1:3"',
      );
      expect(adapter.last.method, 'PATCH');
      expect(adapter.last.headers['If-Match'], '"s1:3"');
      // Only the touched field is sent, so a PATCH cannot clobber the rest.
      expect(adapter.last.data, {'name': 'Renamed'});
    });

    test('createSource asks for an inline deploy key when named', () async {
      final adapter = _Adapter((_) async => _ok(_sourceJson, status: 201));
      final repo = DocsRepositoryImpl(_client(adapter));
      await repo.createSource(
        'p1',
        const CreateDocSourceRequest(
          name: 'Handbook',
          sshUrl: 'git@github.com:acme/docs.git',
          webUrl: 'https://github.com/acme/docs',
          branch: 'main',
          docPath: 'docs',
          newKeyName: 'docs-deploy',
        ),
      );
      final body = adapter.last.data as Map<String, dynamic>;
      // A documentation deploy key only ever reads.
      expect(body['new_key'], {'name': 'docs-deploy', 'read_only': true});
      expect(body.containsKey('ssh_key_id'), isFalse);
    });

    test('tree parses the nested hierarchy and its entry point', () async {
      final adapter = _Adapter(
        (_) async => _ok(
          '{"source_id":"s1","commit":"abc123","entry_path":"README.md", '
          '"entries":[{"path":"guides","name":"guides","kind":"dir", '
          '"children":[{"path":"guides/intro.md","name":"intro.md", '
          '"kind":"doc","size":120}]}, '
          '{"path":"README.md","name":"README.md","kind":"doc","size":80}]}',
        ),
      );
      final repo = DocsRepositoryImpl(_client(adapter));
      final tree = (await repo.tree('p1', 's1')).valueOrNull;
      expect(adapter.last.path, '/api/v1/projects/p1/doc-sources/s1/tree');
      expect(tree!.entryPath, 'README.md');
      expect(tree.entries, hasLength(2));
      expect(tree.entries.first.isDir, isTrue);
      expect(tree.entries.first.children.single.path, 'guides/intro.md');
      // Flattening skips directories, giving the document list for prev/next.
      expect(tree.documents.map((d) => d.path), [
        'guides/intro.md',
        'README.md',
      ]);
    });

    test(
      'doc sends the path as a query parameter and parses the blob id',
      () async {
        final adapter = _Adapter(
          (_) async => _ok(
            r'{"source_id":"s1","path":"guides/intro.md","body":"# Intro\n", '
            '"blob_oid":"deadbeef","commit":"abc123","can_edit":true, '
            '"last_commit":{"sha":"abc123","author_name":"Ann", '
            '"message":"tidy up","committed_at":"2026-08-01T09:00:00Z"}}',
          ),
        );
        final repo = DocsRepositoryImpl(_client(adapter));
        final doc = (await repo.doc('p1', 's1', 'guides/intro.md')).valueOrNull;
        expect(adapter.last.queryParameters, {'path': 'guides/intro.md'});
        expect(doc!.body, '# Intro\n');
        expect(doc.canEdit, isTrue);
        expect(doc.fileName, 'intro.md');
        // The save guard is the blob id, not the source version.
        expect(doc.etag, '"deadbeef"');
        expect(doc.lastCommit?.authorName, 'Ann');
        expect(doc.lastCommit?.shortSha, 'abc123');
      },
    );

    test('saveDoc guards on the blob id and re-reads the document', () async {
      final adapter = _Adapter((options) async {
        if (options.method == 'PUT') return _ok('{"commit":"newsha"}');
        return _ok(
          r'{"source_id":"s1","path":"a.md","body":"# New\n", '
          '"blob_oid":"newblob","commit":"newsha","can_edit":true}',
        );
      });
      final repo = DocsRepositoryImpl(_client(adapter));
      final saved = await repo.saveDoc(
        'p1',
        's1',
        path: 'a.md',
        content: '# New\n',
        etag: '"oldblob"',
        message: 'tidy',
      );
      final put = adapter.requests.firstWhere((r) => r.method == 'PUT');
      expect(put.headers['If-Match'], '"oldblob"');
      expect(put.data, {'content': '# New\n', 'message': 'tidy'});
      // The PUT response carries only ids; the fresh read is what comes back.
      expect(saved.valueOrNull?.blobOid, 'newblob');
      expect(adapter.last.method, 'GET');
    });

    test('an omitted commit message is not sent as null', () async {
      final adapter = _Adapter((options) async {
        if (options.method == 'PUT') return _ok('{}');
        return _ok(
          '{"source_id":"s1","path":"a.md","body":"x","blob_oid":"b", '
          '"commit":"c","can_edit":true}',
        );
      });
      final repo = DocsRepositoryImpl(_client(adapter));
      await repo.saveDoc(
        'p1',
        's1',
        path: 'a.md',
        content: 'x',
        etag: '"b"',
      );
      final put = adapter.requests.firstWhere((r) => r.method == 'PUT');
      expect(put.data, {'content': 'x'});
    });

    test('myKey reads a null doc_key as "no key registered"', () async {
      final adapter = _Adapter((_) async => _ok('{"doc_key":null}'));
      final repo = DocsRepositoryImpl(_client(adapter));
      final res = await repo.myKey('p1');
      expect(res.isOk, isTrue);
      expect(res.valueOrNull, isNull);
    });

    test('myKey parses a registered key, which has no private half', () async {
      final adapter = _Adapter(
        (_) async => _ok(
          '{"id":"k1","project_id":"p1","user_id":"u1", '
          '"key_type":"ssh-ed25519","public_key":"ssh-ed25519 AAAA", '
          '"fingerprint":"SHA256:xyz","origin":"imported", '
          '"created_at":"2026-08-01T00:00:00Z"}',
        ),
      );
      final repo = DocsRepositoryImpl(_client(adapter));
      final key = (await repo.myKey('p1')).valueOrNull;
      expect(key!.publicKey, 'ssh-ed25519 AAAA');
      expect(key.isImported, isTrue);
    });

    test('registerMyKey omits private_key when generating', () async {
      final adapter = _Adapter(
        (_) async => _ok(
          '{"id":"k1","key_type":"ssh-ed25519","public_key":"ssh-ed25519 A", '
          '"fingerprint":"SHA256:x","origin":"generated", '
          '"created_at":"2026-08-01T00:00:00Z"}',
        ),
      );
      final repo = DocsRepositoryImpl(_client(adapter));
      await repo.registerMyKey('p1');
      expect(adapter.last.method, 'PUT');
      expect(adapter.last.data, <String, dynamic>{});
    });
  });

  group('deriveWebUrl', () {
    test('derives a browse URL from the common SSH shapes', () {
      expect(
        deriveWebUrl('git@github.com:acme/docs.git'),
        'https://github.com/acme/docs',
      );
      expect(
        deriveWebUrl('git@gitlab.com:group/sub/docs.git'),
        'https://gitlab.com/group/sub/docs',
      );
      expect(
        deriveWebUrl('ssh://git@git.internal:2222/acme/docs.git'),
        'https://git.internal/acme/docs',
      );
      // A missing .git suffix is fine.
      expect(
        deriveWebUrl('git@github.com:acme/docs'),
        'https://github.com/acme/docs',
      );
    });

    test('returns null for shapes it cannot read, leaving the field blank', () {
      expect(deriveWebUrl(''), isNull);
      expect(deriveWebUrl('not a url'), isNull);
      expect(deriveWebUrl('https://github.com/acme/docs'), isNull);
    });
  });

  group('web-link sources', () {
    const webJson =
        '{"id":"w1","project_id":"p1","name":"Status page","kind":"web", '
        '"web_url":"https://status.example.com/docs","doc_path":"", '
        '"read_only":true,"hidden":false,"order":1.0,"color":"","emoji":"", '
        '"cache_status":"ready","cache_bytes":0,"version":1, '
        '"created_at":"2026-08-01T00:00:00Z", '
        '"modified_at":"2026-08-01T00:00:00Z"}';

    test('parses a web source, whose repository fields are absent', () async {
      final adapter = _Adapter((_) async => _ok(webJson));
      final repo = DocsRepositoryImpl(_client(adapter));
      final source = (await repo.getSource('p1', 'w1')).valueOrNull;
      expect(source!.kind, DocSourceKind.web);
      expect(source.kind.isWeb, isTrue);
      expect(source.sshUrl, isNull);
      expect(source.branch, isNull);
      expect(source.readOnly, isTrue);
      expect(source.webUrl, 'https://status.example.com/docs');
      // Nothing is cached for a web link, so it is always ready to show —
      // the browser fetches the page live.
      expect(source.hasContent, isTrue);
      expect(source.isBrowsable, isFalse);
    });

    test('a git source is browsable and keeps its repository fields', () async {
      final adapter = _Adapter((_) async => _ok(_sourceJson));
      final repo = DocsRepositoryImpl(_client(adapter));
      final source = (await repo.getSource('p1', 's1')).valueOrNull;
      expect(source!.kind, DocSourceKind.git);
      expect(source.isBrowsable, isTrue);
      expect(source.sshUrl, 'git@github.com:acme/docs.git');
      expect(source.branch, 'main');
    });

    test('an absent kind is read as git, for older payloads', () async {
      final adapter = _Adapter(
        (_) async => _ok(
          '{"id":"s9","project_id":"p1","name":"Legacy", '
          '"ssh_url":"git@h:a/b.git","web_url":"https://h/a/b", '
          '"branch":"main","doc_path":"","read_only":false,"order":1.0, '
          '"color":"","emoji":"","cache_status":"ready","cache_bytes":0, '
          '"version":1,"created_at":"2026-08-01T00:00:00Z", '
          '"modified_at":"2026-08-01T00:00:00Z"}',
        ),
      );
      final repo = DocsRepositoryImpl(_client(adapter));
      final source = (await repo.getSource('p1', 's9')).valueOrNull;
      expect(source!.kind, DocSourceKind.git);
    });

    test('creating a web source sends only a title, kind and URL', () async {
      final adapter = _Adapter((_) async => _ok(webJson, status: 201));
      final repo = DocsRepositoryImpl(_client(adapter));
      await repo.createSource(
        'p1',
        const CreateDocSourceRequest.web(
          name: 'Status page',
          webUrl: 'https://status.example.com/docs',
          emoji: '🌐',
        ),
      );
      // The server rejects a request mixing the two kinds' fields, so none of
      // the repository-shaped ones may be sent.
      expect(adapter.last.data, {
        'name': 'Status page',
        'kind': 'web',
        'web_url': 'https://status.example.com/docs',
        'emoji': '🌐',
      });
    });

    test('creating a git source still sends its repository fields', () async {
      final adapter = _Adapter((_) async => _ok(_sourceJson, status: 201));
      final repo = DocsRepositoryImpl(_client(adapter));
      await repo.createSource(
        'p1',
        const CreateDocSourceRequest(
          name: 'Handbook',
          sshUrl: 'git@github.com:acme/docs.git',
          webUrl: 'https://github.com/acme/docs',
          branch: 'main',
          docPath: 'docs',
          newKeyName: 'docs-deploy',
        ),
      );
      final body = adapter.last.data as Map<String, dynamic>;
      expect(body['kind'], 'git');
      expect(body['ssh_url'], 'git@github.com:acme/docs.git');
      expect(body['branch'], 'main');
      expect(body['doc_path'], 'docs');
    });
  });

  group('the hide switch', () {
    test('hidden round-trips and is patched on its own', () async {
      final adapter = _Adapter(
        (_) async => _ok(
          '{"id":"s1","project_id":"p1","name":"Handbook","kind":"git", '
          '"ssh_url":"git@h:a/b.git","web_url":"https://h/a/b", '
          '"branch":"main","doc_path":"","read_only":false,"hidden":true, '
          '"order":1.0,"color":"","emoji":"","cache_status":"ready", '
          '"cache_bytes":0,"version":2, '
          '"created_at":"2026-08-01T00:00:00Z", '
          '"modified_at":"2026-08-01T00:00:00Z"}',
        ),
      );
      final repo = DocsRepositoryImpl(_client(adapter));
      final updated = await repo.updateSource(
        'p1',
        's1',
        body: const UpdateDocSourceRequest(hidden: true),
        etag: '"s1:1"',
      );
      expect(adapter.last.data, {'hidden': true});
      expect(updated.valueOrNull?.hidden, isTrue);
    });

    test('a payload without the flag reads as visible', () async {
      final adapter = _Adapter((_) async => _ok(_sourceJson));
      final repo = DocsRepositoryImpl(_client(adapter));
      final source = (await repo.getSource('p1', 's1')).valueOrNull;
      expect(source?.hidden, isFalse);
    });
  });
}
