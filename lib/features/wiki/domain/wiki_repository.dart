import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/features/wiki/data/dtos/wiki_dtos.dart';

abstract interface class WikiRepository {
  Future<Result<List<WikiPage>, AppFailure>> list(String projectId);
  Future<Result<WikiPage, AppFailure>> get(String projectId, String pageId);
  Future<Result<WikiPage, AppFailure>> create(
    String projectId,
    CreateWikiPageRequest body,
  );
  Future<Result<WikiPage, AppFailure>> update(
    String projectId,
    String pageId, {
    required UpdateWikiPageRequest body,
    required String etag,
  });
  Future<Result<Unit, AppFailure>> delete(
    String projectId,
    String pageId, {
    required String etag,
  });
  Future<Result<List<WikiRevision>, AppFailure>> listRevisions(
    String projectId,
    String pageId,
  );
  Future<Result<WikiRevision, AppFailure>> getRevision(
    String projectId,
    String pageId,
    int rev,
  );
  Future<Result<WikiDiff, AppFailure>> diff(
    String projectId,
    String pageId,
    int from, {
    int? to,
  });
  Future<Result<WikiPage, AppFailure>> restore(
    String projectId,
    String pageId,
    int rev,
  );
}
