import 'dart:typed_data';

import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/features/docs/data/dtos/doc_dtos.dart';

/// External documentation sources: registration, browsing, and editing.
abstract class DocsRepository {
  Future<Result<List<DocSource>, AppFailure>> listSources(String projectId);

  Future<Result<DocSource, AppFailure>> getSource(
    String projectId,
    String sourceId,
  );

  Future<Result<DocSource, AppFailure>> createSource(
    String projectId,
    CreateDocSourceRequest body,
  );

  /// [etag] guards against a concurrent edit; pass [DocSource.etag].
  Future<Result<DocSource, AppFailure>> updateSource(
    String projectId,
    String sourceId, {
    required UpdateDocSourceRequest body,
    required String etag,
  });

  Future<Result<Unit, AppFailure>> deleteSource(
    String projectId,
    String sourceId,
  );

  /// Ask the server to refresh its cache. Rate-limited server-side, so a
  /// burst of clicks costs one fetch.
  Future<Result<DocSource, AppFailure>> sync(String projectId, String sourceId);

  Future<Result<DocTree, AppFailure>> tree(String projectId, String sourceId);

  Future<Result<DocContent, AppFailure>> doc(
    String projectId,
    String sourceId,
    String path,
  );

  /// Commit and push a document. [etag] is the blob OID the editor started
  /// from ([DocContent.etag]); a mismatch means someone else changed it.
  Future<Result<DocContent, AppFailure>> saveDoc(
    String projectId,
    String sourceId, {
    required String path,
    required String content,
    required String etag,
    String? message,
  });

  /// Raw bytes of an image referenced by a document. Goes through the API so
  /// the request carries the caller's credentials, which a plain image URL
  /// could not.
  Future<Result<Uint8List, AppFailure>> blob(
    String projectId,
    String sourceId,
    String path,
  );

  /// The caller's own write key for this project, or null if they have none.
  Future<Result<DocUserKey?, AppFailure>> myKey(String projectId);

  /// Generate a key, or import [privateKey] if one is supplied.
  Future<Result<DocUserKey, AppFailure>> registerMyKey(
    String projectId, {
    String? privateKey,
  });

  Future<Result<Unit, AppFailure>> deleteMyKey(String projectId);
}
