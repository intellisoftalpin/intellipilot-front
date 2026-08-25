import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/core/network/api_client.dart';
import 'package:intellipilot/core/network/api_config.dart';
import 'package:intellipilot/core/utils/uuid_gen.dart';
import 'package:intellipilot/features/admin/data/dtos/admin_dtos.dart';
import 'package:intellipilot/features/profile/data/dtos/profile_dtos.dart';
import 'package:intellipilot/features/timesheet/data/timesheet_repository_impl.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.body);
  final String body;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<dynamic>? cancelFuture,
  ) async => ResponseBody.fromString(
    body,
    200,
    headers: {
      Headers.contentTypeHeader: ['application/json'],
    },
  );
}

TimesheetRepositoryImpl _repo(String body) => TimesheetRepositoryImpl(
  ApiClient(
    config: const ApiConfig(baseUrl: 'http://localhost'),
    uuidGen: const DefaultUuidGen(),
    tokenProvider: () => null,
    dio: Dio()..httpClientAdapter = _Adapter(body),
  ),
);

const _oneMember = '''
{"year":2026,"month":3,
 "members":[{"user_id":"u1","username":"ann","full_name":"Ann",
             "total_minutes":480,"days":[{"date":"2026-03-02","minutes":480}]}]}
''';

void main() {
  group('UpdateUserRequest', () {
    test('sends exclude_from_time_reports only when set', () {
      expect(
        const UpdateUserRequest(excludeFromTimeReports: true).toJson(),
        {'exclude_from_time_reports': true},
      );
      // Clearing the flag must send `false`, not omit the key — otherwise the
      // server would leave it unchanged.
      expect(
        const UpdateUserRequest(excludeFromTimeReports: false).toJson(),
        {'exclude_from_time_reports': false},
      );
      expect(
        const UpdateUserRequest(isActive: true).toJson(),
        isNot(contains('exclude_from_time_reports')),
      );
    });
  });

  group('UserProfile', () {
    test('parses the flag, defaulting to not-excluded', () {
      final on = UserProfile.fromJson(
        jsonDecode('''
        {"id":"u1","email":"a@b","username":"a","full_name":"A",
         "created_at":"2026-01-01T00:00:00Z","exclude_from_time_reports":true}
        ''')
            as Map<String, dynamic>,
      );
      expect(on.excludeFromTimeReports, isTrue);

      final absent = UserProfile.fromJson(
        jsonDecode('''
        {"id":"u1","email":"a@b","username":"a","full_name":"A",
         "created_at":"2026-01-01T00:00:00Z"}
        ''')
            as Map<String, dynamic>,
      );
      expect(absent.excludeFromTimeReports, isFalse);
    });
  });

  group('TeamMonth', () {
    test('reads the excluded count when the server discloses it', () async {
      const body = '''
      {"year":2026,"month":3,"members":[],"excluded_members":2}
      ''';
      final res = await _repo(body).teamMonth('p1', year: 2026, month: 3);
      final grid = res.valueOrNull!;
      expect(grid.excludedMembers, 2);
      expect(grid.hasExclusions, isTrue);
    });

    test('an omitted count stays null, never coerced to zero', () async {
      // The API drops the field for non-superadmins. Null and 0 must stay
      // distinguishable: 0 means "nobody is excluded", null means "you are not
      // told" — and only the former is safe to render as a reassurance.
      final res = await _repo(_oneMember).teamMonth('p1', year: 2026, month: 3);
      final grid = res.valueOrNull!;
      expect(grid.excludedMembers, isNull);
      expect(grid.hasExclusions, isFalse);
      expect(grid.members.single.userId, 'u1');
    });

    test('zero disclosed means no note is shown', () async {
      const body = '''
      {"year":2026,"month":3,"members":[],"excluded_members":0}
      ''';
      final grid = (await _repo(
        body,
      ).teamMonth('p1', year: 2026, month: 3)).valueOrNull!;
      expect(grid.excludedMembers, 0);
      expect(grid.hasExclusions, isFalse);
    });

    test('the global admin grid parses the same shape', () async {
      const body = '''
      {"year":2026,"month":3,"members":[],"excluded_members":1}
      ''';
      final grid = (await _repo(
        body,
      ).adminGlobalMonth(year: 2026, month: 3)).valueOrNull!;
      expect(grid.excludedMembers, 1);
    });
  });
}
