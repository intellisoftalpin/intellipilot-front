import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/core/storage/hive_boxes.dart';

void main() {
  group('InMemoryKeyValueStorage', () {
    late InMemoryKeyValueStorage storage;
    setUp(() => storage = InMemoryKeyValueStorage());

    test('set + get round-trip', () async {
      await storage.set<String>('a', 'hello');
      expect(storage.get<String>('a'), 'hello');
    });

    test('get returns null on missing key', () {
      expect(storage.get<String>('absent'), isNull);
    });

    test('get returns null on type mismatch', () async {
      await storage.set<int>('n', 42);
      expect(storage.get<String>('n'), isNull);
    });

    test('remove deletes the entry', () async {
      await storage.set<int>('n', 1);
      await storage.remove('n');
      expect(storage.get<int>('n'), isNull);
    });

    test('HiveBoxes exposes stable box names', () {
      expect(HiveBoxes.settings, 'settings');
      expect(HiveBoxes.ui, 'ui');
      expect(HiveBoxes.etags, 'etags');
      expect(HiveBoxes.drafts, 'drafts');
    });
  });
}
