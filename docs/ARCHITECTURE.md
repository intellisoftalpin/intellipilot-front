# IntelliPilot Frontend — Architecture

> Companion document: see [`ROADMAP.md`](./ROADMAP.md) for the phased delivery plan.

## 1. Goals & non-goals

**Goal.** A cross-platform Flutter client for the IntelliPilot backend that delivers a Jira-grade project-management UX: project boards, backlog, sprints, issues, wiki, attachments, and team administration. The app must run on **Web, Android, iOS, Linux, macOS, Windows** from a single codebase.

**Quality bar.**

- Material 3 design, polished UX, full keyboard support on desktop/web.
- Live theme switch (light / dark / system, with seed-color customization).
- Live language switch (no app restart).
- Multi-role aware UI: every action is gated by the backend permission catalog (`intellipilot_core::perms::Permission`).
- Comprehensive automated tests (unit / widget / golden / integration).
- Hot-reload-friendly DI; no service locator anti-patterns sprinkled across widgets.

**Non-goals (initial).**

- Native mobile push notifications (depends on backend support — currently absent).
- Real-time websocket/SSE updates (backend is pure REST today; we use ETag + polling and design the data layer so a streaming layer can be slotted in later without rewrites).
- Offline-first sync. The data layer is repository-based and *can* be extended with a cache + outbox later; we do not commit to it now.

---

## 2. Tech stack

| Concern | Choice | Rationale |
|---|---|---|
| **Language / SDK** | Dart 3.x, Flutter stable (≥ 3.24) | Sound null safety, records, patterns, full multi-platform support. |
| **State management** | `flutter_bloc` (BLoC + Cubit) | Strict separation of events/states, excellent testability, mature ecosystem. Cubit for simple state; full Bloc when event-sourcing is valuable (audit-style features map well). |
| **DI / service locator** | `get_it` + `injectable` | Codegen-driven, compile-time-safe registrations, easy module scoping. |
| **Routing** | `go_router` | Declarative routes, deep-linking on web, type-safe params via `go_router_builder`. |
| **HTTP** | `dio` + `pretty_dio_logger` (dev) | Interceptor pipeline for auth, request-id, problem+JSON, retries, idempotency keys. |
| **Serialization / models** | `freezed` + `json_serializable` | Immutable data classes with sealed unions for `Result<T>` / domain errors. |
| **Local storage** | `flutter_secure_storage` (refresh token / secrets) + `hive_ce` (KV cache, settings, last-seen) | Secure store on every platform; Hive is lightweight and works on Web too. |
| **Theme persistence** | Hive box `settings` | Survives restart; broadcast via `ThemeCubit`. |
| **i18n** | `flutter_localizations` + `intl` + `.arb` files via `flutter gen-l10n` | Official, supports plurals/gender, hot-swap at runtime via `Localizations` rebuild. |
| **Forms** | `reactive_forms` | Reactive validation, integrates with BLoC streams; mirrors backend `garde` constraints. |
| **Markdown** | `flutter_markdown_plus` + `markdown` + `flutter_html` (when needed) | Render comments / wiki rendered by backend; we also support client-side preview. |
| **File picking / uploads** | `file_picker` + `dio`'s multipart | Single API across desktop/mobile/web. |
| **Charts (burndown, stats)** | `fl_chart` | Pure-Dart, works on all platforms. |
| **Date / time / TZ** | `intl` + `timezone` | Honor `user.timezone` from backend profile. |
| **Logging** | `logger` + `dio` interceptor → bridges to backend `X-Request-Id` for correlation. |
| **Crash reporting** | `sentry_flutter` (optional, env-gated) | Web + native. |
| **Testing** | `flutter_test`, `bloc_test`, `mocktail`, `golden_toolkit`, `patrol` (integration) | Standard combo. |
| **Build tooling** | `melos` (mono-repo command runner), `very_good_cli` for analyzer config | Even with a single package, melos is useful for scripts. |

**Versions.** Pin Flutter via `fvm` (project-local `.fvmrc`). Pin Dart and dependencies via `pubspec.lock` (committed for app, not for library packages).

---

## 3. Layered architecture

