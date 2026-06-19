import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/error/failure_mapper.dart';
import 'package:intellipilot/core/network/api_client.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/features/activity/data/dtos/activity_dtos.dart';
import 'package:intellipilot/features/activity/domain/activity_repository.dart';

const _base = '/api/v1/projects';

class ActivityRepositoryImpl implements ActivityRepository {
  ActivityRepositoryImpl(this._api);
  final ApiClient _api;

  // ---- comments ----

  @override
  Future<Result<List<Comment>, AppFailure>> listComments(
    String projectId,
    EntityKind kind,
    String entityId,
  ) async {
    final res = await _api.get(
      '$_base/$projectId/${kind.slug}/$entityId/comments',
    );
    return res.when(
      ok: (r) {
        final body = r.data as Map<String, dynamic>;
        final raw = body['comments'] as List<dynamic>? ?? const [];
        return Ok(
          raw
              .map((e) => Comment.fromJson(e as Map<String, dynamic>))
              .toList(),
        );
      },
      err: Err.new,
    );
  }

  @override
  Future<Result<Comment, AppFailure>> createComment(
    String projectId,
    EntityKind kind,
    String entityId,
    CreateCommentRequest body,
  ) async {
    final res = await _api.post(
      '$_base/$projectId/${kind.slug}/$entityId/comments',
      body: body.toJson(),
    );
    return res.when(
      ok: (r) => Ok(Comment.fromJson(r.data as Map<String, dynamic>)),
      err: Err.new,
    );
  }

  @override
  Future<Result<Comment, AppFailure>> updateComment(
    String projectId,
    EntityKind kind,
    String entityId,
    String commentId,
    UpdateCommentRequest body,
  ) async {
    try {
      final response = await _api.dio.patch<dynamic>(
        '$_base/$projectId/${kind.slug}/$entityId/comments/$commentId',
        data: body.toJson(),
      );
      return Ok(Comment.fromJson(response.data as Map<String, dynamic>));
    } on DioException catch (e) {
      return Err(mapDioExceptionToFailure(e));
    }
  }

  @override
  Future<Result<Unit, AppFailure>> deleteComment(
    String projectId,
    EntityKind kind,
    String entityId,
    String commentId,
  ) async {
    try {
      await _api.dio.delete<dynamic>(
        '$_base/$projectId/${kind.slug}/$entityId/comments/$commentId',
      );
      return const Ok<Unit, AppFailure>(Unit.instance);
    } on DioException catch (e) {
      if (e.response?.statusCode == 204) {
        return const Ok<Unit, AppFailure>(Unit.instance);
      }
      return Err(mapDioExceptionToFailure(e));
    }
  }

  // ---- history ----

  @override
  Future<Result<List<HistoryEvent>, AppFailure>> listHistory(
    String projectId,
    EntityKind kind,
    String entityId,
  ) async {
    final res = await _api.get(
      '$_base/$projectId/${kind.slug}/$entityId/history',
    );
    return res.when(
      ok: (r) {
        final body = r.data as Map<String, dynamic>;
        final raw = body['history'] as List<dynamic>? ?? const [];
        return Ok(
          raw
              .map((e) => HistoryEvent.fromJson(e as Map<String, dynamic>))
              .toList(),
        );
      },
      err: Err.new,
    );
  }

  // ---- attachments ----

  @override
  Future<Result<List<Attachment>, AppFailure>> listAttachments(
    String projectId,
    EntityKind kind,
    String entityId,
  ) async {
    final res = await _api.get(
      '$_base/$projectId/${kind.slug}/$entityId/attachments',
    );
    return res.when(
      ok: (r) {
        final body = r.data as Map<String, dynamic>;
        final raw = body['attachments'] as List<dynamic>? ?? const [];
        return Ok(
          raw
              .map((e) => Attachment.fromJson(e as Map<String, dynamic>))
              .toList(),
        );
      },
      err: Err.new,
    );
  }

  @override
  Future<Result<Attachment, AppFailure>> uploadAttachment(
    String projectId,
    EntityKind kind,
    String entityId, {
    required String filename,
    required Uint8List bytes,
    String? contentType,
    ProgressCallback? onSendProgress,
    CancelToken? cancelToken,
  }) async {
    try {
      final form = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
          filename: filename,
          contentType: contentType == null
              ? null
              : DioMediaType.parse(contentType),
        ),
      });
      final response = await _api.dio.post<dynamic>(
        '$_base/$projectId/${kind.slug}/$entityId/attachments',
        data: form,
        onSendProgress: onSendProgress,
        cancelToken: cancelToken,
        options: Options(
          // Let dio compute the multipart boundary; otherwise the default
          // `application/json` header from ApiClient would clobber it.
          contentType: 'multipart/form-data',
        ),
      );
      return Ok(Attachment.fromJson(response.data as Map<String, dynamic>));
    } on DioException catch (e) {
      return Err(mapDioExceptionToFailure(e));
    }
  }

  @override
  Future<Result<Unit, AppFailure>> deleteAttachment(
    String projectId,
    String attachmentId,
  ) async {
    try {
      await _api.dio.delete<dynamic>(
        '$_base/$projectId/attachments/$attachmentId',
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
  Future<Result<SignedDownload, AppFailure>> signAttachmentUrl(
    String projectId,
    String attachmentId,
  ) async {
    final res = await _api.get('$_base/$projectId/attachments/$attachmentId');
    return res.when(
      ok: (r) => Ok(SignedDownload.fromJson(r.data as Map<String, dynamic>)),
      err: Err.new,
    );
  }

  // ---- comment attachments ----

  @override
  Future<Result<List<Attachment>, AppFailure>> listCommentAttachments(
    String projectId,
    String commentId,
  ) async {
    final res = await _api.get(
      '$_base/$projectId/comments/$commentId/attachments',
    );
    return res.when(
      ok: (r) {
        final body = r.data as Map<String, dynamic>;
        final raw = body['attachments'] as List<dynamic>? ?? const [];
        return Ok(
          raw
              .map((e) => Attachment.fromJson(e as Map<String, dynamic>))
              .toList(),
        );
      },
      err: Err.new,
    );
  }

  @override
  Future<Result<Attachment, AppFailure>> uploadCommentAttachment(
    String projectId,
    String commentId, {
    required String filename,
    required Uint8List bytes,
    String? contentType,
  }) async {
    try {
      final form = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
          filename: filename,
          contentType: contentType == null
              ? null
              : DioMediaType.parse(contentType),
        ),
      });
      final response = await _api.dio.post<dynamic>(
        '$_base/$projectId/comments/$commentId/attachments',
        data: form,
        options: Options(contentType: 'multipart/form-data'),
      );
      return Ok(Attachment.fromJson(response.data as Map<String, dynamic>));
    } on DioException catch (e) {
      return Err(mapDioExceptionToFailure(e));
    }
  }
}
