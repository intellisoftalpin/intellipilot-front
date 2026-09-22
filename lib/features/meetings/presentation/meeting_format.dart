import 'package:flutter/material.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/features/meetings/data/dtos/meeting_dtos.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';
import 'package:intl/intl.dart';

/// `09:30–10:15`, `09:30`, or "All day" — in the meeting's own time zone, as
/// entered. The zone is appended when it differs from [viewerTimezone].
String meetingTimeLabel(
  AppLocalizations t, {
  MeetingTime? start,
  MeetingTime? end,
  String? timezone,
  String? viewerTimezone,
}) {
  if (start == null) return t.meetingsAllDay;
  final range = end == null ? start.wire : '${start.wire}–${end.wire}';
  if (timezone == null || timezone == viewerTimezone) return range;
  return '$range ($timezone)';
}

/// Long form of a meeting day, e.g. "Tuesday, 22 September 2026".
String meetingDayLabel(BuildContext context, DateTime day) {
  final locale = Localizations.localeOf(context).toLanguageTag();
  return DateFormat.yMMMMEEEEd(locale).format(day);
}

/// Human-readable byte size.
String humanSize(int bytes) {
  const units = ['B', 'KiB', 'MiB', 'GiB'];
  var b = bytes.toDouble();
  var i = 0;
  while (b >= 1024 && i < units.length - 1) {
    b /= 1024;
    i++;
  }
  return '${b.toStringAsFixed(b < 10 && i > 0 ? 1 : 0)} ${units[i]}';
}

/// A message for a meeting write that failed, specific where the server's
/// code says what went wrong.
String meetingFailureMessage(AppLocalizations t, AppFailure failure) {
  if (failure is ConflictFailure) return t.meetingConflict;
  if (failure is ForbiddenFailure) return t.meetingErrForbidden;
  final code = failure.problem?.code;
  switch (code) {
    case 'not_media':
      return t.meetingErrNotMedia;
    case 'too_large':
      return t.meetingErrTooLarge;
    case 'unsupported_format':
      return t.meetingErrUnsupportedFormat;
    case 'invalid_encoding':
      return t.meetingErrEncoding;
    case 'invalid_times':
      return t.meetingEndBeforeStart;
    case 'invalid_timezone':
      return t.meetingErrTimezone;
    case 'mime_mismatch':
      return t.meetingErrMimeMismatch;
  }
  if (failure.problem?.status == 413) return t.meetingErrTooLarge;
  return failure.serverMessage ?? t.errUnknown;
}

/// Why a meeting form can't be saved yet.
enum MeetingFormError {
  titleRequired,
  dateRequired,
  endNeedsStart,
  endBeforeStart,
}

/// Validates the meeting details form: a title and a date are required; an
/// end time needs a start time and must come after it (same day).
MeetingFormError? validateMeetingForm({
  required String title,
  required DateTime? date,
  required MeetingTime? start,
  required MeetingTime? end,
}) {
  if (title.trim().isEmpty) return MeetingFormError.titleRequired;
  if (date == null) return MeetingFormError.dateRequired;
  if (end != null && start == null) return MeetingFormError.endNeedsStart;
  if (start != null && end != null && end.compareTo(start) <= 0) {
    return MeetingFormError.endBeforeStart;
  }
  return null;
}

String meetingFormErrorText(AppLocalizations t, MeetingFormError e) =>
    switch (e) {
      MeetingFormError.titleRequired => t.meetingTitleRequired,
      MeetingFormError.dateRequired => t.meetingDateRequired,
      MeetingFormError.endNeedsStart => t.meetingEndNeedsStart,
      MeetingFormError.endBeforeStart => t.meetingEndBeforeStart,
    };
