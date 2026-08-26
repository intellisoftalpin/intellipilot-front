import 'package:hive_ce_flutter/hive_flutter.dart';

/// Centralized Hive box names. Tests can swap implementations behind the
/// [KeyValueStorage] interface; production uses [HiveKeyValueStorage].
class HiveBoxes {
  HiveBoxes._();

  static const String settings = 'settings';
  static const String ui = 'ui';
  static const String etags = 'etags';
  static const String drafts = 'drafts';
  static const String boards = 'boards';

  /// Initialize Hive and open all app-lifetime boxes.
  static Future<void> init() async {
    await Hive.initFlutter();
    await Future.wait([
      Hive.openBox<dynamic>(settings),
      Hive.openBox<dynamic>(ui),
      Hive.openBox<dynamic>(etags),
      Hive.openBox<dynamic>(drafts),
      Hive.openBox<dynamic>(boards),
    ]);
  }
}

/// Minimal key-value contract used by cubits/blocs so storage can be mocked
/// in tests without touching Hive.
abstract class KeyValueStorage {
  T? get<T>(String key);
  Future<void> set<T>(String key, T value);
  Future<void> remove(String key);

  /// Drop every key in this box. Used when the app switches servers: cached
  /// data keyed by `(userId, projectId)` carries no notion of *which* server it
  /// came from, so it cannot be allowed to outlive the connection.
  Future<void> clear();
}

class HiveKeyValueStorage implements KeyValueStorage {
  HiveKeyValueStorage(String boxName) : _box = Hive.box<dynamic>(boxName);
  final Box<dynamic> _box;

  @override
  T? get<T>(String key) {
    final value = _box.get(key);
    return value is T ? value : null;
  }

  @override
  Future<void> set<T>(String key, T value) => _box.put(key, value);

  @override
  Future<void> remove(String key) => _box.delete(key);

  @override
  Future<void> clear() => _box.clear();
}

/// In-memory implementation used in tests.
class InMemoryKeyValueStorage implements KeyValueStorage {
  final Map<String, Object?> _store = <String, Object?>{};

  @override
  T? get<T>(String key) {
    final value = _store[key];
    return value is T ? value : null;
  }

  @override
  Future<void> set<T>(String key, T value) async {
    _store[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    _store.remove(key);
  }

  @override
  Future<void> clear() async {
    _store.clear();
  }
}
