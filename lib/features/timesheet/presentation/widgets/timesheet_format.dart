import 'package:flutter/material.dart';
import 'package:intellipilot/features/timesheet/data/dtos/timesheet_dtos.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// `2h 30m` / `45m` / `0m` from a minute count.
String fmtMins(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '${m}m';
  if (m == 0) return '${h}h';
  return '${h}h ${m}m';
}

String isoDate(int y, int m, int d) =>
    '${y.toString().padLeft(4, '0')}-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';

int lastDay(int y, int m) => DateTime(y, m + 1, 0).day;

String isoFrom(DateTime d) => isoDate(d.year, d.month, d.day);

IconData kindIcon(EntryKind kind) => switch (kind) {
  EntryKind.work => Icons.work_outline,
  EntryKind.meeting => Icons.groups_outlined,
  EntryKind.vacation => Icons.beach_access_outlined,
  EntryKind.illness => Icons.sick_outlined,
  EntryKind.dayOff => Icons.weekend_outlined,
  EntryKind.holiday => Icons.celebration_outlined,
};

String kindLabel(AppLocalizations t, EntryKind kind) => switch (kind) {
  EntryKind.work => t.ttKindWork,
  EntryKind.meeting => t.ttKindMeeting,
  EntryKind.vacation => t.ttKindVacation,
  EntryKind.illness => t.ttKindIllness,
  EntryKind.dayOff => t.ttKindDayOff,
  EntryKind.holiday => t.ttKindHoliday,
};

String meetingTypeLabel(AppLocalizations t, MeetingType type) => switch (type) {
  MeetingType.daily => t.ttMeetingDaily,
  MeetingType.planning => t.ttMeetingPlanning,
  MeetingType.troubleshooting => t.ttMeetingTroubleshooting,
  MeetingType.retro => t.ttMeetingRetro,
  MeetingType.refinement => t.ttMeetingRefinement,
  MeetingType.other => t.ttMeetingOther,
};
