# Changelog

All notable changes to the IntelliPilot frontend are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to Semantic Versioning.

## [0.7.11] - 2026-10-07

### Fixed
- The built-in version fallback was left at 0.7.9 in 0.7.10, so CI failed and
  0.7.10 was never published. Its changes ship in this release.

## [0.7.10] - 2026-10-07

### Added
- **Milestones in the top navigation.** A cross-project timeline of every
  milestone you may see, each row in its project's colour with a prefix chip.
  View only — no creating — but a row opens the usual detail sidebar,
  editable where your project role allows. Rows are chronological by default,
  or grouped by project.
- **Planned and actual start date** in the milestone sidebar, next to the
  planned and actual end. Row labels show both ranges; actual dates are
  coloured orange when late and green when early.

### Changed
- **The timeline is the default milestones view** (a board choice you made
  earlier is kept). It opens centred on today, a Today button re-centres it,
  zooming keeps the centre date in place, and the date header stays put while
  rows scroll.
- **Completed milestones start collapsed** as "Completed (N)" — on the
  timeline and on the board — and are only loaded when expanded.
- **New bar design.** Bars take the project colour with the done fraction
  filled in; late and early starts/ends are striped orange/green; the business
  release is a thin blue tail ending in a diamond; estimated dates get a
  dashed outline and overdue milestones a red one. A legend explains it.
- **Progress ring** is larger and its label always fits inside; a full ring
  shows a check mark.

### Fixed
- Demo mode no longer drops a milestone's actual end date when it is edited
  or completed.

## [0.7.9] - 2026-10-07

### Added
- **Arch Linux package.** `scripts/build-linux.sh` also builds
  `intellipilot-<version>-<build>-<x86_64|aarch64>.pkg.tar.zst` (depends on
  `gtk3` and `libsecret`; install with `pacman -U`), and every release tag
  attaches it for x86_64 and aarch64 (Arch Linux ARM) next to the `.deb` and
  `.rpm`.

## [0.7.8] - 2026-10-06

### Added
- **Linux desktop packages.** `scripts/build-linux.sh` builds the app and
  packages it as `.deb` and `.rpm` (installed under `/opt/intellipilot`, with
  an `intellipilot` command, a launcher entry and icons; needs glibc 2.39+:
  Ubuntu 24.04+, Debian 13+, Fedora 40+, RHEL 10). Every release tag builds
  them for x86_64 and arm64 in CI and attaches them to the GitHub release.
- **The Linux app draws its own title bar.** GTK's title bar is gone; the
  window buttons sit in the app's top bar, laid out the way the desktop lays
  them out (GNOME: a close button on the right). The bar's empty space moves
  the window, double-click maximizes it.

### Changed
- **Dashboard: projects in a column on the right**, each card with the
  project icon and name and no task count. It lists every project you are a
  member of, those you are involved in most first (needs the 0.7.8 server).
  Narrow windows keep the projects below the rest.
- **Settings left the top navigation**; it stays in the account menu.
- **The login screen no longer animates.** The drifting background and the
  floating logo repainted the whole window every frame, which made the screen
  sluggish where rendering runs on the CPU; the form now appears at once.

## [0.7.7] - 2026-10-06

### Fixed
- **401 errors in the console, slow or missing pages after a tab or device
  wakes up.** Browsers pause the token refresh timer in background tabs and
  while the device sleeps, so the first requests after a wake-up went out
  with an expired token and each came back 401 before being retried. A
  request now waits for the renewal instead of sending an expired token, and
  the app renews as soon as it returns to the foreground.
- **Pages restarted their loading on every token renewal.** The router
  rebuilt the open page whenever the session state changed, including the two
  changes of a routine renewal, and Milestones, Backlog, Project settings and
  the Wiki pages fetched the profile again each time. The router now reacts
  only to sign-in, sign-out and account switches, and those pages load the
  profile once.
- **A dropped connection during a renewal signed the user out.** Network
  errors, server errors and rate limiting now keep the session and retry
  (5 s, 10 s, 20 s, 40 s, then every minute, and at once when the app comes
  back to the foreground); only a refusal from the server ends it.
- **The project name in the header could stay blank for the whole session**
  after one failed lookup. Failed lookups are no longer cached; the next
  navigation asks again.

## [0.7.6] - 2026-09-23

