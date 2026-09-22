// Underscore-prefixed fields are clearer than `{required this._repo}` in
// the public constructor — silence the lint at file scope.
// ignore_for_file: prefer_initializing_formals

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/error/failure_mapper.dart';
import 'package:intellipilot/core/error/problem.dart';
import 'package:intellipilot/core/io/file_picker.dart';
import 'package:intellipilot/core/io/large_upload.dart';
import 'package:intellipilot/core/network/api_client.dart';
import 'package:intellipilot/core/network/interceptors/auth_interceptor.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/features/activity/data/dtos/activity_dtos.dart';
import 'package:intellipilot/features/meetings/data/dtos/meeting_dtos.dart';
import 'package:intellipilot/features/meetings/domain/meetings_repository.dart';

const _base = '/api/v1/projects';

class MeetingsRepositoryImpl implements MeetingsRepository {
  MeetingsRepositoryImpl(
    this._api, {
    required AccessTokenProvider tokenProvider,
    LargeUploader? uploader,
  }) : _tokenProvider = tokenProvider,
       _uploader = uploader ?? LargeUploader();

  final ApiClient _api;
  final AccessTokenProvider _tokenProvider;
  final LargeUploader _uploader;

  String _meeting(String projectId, String meetingId) =>
      '$_base/$projectId/meetings/$meetingId';

  Result<Meeting, AppFailure> _meetingOf(Response<dynamic> r) =>
      Ok(Meeting.fromJson(r.data as Map<String, dynamic>));

  Future<Result<Meeting, AppFailure>> _send(
    Future<Response<dynamic>> Function() call,
  ) async {
    try {
      return _meetingOf(await call());
    } on DioException catch (e) {
      return Err(mapDioExceptionToFailure(e));
    }
  }

  Future<Result<Unit, AppFailure>> _sendUnit(
    Future<Response<dynamic>> Function() call,
  ) async {
    try {
      await call();
      return const Ok<Unit, AppFailure>(Unit.instance);
    } on DioException catch (e) {
      if (e.response?.statusCode == 204) {
        return const Ok<Unit, AppFailure>(Unit.instance);
      }
      return Err(mapDioExceptionToFailure(e));
    }
  }

  @override
  Future<Result<MeetingRange, AppFailure>> listRange(
    String projectId, {
    required DateTime from,
    required DateTime to,
  }) async {
    final res = await _api.get(
      '$_base/$projectId/meetings',
      query: {'from': formatMeetingDate(from), 'to': formatMeetingDate(to)},
    );
    return res.when(
      ok: (r) => Ok(MeetingRange.fromJson(r.data as Map<String, dynamic>)),
      err: Err.new,
    );
  }

  @override
  Future<Result<Meeting, AppFailure>> get(String projectId, String meetingId) =>
      _send(() => _api.dio.get<dynamic>(_meeting(projectId, meetingId)));

  @override
  Future<Result<Meeting, AppFailure>> create(
    String projectId,
    CreateMeetingRequest body,
  ) => _send(
    () => _api.dio.post<dynamic>(
      '$_base/$projectId/meetings',
      data: body.toJson(),
    ),
  );

  @override
  Future<Result<Meeting, AppFailure>> update(
    String projectId,
    String meetingId, {
    required UpdateMeetingRequest body,
    required String etag,
  }) => _send(
    () => _api.dio.patch<dynamic>(
      _meeting(projectId, meetingId),
      data: body.toJson(),
      options: Options(headers: {'If-Match': etag}),
    ),
  );

  @override
  Future<Result<Unit, AppFailure>> delete(String projectId, String meetingId) =>
      _sendUnit(() => _api.dio.delete<dynamic>(_meeting(projectId, meetingId)));

  @override
  Future<Result<Meeting, AppFailure>> link(
    String projectId,
    String meetingId,
    MeetingLinkKind kind,
    String targetId,
  ) => _send(
    () => _api.dio.post<dynamic>(
      '${_meeting(projectId, meetingId)}/links/${kind.wire}/$targetId',
    ),
  );

  @override
  Future<Result<Meeting, AppFailure>> unlink(
    String projectId,
    String meetingId,
    MeetingLinkKind kind,
    String targetId,
  ) => _send(
    () => _api.dio.delete<dynamic>(
      '${_meeting(projectId, meetingId)}/links/${kind.wire}/$targetId',
    ),
  );

  @override
  bool get supportsLargeUploads => _uploader.isSupported;

  @override
  Future<PickedUpload?> pickUpload({String? accept}) =>
      _uploader.pick(accept: accept);

