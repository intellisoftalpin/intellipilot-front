import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/core/storage/hive_boxes.dart';
import 'package:intl/intl.dart';

/// Which day calendars start the week on. Monday is the app default,
/// regardless of the locale's own convention.
enum WeekStart {
  monday('monday', DateTime.monday),
  saturday('saturday', DateTime.saturday),
  sunday('sunday', DateTime.sunday);

  const WeekStart(this.wire, this.weekday);

  /// Stable storage token.
  final String wire;

  /// [DateTime.weekday] value (Mon=1 … Sun=7).
  final int weekday;

  /// intl `DateSymbols.FIRSTDAYOFWEEK` convention: 0 = Monday … 6 = Sunday.
  int get intlIndex => weekday - 1;

  static WeekStart fromWire(String? wire) {
    for (final w in WeekStart.values) {
      if (w.wire == wire) return w;
    }
    return WeekStart.monday;
  }
}

/// Owns the calendar week-start preference (default: Monday).
///
/// Material date pickers lay their calendar out from
/// `MaterialLocalizations.firstDayOfWeekIndex`, which the localizations
/// read live from intl's per-locale `DateSymbols`. [applyToLocale] patches
/// that value for the active locale, so every picker app-wide follows the
/// preference without wrapping each call site.
class WeekStartCubit extends Cubit<WeekStart> {
  WeekStartCubit(this._storage)
    : super(WeekStart.fromWire(_storage.get<String>(_kWeekStart)));

  final KeyValueStorage _storage;
  static const _kWeekStart = 'app.weekStart';

  Future<void> setWeekStart(WeekStart value) async {
    emit(value);
    await _storage.set(_kWeekStart, value.wire);
  }

  /// Point intl's (mutable, shared) date symbols for [locale] at the chosen
  /// week start. Safe to call on every build — it is a plain field write on
  /// an already-loaded symbols object.
  static void applyToLocale(Locale locale, WeekStart value) {
    for (final tag in {locale.toLanguageTag(), locale.languageCode}) {
      try {
        DateFormat.yMd(tag).dateSymbols.FIRSTDAYOFWEEK = value.intlIndex;
      } on Object {
        // Locale data not initialised (yet) under this tag — the other tag
        // or a later build covers it.
      }
    }
  }
}
