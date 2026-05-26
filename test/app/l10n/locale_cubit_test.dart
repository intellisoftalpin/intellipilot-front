import 'dart:ui';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/app/l10n/locale_cubit.dart';
import 'package:intellipilot/core/storage/hive_boxes.dart';

void main() {
  group('LocaleCubit', () {
    late InMemoryKeyValueStorage storage;
    setUp(() => storage = InMemoryKeyValueStorage());

    test('initial state is null when no locale stored', () {
      expect(LocaleCubit(storage).state, isNull);
    });

    test('restores persisted language code', () async {
      await storage.set('app.locale', 'de');
      expect(LocaleCubit(storage).state, const Locale('de'));
    });

    test('restores persisted language + country code', () async {
      await storage.set('app.locale', 'de_CH');
      final locale = LocaleCubit(storage).state;
      expect(locale?.languageCode, 'de');
      expect(locale?.countryCode, 'CH');
    });

    blocTest<LocaleCubit, Locale?>(
      'setLocale(null) clears persisted value',
      build: () => LocaleCubit(storage),
      seed: () => const Locale('en'),
      act: (c) => c.setLocale(null),
      expect: () => [null],
      verify: (_) => expect(storage.get<String>('app.locale'), isNull),
    );

    blocTest<LocaleCubit, Locale?>(
      'setLocale persists language code',
      build: () => LocaleCubit(storage),
      act: (c) => c.setLocale(const Locale('en')),
      expect: () => [const Locale('en')],
      verify: (_) => expect(storage.get<String>('app.locale'), 'en'),
    );
  });
}
