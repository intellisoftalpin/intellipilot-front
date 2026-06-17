# IntelliPilot — Flutter client for the free, self-hosted Jira alternative

Cross-platform [Flutter](https://flutter.dev) client for **IntelliPilot**, a
**free, open-source, self-hosted Jira alternative** with built-in **LDAP /
Active Directory / OpenLDAP single sign-on**. One codebase targets **web,
macOS, Linux, Windows, Android, and iOS**.

It pairs with the Rust + PostgreSQL backend and REST API →
[github.com/intellisoftalpin/intellipilot](https://github.com/intellisoftalpin/intellipilot).
Project management for agile/scrum teams: Kanban board, backlog (epics, user
stories, tasks, issues), sprints/milestones, wiki, roles & permissions, 2FA /
passkeys, and directory SSO. MIT-licensed · [intellisoftalpin.com](https://intellisoftalpin.com).

- Architecture overview → [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
- Phased delivery plan → [`docs/ROADMAP.md`](docs/ROADMAP.md)
- Adding a locale → [`docs/I18N.md`](docs/I18N.md)

## Prerequisites

- **[fvm](https://fvm.app/)** is the recommended Flutter version manager.
  The pinned channel is in `.fvmrc` (`stable`).
- Or have `flutter` on your `PATH` matching `pubspec.yaml`'s
  `flutter: ">=3.44.0"` constraint.
- Python 3 (only needed if you use `--build` to serve a release bundle).

First-run bootstrap:

```sh
fvm install
fvm flutter pub get
fvm flutter gen-l10n
```

## Running the web app

A cross-platform launcher lives under `scripts/`:

```sh
# macOS / Linux / Git Bash / WSL / MSYS2
./scripts/run-web.sh

# Native Windows PowerShell
.\scripts\run-web.ps1
```

Defaults: debug build, hot-reload, `http://127.0.0.1:8080`.

### Common flags

```sh
./scripts/run-web.sh --port 5173            # pick another port
./scripts/run-web.sh --host 0.0.0.0         # expose on the LAN
./scripts/run-web.sh --mode release         # `flutter run` in release
./scripts/run-web.sh --build                # release bundle, served via python http.server
./scripts/run-web.sh -- --dart-define=FOO=1 # pass-through after `--`
```

The PowerShell shim mirrors the same flags
(`-Port 5173`, `-Mode release`, `-Build`, etc.) and delegates to the bash
script when Git Bash is on `PATH`.

### Running without a backend (demo mode)

The app ships with a seeded in-memory demo so you can click through every
feature with no API process behind it. Enable it via a `--dart-define`:

```sh
# Run the offline demo (no backend needed)
./scripts/run-web.sh -- --dart-define=INTELLIPILOT_DEMO=true

# Release build of the offline demo
./scripts/run-web.sh --build -- --dart-define=INTELLIPILOT_DEMO=true
```

What you get:

- Auto-logged-in demo user, all 40 permissions on the seeded project.
- One project, 2 epics, 4 user stories, 3 tasks, 2 issues, 1 milestone,
  taxonomy / labels / components, 1 wiki page (with a revision + diff),
  1 comment, 1 history event.
- Every mutation (create, edit, delete, drag-drop, reorder) persists in
  memory until you hard-reload — at which point the state resets.
- Attachments "upload" into the in-memory store; download surfaces an
  `about:blank#…` placeholder URL.
- MFA flows are skipped; the session auto-establishes on boot.

Pin the real backend later by removing the `--dart-define` and pointing
`INTELLIPILOT_API_BASE` at it (see Configuration below).

## Configuration via `--dart-define`

| Define | Default | Notes |
|---|---|---|
| `INTELLIPILOT_API_BASE` | `http://localhost:8080` | Backend root for the real API client. |
| `INTELLIPILOT_LOG_HTTP` | `false` | Dump request/response pairs to the logger. |
| `INTELLIPILOT_DEMO` | `false` | Swap in the in-memory demo data (above). |

Example wiring against a remote backend:

```sh
./scripts/run-web.sh -- \
  --dart-define=INTELLIPILOT_API_BASE=https://api.example.com \
  --dart-define=INTELLIPILOT_LOG_HTTP=true
```

## Tests + checks

```sh
fvm flutter analyze    # static analysis, hard gate at every commit
fvm flutter test       # unit / widget tests (≈ 224 at the time of writing)
```

## Production build

```sh
# web
fvm flutter build web --release

# desktop (each platform needs the matching toolchain locally)
fvm flutter build macos --release
fvm flutter build linux --release
fvm flutter build windows --release

# mobile
fvm flutter build apk --release
fvm flutter build ipa --release
```

The web release bundle lands in `build/web/`. Phase 16's `pathUrlStrategy`
is wired in, so deploy it behind a server that rewrites unknown paths to
`index.html` (any SPA host works — Caddy, Netlify, Vercel, GitHub Pages
with the 404-fallback trick, etc.).

## Project layout

```
lib/
  app/                 # bootstrap, DI, router, theme, session, keyboard shell
  core/                # io, network, storage, result, ui primitives
  features/            # one folder per feature slice
    activity/          # comments + history + attachments
    auth/              # login, register, password reset
    backlog/           # epics, user stories, tasks, issues
    board/             # Kanban
    catalog/           # taxonomy, labels, components
    home/
    mfa/               # TOTP, recovery codes, passkeys
    milestones/        # sprints + stats + scope planning
    palette/           # Cmd-K
    profile/           # me, account, GDPR
    projects/          # list, settings, members, roles, invitations, perms
    settings/
    wiki/              # pages, split editor, revisions, diff
  demo/                # in-memory store + repositories for demo mode
  l10n/                # generated localisation bindings
test/                  # mirrors lib/ layout
assets/l10n/           # ARB files (template = intl_en.arb, intl_de.arb)
docs/                  # ARCHITECTURE, ROADMAP, I18N
scripts/               # run-web.sh / run-web.ps1
```

## Keyboard shortcuts

- `Ctrl/Cmd+K` — command palette (search projects, wiki pages, `#123`
  references).
- `?` — keyboard shortcut help.
- `g p` / `g s` — go to projects / settings.
- `g b` / `g w` — go to this project's board / wiki (when a project is
  open).

The full registry lives in `lib/app/shell/keyboard_shortcuts.dart` and is
the single source of truth — the help dialog renders directly from it.

## Where things live for common changes

- **Add a string** → `assets/l10n/intl_en.arb`, run `fvm flutter gen-l10n`,
  use `AppLocalizations.of(context).yourNewKey`. See
  [`docs/I18N.md`](docs/I18N.md).
- **Add a route** → `lib/app/router/app_router.dart` (`Routes.` helper +
  `GoRoute` entry).
- **Add a repository** → DTOs under `lib/features/<slice>/data/dtos/`,
  interface under `domain/`, impl under `data/`, register in
  `lib/app/di/injection.dart` and add an in-memory variant in
  `lib/demo/demo_repositories.dart`.
- **Add a permission gate** → `PermissionGate(permission: …, child: …)`
  reads from the surrounding `ProjectDetailCubit`. Set
  `showRequestAccess: true` at page level for the "request access" CTA.
