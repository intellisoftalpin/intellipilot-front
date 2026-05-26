import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/app/theme/app_theme.dart';
import 'package:intellipilot/app/theme/theme_cubit.dart';
import 'package:intellipilot/core/storage/hive_boxes.dart';

void main() {
  group('ThemeCubit', () {
    late InMemoryKeyValueStorage storage;

    setUp(() => storage = InMemoryKeyValueStorage());

    test('starts with defaults when storage is empty', () {
      final cubit = ThemeCubit(storage);
      expect(cubit.state.mode, ThemeMode.system);
      expect(cubit.state.seedColor, SeedPalette.defaultSeed);
      expect(cubit.state.useDynamic, isFalse);
    });

    test('restores previously persisted preferences', () async {
      await storage.set('theme.mode', 'dark');
      await storage.set('theme.seed', 0xFF112233);
      await storage.set('theme.dynamic', true);

      final cubit = ThemeCubit(storage);
      expect(cubit.state.mode, ThemeMode.dark);
      expect(cubit.state.seedColor.toARGB32(), 0xFF112233);
      expect(cubit.state.useDynamic, isTrue);
    });

    blocTest<ThemeCubit, ThemeState>(
      'setMode emits and persists',
      build: () => ThemeCubit(storage),
      act: (c) => c.setMode(ThemeMode.dark),
      expect: () => [
        isA<ThemeState>().having((s) => s.mode, 'mode', ThemeMode.dark),
      ],
      verify: (_) => expect(storage.get<String>('theme.mode'), 'dark'),
    );

    blocTest<ThemeCubit, ThemeState>(
      'setSeedColor emits and persists',
      build: () => ThemeCubit(storage),
      act: (c) => c.setSeedColor(const Color(0xFFAB12CD)),
      expect: () => [
        isA<ThemeState>().having(
          (s) => s.seedColor.toARGB32(),
          'seed',
          0xFFAB12CD,
        ),
      ],
      verify: (_) => expect(storage.get<int>('theme.seed'), 0xFFAB12CD),
    );

    blocTest<ThemeCubit, ThemeState>(
      'setUseDynamic emits and persists',
      build: () => ThemeCubit(storage),
      act: (c) => c.setUseDynamic(true),
      expect: () => [
        isA<ThemeState>().having((s) => s.useDynamic, 'useDynamic', true),
      ],
      verify: (_) => expect(storage.get<bool>('theme.dynamic'), isTrue),
    );
  });
}
