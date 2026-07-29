import 'package:intellipilot/features/profile/data/dtos/profile_dtos.dart';

/// Which second factors an account holds — mirrors
/// `intellipilot_core::user::TwoFactorStatus`.
///
/// [enabled] is what the login path gates on. It matters for recovery: a user
/// who lost a passkey is as locked out as one who lost their authenticator, so
/// the admin reset clears every factor listed here.
class TwoFactorStatus {
  const TwoFactorStatus({
    this.enabled = false,
    this.totp = false,
    this.passkeys = 0,
    this.recoveryCodesLeft = 0,
  });

  factory TwoFactorStatus.fromJson(Map<String, dynamic> json) {
    return TwoFactorStatus(
      enabled: json['enabled'] as bool? ?? false,
      totp: json['totp'] as bool? ?? false,
      passkeys: (json['passkeys'] as num?)?.toInt() ?? 0,
      recoveryCodesLeft: (json['recovery_codes_left'] as num?)?.toInt() ?? 0,
    );
  }

  final bool enabled;
  final bool totp;
  final int passkeys;
  final int recoveryCodesLeft;
}

/// One logical session — mirrors `intellipilot_core::user::SessionInfo`.
class SessionInfo {
  const SessionInfo({
    required this.id,
    required this.createdAt,
    required this.lastSeenAt,
    this.ip,
    this.countryCode,
    this.city,
    this.userAgent = '',
  });

  factory SessionInfo.fromJson(Map<String, dynamic> json) {
    return SessionInfo(
      id: json['id'] as String? ?? '',
      createdAt: DateTime.parse(json['created_at'] as String),
      lastSeenAt: DateTime.parse(json['last_seen_at'] as String),
      ip: json['ip'] as String?,
      countryCode: json['country_code'] as String?,
      city: json['city'] as String?,
      userAgent: json['user_agent'] as String? ?? '',
    );
  }

  final String id;
  final DateTime createdAt;
  final DateTime lastSeenAt;
  final String? ip;

  /// ISO 3166-1 alpha-2. Null when geolocation is off (the default), the
  /// address is private, or the database had no entry.
  final String? countryCode;
  final String? city;
  final String userAgent;

  /// True when the address is one geolocation deliberately never resolves.
  ///
  /// Mirrors the server's `geoip::is_private`. Checked client-side so a
  /// private address can render as "Local network" without the server storing
  /// an invented location for it.
  bool get isPrivateAddress => isPrivateIp(ip);
}

/// Whether an address is private, loopback, link-local or carrier-NAT.
///
/// Kept in step with `crates/api/src/geoip.rs::is_private`. Deliberately
/// tolerant: anything unparseable is treated as public so we never mislabel a
/// real location as "Local network".
bool isPrivateIp(String? ip) {
  if (ip == null || ip.isEmpty) return false;
  final v = ip.trim();
  if (v == '::1' || v == '::') return true;

  // IPv6 unique-local (fc00::/7) and link-local (fe80::/10).
  final lower = v.toLowerCase();
  if (lower.startsWith('fc') ||
      lower.startsWith('fd') ||
      lower.startsWith('fe8') ||
      lower.startsWith('fe9') ||
      lower.startsWith('fea') ||
      lower.startsWith('feb')) {
    if (lower.contains(':')) return true;
  }

  // IPv4-mapped IPv6 (::ffff:10.0.0.1) reduces to its IPv4 part.
  final mapped = lower.startsWith('::ffff:') ? lower.substring(7) : lower;

  final parts = mapped.split('.');
  if (parts.length != 4) return false;
  final octets = <int>[];
  for (final p in parts) {
    final n = int.tryParse(p);
    if (n == null || n < 0 || n > 255) return false;
    octets.add(n);
  }
  final a = octets[0];
  final b = octets[1];
  if (a == 10 || a == 127 || a == 0) return true;
  if (a == 192 && b == 168) return true;
  if (a == 172 && b >= 16 && b <= 31) return true;
  if (a == 169 && b == 254) return true;
  // 100.64.0.0/10 — carrier-grade NAT.
  if (a == 100 && b >= 64 && b <= 127) return true;
  return false;
}

/// The flag emoji for an ISO 3166-1 alpha-2 code.
///
/// Built from regional-indicator code points rather than a lookup table, so
/// every country works without shipping (or translating) a 250-entry map.
/// Returns an empty string for anything that is not two ASCII letters.
String countryFlagEmoji(String? isoCode) {
  final code = isoCode?.trim().toUpperCase();
  if (code == null || code.length != 2) return '';
  const base = 0x1F1E6; // REGIONAL INDICATOR SYMBOL LETTER A
  final first = code.codeUnitAt(0);
  final second = code.codeUnitAt(1);
  if (first < 0x41 || first > 0x5A || second < 0x41 || second > 0x5A) return '';
  return String.fromCharCodes([
    base + (first - 0x41),
    base + (second - 0x41),
  ]);
}

/// A user row on the admin list, carrying the account's security posture.
///
/// Mirrors `intellipilot_core::user::AdminUserRow`. The security fields ride
/// alongside the flattened [UserProfile] rather than inside it, because they
/// exist only on this endpoint — `/me` and embedded user references never
/// carry them.
class AdminUserRow {
  const AdminUserRow({
    required this.user,
    required this.status,
    required this.twoFactor,
    this.activeSessions = 0,
    this.lastSession,
    this.lastSeenAt,
    this.lastLoginAt,
    this.bannedAt,
    this.banReason,
  });

