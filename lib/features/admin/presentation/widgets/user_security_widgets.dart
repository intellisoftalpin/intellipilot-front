import 'package:flutter/material.dart';
import 'package:intellipilot/core/datetime/relative_time.dart';
import 'package:intellipilot/features/admin/data/dtos/security_dtos.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// Account status as a coloured pill: Active / Inactive / Banned.
///
/// A ban is the loudest state on the page by design — it is the one an admin
/// most needs to spot, and the only one that cannot happen by accident.
class StatusPill extends StatelessWidget {
  const StatusPill({required this.row, super.key});

  final AdminUserRow row;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    final (label, bg, fg, icon) = switch (row.status) {
      'banned' => (
        l10n.adminUsersStatusBanned,
        scheme.errorContainer,
        scheme.onErrorContainer,
        Icons.block,
      ),
      'inactive' => (
        l10n.adminUsersStatusInactive,
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
        Icons.pause_circle_outline,
      ),
      _ => (
        l10n.adminUsersStatusActive,
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
        Icons.check_circle_outline,
      ),
    };

    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style:
                Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );

    // The reason is the first thing an admin wants when they see a ban.
    final reason = row.banReason;
    if (row.isBanned && reason != null && reason.isNotEmpty) {
      return Tooltip(
        message: l10n.adminUsersBannedReasonTooltip(reason),
        child: pill,
      );
    }
    return pill;
  }
}

/// Second-factor state: a filled shield when the account is protected, an
/// outlined one when it is not.
///
/// The tooltip breaks the total down, because "2FA on" hides the distinction
/// that matters during recovery — an account with only a passkey is locked out
/// just as hard as one with only TOTP.
class TwoFactorBadge extends StatelessWidget {
  const TwoFactorBadge({required this.status, super.key});

  final TwoFactorStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final on = status.enabled;

    final parts = <String>[
      if (status.totp) l10n.adminUsers2faTotp,
      if (status.passkeys > 0) l10n.adminUsers2faPasskeys(status.passkeys),
      if (status.recoveryCodesLeft > 0)
        l10n.adminUsers2faRecoveryCodes(status.recoveryCodesLeft),
    ];

    return Tooltip(
      message: on ? parts.join(' · ') : l10n.adminUsers2faOffTooltip,
      child: Icon(
        on ? Icons.verified_user : Icons.shield_outlined,
        size: 18,
        color: on ? scheme.primary : scheme.outline,
      ),
    );
  }
}

/// Live-session count. Tapping opens the per-session detail sheet.
class SessionChip extends StatelessWidget {
  const SessionChip({required this.count, required this.onTap, super.key});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final none = count == 0;

    return Tooltip(
      message: l10n.adminUsersSessionsTooltip(count),
      child: InkWell(
        onTap: none ? null : onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                none ? Icons.devices_outlined : Icons.devices,
                size: 16,
                color: none ? scheme.outline : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                '$count',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: none ? scheme.outline : scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Where the most recent session is: flag + city.
///
/// Falls back down a chain, because a city database leaves plenty of ranges
/// unresolved and an on-premise deployment resolves none of them:
/// city+country → country → "Local network" (private address) → "—".
class SessionLocation extends StatelessWidget {
  const SessionLocation({required this.session, super.key});

  final SessionInfo? session;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.outline,
    );

    final s = session;
    if (s == null) {
      return Text('—', style: muted);
    }

    final flag = countryFlagEmoji(s.countryCode);
    final hasLocation = s.countryCode != null || s.city != null;

    final String label;
    if (s.city != null && s.city!.isNotEmpty) {
      label = s.city!;
    } else if (s.countryCode != null) {
      label = s.countryCode!;
    } else if (s.isPrivateAddress) {
      // Deliberately not stored server-side: a private address has no
      // meaningful location, and inventing one would be worse than none.
      label = l10n.adminUsersLocationLocal;
    } else {
      label = '—';
    }

    final detail = <String>[
      if (s.city != null && s.city!.isNotEmpty) s.city!,
      if (s.countryCode != null) s.countryCode!,
      if (s.ip != null && s.ip!.isNotEmpty) s.ip!,
      l10n.adminUsersLastActiveTooltip(relativeTime(l10n, s.lastSeenAt)),
    ].join(' · ');

    return Tooltip(
      message: detail,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (flag.isNotEmpty) ...[
            Text(flag, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: hasLocation ? theme.textTheme.bodySmall : muted,
            ),
          ),
        ],
      ),
    );
  }
}

