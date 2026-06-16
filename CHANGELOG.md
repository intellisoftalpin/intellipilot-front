# Changelog

All notable changes to the IntelliPilot frontend are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to Semantic Versioning.

## [0.3.0] - 2026-06-16

### Added
- **Admin → Notifications** page: configure email delivery (SMTP or Mailgun),
  Matrix, and Telegram, each with a "send test" button, plus per-event delivery
  toggles (login, issue created, issue resolved, daily status report) split
  across email and messengers. Secret fields are write-only (blank keeps the
  stored value).

### Fixed
- Admin → Platform settings page no longer hangs on an infinite spinner. The
  failure was an unparseable timestamp from the backend; the admin repository
  now also converts any response-parse error into a surfaced failure instead of
  letting it hang the page.

### Added
- Change password from **Account → Security** (local accounts only; LDAP users
  manage their password in the directory).
- German (Deutsch) language option in Settings.
- App logo: black-and-white mark in the navigation bar and on the login screen,
  full-colour mark in the About dialog.

### Changed
- The login form accepts an email address or a username.
- The "Sign up" link and the `/register` page are hidden when self-service
  registration is disabled on the server. Invitation links still work.
- The forgot-password page shows a "contact an administrator" message instead
  of an email form when the server has no mailer configured.