We use **Clean-Architecture-inspired feature-first layout**. Layers:

```
┌─────────────────────────────────────────────┐
│  Presentation   (UI, widgets, Bloc/Cubit)   │
├─────────────────────────────────────────────┤
│  Domain         (entities, use-cases,       │
│                 repository contracts)       │
├─────────────────────────────────────────────┤
│  Data           (repositories impl, DTOs,   │
│                 data sources, mappers)      │
├─────────────────────────────────────────────┤
│  Infrastructure (HTTP client, secure store, │
│                 cache, platform integrations)│
└─────────────────────────────────────────────┘
```

Dependencies point **inward only** (presentation → domain ← data → infra). Domain is pure Dart, no Flutter or HTTP imports. This means domain code is platform-independent and trivially testable.

**Feature-first**: each business capability is a self-contained folder with its own `presentation/`, `domain/`, `data/` subtrees, so a developer can grep one folder and see the whole vertical.

---

## 4. Source code structure

```
intellipilot-front/
├── lib/
│   ├── app/                         # App shell: bootstrap, root widget, router, theme, l10n
│   │   ├── app.dart                 # Top-level MaterialApp.router
│   │   ├── bootstrap.dart           # runApp() entry per flavor
│   │   ├── router/                  # go_router config + guards
│   │   ├── theme/                   # ThemeCubit, M3 color schemes, typography, light/dark
│   │   ├── l10n/                    # LocaleCubit + generated bindings
│   │   └── di/                      # GetIt config, injectable modules
│   │
│   ├── core/                        # Cross-cutting, framework-agnostic helpers
│   │   ├── error/                   # AppFailure sealed union, mapping from Problem+JSON
│   │   ├── network/                 # ApiClient (dio wrapper), interceptors, ETag helpers
│   │   ├── result/                  # Result<T, F> sealed type
│   │   ├── permissions/             # Permission enum mirroring backend, hasPermission()
│   │   ├── utils/                   # debounce, throttle, fractional-index helpers
│   │   └── widgets/                 # PrimaryButton, AppScaffold, EmptyState, ErrorView, …
│   │
│   ├── features/
│   │   ├── auth/                    # Login, register, password reset, MFA, passkeys
│   │   ├── session/                 # Current user, refresh loop, logout
│   │   ├── profile/                 # /me CRUD, TOTP setup, passkey management, export
│   │   ├── projects/                # List, create, settings, members, roles, invitations
│   │   ├── taxonomy/                # Status/type/priority/severity/points dropdown editors
│   │   ├── backlog/                 # Epics, user stories, tasks, issues — list & detail
│   │   ├── board/                   # Kanban + sprint board (Jira-style swimlanes)
│   │   ├── milestones/              # Sprint list, board, stats (burndown)
│   │   ├── comments/                # Polymorphic comment thread widget
│   │   ├── attachments/             # Upload UI, gallery, signed-URL handling
│   │   ├── wiki/                    # Page tree, editor, revision history, diff viewer
│   │   ├── labels_components/       # Project-level catalog editors
│   │   └── settings/                # Theme, locale, notifications, dev tools
│   │
│   └── main_dev.dart / main_prod.dart  # Flavor entry-points
│
├── test/                            # Unit + widget tests, mirrors lib/
├── integration_test/                # patrol scenarios
├── assets/
│   ├── icons/                       # SVGs
│   ├── images/
│   └── l10n/                        # .arb sources (intl_en.arb, etc.)
└── docs/                            # This folder
```

Each feature folder is structured identically:

```
features/projects/
├── data/
│   ├── dto/                # ProjectDto, MemberDto — JSON-mapped DTOs (freezed)
│   ├── datasource/         # ProjectsRemoteDataSource (dio calls)
│   └── repository/         # ProjectsRepositoryImpl (implements domain contract)
├── domain/
│   ├── entity/             # Project, Member, Role — pure types
│   ├── repository/         # abstract class ProjectsRepository
│   └── usecase/            # ListProjects, CreateProject, InviteMember, …
└── presentation/
    ├── bloc/               # ProjectsBloc / ProjectsCubit
    ├── page/               # ProjectListPage, ProjectDetailPage
    └── widget/             # ProjectTile, RoleBadge, MemberAvatar
```

