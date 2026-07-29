import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/core/network/api_client.dart';
import 'package:intellipilot/core/network/api_config.dart';
import 'package:intellipilot/core/utils/uuid_gen.dart';
import 'package:intellipilot/features/admin/data/admin_repository_impl.dart';
import 'package:intellipilot/features/admin/data/dtos/security_dtos.dart';
import 'package:intellipilot/features/admin/presentation/widgets/user_security_widgets.dart';
import 'package:intellipilot/features/profile/data/dtos/profile_dtos.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);
  final Future<ResponseBody> Function(RequestOptions) respond;
  RequestOptions? lastRequest;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<dynamic>? cancelFuture,
  ) {
    lastRequest = options;
    return respond(options);
  }
}

ResponseBody _ok(String body, {int status = 200}) => ResponseBody.fromString(
  body,
  status,
  headers: {
    Headers.contentTypeHeader: ['application/json'],
  },
);

ApiClient _client(_Adapter adapter) {
  final dio = Dio()..httpClientAdapter = adapter;
  return ApiClient(
    config: const ApiConfig(baseUrl: 'http://localhost'),
    uuidGen: const DefaultUuidGen(),
    tokenProvider: () => null,
    dio: dio,
  );
}

/// Wraps a widget with the localizations it needs.
Widget _host(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

AdminUserRow _row({
  String status = 'active',
  TwoFactorStatus twoFactor = const TwoFactorStatus(),
  int sessions = 0,
  SessionInfo? lastSession,
  DateTime? lastSeenAt,
  String? banReason,
}) => AdminUserRow(
  user: UserProfileFixture.build(),
  status: status,
  twoFactor: twoFactor,
  activeSessions: sessions,
  lastSession: lastSession,
  lastSeenAt: lastSeenAt,
  banReason: banReason,
);

void main() {
  group('AdminUserRow parsing', () {
    test('reads the security posture the admin list renders', () {
      final json =
          jsonDecode('''
        {
          "id": "u1", "email": "bob@example.com", "username": "bob",
          "full_name": "Bob B", "lang": "en", "timezone": "UTC",
          "is_active": true, "is_superadmin": false,
          "must_change_password": false, "auth_source": "local",
          "created_at": "2026-01-01T00:00:00Z",
          "status": "active",
          "two_factor": {
            "enabled": true, "totp": true,
            "passkeys": 2, "recovery_codes_left": 7
          },
          "active_sessions": 3,
          "last_session": {
            "id": "s1",
            "created_at": "2026-07-01T10:00:00Z",
            "last_seen_at": "2026-07-29T09:00:00Z",
            "ip": "84.75.10.20",
            "country_code": "CH",
            "city": "Zürich",
            "user_agent": "Mozilla/5.0 Chrome/120 Safari/537.36"
          },
          "last_seen_at": "2026-07-29T09:00:00Z",
          "last_login_at": "2026-07-28T08:00:00Z",
          "banned_at": null,
          "ban_reason": null,
          "banned_by": null
        }
      ''')
              as Map<String, dynamic>;

      final row = AdminUserRow.fromJson(json);
      expect(row.status, 'active');
      expect(row.twoFactor.enabled, isTrue);
      expect(row.twoFactor.passkeys, 2);
      expect(row.twoFactor.recoveryCodesLeft, 7);
      expect(row.activeSessions, 3);
      expect(row.lastSession?.city, 'Zürich');
      expect(row.lastSession?.countryCode, 'CH');
      expect(row.lastLoginAt, isNotNull);
      expect(row.isBanned, isFalse);
    });

    test('a banned row carries its reason', () {
      final json =
          jsonDecode('''
        {
          "id": "u2", "email": "eve@example.com", "username": "eve",
          "full_name": "", "lang": "en", "timezone": "UTC",
          "is_active": true, "is_superadmin": false,
          "must_change_password": false, "auth_source": "ldap",
          "created_at": "2026-01-01T00:00:00Z",
          "status": "banned",
          "two_factor": {"enabled": false, "totp": false,
                          "passkeys": 0, "recovery_codes_left": 0},
          "active_sessions": 0,
          "last_session": null,
          "banned_at": "2026-07-20T00:00:00Z",
          "ban_reason": "policy violation"
        }
      ''')
              as Map<String, dynamic>;

      final row = AdminUserRow.fromJson(json);
      expect(row.isBanned, isTrue);
      expect(row.banReason, 'policy violation');
      expect(row.lastSession, isNull);
      // The account is still `is_active` — a ban is a separate concept, and
      // conflating them is what let LDAP logins undo a deactivation.
      expect(row.user.isActive, isTrue);
    });

    test('tolerates absent security fields', () {
      final json =
          jsonDecode('''
        {
          "id": "u3", "email": "a@b.c", "username": "abc",
          "full_name": "", "lang": "en", "timezone": "UTC",
          "is_active": true, "is_superadmin": false,
          "must_change_password": false, "auth_source": "local",
          "created_at": "2026-01-01T00:00:00Z"
        }
      ''')
              as Map<String, dynamic>;

      final row = AdminUserRow.fromJson(json);
      expect(row.status, 'active');
      expect(row.twoFactor.enabled, isFalse);
      expect(row.activeSessions, 0);
      expect(row.lastSeenAt, isNull);
    });
  });

  group('country flags', () {
    test('builds a flag from any two-letter code', () {
      expect(countryFlagEmoji('CH'), '🇨🇭');
      expect(countryFlagEmoji('de'), '🇩🇪');
      expect(countryFlagEmoji('UA'), '🇺🇦');
    });

    test('returns nothing for codes that are not two ASCII letters', () {
      expect(countryFlagEmoji(null), '');
      expect(countryFlagEmoji(''), '');
      expect(countryFlagEmoji('CHE'), '');
      expect(countryFlagEmoji('1A'), '');
    });
  });

  group('private address detection', () {
    test('recognises the ranges the server refuses to resolve', () {
      for (final ip in [
        '10.0.0.1',
        '192.168.1.5',
        '172.16.0.1',
        '172.31.255.254',
        '127.0.0.1',
        '169.254.1.1',
        '100.64.0.1',
        '::1',
        'fd00::1',
        'fe80::1',
        '::ffff:10.0.0.1',
      ]) {
        expect(isPrivateIp(ip), isTrue, reason: '$ip should be private');
      }
    });

    test('treats public and unparseable addresses as public', () {
      for (final ip in ['8.8.8.8', '84.75.10.20', '172.32.0.1', 'nonsense']) {
        expect(isPrivateIp(ip), isFalse, reason: '$ip should not be private');
      }
      expect(isPrivateIp(null), isFalse);
    });
  });

  group('repository', () {
    test('reset-2fa reports what was cleared', () async {
      final adapter = _Adapter(
        (_) async => _ok(
          '{"totp_cleared":true,"passkeys_removed":2,'
          '"recovery_codes_removed":8,"sessions_revoked":3}',
        ),
      );
      final repo = AdminRepositoryImpl(_client(adapter));

      final res = await repo.resetTwoFactor('u1');
      final value = res.when(ok: (v) => v, err: (_) => null);

      expect(adapter.lastRequest?.path, '/api/v1/admin/users/u1/reset-2fa');
      expect(adapter.lastRequest?.method, 'POST');
      expect(value?.passkeysRemoved, 2);
      expect(value?.recoveryCodesRemoved, 8);
      expect(value?.clearedNothing, isFalse);
    });

    test('a reset that cleared nothing is reported as such', () {
      const result = TwoFactorResetResult(
        totpCleared: false,
        passkeysRemoved: 0,
        recoveryCodesRemoved: 0,
        sessionsRevoked: 0,
      );
      expect(result.clearedNothing, isTrue);
    });

    test('ban sends the reason', () async {
      final adapter = _Adapter(
        (_) async => _ok(
          '{"id":"u1","email":"a@b.c","username":"ab","full_name":"",'
          '"lang":"en","timezone":"UTC","is_active":true,'
          '"is_superadmin":false,"must_change_password":false,'
          '"auth_source":"local","created_at":"2026-01-01T00:00:00Z"}',
        ),
      );
      final repo = AdminRepositoryImpl(_client(adapter));

      await repo.banUser('u1', reason: 'spam');

      expect(adapter.lastRequest?.path, '/api/v1/admin/users/u1/ban');
      expect(
        (adapter.lastRequest?.data as Map<String, dynamic>?)?['reason'],
        'spam',
      );
    });

    test('ban omits an empty reason rather than sending a blank', () async {
      final adapter = _Adapter(
        (_) async => _ok(
          '{"id":"u1","email":"a@b.c","username":"ab","full_name":"",'
          '"lang":"en","timezone":"UTC","is_active":true,'
          '"is_superadmin":false,"must_change_password":false,'
          '"auth_source":"local","created_at":"2026-01-01T00:00:00Z"}',
        ),
      );
      final repo = AdminRepositoryImpl(_client(adapter));

      await repo.banUser('u1', reason: '');

      final body = adapter.lastRequest?.data as Map<String, dynamic>?;
      expect(body?.containsKey('reason'), isFalse);
    });

    test('the status filter reaches the query string', () async {
      final adapter = _Adapter(
        (_) async => _ok('{"items":[],"total":0,"limit":50,"offset":0}'),
      );
      final repo = AdminRepositoryImpl(_client(adapter));

      await repo.listUsers(status: 'banned');

      expect(adapter.lastRequest?.queryParameters['status'], 'banned');
    });

    test('geoip settings send only the fields being changed', () async {
      final adapter = _Adapter(
        (_) async => _ok(
          '{"enabled":true,"variant":"city","auto_update":true,'
          '"database_loaded":false,"attribution":"DB-IP"}',
        ),
      );
      final repo = AdminRepositoryImpl(_client(adapter));

      await repo.updateGeoipSettings(enabled: true);

      final body = adapter.lastRequest?.data as Map<String, dynamic>?;
      expect(body?['enabled'], isTrue);
      // Omitted fields must stay omitted or the server would overwrite them.
      expect(body?.containsKey('variant'), isFalse);
      expect(body?.containsKey('auto_update'), isFalse);
    });

    test('a variant change is sent through', () async {
      final adapter = _Adapter(
        (_) async => _ok(
          '{"enabled":true,"variant":"country","auto_update":true,'
          '"database_loaded":false,"attribution":"DB-IP"}',
        ),
      );
      final repo = AdminRepositoryImpl(_client(adapter));

      final res = await repo.updateGeoipSettings(variant: 'country');
      final value = res.when(ok: (v) => v, err: (_) => null);

      final body = adapter.lastRequest?.data as Map<String, dynamic>?;
      expect(body?['variant'], 'country');
      expect(value?.variant, 'country');
    });
  });

  group('widgets', () {
    testWidgets('the status pill names each state', (tester) async {
      await tester.pumpWidget(
        _host(
          Column(
            children: [
              StatusPill(row: _row()),
              StatusPill(row: _row(status: 'inactive')),
              StatusPill(
                row: _row(status: 'banned', banReason: 'spam'),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Active'), findsOneWidget);
      expect(find.text('Inactive'), findsOneWidget);
      expect(find.text('Banned'), findsOneWidget);
    });

    testWidgets('the 2FA badge distinguishes protected from bare accounts', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const Column(
            children: [
              TwoFactorBadge(
                status: TwoFactorStatus(
                  enabled: true,
                  totp: true,
                  passkeys: 1,
                  recoveryCodesLeft: 5,
                ),
              ),
              TwoFactorBadge(status: TwoFactorStatus()),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.verified_user), findsOneWidget);
      expect(find.byIcon(Icons.shield_outlined), findsOneWidget);
    });

    testWidgets('location shows the city when the database resolved one', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          SessionLocation(
            session: SessionInfo(
              id: 's1',
              createdAt: DateTime.utc(2026, 7, 1),
              lastSeenAt: DateTime.utc(2026, 7, 29),
              ip: '84.75.10.20',
              countryCode: 'CH',
              city: 'Zürich',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Zürich'), findsOneWidget);
      expect(find.text('🇨🇭'), findsOneWidget);
    });

    testWidgets('location falls back to the country when there is no city', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          SessionLocation(
            session: SessionInfo(
              id: 's1',
              createdAt: DateTime.utc(2026, 7, 1),
              lastSeenAt: DateTime.utc(2026, 7, 29),
              ip: '84.75.10.20',
              countryCode: 'DE',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('DE'), findsOneWidget);
    });

    testWidgets('a private address reads as the local network', (tester) async {
      await tester.pumpWidget(
        _host(
          SessionLocation(
            session: SessionInfo(
              id: 's1',
              createdAt: DateTime.utc(2026, 7, 1),
              lastSeenAt: DateTime.utc(2026, 7, 29),
              ip: '192.168.1.10',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Local network'), findsOneWidget);
    });

    testWidgets('no session renders a dash rather than a blank', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const SessionLocation(session: null)));
      await tester.pumpAndSettle();

      expect(find.text('—'), findsOneWidget);
    });

    testWidgets('the sessions sheet lists each device', (tester) async {
      await tester.pumpWidget(
        _host(
          UserSessionsSheet(
            email: 'bob@example.com',
            sessions: [
              SessionInfo(
                id: 's1',
                createdAt: DateTime.utc(2026, 7, 1),
                lastSeenAt: DateTime.utc(2026, 7, 29),
                ip: '84.75.10.20',
                countryCode: 'CH',
                city: 'Zürich',
                userAgent:
                    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
                    'AppleWebKit/537.36 (KHTML, like Gecko) '
                    'Chrome/120 Safari/537.36',
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Zürich'), findsWidgets);
      // The raw user-agent is unreadable; a browser/OS summary is shown.
      expect(find.text('Chrome · macOS'), findsOneWidget);
    });

    testWidgets('an empty sessions sheet says so', (tester) async {
      await tester.pumpWidget(
        _host(
          const UserSessionsSheet(email: 'bob@example.com', sessions: []),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No active sessions.'), findsOneWidget);
    });

    testWidgets('the activity dot appears only for recent activity', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          Column(
            children: [
              ActivityDot(
                lastSeenAt: DateTime.now().toUtc().subtract(
                  const Duration(minutes: 1),
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Tooltip), findsOneWidget);

      await tester.pumpWidget(
        _host(
          Column(
            children: [
              ActivityDot(
                lastSeenAt: DateTime.now().toUtc().subtract(
                  const Duration(hours: 3),
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Tooltip), findsNothing);
    });
  });
}

/// Minimal user fixture for the widget tests.
abstract final class UserProfileFixture {
  static UserProfile build() => UserProfile(
    id: 'u1',
    email: 'bob@example.com',
    username: 'bob',
    fullName: 'Bob B',
    lang: 'en',
    timezone: 'UTC',
    isActive: true,
    isSuperadmin: false,
    mustChangePassword: false,
    createdAt: DateTime.utc(2026),
  );
}
