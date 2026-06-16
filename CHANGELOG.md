# Changelog

All notable changes to the IntelliPilot frontend are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to Semantic Versioning.

## [0.3.2] - 2026-06-16

### Added
- **Admin → LDAP**: a bind-mode selector (Direct bind / Service account). The
  service-account mode adds fields for the service bind DN and password
  (write-only), the user search base, and a reverse group search (group search
  base + filter) — enabling OpenLDAP directories where the login name isn't the
  entry's RDN. Direct-bind setups are unchanged.

## [0.3.1] - 2026-06-16

### Added
- White-label branding: a developer footer on the login screen (links to the
  developer website, the GitHub repository, copyright, and the MIT license).
  Admin-configured custom app name, icon, and an optional login message now
  apply to the login screen, the top-bar brand mark, and the browser tab title
  (with fallback to the bundled name/logo).
- **Admin → Branding** page (superadmin): upload or reset the app icon, set or
  reset a custom app name, and set an optional message shown to users on the
  login screen.

### Changed
- **Admin → Notifications** redesigned into tabs (Email · Matrix · Telegram ·
  Events), each with its own Save button. The email provider is now a clear
  SMTP/Mailgun selector so the Mailgun fields (domain, base URL, API key) are
  easy to find.

### Fixed
- The navigation bar no longer disappears when opening an authenticated deep
  link directly (e.g. `/me/settings`). The shell now reacts to the session
  restoring from the refresh cookie instead of relying on a one-time snapshot.
- The LDAP "Test bind" result dialog's **Close** button is no longer stuck; it
  was popping the wrong navigator, leaving the dialog open over the page.

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
