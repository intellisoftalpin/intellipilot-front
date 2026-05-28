import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

/// Locale-aware short timestamp formatter. Renders `2026-05-28 13:45` in
/// English locales and `28.05.2026 13:45` in German — driven by the active
/// `Localizations` locale.
String formatTimestamp(BuildContext context, DateTime dt) {
  final locale = Localizations.localeOf(context).toLanguageTag();
  return DateFormat.yMd(locale).add_Hm().format(dt.toLocal());
}

/// Date-only variant used on milestone date ranges.
String formatDate(BuildContext context, DateTime dt) {
  final locale = Localizations.localeOf(context).toLanguageTag();
  return DateFormat.yMd(locale).format(dt.toLocal());
}
