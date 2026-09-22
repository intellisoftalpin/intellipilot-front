import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/io/large_upload.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/features/activity/data/dtos/activity_dtos.dart';
import 'package:intellipilot/features/meetings/data/dtos/meeting_dtos.dart';
import 'package:intellipilot/features/meetings/domain/meetings_repository.dart';

MeetingListItem meetingRow(String id, DateTime date, {String? title}) =>
    MeetingListItem(
      id: id,
      projectId: 'p1',
      title: title ?? id,
      date: date,
      timezone: 'UTC',
    );

/// Records calls; answers from settable handlers.
class FakeMeetingsRepository extends Fake implements MeetingsRepository {
  final List<(DateTime, DateTime)> rangeCalls = [];
  List<MeetingListItem> rows = [];

  /// Drives an upload: the test pushes progress and completes it.
  Completer<Result<Attachment, AppFailure>>? pendingUpload;
  void Function(int sent, int total)? lastProgress;
  CancelToken? lastCancelToken;

  @override
  Future<Result<MeetingRange, AppFailure>> listRange(
    String projectId, {
    required DateTime from,
    required DateTime to,
  }) async {
    rangeCalls.add((from, to));
    final inRange = rows
        .where((m) => !m.date.isBefore(from) && !m.date.isAfter(to))
        .toList();
    final counts = <DateTime, int>{};
    for (final m in inRange) {
      counts[m.date] = (counts[m.date] ?? 0) + 1;
    }
    return Ok(
      MeetingRange(
        meetings: inRange,
        days: [
          for (final e in counts.entries)
            MeetingDayCount(date: e.key, count: e.value),
        ],
      ),
    );
  }

  /// What [get] answers.
  Meeting? detail;

  @override
  Future<Result<Meeting, AppFailure>> get(
    String projectId,
    String meetingId,
  ) async => detail == null ? const Err(NotFoundFailure()) : Ok(detail!);

  @override
  bool get supportsLargeUploads => true;

  @override
  Future<Result<Attachment, AppFailure>> uploadArtifact(
    String projectId,
    String meetingId, {
    required PickedUpload file,
    required ArtifactKind kind,
    void Function(int sent, int total)? onProgress,
    CancelToken? cancelToken,
  }) {
    lastProgress = onProgress;
    lastCancelToken = cancelToken;
    final c = pendingUpload = Completer();
    unawaited(
      cancelToken?.whenCancel.then((_) {
        if (!c.isCompleted) {
          c.complete(
            const Err(NetworkFailure(cause: UploadCancelledException())),
          );
        }
      }),
    );
    return c.future;
  }
}

Attachment attachment(String id) => Attachment(
  id: id,
  projectId: 'p1',
  targetType: 'meeting',
  targetId: 'm1',
  filename: '$id.mp4',
  contentType: 'video/mp4',
  sizeBytes: 100,
  sha256: '',
  createdAt: DateTime(2026),
  kind: 'recording',
);
