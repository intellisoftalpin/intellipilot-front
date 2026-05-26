import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/core/utils/uuid_gen.dart';

void main() {
  test('DefaultUuidGen produces valid UUIDv4 strings', () {
    const gen = DefaultUuidGen();
    final a = gen.v4();
    final b = gen.v4();
    expect(a, isNot(equals(b)));
    expect(a.length, 36);
    expect(RegExp(r'^[0-9a-f-]{36}$').hasMatch(a), isTrue);
  });
}