### Fixed
- **Creating a user could spin forever (critical).** When the page's access
  token had expired, the create request came back 401 and waited for a session
  renewal that, on 0.7.4, was queued behind a cross-tab lock held by a frozen
  tab (the 0.7.5 fix below). Nothing bounded that wait, so the dialog's button
  spun with no request ever retried. Any request now waits at most 20 seconds
  for a renewal; past that it fails with a visible error and the renewal still
  finishes in the background. A 401 received while signed out no longer waits
  for a sign-in that may never come.

### Changed
- Redesigned the Create user dialog: icon and explanation header, outlined
  fields with icons, a password field with show/hide and a helper line instead
  of a truncated label, a described superadmin option, Create enabled only once
  email and username are filled, Enter submits, and errors shown in a tinted
  panel. A failed session renewal gets its own message.

## [0.7.5] - 2026-09-23

### Fixed
- **The app could hang on a spinner forever after a reload (critical).** Since
  0.7.3, browser tabs take turns renewing the session through a shared lock
  (the Web Locks API), and a tab waited for that lock with no time limit. A
  tab that never let go, typically a background tab the browser had frozen,
  left every other tab and every reload stuck before sign-in: no renewal was
  sent, no login page appeared. A tab now waits at most 5 seconds and then
  takes the lock over. If two renewals overlap as a result, the server's
  0.7.3 grace window handles it. Regression tests cover a lock holder that
  never releases.

## [0.7.4] - 2026-09-23

### Fixed
- **Session renewal sends `{}` instead of an empty body.** The client sets a
  JSON content type on every request; servers before 0.7.4 answer "JSON content
  type, empty body" with 400, which broke every renewal and logged browser
  users out within minutes and on every reload. Also fixes the app against an
  un-upgraded server.
- **The global "+ Create" button now preselects the project you are in.** The
  shell only sees the URL's project segment, which short links canonicalise to
  the project's *prefix* (`/projects/ps/board`), while the picker matches on
  project id — so nothing was ever preselected, anywhere. The shell resolves
  the segment once and hands the id to everything that calls the API, keeping
  the short form for links.
- **Command palette search works inside a project again.** It sent that same
  prefix as `boost_project_id`, which the server — typing both project
  parameters as ids — rejects with 400, failing the whole search: no results
  at all while inside any project. The repository now drops a project value
  that is not an id, so a slip costs ranking, never the search.
- **Sidebar badge counts, live rail updates and the Meetings entry** were
  addressed by that prefix too, and silently 404ed on every short URL.

## [0.7.3] - 2026-09-22

### Fixed
- **Sessions no longer end after a few minutes, and a new tab no longer asks
  you to sign in again.** Two refreshes presenting the same refresh token —
  the proactive timer meeting a 401 after the laptop wakes or a background tab
  is throttled, or two tabs refreshing at once — made the server treat the
  second as token theft and sign the user out of every tab. Now:
  - one refresh at a time per tab: startup, the timer and the 401 hook share a
    single in-flight refresh;
  - one refresh at a time across tabs (Web Locks API, where available), and a
    tab that refreshes hands its new access token to the others over a
    BroadcastChannel, so they adopt it instead of rotating the cookie again;
  - a newly opened tab borrows an open tab's access token and does not touch
    the refresh cookie at all;
  - a `refresh_superseded` answer (from the matching backend) is retried
    once after a short pause instead of ending the session;
  - signing out in one tab signs out the others;
  - proactive refreshes are jittered so tabs opened together don't refresh in
    the same instant.

## [0.7.2] - 2026-09-22

Meetings, customers on any issue, a global Create button, and working search.
Backend companion release is 0.7.2.

