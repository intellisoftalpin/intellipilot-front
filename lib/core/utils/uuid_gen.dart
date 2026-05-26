import 'package:uuid/uuid.dart';

/// Single source of UUIDs across the app. Centralized so tests can swap it.
abstract class UuidGen {
  String v4();
}

class DefaultUuidGen implements UuidGen {
  const DefaultUuidGen();
  static const _uuid = Uuid();

  @override
  String v4() => _uuid.v4();
}