---

## 5. Dependency injection

Single composition root via `get_it`, configured by `injectable` codegen.

- **Scopes**: a global scope for app-lifetime singletons (ApiClient, SecureStorage, Hive boxes, ThemeCubit, LocaleCubit, AuthSessionBloc). A session scope (registered on login, disposed on logout) holds repositories and use-cases that depend on the access token. A project scope (push/pop on entering/leaving a project) for project-bound caches.
- Widgets do NOT call `getIt<X>()` directly. Instead, they receive blocs/cubits via `BlocProvider` near a route, and the bloc resolves its dependencies through its constructor (resolved by `injectable` factories).
- Test overrides via `getIt.allowReassignment = true` in test setup.

---

## 6. Repository pattern & data sources

**Domain contract** (`features/projects/domain/repository/projects_repository.dart`):

```dart
abstract class ProjectsRepository {
  Future<Result<List<Project>, AppFailure>> list({String? cursor});
  Future<Result<Project, AppFailure>> get(ProjectId id);
  Future<Result<Project, AppFailure>> create(NewProject req, {required IdempotencyKey idem});
  Future<Result<Project, AppFailure>> update(ProjectId id, ProjectPatch patch, {required Etag ifMatch});
  Future<Result<Unit, AppFailure>> delete(ProjectId id);
}
```

**Implementation** lives in `data/repository/`. It owns:
- A `ProjectsRemoteDataSource` that talks dio.
- (Future) a `ProjectsLocalDataSource` for cache/offline.
- DTO ↔ entity mapping in `data/mapper/`. Entities never escape the `data` ↔ `domain` boundary as DTOs.

**Result type**. `Result<T, F>` is a sealed freezed union of `Ok(T)` / `Err(F)`. We avoid exceptions across layers — exceptions are an HTTP-layer concern only. Failures are typed (`AppFailure.network`, `.unauthorized`, `.forbidden`, `.validation(fieldErrors)`, `.conflict`, `.rateLimited(retryAfter)`, `.notFound`, `.unknown`).

**Idempotency & ETag.** Repository methods that mutate accept `IdempotencyKey` (UUIDv4 generated client-side) and pass it as `Idempotency-Key` header. Update methods accept `Etag` for `If-Match`. The data source surfaces `412 Precondition Failed` as `AppFailure.conflict(serverVersion)` so blocs can prompt the user to merge.

---

## 7. State management — BLoC patterns

**Cubit vs Bloc.** Default to **Cubit** for simple state (forms, toggles, query screens). Use full **Bloc** when:
- Multiple discrete user intents need event handlers (e.g., `BoardBloc` with `CardMoved`, `CardCreated`, `FilterChanged`).
- The state machine has transitions worth modeling (e.g., MFA challenge flow: idle → password → mfa_required → verifying → success).
- You want a replayable event log for debugging.

**Patterns**:
- States are `freezed` sealed unions: `Initial`, `Loading`, `Loaded(data)`, `Failure(failure)`, often with `refreshing: bool` on `Loaded` to support pull-to-refresh without a flicker.
- Blocs depend on **use-cases**, not repositories directly, when the operation deserves a name (`MoveCardUseCase` is clearer than `repo.update`). Trivial CRUD goes through the repo directly to avoid use-case noise.
- One bloc per screen by default. Cross-screen state (current project, current user) lives in app-scoped blocs (`SessionBloc`, `CurrentProjectCubit`).
- Avoid `BlocListener` for side-effects when a stream-based reaction inside the bloc itself is possible.

---

## 8. Routing

`go_router` with typed routes:

