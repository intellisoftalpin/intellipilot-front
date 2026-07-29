import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// A short, human relative time such as "5m ago" or "3d ago".
///
/// Coarse on purpose: this labels "last active" and "last login" in dense
/// admin rows, where the shape of the answer (minutes vs. months) is what
/// matters. The exact timestamp is always available in the tooltip.
String relativeTime(AppLocalizations l10n, DateTime? when) {
  if (when == null) return l10n.relTimeNever;

  final delta = DateTime.now().toUtc().difference(when.toUtc());
  // A clock skew between client and server can put "last seen" slightly in the
  // future; reading that as "just now" is friendlier than a negative age.
  if (delta.isNegative || delta.inSeconds < 60) return l10n.relTimeJustNow;
  if (delta.inMinutes < 60) return l10n.relTimeMinutes(delta.inMinutes);
  if (delta.inHours < 24) return l10n.relTimeHours(delta.inHours);
  if (delta.inDays < 30) return l10n.relTimeDays(delta.inDays);
  if (delta.inDays < 365) return l10n.relTimeMonths(delta.inDays ~/ 30);
  return l10n.relTimeYears(delta.inDays ~/ 365);
}

/// Whether an activity timestamp counts as "right now" for the online dot.
bool isRecentlyActive(DateTime? when) {
  if (when == null) return false;
  final delta = DateTime.now().toUtc().difference(when.toUtc());
  return !delta.isNegative && delta.inMinutes < 5;
}

/// An absolute timestamp in the viewer's local zone, for tooltips.
String absoluteTime(DateTime? when) {
  if (when == null) return '—';
  final local = when.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
