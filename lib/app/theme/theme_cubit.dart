import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/app/theme/app_theme.dart';
import 'package:intellipilot/core/storage/hive_boxes.dart';

class ThemeState extends Equatable {
  const ThemeState({
    required this.mode,
    required this.seedColor,
    required this.useDynamic,
  });

  static const initial = ThemeState(
    mode: ThemeMode.system,
    seedColor: SeedPalette.defaultSeed,
    useDynamic: false,
  );

  final ThemeMode mode;
  final Color seedColor;
  final bool useDynamic;

  ThemeState copyWith({ThemeMode? mode, Color? seedColor, bool? useDynamic}) {
    return ThemeState(
      mode: mode ?? this.mode,
      seedColor: seedColor ?? this.seedColor,
      useDynamic: useDynamic ?? this.useDynamic,
    );
  }

  @override
  List<Object?> get props => [mode, seedColor.toARGB32(), useDynamic];
}

/// Owns the user's theme preferences. Changes propagate to `MaterialApp` via
/// `BlocBuilder` and are persisted to the `settings` Hive box.
class ThemeCubit extends Cubit<ThemeState> {
  ThemeCubit(this._storage) : super(_load(_storage));

  final KeyValueStorage _storage;

  static const _kMode = 'theme.mode';
  static const _kSeed = 'theme.seed';
  static const _kDynamic = 'theme.dynamic';

  static ThemeState _load(KeyValueStorage storage) {
    final mode = switch (storage.get<String>(_kMode)) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    final seedArgb =
        storage.get<int>(_kSeed) ?? SeedPalette.defaultSeed.toARGB32();
    final useDynamic = storage.get<bool>(_kDynamic) ?? false;
    return ThemeState(
      mode: mode,
      seedColor: Color(seedArgb),
      useDynamic: useDynamic,
    );
  }

  Future<void> setMode(ThemeMode mode) async {
    emit(state.copyWith(mode: mode));
    await _storage.set(_kMode, mode.name);
  }

  Future<void> setSeedColor(Color color) async {
    emit(state.copyWith(seedColor: color));
    await _storage.set(_kSeed, color.toARGB32());
  }

  Future<void> setUseDynamic(bool value) async {
    emit(state.copyWith(useDynamic: value));
    await _storage.set(_kDynamic, value);
  }
}
