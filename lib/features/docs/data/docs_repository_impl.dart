import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/error/failure_mapper.dart';
import 'package:intellipilot/core/network/api_client.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/features/docs/data/dtos/doc_dtos.dart';
import 'package:intellipilot/features/docs/domain/docs_repository.dart';

const _base = '/api/v1/projects';

class DocsRepositoryImpl implements DocsRepository {
  DocsRepositoryImpl(this._api);
  final ApiClient _api;

  String _sources(String projectId) => '$_base/$projectId/doc-sources';

  @override
  Future<Result<List<DocSource>, AppFailure>> listSources(
    String projectId,
  ) async {
    final res = await _api.get(_sources(projectId));
    return res.when(
      ok: (r) {
        final body = r.data as Map<String, dynamic>;
        final raw = body['doc_sources'] as List<dynamic>? ?? const [];
        return Ok(
          raw
              .map((e) => DocSource.fromJson(e as Map<String, dynamic>))
              .toList(),
        );
      },
      err: Err.new,
    );
  }

  @override
  Future<Result<DocSource, AppFailure>> getSource(
    String projectId,
    String sourceId,
  ) async {
    final res = await _api.get('${_sources(projectId)}/$sourceId');
    return res.when(
      ok: (r) => Ok(DocSource.fromJson(r.data as Map<String, dynamic>)),
      err: Err.new,
    );
  }

  @override
  Future<Result<DocSource, AppFailure>> createSource(
    String projectId,
    CreateDocSourceRequest body,
  ) async {
    final res = await _api.post(_sources(projectId), body: body.toJson());
    return res.when(
      ok: (r) => Ok(DocSource.fromJson(r.data as Map<String, dynamic>)),
      err: Err.new,
    );
  }

  @override
  Future<Result<DocSource, AppFailure>> updateSource(
    String projectId,
    String sourceId, {
    required UpdateDocSourceRequest body,
    required String etag,
  }) async {
    try {
      final response = await _api.dio.patch<dynamic>(
        '${_sources(projectId)}/$sourceId',
        data: body.toJson(),
        options: Options(headers: {'If-Match': etag}),
      );
      return Ok(DocSource.fromJson(response.data as Map<String, dynamic>));
    } on DioException catch (e) {
      return Err(mapDioExceptionToFailure(e));
    }
  }

  @override
  Future<Result<Unit, AppFailure>> deleteSource(
    String projectId,
    String sourceId,
  ) async {
    try {
      await _api.dio.delete<dynamic>('${_sources(projectId)}/$sourceId');
      return const Ok<Unit, AppFailure>(Unit.instance);
    } on DioException catch (e) {
      if (e.response?.statusCode == 204) {
        return const Ok<Unit, AppFailure>(Unit.instance);
      }
      return Err(mapDioExceptionToFailure(e));
    }
  }

  @override
  Future<Result<DocSource, AppFailure>> sync(
    String projectId,
    String sourceId,
  ) async {
    final res = await _api.post('${_sources(projectId)}/$sourceId/sync');
    return res.when(
      ok: (r) => Ok(DocSource.fromJson(r.data as Map<String, dynamic>)),
      err: Err.new,
    );
  }

  @override
  Future<Result<DocTree, AppFailure>> tree(
    String projectId,
    String sourceId,
  ) async {
    final res = await _api.get('${_sources(projectId)}/$sourceId/tree');
    return res.when(
      ok: (r) => Ok(DocTree.fromJson(r.data as Map<String, dynamic>)),
      err: Err.new,
    );
  }

  @override
  Future<Result<DocContent, AppFailure>> doc(
    String projectId,
    String sourceId,
    String path,
  ) async {
    final res = await _api.get(
      '${_sources(projectId)}/$sourceId/doc',
      query: {'path': path},
    );
    return res.when(
      ok: (r) => Ok(DocContent.fromJson(r.data as Map<String, dynamic>)),
      err: Err.new,
    );
  }

  @override
  Future<Result<DocContent, AppFailure>> saveDoc(
    String projectId,
    String sourceId, {
    required String path,
    required String content,
    required String etag,
    String? message,
  }) async {
    try {
      await _api.dio.put<dynamic>(
        '${_sources(projectId)}/$sourceId/doc',
        queryParameters: {'path': path},
        data: {'content': content, 'message': ?message},
        options: Options(headers: {'If-Match': etag}),
      );
    } on DioException catch (e) {
      return Err(mapDioExceptionToFailure(e));
    }
    // The save response carries only the new commit and blob id. Re-reading
    // gives back the full document — including the refreshed `last_commit`
    // the footer shows — from one authoritative place.
    return doc(projectId, sourceId, path);
  }

  @override
  Future<Result<Uint8List, AppFailure>> blob(
    String projectId,
    String sourceId,
    String path,
  ) async {
    try {
      final response = await _api.dio.get<List<int>>(
        '${_sources(projectId)}/$sourceId/blob',
        queryParameters: {'path': path},
        options: Options(responseType: ResponseType.bytes),
      );
      return Ok(Uint8List.fromList(response.data ?? const []));
    } on DioException catch (e) {
      return Err(mapDioExceptionToFailure(e));
    }
  }

  @override
  Future<Result<DocUserKey?, AppFailure>> myKey(String projectId) async {
    final res = await _api.get('$_base/$projectId/doc-keys/me');
    return res.when(
      ok: (r) {
        final body = r.data as Map<String, dynamic>;
        // The server answers `{"doc_key": null}` when there is none, and the
        // bare key object when there is.
        if (body.containsKey('doc_key') && body['doc_key'] == null) {
          return const Ok<DocUserKey?, AppFailure>(null);
        }
        return Ok(DocUserKey.fromJson(body));
      },
      err: Err.new,
    );
  }

  @override
  Future<Result<DocUserKey, AppFailure>> registerMyKey(
    String projectId, {
    String? privateKey,
  }) async {
    try {
      final response = await _api.dio.put<dynamic>(
        '$_base/$projectId/doc-keys/me',
        data: {'private_key': ?privateKey},
      );
      return Ok(DocUserKey.fromJson(response.data as Map<String, dynamic>));
    } on DioException catch (e) {
      return Err(mapDioExceptionToFailure(e));
    }
  }

  @override
  Future<Result<Unit, AppFailure>> deleteMyKey(String projectId) async {
    try {
      await _api.dio.delete<dynamic>('$_base/$projectId/doc-keys/me');
      return const Ok<Unit, AppFailure>(Unit.instance);
    } on DioException catch (e) {
      if (e.response?.statusCode == 204) {
        return const Ok<Unit, AppFailure>(Unit.instance);
      }
      return Err(mapDioExceptionToFailure(e));
    }
  }
}
