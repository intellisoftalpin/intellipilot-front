import 'dart:ui';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/core/storage/hive_boxes.dart';

/// Owns the active app locale. `null` means "follow system".
class LocaleCubit extends Cubit<Locale?> {
  LocaleCubit(this._storage) : super(_load(_storage));

  final KeyValueStorage _storage;
  static const _kLocale = 'app.locale';

  static Locale? _load(KeyValueStorage storage) {
    final tag = storage.get<String>(_kLocale);
    if (tag == null || tag.isEmpty) return null;
    final parts = tag.split('_');
    if (parts.isEmpty) return null;
    return Locale(parts[0], parts.length > 1 ? parts[1] : null);
  }

  Future<void> setLocale(Locale? locale) async {
    emit(locale);
    if (locale == null) {
      await _storage.remove(_kLocale);
    } else {
      final tag = locale.countryCode == null
          ? locale.languageCode
          : '${locale.languageCode}_${locale.countryCode}';
      await _storage.set(_kLocale, tag);
    }
  }
}
