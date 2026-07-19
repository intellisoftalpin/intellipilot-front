import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/network/api_client.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/features/activity/data/dtos/activity_dtos.dart';
import 'package:intellipilot/features/links/data/dtos/link_dtos.dart';
import 'package:intellipilot/features/links/domain/links_repository.dart';

/// HTTP-backed implementation over the issue-scoped link routes:
/// `GET/POST /api/v1/projects/{pid}/issues/{id}/links` and
/// `DELETE /api/v1/projects/{pid}/issues/{id}/links/{linkId}`.
///
/// The backend stores links between issues only. The wire shape is
/// issue-relative (`other_issue_id` + `direction`), so this impl folds it
/// back into the symmetric [EntityLink] the UI renders.
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
    // Only issues participate in links; epics render an empty panel.
    if (kind != EntityKind.issue) return const Ok([]);
    final res = await _api.get('$_base/$projectId/issues/$entityId/links');
    return res.when(
      ok: (r) {
        final body = r.data as Map<String, dynamic>;
        final raw = body['links'] as List<dynamic>? ?? const [];
        return Ok([
          for (final e in raw)
            _fromWire(projectId, entityId, e as Map<String, dynamic>),
        ]);
      },
      err: Err.new,
    );
  }

  @override
  Future<Result<EntityLink, AppFailure>> create(
    String projectId,
    CreateLinkRequest body,
  ) async {
    if (body.sourceKind != EntityKind.issue ||
        body.targetKind != EntityKind.issue) {
      return const Err(ValidationFailure(fieldErrors: []));
    }
    final res = await _api.post(
      '$_base/$projectId/issues/${body.sourceId}/links',
      body: {
        'target_issue_id': body.targetId,
        'link_type': body.type.wire,
      },
    );
    return res.when(
      ok: (r) => Ok(
        _fromWire(projectId, body.sourceId, r.data as Map<String, dynamic>),
      ),
      err: Err.new,
    );
  }

  @override
  Future<Result<Unit, AppFailure>> delete(
    String projectId,
    String entityId,
    String linkId,
  ) async {
    final res = await _api.dio.delete<dynamic>(
      '$_base/$projectId/issues/$entityId/links/$linkId',
    );
    final code = res.statusCode ?? 500;
    return code >= 200 && code < 300
        ? const Ok(Unit.instance)
        : const Err(ServerFailure());
  }

  /// Fold the issue-relative wire link into the symmetric [EntityLink]:
  /// `outgoing` means the queried issue is the source, `incoming` the target.
  EntityLink _fromWire(
    String projectId,
    String issueId,
    Map<String, dynamic> json,
  ) {
    final outgoing = (json['direction'] as String? ?? 'outgoing') == 'outgoing';
    final otherId = json['other_issue_id'] as String;
    return EntityLink(
      id: json['id'] as String,
      projectId: projectId,
      sourceKind: EntityKind.issue,
      sourceId: outgoing ? issueId : otherId,
      targetKind: EntityKind.issue,
      targetId: outgoing ? otherId : issueId,
      type:
          LinkType.fromWire(json['link_type'] as String? ?? 'relates') ??
          LinkType.relates,
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}