  factory AdminUserRow.fromJson(Map<String, dynamic> json) {
    final session = json['last_session'];
    return AdminUserRow(
      user: UserProfile.fromJson(json),
      status: json['status'] as String? ?? 'active',
      twoFactor: TwoFactorStatus.fromJson(
        (json['two_factor'] as Map<String, dynamic>?) ?? const {},
      ),
      activeSessions: (json['active_sessions'] as num?)?.toInt() ?? 0,
      lastSession: session is Map<String, dynamic>
          ? SessionInfo.fromJson(session)
          : null,
      lastSeenAt: _parseOrNull(json['last_seen_at']),
      lastLoginAt: _parseOrNull(json['last_login_at']),
      bannedAt: _parseOrNull(json['banned_at']),
      banReason: json['ban_reason'] as String?,
    );
  }

  static DateTime? _parseOrNull(Object? raw) =>
      raw is String ? DateTime.tryParse(raw) : null;

  final UserProfile user;

  /// `active` | `inactive` | `banned`. Precomputed server-side: the three
  /// inputs have a precedence the client should not reimplement.
  final String status;
  final TwoFactorStatus twoFactor;
  final int activeSessions;

  /// The most recently active session — source of the location shown in the
  /// list. Null when the user has no live session.
  final SessionInfo? lastSession;
  final DateTime? lastSeenAt;
  final DateTime? lastLoginAt;
  final DateTime? bannedAt;
  final String? banReason;

  bool get isBanned => status == 'banned';
  bool get isInactive => status == 'inactive';

  String get id => user.id;
  String get email => user.email;
}

/// What an admin 2FA reset removed — mirrors
/// `crate::admin::dto::TwoFactorResetResponse`.
class TwoFactorResetResult {
  const TwoFactorResetResult({
    required this.totpCleared,
    required this.passkeysRemoved,
    required this.recoveryCodesRemoved,
    required this.sessionsRevoked,
  });

  factory TwoFactorResetResult.fromJson(Map<String, dynamic> json) {
    return TwoFactorResetResult(
      totpCleared: json['totp_cleared'] as bool? ?? false,
      passkeysRemoved: (json['passkeys_removed'] as num?)?.toInt() ?? 0,
      recoveryCodesRemoved:
          (json['recovery_codes_removed'] as num?)?.toInt() ?? 0,
      sessionsRevoked: (json['sessions_revoked'] as num?)?.toInt() ?? 0,
    );
  }

  final bool totpCleared;
  final int passkeysRemoved;
  final int recoveryCodesRemoved;
  final int sessionsRevoked;

  /// True when the account had no second factor at all — worth telling the
  /// admin, since the reset then changed nothing.
  bool get clearedNothing =>
      !totpCleared && passkeysRemoved == 0 && recoveryCodesRemoved == 0;
}

/// Geolocation configuration + installed-database state — mirrors
/// `crate::admin::dto::GeoipStatusResponse`.
class GeoipStatus {
  const GeoipStatus({
    required this.enabled,
    required this.variant,
    required this.autoUpdate,
    required this.databaseLoaded,
    required this.attribution,
    this.installedVariant,
    this.buildMonth,
    this.fileSize,
    this.source,
    this.downloadedAt,
    this.checkedAt,
    this.lastError,
  });

  factory GeoipStatus.fromJson(Map<String, dynamic> json) {
    return GeoipStatus(
      enabled: json['enabled'] as bool? ?? false,
      variant: json['variant'] as String? ?? 'city',
      autoUpdate: json['auto_update'] as bool? ?? true,
      databaseLoaded: json['database_loaded'] as bool? ?? false,
      attribution: json['attribution'] as String? ?? '',
      installedVariant: json['installed_variant'] as String?,
      buildMonth: json['build_month'] as String?,
      fileSize: (json['file_size'] as num?)?.toInt(),
      source: json['source'] as String?,
      downloadedAt: AdminUserRow._parseOrNull(json['downloaded_at']),
      checkedAt: AdminUserRow._parseOrNull(json['checked_at']),
      lastError: json['last_error'] as String?,
    );
  }

  final bool enabled;

  /// `country` (~4 MB) or `city` (~62 MB).
  final String variant;
  final bool autoUpdate;

  /// Whether a database is loaded and answering lookups right now.
  final bool databaseLoaded;

  /// Attribution required by the database licence (CC BY 4.0). Must be shown
  /// wherever geolocation results appear.
  final String attribution;
  final String? installedVariant;
  final String? buildMonth;
  final int? fileSize;
  final String? source;
  final DateTime? downloadedAt;
  final DateTime? checkedAt;

  /// Message from the last failed refresh — surfaced so a monthly update that
  /// has been quietly failing stays visible.
  final String? lastError;

  bool get hasDatabase => buildMonth != null;
}

/// Outcome of a manual "update now".
class GeoipUpdateResult {
  const GeoipUpdateResult({
    required this.installed,
    required this.status,
    this.buildMonth,
  });

  factory GeoipUpdateResult.fromJson(Map<String, dynamic> json) {
    return GeoipUpdateResult(
      installed: json['installed'] as bool? ?? false,
      status: GeoipStatus.fromJson(
        (json['status'] as Map<String, dynamic>?) ?? const {},
      ),
      buildMonth: json['build_month'] as String?,
    );
  }

  /// False when the installed database was already the newest published one.
  final bool installed;
  final GeoipStatus status;
  final String? buildMonth;
}