```
/                                          → home (project list when authed, landing when not)
/login                                     → public
/register                                  → public
/forgot                                    → public
/mfa                                       → public (consumes mfa_token)
/passkeys/sign-in                          → public
/me                                        → profile
/me/security                               → TOTP, passkeys, sessions
/me/settings                               → theme, locale
/projects/:projectId                       → overview
/projects/:projectId/backlog               → backlog list (US + epics + grouping)
/projects/:projectId/board                 → Kanban
/projects/:projectId/milestones            → list
/projects/:projectId/milestones/:id        → sprint board + burndown
/projects/:projectId/wiki                  → page tree
/projects/:projectId/wiki/:wikiId          → page view
/projects/:projectId/wiki/:wikiId/edit     → editor
/projects/:projectId/wiki/:wikiId/history  → revision list / diff
/projects/:projectId/{entity}/:id          → entity detail (epic/userstory/task/issue) — deep-linkable
/projects/:projectId/settings              → project admin (members, roles, taxonomy, labels, components, integrations)
/i/:token                                  → invitation accept
```

**Guards.** A top-level redirect:
1. If the route is `public` (login/register/...), allow.
2. If `SessionBloc.state` is unauthenticated, redirect to `/login` and remember the original URI.
3. If a project route is hit and the user is not a member of that project, redirect to `/projects` with a snackbar.

**Permission-based UI gating** is *not* done in the router (overkill, racy). It's done in widgets via a `PermissionGate(required: Permission.epicCreate, child: …)` helper.

**Web URL strategy.** `usePathUrlStrategy()` — no hash routing — for clean shareable URLs that mirror Jira's.

---

## 9. Networking & API client

Single `ApiClient` (dio wrapper) registered as a singleton. Interceptors in order:

1. **RequestIdInterceptor** — injects an `X-Request-Id` header (UUIDv4) per request; surfaced in logs and crash reports.
2. **AuthInterceptor** — attaches `Authorization: Bearer <access>` from `SessionBloc`. On `401`, triggers refresh via `POST /api/v1/auth/refresh` (using HttpOnly cookie on web, refresh token on native), queues failed requests, retries them once.
3. **IdempotencyInterceptor** — for POST/PATCH/DELETE on mutating endpoints, adds an `Idempotency-Key` header from the request's `extra` map (set by the data source).
4. **ETagInterceptor** — for PATCH, attaches `If-Match: <etag>` from request extras; surfaces `412` distinctly.
5. **ProblemJsonInterceptor** — converts non-2xx Problem+JSON responses to a typed `ApiException(problem)`. Repos translate to `AppFailure`.
6. **LoggingInterceptor** (dev only) — pretty logger with body redaction for passwords/tokens.
7. **RetryInterceptor** — retries on idempotent methods (`GET`, `HEAD`) with jitter on `429` / `503` / network errors. Honors `Retry-After`.

**Base URL** comes from compile-time env var `INTELLIPILOT_API_BASE` (`--dart-define`). Web build also reads from `window.origin` as a fallback.

**Refresh flow.**
- **Web**: refresh token lives in HttpOnly cookie set by backend → browser sends it automatically. `dio` is configured with `withCredentials: true`.
- **Native (mobile/desktop)**: cookies aren't reliable; the backend returns `refresh_token` in the body (dev or non-browser path). We store it in `flutter_secure_storage` and send it as a body parameter to `/auth/refresh`.
- Refresh-token *family* + parent chain is server-side; client just supplies the latest token.

**Cancellation.** Every bloc holds a `CancelToken` per active request and cancels on dispose / new query.

---

## 10. Auth flow

States in `SessionBloc`:

```
Unknown               ← app boot, before bootstrap finishes
Unauthenticated       ← no valid session
AuthenticatingPwd     ← submitting credentials
MfaRequired(token)    ← server returned 200 with mfa_token
VerifyingMfa
PasskeyChallenge(opts)← from /auth/passkeys/authenticate/start
Authenticated(user, accessToken, exp)
Refreshing
```

Transitions are explicit; the UI subscribes via `BlocSelector` to show the right screen.