### Added
- **Meetings** in the project menu: a month calendar with per-day markers and
  the selected day's meetings; a meeting page with summary (markdown), a
  searchable transcript, recordings with an in-app player (download fallback
  for formats the platform can't play), files, and links to participants,
  issues, epics and customers. Large uploads show progress and can be
  cancelled; on web they stream from disk. Issues and epics show their
  meetings. Uploading is web-only, as for other attachments.
- **Global "+ Create"** in the top bar and the `c` shortcut: pick the project
  (current one preselected), type and title, then the issue's detail panel
  opens. The Issues page, board column "+" and global Create share one dialog.
- **Customers panel** on every issue, and a customer filter on the Issues list
  and the Board (lockable in board settings). Import maps a Customers column.
- **Project menu on narrow screens** (< 600px) as a drawer from the top bar.

### Fixed
- **Command palette search** covers all projects with the current one ranked
  first, finds issues by key in any spelling, labels hits `PS-1262` /
  `PS-E-12`, and waits 250 ms after typing before searching.
- **Changing an issue's category no longer deletes its customers.**
- **Global keyboard shortcuts** (Cmd-K, `?`, `g p/s/b/w`) never fired because
  the listener sat above the router's navigator; they work now.
- **Top bar no longer overflows** between 360px and wide screens; items
  collapse progressively.
- **Project rail** shows a scrollbar when its items exceed the window.

## [0.7.1] - 2026-09-22

Re-release of 0.7.0, whose image was never published: the release's test job
hung until the 6-hour runner limit and was cancelled. Backend companion release
is still 0.7.0.

### Fixed
- **Login page no longer spins forever without a router.** Reading the
  `?sso_error=` parameter went through `GoRouterState.of`, which loops endlessly
  when no GoRouter is present (as in the widget tests) instead of throwing. It
  now reads the URI through `GoRouter.maybeOf` and returns nothing without one.
- **Test harness registers a single-sign-on repository.** The Security page
  lists linked identities on open; tests now get a stub that reports none
  instead of failing on an unregistered type.
- Built-in version defaults brought in line with `pubspec.yaml`.

## [0.7.0] - 2026-08-28

Single sign-on in the client. Backend companion release is 0.7.0. Nothing
changes on an install without a configured identity provider: no buttons, the
password form exactly as before.

### Added
- **Sign-in buttons on the login screen**, one per enabled provider. On web the
  button leaves the app for the identity provider and returns to the server's
  callback, which sets the session before handing control back. Desktop and
  mobile use a device-code dialog instead — a code to type at the provider, a
  copyable URL, an "open browser" button, and a countdown — because there is no
  redirect for a native client to come back to.
- **Connect / disconnect providers** under Profile → Security, beside passkeys.
  This is the only self-service way to link an account: an SSO sign-in never
  links itself by email, so the user proves both sides instead. Disconnecting
  the last way into an account is refused by the server, and the reason is
  shown.
- **Admin → Settings → Single sign-on**: add, edit, test, enable and delete
  providers. The redirect and back-channel-logout URIs are shown on each card
  with a copy button, since they are what has to be pasted into the provider.
- **Disable password sign-in** switch in admin settings, which states plainly
  that a superadmin with a local password can always get in.
- **Allow single sign-on linking** action on a user row — the 24-hour rescue
  window for someone who cannot sign in to link a provider themselves.
- The login screen renders the server's SSO failure reasons in full; the
  email-collision case carries the actual instruction rather than a generic
  error, because it is a dead end otherwise.

### Changed
- The auth-source tag in the admin user list now names three sources
  (Local / LDAP / SSO) rather than two.
- The password card on the Security page hides for any externally
  authenticated account, not only LDAP ones — a single-sign-on account has no
  local password to change.
- When a deployment disables password sign-in, the form is hidden behind an
  "Administrator sign-in" link rather than removed, so the break-glass account
  can still reach it.

### Notes
- New dependency: `url_launcher`, for the device dialog's "open in browser"
  button. A convenience only — the URL is always shown as selectable, copyable
  text, so a platform where launching fails is still usable.

## [0.6.20] - 2026-07-31

Second round of epic / issue detail work: performance, concurrency safety,
live updates, sub-tasks, and a real markdown editor.

### Added
- **Live updates.** The detail page subscribes to the project change feed, so
  another person's edits, and their comments, appear without a reload. Your own
  changes are suppressed (the optimistic value is already on screen), stale
  events are rejected by version, and a dropped connection triggers a re-read
  rather than a silent gap.
- **Sub-tasks panel** on issues, with a done/total count, a progress bar and
  inline quick-add. A new sub-task inherits the parent's epic. Previously you
  could set an issue's parent but never see its children.
- **Markdown editor** for descriptions and comments: formatting toolbar
  (bold, italic, code, heading, lists, quote, link), a live preview, and
  Cmd/Ctrl+Enter to save.
- **Full-window editor.** An expand button opens the description in a large
  dialog with a side-by-side source/preview split on wide screens — editing
  markdown inside a 420px side panel was miserable.
- **Paste images** into a description or comment: the image uploads as an
  attachment and is inserted inline. `MarkdownText` now renders images.
- **@mention autocomplete** in the editor, and mentions render as member chips.
  Inserted handles feed the existing "mentioned" work feed.
- **Collapsible panels**, remembered per panel and separately for the narrow
  board panel vs. the full page. Collapsed panels keep their header summary.
- **Retry on load failure**, with distinct messages for no-access, deleted, and
  network errors instead of one catch-all string.
- **Loading skeleton** shaped like the real page, replacing the bare spinner.

### Changed
- **A field edit now costs one request instead of ~18.** Changing a dropdown
  used to re-fetch the entity for an etag, then reload the whole page: profile,
  project, entity and 13 parallel lookups — including every issue in the
  project. Reference data moved to a per-project session cache kept current by
  live events; only the entity is re-fetched.
- **Activity shows the newest 5 entries** with a "show all" expander, so a
  noisy issue no longer lays out hundreds of history rows at once. (The API
  returns the full list; this is a rendering cap, not pagination.)

### Fixed
- **Concurrent edits were silently overwritten.** The backend implements
  optimistic concurrency correctly (428 without `If-Match`, 412 when stale),
  but the client defeated it: every PATCH re-fetched the entity for a *fresh*
  etag first, so the precondition could never fail. The etag captured at load
  is now sent, and a 412 surfaces "changed by someone else" with a reload
  action instead of discarding your edit.

## [0.6.19] - 2026-07-31

Epic / issue detail rework — how the detail page shows and organises its data.
Frontend-only; no API, schema or backend behaviour changed.

### Added
- **Links in text are clickable.** Markdown `[label](url)` links and bare
  `https://…` / `www.…` URLs now navigate everywhere text is rendered —
  descriptions, comments, wiki pages, attachment previews. In-app targets route
  through the SPA router without a page reload; external ones open in a new tab.
- **Included issues on an epic are clickable rows** with the assignee's avatar
  and a count in the panel header.
- **Entity keys in the breadcrumb are clickable.** An issue that belongs to an
  epic also shows the epic's key as its own crumb, so the trail mirrors the real
  hierarchy. From the board side panel or the slide-over sheet, tapping a key
  dismisses the overlay and opens the full page.
- **Milestone can be set on an epic**, in the epic properties panel.

### Changed
- **Activity defaults to Comments** instead of All, and a reload (e.g. after
  posting) no longer resets whichever filter you had selected.
- **Created / Updated moved into the Details panel header**, replacing the
  separate DATES panel that spent a whole card on two timestamps.
- **Details shows two columns** when the panel is wide enough, roughly halving
  its height on a desktop viewport. Measured from the panel's own width, so it
  behaves correctly inside the narrow board panel and the slide-over sheet.
- **Status, Issue type, Priority and Size render as coloured badges.** Size
  shows just the letter (`M`), scaled by its weight; the numeric value stays in
  the picker where it helps you choose.
- **Links, Attachments, Time tracking and Watchers moved to the right column**,
  after People — leaving Details, Description, Included issues and Activity on
  the left. Column split re-balanced 60/40 to suit the new distribution.
- Links now navigate by short key (`/projects/ps/issues/ps-398`) instead of the
  legacy double-UUID URL, and the whole row is the target, key chip included.
- The "Comment" action button scrolls to the activity panel instead of showing
  a snackbar telling you to scroll there yourself.
- Panels are outlined with a consistent radius and carry a leading icon.

### Removed
- **The "Type" row** from Details — it restated what the breadcrumb, the key and
  the route already say.
- **The editable Milestone row on issues.** A milestone is composed of epics, so
  an issue now shows a read-only *Milestone* resolved through its epic, linking
  to the milestone. Existing `milestone_id` values on issues are untouched.
- **The duplicate "Relationships" panel** on issues. It read the same endpoint as
  the Links panel and offered a strict subset of its link types.
- **The Links panel on epics.** Links exist only between issues, so epics no
  longer show a permanently-empty block with no way to add anything.

### Fixed
- The trailing breadcrumb segment dropped its tap target: a crumb rendered as
  the active page was always plain text, even when it had somewhere to go.

## [0.6.18] - 2026-07-29

Account security in the admin area. Backend companion release is also 0.6.18 —
the two version lines are realigned (0.6.14–0.6.16 were frontend-only; 0.6.17
was burned by a CI failure and never released).

### Added
- The admin user list now shows each account's security posture at a glance:
  a status pill (Active / Inactive / Banned, with the ban reason on hover), a
  two-factor shield that breaks down TOTP, passkeys and remaining recovery
  codes, a live-session count, the country and city of the most recent session,
  and relative "last active" / "last login" with exact timestamps on hover.
  A green dot marks accounts active in the last few minutes.
- Row actions: **Reset two-factor** (a confirmation that itemises exactly what
  will be removed, since the user must re-enrol afterwards), **Sign out of all
  sessions**, and **Ban / Lift ban** with an optional reason. The ban dialog
  points out that for an LDAP account, deactivation would be undone at the next
  directory login but a ban holds.
- Tapping the session count opens a sheet listing each session with its
  location, browser/OS, address and last activity.
- Filter chips: All / Active / Banned / Inactive / No 2FA.
- An **IP geolocation** page under admin settings: enable/disable (off by
  default), choose the country or city database, toggle the monthly refresh,
  update now, clear collected location data, and the attribution the database
  licence requires.

### Notes
- Countries render as a flag plus their ISO code rather than a translated
  name — the flag is derived from the code, which avoids shipping and
  translating a 250-entry country-name table in four languages. Cities are
  shown as the database publishes them.
- A private or loopback address renders as "Local network"; the server
  deliberately stores no location for those.

## [0.6.13] - 2026-07-19

One combined release (0.6.10/0.6.11 were absorbed for backend lockstep;
the backend companion release is 0.6.11).

### Added
- **Short deep links** — pages now live at short, memorable URLs:
  `/projects/ip`, `/projects/ip/boards/sb`, `/projects/ip/issues/ip-42`.
  Prefixes and keys work in ANY letter-case (`IP`, `Ip`, `ip`…), old UUID
  links keep working forever, and every page rewrites the address bar to the
  canonical short URL. Board keys are editable in board settings
  ("Key (URL)" field, with duplicate detection); a renamed-away prefix/key
  still resolves via history. Superadmins get Settings → "Short link
  history" to inspect and prune old entries (one by one or in bulk).
- **Attachment previews** — inline preview for markdown (rendered), plain
  text/logs/code (monospace, selectable), HTML (real sandboxed rendering
  with a Source toggle), and PDF (browser viewer). Image attachments show
  real thumbnails in the list; videos a play badge.
- **Kanban**: every column header has a "+" that creates an issue directly
  in that column (status preset; on grouped boards the swimlane value is
  preset too) and opens the new issue's side window right away, like the
  Issues page. One universal Assignee filter matches assignee, QA, or
  reviewer (reporter excluded). Component + a dependent Release filter live
  in the second filter row.
- **Milestones timeline** — a Gantt-style view toggle next to the list:
  bars per milestone with a today marker; missing dates default to
  start = today / end = +7 days and render as estimates. The list now sorts
  by nearest end date first.
- **Timesheet**: work-log entries are fully editable (date included); time
  input accepts both decimals (`1.5`) and `1h 30m` notation.
- **Week start setting** — Settings → "Week starts on" (Monday by default)
  drives every date picker and the timesheet month calendar.
- **Epics full screen** — epics gained a full-screen view with a clean URL,
  plus copy-link; embedded side panels (issues and epics) gained a direct
  "open full screen" button.

### Changed
- Issue/epic descriptions and comments are selectable across paragraphs in
  one sweep; the description gained a copy button.
- Project Overview reworked: compact header card (identity, description,
  features, quick navigation) and dashboard sections in two columns on wide
  screens.
- The non-functional "+ Create" button was removed from the top bar.

### Fixed
- Login screen reached via a deep link no longer mirrors typed text between
  the username and password fields.
- Linked tasks now actually save (the panel talked to a wrong endpoint and
  silently dropped every link).
- The Log Time dialog no longer pre-fills today's date when a different day
  or month is selected.
- Any issue can now be chosen as a parent (multi-level hierarchy); only
  assignments that would create a cycle are refused.

## [0.6.9]

Version bump only (lockstep alignment), no frontend changes.

## [0.6.8] - 2026-07-09

### Changed
- **Release badge polish** (frontend-only fix, no backend changes):
  - The fix-version picker now shows a release-name header row followed by
    its versions, instead of repeating the release name on every version.
  - The release badge (issue detail, issues list, board card) now shows the
    version only, not the release name.
  - The issue detail page's fix-version badge now renders with the exact
    same tinted-pill style as the issues list and board card.

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
