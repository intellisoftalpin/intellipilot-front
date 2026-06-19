// Repo-level wire-format tests for Phase 9. Broader BLoC / page tests are
// intentionally skipped per the paused coverage gate.

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/core/network/api_client.dart';
import 'package:intellipilot/core/network/api_config.dart';
import 'package:intellipilot/core/utils/uuid_gen.dart';
import 'package:intellipilot/features/activity/data/activity_repository_impl.dart';
import 'package:intellipilot/features/activity/data/dtos/activity_dtos.dart';

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

const _commentJson =
    '{"id":"c1","target_type":"user_story","target_id":"u1",'
    '"author_id":"a1","body":"hi","body_html":"<p>hi</p>",'
    '"edited_at":null,"created_at":"2026-05-28T00:00:00Z"}';

const _historyJson =
    '{"diff":{"subject":["old","new"]},"actor_id":"a1",'
    '"created_at":"2026-05-28T00:00:00Z"}';

const _attachmentJson =
    '{"id":"att1","project_id":"p1","target_type":"user_story",'
    '"target_id":"u1","uploader_id":"a1","filename":"logo.png",'
    '"content_type":"image/png","size_bytes":42,"sha256":"deadbeef",'
    '"created_at":"2026-05-28T00:00:00Z"}';

void main() {
  group('ActivityRepositoryImpl', () {
    test('listComments unwraps {comments: [...]} envelope', () async {
      final repo = ActivityRepositoryImpl(
        _client(_Adapter((_) async => _ok('{"comments":[$_commentJson]}'))),
      );
      final res = await repo.listComments(
        'p1',
        EntityKind.issue,
        'u1',
      );
      expect(res.valueOrNull?.single.body, 'hi');
    });

    test(
      'createComment posts to the kind-specific path with {body} envelope',
      () async {
        final adapter = _Adapter(
          (_) async => _ok(_commentJson, status: 201),
        );
        final repo = ActivityRepositoryImpl(_client(adapter));
        await repo.createComment(
          'p1',
          EntityKind.issue,
          'u1',
          const CreateCommentRequest(body: 'hello'),
        );
        expect(
          adapter.lastRequest?.path,
          '/api/v1/projects/p1/issues/u1/comments',
        );
        expect(adapter.lastRequest?.data, {'body': 'hello'});
      },
    );

    test('listHistory unwraps {history: [...]} envelope', () async {
      final repo = ActivityRepositoryImpl(
        _client(_Adapter((_) async => _ok('{"history":[$_historyJson]}'))),
      );
      final res = await repo.listHistory('p1', EntityKind.issue, 'i1');
      final ev = res.valueOrNull?.single;
      expect(ev?.diff['subject'], ['old', 'new']);
    });

    test('listAttachments unwraps {attachments: [...]} envelope', () async {
      final repo = ActivityRepositoryImpl(
        _client(
          _Adapter((_) async => _ok('{"attachments":[$_attachmentJson]}')),
        ),
      );
      final res = await repo.listAttachments(
        'p1',
        EntityKind.issue,
        'u1',
      );
      expect(res.valueOrNull?.single.filename, 'logo.png');
    });

    test('uploadAttachment posts multipart with the file field', () async {
      final adapter = _Adapter(
        (_) async => _ok(_attachmentJson, status: 201),
      );
      final repo = ActivityRepositoryImpl(_client(adapter));
      await repo.uploadAttachment(
        'p1',
        EntityKind.issue,
        'u1',
        filename: 'logo.png',
        bytes: Uint8List.fromList([1, 2, 3, 4]),
        contentType: 'image/png',
      );
      expect(
        adapter.lastRequest?.path,
        '/api/v1/projects/p1/issues/u1/attachments',
      );
      expect(adapter.lastRequest?.data, isA<FormData>());
      final form = adapter.lastRequest?.data as FormData;
      expect(form.files.single.key, 'file');
      expect(form.files.single.value.filename, 'logo.png');
    });

    test('signAttachmentUrl returns the {url, expires_at} envelope',
        () async {
      final adapter = _Adapter(
        (_) async => _ok(
          '{"url":"/api/v1/projects/p1/attachments/a1/download?exp=1&sig=z",'
          '"expires_at":1,"filename":"logo.png"}',
        ),
      );
      final repo = ActivityRepositoryImpl(_client(adapter));
      final res = await repo.signAttachmentUrl('p1', 'a1');
      expect(
        res.valueOrNull?.url,
        '/api/v1/projects/p1/attachments/a1/download?exp=1&sig=z',
      );
      expect(res.valueOrNull?.filename, 'logo.png');
    });
  });
}