  @override
  Future<Result<Attachment, AppFailure>> uploadArtifact(
    String projectId,
    String meetingId, {
    required PickedUpload file,
    required ArtifactKind kind,
    void Function(int sent, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    // A cheap authenticated read first: it goes through Dio, so an expired
    // access token is refreshed here. The upload itself bypasses Dio (see
    // [LargeUploader]) and would otherwise fail a long transfer on a 401.
    final probe = await get(projectId, meetingId);
    final probeFailure = probe.failureOrNull;
    if (probeFailure != null) return Err(probeFailure);

    final token = _tokenProvider();
    final url =
        '${_api.baseUrl}${_meeting(projectId, meetingId)}'
        '/artifacts?kind=${kind.wire}';
    try {
      final res = await _uploader.send(
        url: url,
        file: file,
        headers: {
          'Accept': 'application/json',
          if (token != null && token.isNotEmpty)
            'Authorization': 'Bearer $token',
        },
        withCredentials: _api.config.withCredentials,
        onProgress: onProgress,
        cancelToken: cancelToken,
      );
      if (res.ok) {
        return Ok(
          Attachment.fromJson(jsonDecode(res.body) as Map<String, dynamic>),
        );
      }
      return Err(failureFromResponse(res.status, res.body));
    } on UploadCancelledException catch (e) {
      return Err(NetworkFailure(cause: e));
    } on Object catch (e) {
      return Err(NetworkFailure(cause: e));
    }
  }

  @override
  Future<Result<Unit, AppFailure>> deleteArtifact(
    String projectId,
    String meetingId,
    String attachmentId,
  ) => _sendUnit(
    () => _api.dio.delete<dynamic>(
      '${_meeting(projectId, meetingId)}/artifacts/$attachmentId',
    ),
  );

  @override
  Future<Result<Meeting, AppFailure>> importText(
    String projectId,
    String meetingId, {
    required MeetingTextTarget target,
    required PickedFile file,
  }) => _send(
    () => _api.dio.post<dynamic>(
      '${_meeting(projectId, meetingId)}/${target.wire}/import',
      data: FormData.fromMap({
        'file': MultipartFile.fromBytes(file.bytes, filename: file.name),
      }),
      options: Options(contentType: 'multipart/form-data'),
    ),
  );

  @override
  Future<Result<SignedDownload, AppFailure>> signUrl(
    String projectId,
    String attachmentId,
  ) async {
    final res = await _api.get('$_base/$projectId/attachments/$attachmentId');
    return res.when(
      ok: (r) => Ok(SignedDownload.fromJson(r.data as Map<String, dynamic>)),
      err: Err.new,
    );
  }

  Future<Result<List<MeetingListItem>, AppFailure>> _linked(String path) async {
    final res = await _api.get(path);
    return res.when(
      ok: (r) {
        final raw =
            (r.data as Map<String, dynamic>)['meetings'] as List<dynamic>? ??
            const [];
        return Ok(
          raw
              .map((e) => MeetingListItem.fromJson(e as Map<String, dynamic>))
              .toList(),
        );
      },
      err: Err.new,
    );
  }

  @override
  Future<Result<List<MeetingListItem>, AppFailure>> forIssue(
    String projectId,
    String issueId,
  ) => _linked('$_base/$projectId/issues/$issueId/meetings');

  @override
  Future<Result<List<MeetingListItem>, AppFailure>> forEpic(
    String projectId,
    String epicId,
  ) => _linked('$_base/$projectId/epics/$epicId/meetings');
}

/// Classify a raw HTTP answer the way [mapDioExceptionToFailure] classifies a
/// Dio one, for requests that do not go through Dio.
AppFailure failureFromResponse(int status, String body) {
  Problem? problem;
  try {
    final json = jsonDecode(body);
    if (json is Map<String, dynamic>) problem = Problem.fromJson(json);
  } on FormatException {
    problem = null;
  }
  problem ??= Problem.fallback(status: status);
  return switch (status) {
    401 => UnauthorizedFailure(problem: problem),
    403 => ForbiddenFailure(problem: problem),
    404 => NotFoundFailure(problem: problem),
    409 || 412 => ConflictFailure(problem: problem),
    422 => ValidationFailure(fieldErrors: problem.errors, problem: problem),
    429 => RateLimitedFailure(retryAfter: problem.retryAfter, problem: problem),
    >= 500 => ServerFailure(problem: problem),
    _ => UnknownFailure(problem: problem),
  };
}