**Access token** is held in memory inside `SessionBloc`, never persisted. Expiry is decoded from the PASETO claims `exp` field (we don't validate signatures client-side — just read claims for expiry scheduling). A `Timer` fires a refresh request at `exp - 30s`.

**Passkeys.** Use `webauthn` plugin (`web` package on Web, native plugins on iOS/Android, FIDO2 on desktop). On unsupported platforms, hide the option.

**TOTP enrollment.** Show QR (`qr_flutter`) decoded from `qr_png_base64` returned by backend; provide manual `secret_base32` for users with non-camera-equipped desktops.

---

## 11. Theming

Built around Material 3 `ColorScheme.fromSeed`.

- **`ThemeCubit`** state: `{ themeMode: light|dark|system, seedColor: Color, useDynamic: bool }`.
- Persists to Hive `settings` box.
- On startup, if `useDynamic` and platform supports it, pull a dynamic color (Android 12+ via `dynamic_color`; falls back to seed).
- Provides `ThemeData` for `MaterialApp.router.theme` and `darkTheme`.
- Typography uses `google_fonts` with a configurable family (default Inter).
- Custom semantic tokens (priority colors for Jira-style severity badges) live as `ThemeExtension<IpColors>`.

**Realtime switch.** Settings screen flips the cubit → `MaterialApp` rebuilds → no restart.

---

## 12. Internationalization

- `flutter gen-l10n` driven by `l10n.yaml`. Source files: `assets/l10n/intl_en.arb` (canonical).
- `intl_*.arb` for each shipped language.
- **At launch**: English only. Pipeline is built for additional languages — adding one is dropping a new `.arb` and a CI lint that catches missing keys.
- **`LocaleCubit`** stores selected locale; persisted to Hive. Selecting a new locale rebuilds `MaterialApp.locale` → instant switch.
- Backend `user.lang` is read at login and applied as the initial locale unless the user has overridden it locally.
- Date/time formatting uses `intl` with the active locale; timezone via `timezone` package, seeded from `user.timezone`.
- RTL: `flutter`'s automatic mirroring, plus per-feature audits before adding Arabic/Hebrew.

---

## 13. Permissions & roles

The backend ships a stable permission catalog (40 atoms — see `intellipilot_core::perms::Permission`). The client mirrors it as a Dart enum (generated by a small Dart script that reads the backend OpenAPI spec; *not* hand-maintained).

**`PermissionsCubit`** keeps `Set<Permission>` for the current user in the current project (resolved from `/api/v1/projects/:id/members` filtered to `me.id`, plus their role's `permissions` JSONB).

UI primitive:

```dart
PermissionGate(
  required: Permission.epicCreate,
  child: FloatingActionButton(...),
  fallback: const SizedBox.shrink(), // or a "request access" CTA
)
```

For row-level affordances (edit/delete buttons inside list tiles), check `PermissionsCubit.has(...)` directly.

---

## 14. Error handling & UX

**Layers**:
- HTTP layer throws `ApiException(Problem)` for non-2xx.
- Repository catches it, maps to `AppFailure`, returns `Result.err`.
- Bloc maps `AppFailure` to a `Failure` state with a localized message key.
- UI shows the message via `ErrorView` (for full screens) or `SnackBar` (for transient ops).

**Specific failure handling**:
- `AppFailure.validation(fieldErrors)` → forms light up the offending fields. Field codes are mirrored from backend (`required`, `length`, `pattern`, `email`, …).
- `AppFailure.conflict(serverEtag)` → "Someone else updated this. Reload?" dialog with a side-by-side diff option.
- `AppFailure.rateLimited(retryAfter)` → cooldown indicator with countdown.
- `AppFailure.unauthorized` → session bloc transitions to `Unauthenticated`, router kicks to `/login`.

Crash reporter: `sentry_flutter`, only when `SENTRY_DSN` is provided.

---

## 15. Local persistence

| Data | Store | Why |
|---|---|---|
| Refresh token (native only) | `flutter_secure_storage` | Encrypted by OS keystore. |
| Theme / locale / view prefs | Hive `settings` box | Plain prefs, no secrets. |
| Last-seen project / sidebar collapsed | Hive `ui` box | Per-user UI state. |
| Last-fetched ETags per resource | Hive `etag` box | Faster optimistic updates. |
| Form drafts (comment/issue body) | Hive `drafts` box | Prevents data loss on accidental nav. |

We do not cache backend data eagerly. If the user revisits a page, we re-fetch and rely on backend ETag responses to short-circuit (HTTP-layer 304 → returns last response). Full offline support is a deliberate Phase 12 decision.

---

## 16. Markdown / rich text

- **Comments & wiki bodies** are stored as markdown server-side; the backend also returns sanitized HTML (comrak + ammonia).
- **Editor**: a markdown editor with split-pane preview (`flutter_markdown_plus`). For wiki, an autosave draft every 5s (Hive `drafts`) and a toolbar (bold/italic/code/list/link/image).
- **Renderer**: prefer rendering the server-sanitized HTML (`flutter_html`) for security parity. Client-side preview uses `flutter_markdown_plus` for speed.

---

## 17. Realtime considerations

Backend is REST-only today. Strategy:

- **Polling** with a small ETag-aware "since" cursor on lists that need freshness (board, active sprint, comments). Default 30s, paused when the tab is hidden (`page_visibility` plugin on Web; `WidgetsBindingObserver` elsewhere).
- **Optimistic updates** with rollback on failure — board drag, status change, story-point edit.
- **Pluggable channel**: `RealtimeChannel` interface with `PollingChannel` impl now; SSE/WebSocket impls can be added without changing repositories or blocs.

---

## 18. Accessibility

- All interactive widgets have semantic labels and minimum 48×48 dp tap targets.
- Color contrast meets WCAG AA; theme color picker rejects palettes that drop below threshold.
- Full keyboard nav on desktop/web (Jira parity): `j`/`k` to navigate cards, `c` to create, `e` to edit, `/` to focus search.
- Screen reader audit per release on iOS (VoiceOver) and Web (NVDA + Chrome).
- Reduce motion: respect `MediaQuery.disableAnimations`.

---

## 19. Testing strategy

| Level | Tooling | Coverage target |
|---|---|---|
| Unit (domain, mappers, utils) | `flutter_test` | 90 % |
| Bloc | `bloc_test` + `mocktail` | 100 % of state transitions |
| Widget | `flutter_test` + `mocktail` | All pages: empty / loading / loaded / error |
| Golden | `golden_toolkit` | Critical screens × {light, dark} × {compact, expanded} |
| Integration | `patrol` | Smoke flows: login, create project, create story, move card, comment, logout |
| Contract | OpenAPI-driven DTO tests | Every DTO round-trips a fixture from `/openapi.json` |

CI runs all but golden updates; goldens are reviewed manually via PR diff.

---

## 20. Build, CI, deployment

- **Local**: `melos run gen` (build_runner), `melos run test`, `melos run analyze`, `melos run format`.
- **CI (GitHub Actions or GitLab CI — TBD)**: Lint, format check, codegen check (no drift), unit + widget tests, golden tests, build web bundle. Matrix-build native artifacts on tagged releases.
- **Web deploy**: static bundle behind same domain as backend (`/app/*`) or separate subdomain (`app.intellipilot.dev`). CORS configured on backend.
- **Desktop**: Linux `AppImage` / `.deb`, macOS `.dmg` (notarized), Windows MSIX. Initial focus: Linux + macOS, Windows fast-follow.
- **Mobile**: Play Store internal track + TestFlight from day one of mobile work.

---

## 21. Security notes

- No secrets in `dart-define`s shipped to client. The HMAC attachment secret stays server-side; clients receive only signed URLs.
- Refresh tokens on native are stored in OS keystore. On web they live in HttpOnly cookie (server's job).
- Content from comments / wiki HTML is rendered via `flutter_html` with a strict allowlist; we trust the server's ammonia sanitization but re-check tags client-side.
- All outbound requests pinned to `https://` in prod builds (`assertHttpsOnly` flag in `ApiClient`).
- Sentry breadcrumbs scrub Authorization headers and form passwords.

---

## 22. API mapping (backend → client modules)

Backend route prefix is `/api/v1`. The client feature → backend route mapping:

| Client feature | Backend routes |
|---|---|
| `auth` | `POST /auth/{register,login,logout,refresh}`, `POST /auth/password/reset/{request,confirm}`, `POST /auth/2fa/verify`, `POST /auth/passkeys/authenticate/{start,finish}` |
| `profile` | `GET/PATCH/DELETE /me`, `GET /me/export`, `POST /me/totp/{start,confirm}`, `DELETE /me/totp`, `POST /me/recovery-codes/regenerate`, `* /me/passkeys/...` |
| `projects` | `* /projects`, `* /projects/{id}`, `* /projects/{id}/roles/...`, `* /projects/{id}/members/...`, `* /projects/{id}/invitations`, `POST /invitations/accept` |
| `taxonomy` | `* /projects/{id}/taxonomy/{kind}`, `POST .../move` |
| `backlog` | `* /projects/{id}/{epics,userstories,tasks,issues}`, `POST .../move`, `POST .../bulk` |
| `comments` | `* /projects/{id}/{entity}/{id}/comments`, `GET .../history`, `GET /projects/{id}/resolve/{ref}` |
| `labels_components` | `* /projects/{id}/{labels,components}` |
| `milestones` | `* /projects/{id}/milestones/{id}/...`, `GET .../board`, `GET .../stats`, `POST .../close` |
| `attachments` | `GET/POST /projects/{id}/{entity}/{id}/attachments`, `GET/DELETE /projects/{id}/attachments/{id}`, `GET .../download` |
| `wiki` | `* /projects/{id}/wiki[/{id}[/revisions[/{rev}[/{diff,restore}]]]]` |
| `health` (about page only) | `GET /health/live`, `GET /health/ready` |

The client also consumes `/openapi.json` at build time:
- Permission enum codegen.
- DTO drift check (CI compares generated freezed models to spec).

---

## 23. Jira-inspired UX decisions

Adopted from Jira / Linear / Taiga, adapted to the IntelliPilot backend model:

- **Issue keys**: derive a display key `PROJ-123` from `(project.slug, sequence_number)`. Confirm backend exposes this; if not, surface UUIDv7 in compact base32. (See [`ROADMAP.md`](./ROADMAP.md) Phase 5 open question.)
- **Quick add**: `c` shortcut everywhere opens a modal create dialog scoped to the current view.
- **Board**: columns from project taxonomy (`status` kind), rows optionally grouped by `assignee` / `epic` (swimlanes). Drag persists via `PATCH .../move` + optimistic state.
- **Backlog**: a single ranked list grouped by epic, with collapsible epics; reorder triggers fractional-index update (`POST .../move`).
- **Sprint planning**: side-by-side "backlog" / "active sprint" panes; drag between them; story-point sum live in header.
- **Detail panel**: opens as a side-sheet on wide layouts, full-screen on narrow ones. URL is shareable.
- **Activity stream**: combines `/history`, `/comments` into a unified timeline.
- **Quick filters & saved queries**: a `FilterBuilder` that compiles to backend query params (`?status=...&assignee=me&label=...`) and persists as named "views" in Hive.
- **Notifications**: in-app bell — Phase 11 (backend feature pending).
- **Cmd-K command palette**: jump-to-project, jump-to-issue (via `/resolve/{ref}`), invoke any action.

---

## 24. Open questions for the backend

These will be raised against the backend repo as issues or doc updates:

1. **Human-readable issue keys** (e.g. `PROJ-123`). Currently entities are UUIDv7 only. Either backend assigns sequence per project, or the client derives a short representation.
2. **Server-sent events / WebSocket** support — needed for true realtime; currently we poll.
3. **Push-notification tokens endpoint** for mobile — not present today.
4. **Bulk endpoints** beyond `userstories/bulk` — we'd benefit from `tasks/bulk`, `issues/bulk` for board batch operations.
5. **Per-user notification preferences** endpoint — needed for the future notifications feature.
6. **CORS / cookie domain config** for the production web deploy — document expected setup.
7. **A `me/sessions` listing** for the security page (active sessions, revoke individual) — currently not exposed.

---

## 25. Glossary (project-specific)

- **Backlog entity**: union of `Epic | UserStory | Task | Issue`.
- **Taxonomy kind**: one of `status | type | priority | severity | points`.
- **Fractional index**: a string-encoded rational used to order siblings without reshuffling neighbors on insert.
- **Idempotency key**: client-generated UUID per logical mutation; backend dedupes replays.
- **ETag**: `"<id>:<version>"` used for `If-Match` on PATCH.
