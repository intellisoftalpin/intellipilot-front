import 'package:dio/dio.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/io/file_picker.dart';
import 'package:intellipilot/core/io/large_upload.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/features/activity/data/dtos/activity_dtos.dart';
import 'package:intellipilot/features/meetings/data/dtos/meeting_dtos.dart';

/// Which meeting text an imported file replaces.
enum MeetingTextTarget {
  transcript('transcript'),
  summary('summary');

  const MeetingTextTarget(this.wire);
  final String wire;
}

abstract interface class MeetingsRepository {
  /// Meetings dated [from]..[to] (both inclusive, at most 400 days apart)
  /// plus a per-day count.
  Future<Result<MeetingRange, AppFailure>> listRange(
    String projectId, {
    required DateTime from,
    required DateTime to,
  });

  Future<Result<Meeting, AppFailure>> get(String projectId, String meetingId);

  Future<Result<Meeting, AppFailure>> create(
    String projectId,
    CreateMeetingRequest body,
  );

  /// Partial edit under optimistic concurrency: [etag] is the meeting's
  /// current revision token; a stale one fails with a [ConflictFailure].
  Future<Result<Meeting, AppFailure>> update(
    String projectId,
    String meetingId, {
    required UpdateMeetingRequest body,
    required String etag,
  });

  Future<Result<Unit, AppFailure>> delete(String projectId, String meetingId);

  Future<Result<Meeting, AppFailure>> link(
    String projectId,
    String meetingId,
    MeetingLinkKind kind,
    String targetId,
  );

  Future<Result<Meeting, AppFailure>> unlink(
    String projectId,
    String meetingId,
    MeetingLinkKind kind,
    String targetId,
  );

  /// True when [uploadArtifact] can run on this platform.
  bool get supportsLargeUploads;

  /// Opens the platform picker for a meeting file ([accept] as for
  /// `<input accept>`). Null when cancelled or unsupported.
  Future<PickedUpload?> pickUpload({String? accept});

  /// Streams [file] up as a meeting file of [kind]. [onProgress] reports
  /// bytes sent; cancelling [cancelToken] aborts and yields a
  /// [NetworkFailure] whose cause is an [UploadCancelledException].
  Future<Result<Attachment, AppFailure>> uploadArtifact(
    String projectId,
    String meetingId, {
    required PickedUpload file,
    required ArtifactKind kind,
    void Function(int sent, int total)? onProgress,
    CancelToken? cancelToken,
  });

  Future<Result<Unit, AppFailure>> deleteArtifact(
    String projectId,
    String meetingId,
    String attachmentId,
  );

  /// Replaces the transcript or summary with the text of an uploaded
  /// `.txt` / `.md` / `.vtt` / `.srt` file (subtitle timings stripped).
  Future<Result<Meeting, AppFailure>> importText(
    String projectId,
    String meetingId, {
    required MeetingTextTarget target,
    required PickedFile file,
  });

  /// Short-lived self-authenticating download URL (6 h for audio/video).
  Future<Result<SignedDownload, AppFailure>> signUrl(
    String projectId,
    String attachmentId,
  );

  /// Meetings linked to an issue, newest first.
  Future<Result<List<MeetingListItem>, AppFailure>> forIssue(
    String projectId,
    String issueId,
  );

  /// Meetings linked to an epic, newest first.
  Future<Result<List<MeetingListItem>, AppFailure>> forEpic(
    String projectId,
    String epicId,
  );
}

/// True when [failure] is the result of the user cancelling an upload.
bool isUploadCancelled(AppFailure failure) =>
    failure.cause is UploadCancelledException ||
    (failure.cause is DioException &&
        (failure.cause! as DioException).type == DioExceptionType.cancel);