/// A small green dot for accounts active in the last few minutes.
class ActivityDot extends StatelessWidget {
  const ActivityDot({required this.lastSeenAt, super.key});

  final DateTime? lastSeenAt;

  @override
  Widget build(BuildContext context) {
    if (!isRecentlyActive(lastSeenAt)) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    return Tooltip(
      message: l10n.adminUsersOnlineNow,
      child: Container(
        width: 8,
        height: 8,
        margin: const EdgeInsets.only(right: 6),
        decoration: const BoxDecoration(
          color: Color(0xFF34C759),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

/// "Last active" / "last login" as relative text with the absolute time on
/// hover.
class TimestampCell extends StatelessWidget {
  const TimestampCell({
    required this.label,
    required this.value,
    required this.icon,
    super.key,
  });

  final String label;
  final DateTime? value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Tooltip(
      message: '$label: ${absoluteTime(value)}',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.outline),
          const SizedBox(width: 4),
          Text(
            relativeTime(l10n, value),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Per-session detail, shown in a bottom sheet from the session chip.
class UserSessionsSheet extends StatelessWidget {
  const UserSessionsSheet({
    required this.email,
    required this.sessions,
    super.key,
  });

  final String email;
  final List<SessionInfo> sessions;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.devices, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.adminUsersSessionsTitle(email),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (sessions.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text(l10n.adminUsersSessionsEmpty)),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: sessions.length,
                  separatorBuilder: (_, _) => const Divider(height: 12),
                  itemBuilder: (_, i) => _SessionRow(session: sessions[i]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.session});

  final SessionInfo session;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final flag = countryFlagEmoji(session.countryCode);

    final where = <String>[
      if (session.city != null && session.city!.isNotEmpty) session.city!,
      if (session.countryCode != null) session.countryCode!,
    ].join(', ');

    final location = where.isNotEmpty
        ? where
        : (session.isPrivateAddress
              ? l10n.adminUsersLocationLocal
              : l10n.adminUsersLocationUnknown);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: flag.isNotEmpty
              ? Text(flag, style: const TextStyle(fontSize: 18))
              : Icon(
                  Icons.public_off,
                  size: 18,
                  color: theme.colorScheme.outline,
                ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(location, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 2),
              Text(
                _describeAgent(session.userAgent, l10n),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                '${session.ip ?? '—'} · '
                '${l10n.adminUsersSessionStarted(absoluteTime(session.createdAt))}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Tooltip(
          message: absoluteTime(session.lastSeenAt),
          child: Text(
            relativeTime(l10n, session.lastSeenAt),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// A readable browser/OS guess from a user-agent string.
///
/// Intentionally shallow: this only has to help an admin recognise their own
/// device in a list, not classify traffic. Unrecognised agents fall back to
/// the raw string rather than a misleading label.
String _describeAgent(String ua, AppLocalizations l10n) {
  if (ua.isEmpty) return l10n.adminUsersDeviceUnknown;

  final browser = switch (ua) {
    _ when ua.contains('Edg/') => 'Edge',
    _ when ua.contains('OPR/') || ua.contains('Opera') => 'Opera',
    _ when ua.contains('Firefox/') => 'Firefox',
    // Chrome's UA also contains "Safari", so Chrome must be tested first.
    _ when ua.contains('Chrome/') => 'Chrome',
    _ when ua.contains('Safari/') => 'Safari',
    _ => null,
  };

  final os = switch (ua) {
    _ when ua.contains('Windows') => 'Windows',
    _ when ua.contains('Android') => 'Android',
    // "like Mac OS X" appears on iOS too, so iOS is tested first.
    _ when ua.contains('iPhone') || ua.contains('iPad') => 'iOS',
    _ when ua.contains('Mac OS') => 'macOS',
    _ when ua.contains('Linux') => 'Linux',
    _ => null,
  };

  if (browser == null && os == null) {
    return ua.length > 60 ? '${ua.substring(0, 60)}…' : ua;
  }
  return [browser, os].where((p) => p != null).join(' · ');
}
