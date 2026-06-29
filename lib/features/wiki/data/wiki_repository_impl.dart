import 'package:dio/dio.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/error/failure_mapper.dart';
import 'package:intellipilot/core/network/api_client.dart';
import 'package:intellipilot/core/network/interceptors/etag_interceptor.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/features/wiki/data/dtos/wiki_dtos.dart';
import 'package:intellipilot/features/wiki/domain/wiki_repository.dart';

const _base = '/api/v1/projects';

String? _etag(Response<dynamic> r) =>
    r.headers.value('etag') ?? r.headers.value('ETag');

class WikiRepositoryImpl implements WikiRepository {
  WikiRepositoryImpl(this._api);
  final ApiClient _api;

  @override
  Future<Result<List<WikiPage>, AppFailure>> list(String projectId) async {
    final res = await _api.get('$_base/$projectId/wiki');
    return res.when(
      ok: (r) {
        final body = r.data as Map<String, dynamic>;
        final raw = body['pages'] as List<dynamic>? ?? const [];
        return Ok(
          raw.map((e) => WikiPage.fromJson(e as Map<String, dynamic>)).toList(),
        );
      },
      err: Err.new,
    );
  }

  @override
  Future<Result<WikiPage, AppFailure>> get(
    String projectId,
    String pageId,
  ) async {
    final res = await _api.get('$_base/$projectId/wiki/$pageId');
    return res.when(
      ok: (r) => Ok(
        WikiPage.fromJson(r.data as Map<String, dynamic>, etag: _etag(r)),
      ),
      err: Err.new,
    );
  }

  @override
  Future<Result<WikiPage, AppFailure>> create(
    String projectId,
    CreateWikiPageRequest body,
  ) async {
    final res = await _api.post('$_base/$projectId/wiki', body: body.toJson());
    return res.when(
      ok: (r) => Ok(
        WikiPage.fromJson(r.data as Map<String, dynamic>, etag: _etag(r)),
      ),
      err: Err.new,
    );
  }

  @override
  Future<Result<WikiPage, AppFailure>> update(
    String projectId,
    String pageId, {
    required UpdateWikiPageRequest body,
    required String etag,
  }) async {
    try {
      final response = await _api.dio.patch<dynamic>(
        '$_base/$projectId/wiki/$pageId',
        data: body.toJson(),
        options: Options(
          extra: <String, dynamic>{EtagInterceptor.etagExtra: etag},
        ),
      );
      return Ok(
        WikiPage.fromJson(
          response.data as Map<String, dynamic>,
          etag: _etag(response),
        ),
      );
    } on DioException catch (e) {
      return Err(mapDioExceptionToFailure(e));
    }
  }

  @override
  Future<Result<Unit, AppFailure>> delete(
    String projectId,
    String pageId, {
    required String etag,
  }) async {
    try {
      await _api.dio.delete<dynamic>(
        '$_base/$projectId/wiki/$pageId',
        options: Options(
          extra: <String, dynamic>{EtagInterceptor.etagExtra: etag},
        ),
      );
      return const Ok<Unit, AppFailure>(Unit.instance);
    } on DioException catch (e) {
      if (e.response?.statusCode == 204) {
        return const Ok<Unit, AppFailure>(Unit.instance);
      }
      return Err(mapDioExceptionToFailure(e));
    }
  }

  @override
  Future<Result<List<WikiRevision>, AppFailure>> listRevisions(
    String projectId,
    String pageId,
  ) async {
    final res = await _api.get('$_base/$projectId/wiki/$pageId/revisions');
    return res.when(
      ok: (r) {
        final body = r.data as Map<String, dynamic>;
        final raw = body['revisions'] as List<dynamic>? ?? const [];
        return Ok(
          raw
              .map((e) => WikiRevision.fromJson(e as Map<String, dynamic>))
              .toList(),
        );
      },
      err: Err.new,
    );
  }

  @override
  Future<Result<WikiRevision, AppFailure>> getRevision(
    String projectId,
    String pageId,
    int rev,
  ) async {
    final res = await _api.get(
      '$_base/$projectId/wiki/$pageId/revisions/$rev',
    );
    return res.when(
      ok: (r) => Ok(WikiRevision.fromJson(r.data as Map<String, dynamic>)),
      err: Err.new,
    );
  }

  @override
  Future<Result<WikiDiff, AppFailure>> diff(
    String projectId,
    String pageId,
    int from, {
    int? to,
  }) async {
    final res = await _api.get(
      '$_base/$projectId/wiki/$pageId/revisions/$from/diff',
      query: to == null ? null : {'to': '$to'},
    );
    return res.when(
      ok: (r) => Ok(WikiDiff.fromJson(r.data as Map<String, dynamic>)),
      err: Err.new,
    );
  }

  @override
  Future<Result<WikiPage, AppFailure>> restore(
    String projectId,
    String pageId,
    int rev,
  ) async {
    final res = await _api.post(
      '$_base/$projectId/wiki/$pageId/revisions/$rev/restore',
    );
    return res.when(
      ok: (r) => Ok(
        WikiPage.fromJson(r.data as Map<String, dynamic>, etag: _etag(r)),
      ),
      err: Err.new,
    );
  }
}
