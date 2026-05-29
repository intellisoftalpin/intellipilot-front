import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/network/api_client.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/features/activity/data/dtos/activity_dtos.dart';
import 'package:intellipilot/features/links/data/dtos/link_dtos.dart';
import 'package:intellipilot/features/links/domain/links_repository.dart';

/// HTTP-backed implementation. The backend does NOT expose link routes
/// yet (no `/api/v1/projects/:id/links` in `crates/api/src/router.rs` at
/// the time of writing) — this impl is wired against the URL shape we'll
/// adopt when it lands. Until then a 404 surfaces as `NotFoundFailure`,
/// which the cubit treats as an empty list rather than a hard error so
/// the panel stays usable.
const _base = '/api/v1/projects';

class LinksRepositoryHttp implements LinksRepository {
  LinksRepositoryHttp(this._api);
  final ApiClient _api;

  @override
  Future<Result<List<EntityLink>, AppFailure>> listFor(
    String projectId,
    EntityKind kind,
    String entityId,
  ) async {
    final res = await _api.get(
      '$_base/$projectId/links',
      query: {'kind': kind.wire, 'id': entityId},
    );
    return res.when(
      ok: (r) {
        final body = r.data as Map<String, dynamic>;
        final raw = body['links'] as List<dynamic>? ?? const [];
        return Ok(
          raw
              .map((e) => EntityLink.fromJson(e as Map<String, dynamic>))
              .toList(),
        );
      },
      err: Err.new,
    );
  }

  @override
  Future<Result<EntityLink, AppFailure>> create(
    String projectId,
    CreateLinkRequest body,
  ) async {
    final res = await _api.post(
      '$_base/$projectId/links',
      body: body.toJson(),
    );
    return res.when(
      ok: (r) => Ok(EntityLink.fromJson(r.data as Map<String, dynamic>)),
      err: Err.new,
    );
  }

  @override
  Future<Result<Unit, AppFailure>> delete(
    String projectId,
    String linkId,
  ) async {
    final res = await _api.dio.delete<dynamic>(
      '$_base/$projectId/links/$linkId',
    );
    final code = res.statusCode ?? 500;
    return code >= 200 && code < 300
        ? const Ok(Unit.instance)
        : const Err(ServerFailure());
  }
}
