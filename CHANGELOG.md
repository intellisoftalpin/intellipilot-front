# Changelog

All notable changes to the IntelliPilot frontend are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to Semantic Versioning.

## [0.6.7] - 2026-07-09

### Added
- **Release badges on issues** — the selected fix version now renders as a
  colored badge (using its release's color) in the issues list row and on
  board cards. The board badge is opt-in: enable "Release" under a board's
  Settings → Card fields.

## [0.6.6] - 2026-07-09

### Added
- **Issue fix-version picker** — the issue detail page's "Fix version" row is
  now editable: click it to pick a release version, scoped to versions of
  releases linked to the issue's own components. If the issue has no
  components yet, the picker is disabled with a hint to add one first. The
  selected version shows its parent release's color as a small dot, and the
  previous bug where an unresolved version showed a raw UUID is fixed.

## [0.6.5] - 2026-07-09

### Added
- **Release badge color** — the release edit dialog (project settings →
  Releases) gained a color picker (same swatch picker used for labels,
  components, and epics); the releases list shows each release's color as a
  dot next to its name.

## [0.4.3] - 2026-06-19

### Added
- **Activity log** admin page (superadmin) — lists auth events (logins, failed
  logins with reason, first logins, password changes) with friendly labels,
  colour-coded success/failure, actor, IP, time, and an action filter.
- **Auth-source marker** in the admin users list — a clear **LDAP** / **Local**
  chip per user.

### Changed
- The **LDAP settings page is read-only** when the signed-in superadmin
  authenticated via LDAP (banner + disabled inputs + hidden Save), matching the
  backend guard.

## [0.4.2] - 2026-06-19

### Added
- **Issue fields**: a scaled **Size** badge (XS–XXL) replacing points; a
  **Category** dropdown; a **Customer** picker (shown for customer-request
  issues); **start/due** dates with overdue styling; a **Resolution** field; a
  **fix-version** field (a dropdown of versions from the issue's components'
  linked releases, or free text); an issue **Relationships** panel
  (blocks/relates/duplicates, in/out) and a **Watchers** control on the issue
  detail page; and **comment-level attachments**.
- **Customers** management tab and **Releases** management tab (releases +
  versions, with optional per-version repository/git-tag and component links) in
  Project Settings, mirroring the Repositories tab.
- **Git repositories & SSH keys management** in Project Settings (new
  *Repositories* tab):
  - **SSH keys**: generate per-project Ed25519 deploy keys (name + read-only
    toggle), view the public key/fingerprint with copy-to-clipboard, rename,
    flip read-only, and delete. Deleting a key in use warns that it will be
    detached from its repositories.
  - **Repositories**: add/edit (name, SSH URL, pick an existing key or create one
    inline), a **Fetch branches** action that lists the real remote branches to
    pick a default branch, reachability/host-fingerprint display, key
    reassignment for keyless repos, and delete.
  - **Per-component linking**: each component manages its linked repositories,
    each pinned to a branch chosen from the live branch list; change branch and
    unlink supported. Many repositories can link to one component.

### Changed
- Web **favicon and PWA icons** now use the IntelliPilot app icon instead of the
  default Flutter logo.
- A single **Priority** field (Low/Medium/High/Critical/Blocker) replaces the
  separate priority + severity pickers; **Size** replaces points across the
  board, backlog and editors.
- Removed the free-text git-repository field from the component editor —
  repositories are now structured and linked per branch.

## [0.3.4] - 2026-06-17

### Changed
- Redesigned the login screen: a modern two-pane "split hero" layout (branding
  panel + sign-in form) that collapses to a centered card on narrow screens. A
  gentle, low-cost animated backdrop (slowly drifting theme-coloured gradient
  blobs, no blur, isolated in a RepaintBoundary) plus polish touches: staggered
  fade/slide entrance, focus glow on inputs, a press-scale sign-in button that
  cross-fades into its spinner, and a softly floating logo. Honours the OS
  "reduce motion" setting and the white-label name/icon.

## [0.3.3] - 2026-06-17

### Added
- **Russian (Русский)** and **Belarusian (Беларуская)** UI translations, in
  addition to completing the **German** translation. All app strings — including
  the entire admin area (settings, branding, LDAP, notifications, users,
  invitations) — are now localised across English, German, Russian and
  Belarusian. The language picker in Settings offers all four.
- Profile: the timezone field is now a searchable dropdown of IANA timezones
  instead of a free-text field.

### Changed
- The whole admin area was moved off hardcoded English onto the localisation
  system, so it follows the selected language like the rest of the app.

### Removed
- The non-functional language dropdown on the Profile page. Language is chosen
  in **Settings** (it drives the whole app); the profile field did nothing.

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
