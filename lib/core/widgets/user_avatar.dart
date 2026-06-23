import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/session/session_bloc.dart';
import 'package:intellipilot/core/models/user_ref.dart';
import 'package:intellipilot/core/network/api_config.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';
import 'package:intl/intl.dart';

/// Deterministic accent palette for default (initials) avatars.
const _palette = <Color>[
  Color(0xFF1565C0),
  Color(0xFF6A1B9A),
  Color(0xFF2E7D32),
  Color(0xFFAD1457),
  Color(0xFFEF6C00),
  Color(0xFF00838F),
  Color(0xFF4527A0),
  Color(0xFFC62828),
  Color(0xFF558B2F),
  Color(0xFF00695C),
  Color(0xFF5D4037),
  Color(0xFF283593),
];

Color _colorFor(String id) => _palette[id.hashCode.abs() % _palette.length];

/// Emoji shown as a small corner badge when a user is out today.
String _absenceBadge(String kind) => switch (kind) {
  'vacation' => '🌴',
  'illness' => '🤒',
  'day_off' => '🏠',
  'holiday' => '🎉',
  _ => '•',
};

String _absenceLabel(AppLocalizations t, String kind) => switch (kind) {
  'vacation' => t.ttKindVacation,
  'illness' => t.ttKindIllness,
  'day_off' => t.ttKindDayOff,
  'holiday' => t.ttKindHoliday,
  _ => kind,
};

/// A circular user avatar — uploaded image (incl. animated GIF), emoji, or
/// initials-on-color — with an optional out-of-office badge and a rich hover
/// card (name, @user, email, id, motto, mood, out-of-office).
class UserAvatar extends StatefulWidget {
  const UserAvatar({
    required this.user,
    this.size = 32,
    this.enableHover = true,
    this.showBadge = true,
    super.key,
  });

  final UserRef user;
  final double size;
  final bool enableHover;
  final bool showBadge;

  @override
  State<UserAvatar> createState() => _UserAvatarState();
}

class _UserAvatarState extends State<UserAvatar> {
  final _controller = OverlayPortalController();
  final _link = LayerLink();
  bool _overAvatar = false;
  bool _overCard = false;
  Timer? _hideTimer;

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _show() {
    _hideTimer?.cancel();
    if (!_controller.isShowing) _controller.show();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 180), () {
      if (!_overAvatar && !_overCard) _controller.hide();
    });
  }

  String? _imageUrl() {
    final c = widget.user.card;
    if (!c.hasImage) return null;
    final base = getIt<ApiConfig>().baseUrl;
    final v = Uri.encodeQueryComponent(c.avatarUpdatedAt ?? '');
    return '$base/api/v1/users/${widget.user.id}/avatar?v=$v';
  }

  @override
  Widget build(BuildContext context) {
    final avatar = _Disc(
      user: widget.user,
      size: widget.size,
      imageUrl: _imageUrl(),
    );
    final badge = widget.user.card.outToday;

    Widget stack = avatar;
    if (widget.showBadge && badge != null) {
      final bs = (widget.size * 0.42).clamp(12.0, 22.0);
      stack = Stack(
        clipBehavior: Clip.none,
        children: [
          avatar,
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: bs,
              height: bs,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).colorScheme.surface,
                  width: 1,
                ),
              ),
              child: Text(
                _absenceBadge(badge.kind),
                style: TextStyle(fontSize: bs * 0.7),
              ),
            ),
          ),
        ],
      );
    }

    if (!widget.enableHover) return stack;

    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _controller,
        overlayChildBuilder: (_) => CompositedTransformFollower(
          link: _link,
          targetAnchor: Alignment.bottomLeft,
          followerAnchor: Alignment.topLeft,
          offset: const Offset(0, 8),
          child: Align(
            alignment: Alignment.topLeft,
            child: MouseRegion(
              onEnter: (_) {
                _overCard = true;
                _show();
              },
              onExit: (_) {
                _overCard = false;
                _scheduleHide();
              },
              child: UserHoverCard(user: widget.user),
            ),
          ),
        ),
        child: MouseRegion(
          onEnter: (_) {
            _overAvatar = true;
            _show();
          },
          onExit: (_) {
            _overAvatar = false;
            _scheduleHide();
          },
          child: GestureDetector(
            onTap: () => _controller.isShowing ? _controller.hide() : _show(),
            child: stack,
          ),
        ),
      ),
    );
  }
}

class _Disc extends StatelessWidget {
  const _Disc({required this.user, required this.size, this.imageUrl});
  final UserRef user;
  final double size;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(user.id);
    final url = imageUrl;
    if (url != null) {
      final token = getIt<SessionBloc>().currentAccessToken;
      return ClipOval(
        child: Image.network(
          url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          headers: token == null ? null : {'Authorization': 'Bearer $token'},
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => _fallback(color),
        ),
      );
    }
    return _fallback(color);
  }

  Widget _fallback(Color color) {
    final emoji = user.card.hasEmoji ? user.card.avatarEmoji : null;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: emoji != null
          ? Text(emoji, style: TextStyle(fontSize: size * 0.55))
          : Text(
              user.initials,
              style: TextStyle(
                color: Colors.white,
                fontSize: size * 0.4,
                fontWeight: FontWeight.w600,
              ),
            ),
    );
  }
}

/// The hover/tap popover with the user's identity and status.
class UserHoverCard extends StatelessWidget {
  const UserHoverCard({required this.user, super.key});
  final UserRef user;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final c = user.card;
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(12),
      color: theme.colorScheme.surface,
      child: Container(
        width: 280,
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                UserAvatar(user: user, size: 56, enableHover: false),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.displayName,
                        style: theme.textTheme.titleMedium,
                      ),
                      if (user.username.isNotEmpty)
                        Text(
                          '@${user.username}',
                          style: theme.textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (c.hasMood) ...[
              const SizedBox(height: 10),
              _MoodChip(emoji: c.moodEmoji, text: c.moodText),
            ],
            if (c.outToday != null) ...[
              const SizedBox(height: 8),
              _outOfOffice(context, t, c.outToday!),
            ],
            if (c.motto.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                '“${c.motto}”',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            const Divider(height: 20),
            if (user.email.isNotEmpty)
              _kv(context, Icons.mail_outline, user.email),
            _kv(context, Icons.tag, user.id, mono: true),
          ],
        ),
      ),
    );
  }

  Widget _outOfOffice(BuildContext context, AppLocalizations t, OutToday o) {
    final theme = Theme.of(context);
    final fmt = DateFormat.MMMd(
      Localizations.localeOf(context).toLanguageTag(),
    );
    String range;
    try {
      final s = fmt.format(DateTime.parse(o.startDate));
      range = o.isRange ? '$s – ${fmt.format(DateTime.parse(o.endDate))}' : s;
    } on FormatException {
      range = o.startDate;
    }
    return Row(
      children: [
        Text(_absenceBadge(o.kind)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '${_absenceLabel(t, o.kind)} · $range',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ),
      ],
    );
  }

  Widget _kv(
    BuildContext context,
    IconData icon,
    String value, {
    bool mono = false,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(
              value,
              maxLines: 1,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: mono ? 'monospace' : null,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MoodChip extends StatelessWidget {
  const _MoodChip({required this.emoji, required this.text});
  final String emoji;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (emoji.isNotEmpty) ...[Text(emoji), const SizedBox(width: 6)],
          Flexible(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
