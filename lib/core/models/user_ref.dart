// Shared, lightweight user descriptor parsed from any user-bearing JSON the
// backend returns (the flattened `ProfileCard` fields on `User` / `Membership`).
// Drives the avatar widget, the out-of-office badge, and the hover card.

/// An absence in effect today, with its booking's date range.
class OutToday {
  const OutToday({
    required this.kind,
    required this.startDate,
    required this.endDate,
  });

  factory OutToday.fromJson(Map<String, dynamic> j) => OutToday(
    kind: j['kind'] as String? ?? 'vacation',
    startDate: j['start_date'] as String? ?? '',
    endDate: j['end_date'] as String? ?? '',
  );

  final String kind; // vacation | illness | day_off | holiday
  final String startDate; // YYYY-MM-DD
  final String endDate;

  bool get isRange => startDate != endDate;
}

/// Avatar + motto + mood + out-of-office, mirrored from the backend descriptor.
class UserCard {
  const UserCard({
    this.avatarKind = 'default',
    this.avatarEmoji = '',
    this.avatarUpdatedAt,
    this.motto = '',
    this.moodEmoji = '',
    this.moodText = '',
    this.outToday,
  });

  factory UserCard.fromJson(Map<String, dynamic> j) => UserCard(
    avatarKind: j['avatar_kind'] as String? ?? 'default',
    avatarEmoji: j['avatar_emoji'] as String? ?? '',
    avatarUpdatedAt: j['avatar_updated_at'] as String?,
    motto: j['motto'] as String? ?? '',
    moodEmoji: j['mood_emoji'] as String? ?? '',
    moodText: j['mood_text'] as String? ?? '',
    outToday: j['out_today'] == null
        ? null
        : OutToday.fromJson(j['out_today'] as Map<String, dynamic>),
  );

  final String avatarKind; // default | image | emoji
  final String avatarEmoji;
  final String? avatarUpdatedAt;
  final String motto;
  final String moodEmoji;
  final String moodText;
  final OutToday? outToday;

  bool get hasImage => avatarKind == 'image';
  bool get hasEmoji => avatarKind == 'emoji' && avatarEmoji.isNotEmpty;
  bool get hasMood => moodText.isNotEmpty || moodEmoji.isNotEmpty;
}

/// Everything a UI needs to render a person: identity + the descriptor card.
class UserRef {
  const UserRef({
    required this.id,
    required this.username,
    required this.fullName,
    required this.email,
    required this.card,
  });

  /// Parse from any object carrying the flat user/card fields (User,
  /// Membership, admin user). [idKey] lets callers point at `user_id` when the
  /// row's own `id` is the membership id.
  factory UserRef.fromJson(Map<String, dynamic> j, {String idKey = 'id'}) =>
      UserRef(
        id: j[idKey] as String? ?? j['id'] as String? ?? '',
        username: j['username'] as String? ?? '',
        fullName: j['full_name'] as String? ?? '',
        email: j['email'] as String? ?? '',
        card: UserCard.fromJson(j),
      );

  final String id;
  final String username;
  final String fullName;
  final String email;
  final UserCard card;

  String get displayName {
    if (fullName.isNotEmpty) return fullName;
    if (username.isNotEmpty) return username;
    if (email.isNotEmpty) return email;
    return id;
  }

  /// Up-to-two-letter initials for the default avatar.
  String get initials {
    final source = fullName.isNotEmpty ? fullName : username;
    final parts = source
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      final p = parts.first;
      return (p.length >= 2 ? p.substring(0, 2) : p).toUpperCase();
    }
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}
