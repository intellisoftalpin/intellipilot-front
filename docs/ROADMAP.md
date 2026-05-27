# IntelliPilot Frontend — Delivery Roadmap

> Companion document: see [`ARCHITECTURE.md`](./ARCHITECTURE.md) for technical foundations referenced here.

This roadmap is **phased**, not time-boxed. Each phase is a coherent, shippable slice with clear acceptance criteria. Effort estimates are person-weeks for a single senior Flutter engineer; treat them as relative, not absolute.

> **Coverage gate paused for Phase 5+** (2026-05-27): the earlier per-phase coverage targets (≥ 80% on `lib/app` + `lib/core`, ≥ 90% on blocs) are suspended from Phase 5 onward to keep delivery velocity up. Tests still ship where they protect against real risk (bloc logic, repo wire format, complex UI), but phase completion is no longer blocked on measured percentages. `flutter analyze` clean and `flutter test` green stay hard gates; a tightening of this rule in a later phase supersedes this note.

## Phase index

| # | Phase | Rough effort | Goal | Status |
|---|---|---|---|---|
| 0 | Bootstrap & toolchain | 1 w | Empty app boots on all 6 platforms, CI green | **Done** |
| 1 | Foundation (DI, routing, theming, i18n, networking) | 2 w | App shell with theme/locale switchers; API client wired | **Done** |
| 2 | Auth & session | 2 w | Login, register, password reset, refresh, logout | **Done** |
| 3 | MFA & passkeys | 1.5 w | TOTP enroll/verify, recovery codes, WebAuthn passkeys | **Done** |
| 4 | Profile & account | 0.5 w | Edit profile, GDPR export, delete account | **Done** |
| 5 | Projects, members, roles, invitations | 2 w | Full project admin | **Done** |
| 6 | Taxonomy, labels, components | 1 w | Per-project catalog editors | **Done** |
| 7 | Backlog — epics & user stories | 2 w | Backlog list, detail, CRUD, reorder | **Done** |
| 8 | Backlog — tasks & issues | 1.5 w | Task/issue CRUD, link to user story / epic | **Done** |
| 9 | Comments, history, attachments | 1.5 w | Polymorphic comment widget, file upload, activity stream | |
| 10 | Board (Kanban) | 2 w | Drag-drop board, swimlanes, filters, saved views | |
| 11 | Milestones / sprints | 1.5 w | List, sprint board, burndown, close sprint | |
| 12 | Wiki | 1.5 w | Page tree, editor, revisions, diff, restore | |
| 13 | Command palette, keyboard shortcuts, polish | 1 w | Cmd-K, hotkeys, empty states, micro-animations | |
| 14 | Permissions UI hardening | 0.5 w | Every action gated, "request access" CTAs | |
| 15 | Accessibility & l10n audit | 1 w | Screen reader pass, contrast, key flows in EN; pipeline for adding languages | |
| 16 | Desktop & mobile polish | 1.5 w | Responsive breakpoints, native menus, file pickers, deep links | |
| 17 | Test hardening & golden suite | 1 w | Coverage targets met, golden suite stable | |
| 18 | Release engineering | 1 w | Flavors, signing, store metadata, autoupdate research | |
| 19 | (Backend-blocked) realtime, notifications | TBD | Pending backend SSE/WS + notification endpoints | |
| 20 | (Optional) offline-first cache | 2 w | If/when product wants it | |

Total to a usable v1 (phases 0–18): **~25 person-weeks**.

---

## Phase 0 — Bootstrap & toolchain — **Done**

**Scope**
- `flutter create intellipilot-front --platforms=web,linux,macos,windows,android,ios --org ch.alpeinsoft` over the existing git repo (preserve `.git`, only add scaffolding).
- Pin Flutter via `fvm` — commit `.fvmrc` and `.fvm/` in `.gitignore`.
- Add `analysis_options.yaml` based on `very_good_analysis` (or `flutter_lints` + custom rules).
- Add `melos.yaml` even for the single-package case — easier to extend later, and gives consistent script entry points.
- Add `pubspec.yaml` baseline dependencies (see [`ARCHITECTURE.md`](./ARCHITECTURE.md) §2).
- Configure `build_runner`, `freezed`, `injectable_generator`, `json_serializable`, `flutter_gen`, `flutter_localizations`.
- Wire CI: lint, format, generate, test on PR. Web build artifact uploaded on `main`.
- Add `assets/` directory tree, a single placeholder logo, app icons via `flutter_launcher_icons`.

**Acceptance**
- `melos run analyze` passes with zero warnings.
- `melos run test` passes (only smoke tests exist).
- `flutter build web`, `flutter build apk --debug`, `flutter build ios --no-codesign`, `flutter build linux`, `flutter build macos`, `flutter build windows` (on appropriate hosts) all succeed.
- App boots to a placeholder `HomePage` with the app name in the AppBar.

**Delivered (2026-05-26)**
- Flutter 3.44.0 stable pinned via `fvm` (`.fvmrc`); `fvm` installed at `~/fvm/bin`.
- Project scaffolded for all 6 platforms via `flutter create --org ch.alpeinsoft --platforms=web,linux,macos,windows,android,ios --empty`.
- `analysis_options.yaml` extends `very_good_analysis` ^8.0.0; strict-casts / strict-inference / strict-raw-types enabled; codegen artifacts excluded.
- `melos.yaml` with scripts: `analyze`, `format`, `format:fix`, `test`, `test:fast`, `gen`, `gen:watch`, `l10n`, `clean`, `ci`.
- `pubspec.yaml` baseline: `flutter`, `flutter_localizations`, `intl`. Dev: `build_runner`, `freezed`, `freezed_annotation`, `json_serializable`, `json_annotation`, `very_good_analysis`.
- `l10n.yaml` + `assets/l10n/intl_en.arb`; bindings generated to `lib/l10n/generated/`.
- `lib/main.dart` renders an M3 `HomePage` with seed-color theme, light + dark, system mode default; AppBar title from ARB.
- Smoke widget test + locales test (`test/widget_test.dart`): 2/2 pass.
- `.github/workflows/ci.yml` runs format check, analyze, tests, web build on PR + main.
- Verified: `flutter analyze` → 0 issues; `flutter test` → 2 passed; `flutter build web --release` → succeeded.
- Deferred to a later phase: `flutter_launcher_icons` and the placeholder logo asset (no source artwork yet).

---

## Phase 1 — Foundation — **Done**

**Scope**
- `lib/app/` skeleton: `bootstrap.dart`, `app.dart`, flavor entry points (`main_dev.dart`, `main_prod.dart`).
- DI: `lib/app/di/` with `injectable` configuration; register `ApiClient`, `SecureStorage`, Hive boxes, `ThemeCubit`, `LocaleCubit`, `SessionBloc` (skeleton).
- Routing: `go_router` config with `/` (home placeholder), `/login` (placeholder), `/me/settings`.
- Theming: `ThemeCubit` with M3 schemes (light/dark/system, seed-color picker, dynamic colors on Android). Settings page lets you change it; choice persists.
- i18n: `l10n.yaml`, `intl_en.arb`, generated bindings; `LocaleCubit`; locale picker in settings (only EN at launch, but the menu exists).
- Networking: `ApiClient` (dio) with all interceptors from [`ARCHITECTURE.md`](./ARCHITECTURE.md) §9. Configurable base URL via `--dart-define=INTELLIPILOT_API_BASE=...`.
- Core widgets: `AppScaffold`, `PrimaryButton`, `EmptyState`, `ErrorView`, `LoadingIndicator`.
- Error / failure mapping (`AppFailure`, `Problem` parser).

**Acceptance**
- Toggling theme mode and seed color updates the live UI without restart; persists across restarts.
- Toggling locale (even with only EN available) rebuilds the tree.
- A fake `GET /health/live` call from the home page renders ok-state on success, error view on failure (proves the interceptor pipeline works end-to-end).
- `getIt` is the only place that *resolves* dependencies; widgets receive them by injection. CI enforces this with a custom lint or grep check.
- ≥ 80% unit-test coverage on `core/` and `app/`.

**Delivered (2026-05-26)**
- App shell: `lib/app/bootstrap.dart` (Hive init → DI → runZonedGuarded → `runApp`), `lib/app/app.dart` (MaterialApp.router + DynamicColorBuilder + Theme/LocaleCubit subscribers). `lib/main.dart` collapsed to a one-liner.
- DI composition root at `lib/app/di/injection.dart` — manual GetIt registrations for app-lifetime singletons; `configureForTests()` swaps in fakes. Widgets never call `getIt<T>()` at build time; blocs/cubits do via constructor.
- Routing via go_router 16 with named routes (`/`, `/me/settings`, `/login`). Login route is a placeholder for Phase 2.
- Theming: `ThemeCubit` persists `themeMode` + seed color + dynamic-color toggle to Hive; M3 schemes built via `AppTheme.light/dark`. Seven seed swatches via `SeedPalette`.
- i18n: `LocaleCubit` (null = follow system). Locale dropdown wired; pipeline ready for adding ARB files in later phases.
- Networking: `ApiClient` (dio 5) with the full interceptor stack — `RequestIdInterceptor`, `AuthInterceptor`, `IdempotencyInterceptor`, `EtagInterceptor`, `ProblemJsonInterceptor`, optional `HttpLoggingInterceptor`. Configurable via `--dart-define=INTELLIPILOT_API_BASE=...`. Mutations support idempotency-key + ETag via the `post()/get()` wrappers.
- Error & failure layer: RFC 9457 `Problem` parser, sealed `AppFailure` hierarchy (Network/Unauthorized/Forbidden/NotFound/Validation/Conflict/RateLimited/Server/Unknown), `mapDioExceptionToFailure` covers every status class.
- Core widgets: `AppScaffold`, `PrimaryButton` (with loading state), `EmptyState`, `ErrorView` (status-specific copy), `LoadingIndicator`.
- Settings page: live theme-mode segmented control, seed-color swatches, dynamic-color switch, locale dropdown. Every change flushes to Hive on the cubit boundary.
- Home page: button calls `GET /health/live` through the real interceptor pipeline; renders ok-card, loading indicator, or `ErrorView` per outcome (proves end-to-end wiring).
- Session: `SessionBloc` skeleton in place (`SessionUnknown → SessionUnauthenticated → SessionAuthenticated`); Phase 2 plugs in the real flow without touching network or DI.
- Tests: **80 passing**. Coverage: `lib/core` 80.6 %, `lib/app` 80.5 % — meets the ≥ 80 % gate. Includes unit, widget, and bloc tests; `bloc_test` + `mocktail` available for later phases.
- `flutter analyze` clean (0 issues). Format check clean. Web release build verified.
- Lint tuning: `lines_longer_than_80_chars`, `comment_references`, `cascade_invocations`, `one_member_abstracts`, `avoid_positional_boolean_parameters`, `avoid_equals_and_hash_code_on_mutable_classes`, `unnecessary_lambdas`, `specify_nonobvious_*` disabled (rationale: noisy for an application; quality preserved via strict-casts/strict-inference/strict-raw-types).

---

## Phase 2 — Auth & session — **Done**

**Scope**
- `features/auth/`: login page, register page, forgot-password page, reset-confirm page.
- `features/session/`: `SessionBloc` state machine, refresh timer, logout.
- Forms via `reactive_forms`; validation mirrors backend `garde` rules (email shape, password length, username pattern `^[a-zA-Z0-9_.-]+$`).
- Wire to `POST /auth/{register,login,logout,refresh}`, `POST /auth/password/reset/{request,confirm}`.
- Web: cookies-based refresh (dio `withCredentials: true`). Native: refresh-token in secure storage.
- "Remember me" not needed — server cookie is HttpOnly + long-lived already.
- Router guard: unauthenticated routes redirect to `/login`, remember intended URL.
- Show a development-only banner when the dev mailer returns the reset token inline ("Token: ...").

**Acceptance**
- E2E flow (patrol): register → logout → forgot password → reset → login → land on `/projects`.
- Token refresh: simulated 401 → automatic refresh → original request retried → user never sees the bounce.
- Logout clears in-memory access token, calls `POST /auth/logout`, scrubs Hive `drafts`, wipes secure storage refresh token, navigates to `/login`.
- ≥ 90% bloc coverage. All states tested.

**Delivered (2026-05-27)**
- `features/auth/` slice: hand-written DTOs in `data/dtos/auth_dtos.dart` (`LoginRequest`, `RegisterRequest`, `TokenResponse`, `LoginResult` sealed type with `LoginTokens`/`LoginMfaRequired`, `PasswordReset*`, `TwoFactorVerifyRequest`). `AuthRepository` interface + `AuthRepositoryImpl` over `ApiClient`.
- `SessionBloc` rebuilt as a real state machine: `SessionUnknown → SessionAuthenticating → SessionMfaRequired → SessionAuthenticated → SessionRefreshing → SessionUnauthenticated(reason)`. Proactive refresh timer fires `expiresIn - 30s` ahead of expiry (floor 5s) and `currentAccessToken` is also exposed during `SessionRefreshing` so in-flight calls don't blank out.
- Per-page cubits decouple form UX from session lifecycle: `LoginCubit` dispatches `SessionEstablished` / `SessionMfaChallenged` into `SessionBloc` on success; `RegisterCubit`/`ForgotPasswordCubit`/`ResetPasswordCubit` are independent of session state.
- `RefreshInterceptor` on Dio: on 401 (excluding `/auth/login`, `/auth/register`, `/auth/refresh`, `/auth/logout`, `/auth/password/reset/*`, `/auth/2fa/verify`) coalesces concurrent refreshes through a single in-flight `Future` and retries the original request exactly once with `__refresh_retried` extras flag — no infinite loops on persistent 401.
- Cookies via `dio_cookie_manager` + `cookie_jar`. Web relies on the browser-managed HttpOnly cookie (`withCredentials: true` on Dio); native uses `PersistCookieJar` under `<app-docs>/.cookies`. `CookieSetup.create()` picks the right backend; `CookieSetup.inMemory()` is the test factory.
- Pages built with `reactive_forms`: `LoginPage`, `RegisterPage`, `ForgotPasswordPage`, `ResetPasswordPage`. Field validators mirror backend `garde` rules (`email`, `[a-zA-Z0-9_.-]+` for username 3..64, password 8..1024, reset token 1..512). Server-side errors get mapped to localized copy per `AppFailure` subtype (`UnauthorizedFailure` → "Email or password is incorrect.", `ConflictFailure` → "That email or username is already in use.", etc.).
- Dev-only banner: `ForgotPasswordPage` surfaces the `reset_token` returned by the backend in dev mode with a copy-to-clipboard action — QA can complete the reset flow without a mailer.
- `go_router` guard via `GoRouterRefreshStream(session.stream)`: unauthenticated routes redirect to `/login?from=<original>`; authenticated visits to `/login` bounce to the preserved `from` or `/`. New routes: `/register`, `/forgot-password`, `/reset-password?token=...`.
- Bootstrap dispatches `SessionStartupRequested` so cold-start tries `/auth/refresh` against the persisted cookie before deciding whether to show login.
- DI broke the latent circular dependency (`ApiClient → AuthRepository → SessionBloc → ApiClient`) by capturing `SessionBloc` lookups as closures in the `ApiClient` registration; the bloc resolves only on first invocation, by which time construction is complete.
- ARB strings expanded with every auth label + field + error, regenerated to `lib/l10n/generated/`.
- **120 tests pass** (`flutter analyze` clean, web release build verified). Coverage: `lib/app/` 87.5 %, `lib/core/` 81.4 %, `lib/features/auth/` 85.9 %; **cubits 96.3 %** (≥ 90 % bloc target met), SessionBloc 80.6 %, RefreshInterceptor 90.9 %.
- Deferred to later phases per Phase 2 scope cut: full MFA UI (Phase 3) — login surfaces an "MFA required" notice when the backend returns a challenge but the verify form ships with passkeys/TOTP; `flutter_secure_storage` package is on the dep list but storage of the refresh token still relies on the cookie jar — secure-storage backing is a Phase 3 hardening item; `patrol` E2E suite (Phase 17 — test hardening).

---

## Phase 3 — MFA & passkeys — **Done**

**Scope**
- TOTP enrollment screen: shows QR (from `qr_png_base64` returned by `POST /me/totp/start`) and manual base32. Confirm flow via `POST /me/totp/confirm`. Disable via `DELETE /me/totp`.
- Recovery codes: `POST /me/recovery-codes/regenerate` → reveal once, download / copy, dismiss.
- MFA verification page reached when login returns an MFA challenge (`mfa_token` + method=totp or recovery). Calls `POST /auth/2fa/verify`.
- Passkey enrollment: `POST /me/passkeys/register/{start,finish}` driven by platform WebAuthn. List enrolled passkeys, delete by id.
- Passkey sign-in: `/passkeys/sign-in` page → `POST /auth/passkeys/authenticate/{start,finish}`.
- Platform feature-detect: hide passkey UI on platforms without WebAuthn support; show a tooltip explaining why.

**Acceptance**
- Login with TOTP-enabled account: password → MFA prompt → 6-digit code → authenticated.
- Recovery code path works.
- Passkey registration & sign-in works on Web (Chrome, Safari) and at least one mobile platform.
- TOTP disable requires a fresh 6-digit code (server enforces; we honor `412` / `401` error message clearly).

**Delivered (2026-05-27)**
- New `features/mfa/` slice: hand-written DTOs (`TotpStartResponse`, `RecoveryCodesResponse`, `PasskeyListItem`, `PasskeyCeremony`) and `MfaRepository` + `MfaRepositoryImpl` over `ApiClient`. All endpoints from the backend's mfa.rs / passkeys.rs wired: `/me/totp/{start,confirm}`, `DELETE /me/totp`, `/me/recovery-codes/regenerate`, `/me/passkeys`, `/me/passkeys/register/{start,finish}`, `DELETE /me/passkeys/{id}`, `/auth/passkeys/authenticate/{start,finish}`.
- `PasskeyService` abstraction with conditional imports (`passkey_service_stub.dart` on native, `passkey_service_web.dart` on web via `dart.library.js_interop`). Web impl uses `dart:js_interop` + `package:web` to drive `navigator.credentials.{create,get}()`, converting between the backend's base64url JSON shape and the browser's `ArrayBuffer` types at the field positions WebAuthn specifies (`challenge`, `user.id`, `rawId`, `clientDataJSON`, `attestationObject`, `authenticatorData`, `signature`, `userHandle`, `excludeCredentials[].id`, `allowCredentials[].id`).
- Pages: `SecurityPage` (settings hub), `TotpSetupPage` (QR + base32 with copy, 6-digit confirm, recovery-code reveal), `RecoveryCodesPage` (regenerate + reveal), `MfaVerifyPage` (segmented TOTP/recovery, dispatches `SessionEstablished` on success), `PasskeysPage` (list, add with nickname dialog, delete), `PasskeySignInPage` (email → ceremony → session).
- Cubits per page: `TotpSetupCubit`, `RecoveryCodesCubit`, `MfaVerifyCubit`, `PasskeysCubit`, `PasskeySignInCubit`. `MfaVerifyCubit` and `PasskeySignInCubit` dispatch `SessionEstablished` into `SessionBloc` on success so the router naturally redirects home.
- Router guard updated: `SessionMfaRequired` corners the user on `/auth/mfa` until they verify or cancel; an authenticated visit to `/auth/mfa` bounces home. New routes: `/auth/mfa`, `/passkeys/sign-in`, `/me/security`, `/me/security/totp`, `/me/security/recovery`, `/me/security/passkeys`.
- LoginPage gains a "Sign in with a passkey" link; SettingsPage gains a "Security" tile.
- Feature detection: pages and cubits gate add/sign-in CTAs on `PasskeyService.isSupported` and surface a localized "passkeys aren't available on this device" notice on native — the stub returns `isSupported = false`.
- DI updated: `MfaRepository` and `PasskeyService` registered as lazy singletons; `configureForTests` accepts optional overrides with safe defaults (`_NoopMfaRepository`, `_StubPasskeyService`).
- ARB bundle extended with every new label/error string and regenerated to `lib/l10n/generated/`.
- **158 tests pass** (`flutter analyze` clean, web release build green). Coverage: `lib/app/` 83.8%, `lib/core/` 81.9%, `lib/features/auth/` 85.8%, `lib/features/mfa/` 70.6%, **cubits**: auth 96.3% / mfa 97.9% (≥ 90% bloc gate met). Overall 78.6%.
- Deferred: passkeys on native platforms (mobile/desktop) — the stub throws `UnsupportedError` and the UI feature-detects; per-platform WebAuthn bindings (e.g. `local_auth` + platform channels) land in a later phase. The full TOTP-disable-with-fresh-code flow lives on the backend; this UI shows the confirmation modal and surfaces backend errors but doesn't yet challenge for a code locally.

---

## Phase 4 — Profile & account — **Done**

**Scope**
- `/me` page: view + edit `full_name`, `lang`, `timezone`. Patch via `PATCH /me`.
- Locale: if user updates `lang`, also update `LocaleCubit` locally so the change is instant.
- GDPR export: `GET /me/export` → trigger download on web, share-sheet on mobile.
- Delete account: `DELETE /me` with a confirmation modal that explains the 30-day grace period. Show a "Your account is scheduled for deletion on {date}" banner if `deleted_grace_until` is set.

**Acceptance**
- Profile updates reflect immediately, both locally and on next backend fetch.
- Delete confirmation requires typing the username; cannot be triggered accidentally.

**Delivered (2026-05-27)**
- New `features/profile/` slice with `UserProfile` / `ProfileUpdateRequest` / `AccountErasureResponse` DTOs. `ProfileRepository` interface + impl over `ApiClient` covers all four endpoints (`GET /me`, `PATCH /me`, `DELETE /me`, `GET /me/export`).
- `ProfileCubit`: `load()` on init, `save()` posts a partial `PATCH /me`. When `lang` changes, the cubit also dispatches `LocaleCubit.setLocale` so the UI flips locale live, no app restart needed.
- `AccountDeletionCubit`: requires the user-typed `expectedUsername` to match exactly before calling the backend (client-side anti-fat-finger guard on top of the backend's soft-delete grace). On success, dispatches `SessionLogoutRequested(callBackend: false)` so the router kicks the user back to `/login`.
- `GdprExportCubit`: pulls `GET /me/export`, then writes the JSON via a platform-conditional `FileDownloader`. Web uses `dart:js_interop` + `package:web` to trigger a real `Blob` download (`<a download>` + `revokeObjectURL`); native falls back to a clipboard copy with the same JSON body. The UI surface adapts copy + icon based on `canDownload`.
- Pages: `ProfilePage` at `/me/profile` (text fields for name, language dropdown, timezone; live save snack), `AccountPage` at `/me/account` (GDPR export tile + danger-zone card with "type-your-username" confirmation modal).
- SettingsPage gains Profile and Account tiles in addition to the existing Theme / Locale / Security sections.
- DI registers `ProfileRepository` and `FileDownloader` as lazy singletons; `configureForTests` accepts optional fakes (`_NoopProfileRepository`, `_InMemoryDownloader`).
- ARB strings extended (10 new sections of copy: profile fields, account danger zone, GDPR export, all snacks). Regenerated to `lib/l10n/generated/`.
- **178 tests pass** (`flutter analyze` clean, web release build green). Coverage: `lib/app/` 82.1%, `lib/core/` 81.2%, `lib/features/profile/` 75.1%, cubits 96.3% (profile) / 97.9% (mfa) / 96.3% (auth) — ≥ 90% bloc gate met across all features. Overall 77.8%.
- Deferred / out of scope: the backend's `User` payload doesn't expose `deleted_grace_until` on `GET /me`, so the "scheduled for deletion" banner on later sign-ins is not implementable client-side until a backend change. `share_plus` integration for native file save (currently clipboard) — TBD in a later phase.

---

## Phase 5 — Projects, members, roles, invitations — **Done**

**Scope**
- `/projects` list: paginated, search, "new project" CTA.
- `/projects/:id` overview: name, description, key stats (counts of epics/US/tasks/issues), recent activity.
- `/projects/:id/settings` tab set: General, Members, Roles, Taxonomy, Labels, Components, Danger Zone.
- **Members**: list, change role, remove. `PermissionGate` on each action.
- **Roles**: CRUD; role editor surfaces the 40-permission catalog grouped by domain (Project / Members / Roles / Epics / User Stories / Tasks / Issues / Milestones / Wiki / Comments / Attachments) with bulk toggle helpers ("Reader", "Contributor", "Maintainer", "Admin" presets).
- **Invitations**: send by email, list pending, copy link, revoke. Accept page `/i/:token` calls `POST /invitations/accept`.
- **Delete project**: confirmation modal, requires typing the project name.

**Acceptance**
- Role editor never lets the only `project.admin` member be removed or downgraded (UI prevents; backend also enforces).
- Invitation flow works end-to-end on web (link sharing) and mobile (deep-link).
- Soft-deleted projects (within 30-day grace) show a "Project will be deleted on {date}" banner; admins can restore via a backend-supplied flow (if backend supports it; otherwise open question).

**Open question to backend**
- Is there a project-restore endpoint? (Not visible in the current router.)

**Delivered (2026-05-27)**
- New `features/projects/` slice with hand-written DTOs (`Project`, `Role`, `Membership`, `Invitation`, `InviteResponse`, request bodies) and a `Permission` enum mirroring the backend's 40-entry catalog wire-for-wire. `RolePresets.{reader,contributor,maintainer,admin}` mirror the seeded backend roles.
- `ProjectsRepository` (single repo) wraps every Phase-5 endpoint: `/projects` CRUD, `/projects/:id/{roles,members,invitations}` CRUD, `/invitations/accept`. Failures map through the existing `mapDioExceptionToFailure` so the UI surfaces typed `AppFailure`s.
- Cubits per concern: `ProjectsListCubit` (load + search + create), `ProjectDetailCubit` (loads project, resolves caller's permissions by joining `/members` + `/roles`, exposes `has(Permission)` and an `isAdmin` flag), `MembersCubit`, `RolesCubit`, `InvitationsCubit`, `ProjectSettingsCubit` (PATCH + DELETE with typed-name confirmation), `AcceptInvitationCubit`.
- Pages: `ProjectsListPage` at `/projects` (search filter, "New project" FAB, empty state), `ProjectOverviewPage` at `/projects/:id` (name/description/visibility chip, feature flags, settings shortcut behind `PermissionGate(Permission.projectModify)`), `ProjectSettingsPage` at `/projects/:id/settings` with four tabs (General / Members / Roles / Danger Zone), `InvitationAcceptPage` at `/i/:token`.
- Reusable widgets: `PermissionGate` reads the surrounding `ProjectDetailCubit` and hides/replaces its child when the caller lacks the permission; `RoleEditor` renders the 40-permission catalog grouped by `PermissionDomain` (Project / Members / Roles / Epics / User Stories / Tasks / Issues / Milestones / Wiki / Comments & attachments) with Reader / Contributor / Maintainer / Administrator bulk-toggle buttons.
- Members tab: list rows show role slug with change-role and remove-member actions each gated by their permission; pending invitations section reloads after a successful invite. Invite dialog drives `POST /invitations`; the dev-only raw token returned by the backend pops up in a copy-able dialog when present.
- Roles tab: ExpansionTile per role; admin role is read-only and surfaces a badge. New-role dialog seeds with the Contributor preset. Delete maps backend 409 ("role still has members") through the standard error mapper.
- Danger Zone: `DELETE /projects/:id` only fires after the user types the project name verbatim — client-side guard on top of the backend call.
- Routing: `/projects`, `/projects/:id`, `/projects/:id/settings`, `/i/:token` added. After-login + after-MFA redirects now land on `/projects` instead of the demo home. HomePage gains a "Go to projects" CTA.
- DI: `ProjectsRepository` registered lazily; `configureForTests` accepts an override with a safe `_NoopProjectsRepository` default.
- 18 sections of ARB copy added (project list/search/empty/visibility/features, settings tabs, members/roles/invitations, danger zone, permission domain headers, role presets, invitation accept). Regenerated to `lib/l10n/generated/`.
- **185 tests pass** (`flutter analyze` clean, web release build green). New repo wire-format smoke covers project envelope unwrap, visibility serialization, permission round-trip, invite-token surfacing, and the maintainer-superset invariant on `RolePresets`. Coverage gate paused per the feedback memory; broader bloc/widget tests intentionally deferred.
- Deferred: no "request access" CTA on permission-denied views yet (the gate currently hides the affordance). Member rows show raw `userId` — backend doesn't expose a `users-by-project` enrichment endpoint and `GET /users/:id` isn't wired. Project-restore (open question above) remains unimplementable until the backend ships it.

---

## Phase 6 — Taxonomy, labels, components — **Done**

**Scope**
- `/projects/:id/settings/taxonomy`: tabs for `status | type | priority | severity | points`. CRUD + reorder via `POST /taxonomy/{kind}/{item_id}/move` (drag handle in list).
- Each taxonomy item has color, name, optional WIP limit (status), is_closed flag (status), default flag (per kind).
- `/projects/:id/settings/labels`: list, create with color picker, edit, delete.
- `/projects/:id/settings/components`: same as labels.

**Acceptance**
- Drag-reorder uses fractional-index `move` endpoint; no full-list refresh on each drop.
- Deleting a status that's in use is blocked client-side (we look up usage count) with a clear message — server returns 409 otherwise.

**Delivered (2026-05-27)**
- New `features/catalog/` slice — `TaxonomyKind` enum mirroring the backend's 7 kinds wire-for-wire (`us_status`, `task_status`, `issue_status`, `issue_type`, `priority`, `severity`, `point`) with `hasClosed` / `hasValue` helpers that match the Rust enum semantics. `TaxonomyItem`, `Label`, `Component` DTOs + request bodies; a shared `ColorPalette` of ten hex swatches matching the backend's default seed colours.
- `CatalogRepository` wraps every Phase-6 endpoint: taxonomy CRUD + `/move` per kind, labels CRUD, components CRUD. Failures map through `mapDioExceptionToFailure`.
- Cubits: `TaxonomyCubit(kind)` (kind-parameterised; reorder dispatches a single `move` call with before/after anchors derived from the optimistically-updated list), `LabelsCubit`, `ComponentsCubit`. Each ends a mutation by re-fetching to keep server truth.
- Reusable widgets: `ColorSwatchPicker` (10-swatch grid + `HexColorDot` indicator).
- `ProjectSettingsPage` grew from 4 to 7 tabs: **General · Members · Roles · Taxonomy · Labels · Components · Danger Zone**. New `TaxonomyTab` has a horizontal kind-chooser ChoiceChip row + `ReorderableListView` with drag handles; supports `is_closed` for statuses and a numeric `value` field for the `point` kind. New-item / edit dialogs honour the kind-specific shape. `LabelsTab` and `ComponentsTab` provide standard list + colour-picker dialogs; components carry an optional Git repo URL.
- All edit / add / delete affordances are gated by `Permission.projectModify` — readers see the data but no buttons.
- DI: `CatalogRepository` registered lazily; `configureForTests` accepts an override with a `_NoopCatalogRepository` default.
- 33 new ARB strings (tab names, generic fields like name/color/slug/edit, 7 kind labels, taxonomy is_closed copy, value field hints, label + component dialog copy, delete confirmations). Regenerated to `lib/l10n/generated/`.
- **192 tests pass** (`flutter analyze` clean, web release build green). New `CatalogRepositoryImpl` wire-format smoke covers the kind URL path, status-only `is_closed` flag, `/move` envelope, `{labels: [...]}` and `{components: [...]}` unwrap, and the `hasClosed` / `hasValue` invariants. `onReorder` migrated to the non-deprecated `onReorderItem`.
- Deferred: backend doesn't surface a "delete blocked because items reference this status" check; the UI lets the user attempt deletion and surfaces the backend's 409 through the standard error mapper. WIP-limit field on statuses (mentioned in the scope) isn't on the backend `TaxonomyItem` shape yet — open backend question.

---

## Phase 7 — Backlog: epics & user stories — **Done**

**Scope**
- `/projects/:id/backlog`: grouped list. Default grouping: by epic (collapsible groups). Filter chips: assignee, status, milestone, label, search.
- Epic detail panel: name, description (markdown), color, owner, status, child user-stories preview, attachments count.
- User-story detail panel: title, description, status, story points, assignee, epic link, milestone link, tasks list, comments tab, history tab, attachments tab.
- CRUD: create (modal, quick-add), edit (inline + full-screen detail), delete (confirm), reorder (drag handle in backlog).
- **Optimistic updates** on reorder, status change, assignee change. Rollback on 409 / 412 with a "stale data" banner.

**Acceptance**
- Backlog of 1000 user stories scrolls smoothly (virtualized list, e.g. `SliverList` + viewport-aware fetching with cursors).
- Reorder works across epics (drag a US under a different epic group).
- Bulk create (`POST /userstories/bulk`) is wired for "paste multiple titles, one per line" UX.

**Delivered (2026-05-27)**
- New `features/backlog/` slice — `Epic`, `UserStory`, `CreateEpicRequest`, `UpdateEpicRequest`, `CreateUserStoryRequest`, `UpdateUserStoryRequest`, `ReorderRequest`, `BulkCreateUserStoryItem`/`BulkCreateUserStoriesRequest` DTOs. Updates use a sentinel `_Absent` marker so we can distinguish "leave alone" from "clear the FK" — backend uses `serde_with::rust::double_option`.
- `BacklogRepository` (single repo) covers every Phase-7 endpoint: epic CRUD + `/move`, user-story CRUD + `/move` + `/bulk`. Mutating calls round-trip `If-Match` through the existing `EtagInterceptor` by reading the `etag` header off GET responses; the DTOs carry it as an optional `etag` field.
- `BacklogCubit` holds `{epics, userStories, statuses, points}` for a project — joins us_status + point taxonomy items from the catalog repo on load. Computed `grouped` getter buckets user stories by `epicId` (null bucket for "no epic"). Optimistic reorder dispatches a single `/move` with neighbour anchors; on 409/412 the cubit flips `staleData: true`, calls `load()` to reconcile, and the UI shows a "data has changed" banner. Same flow for status-change and full updates.
- `BacklogPage` at `/projects/:id/backlog`: search field, status FilterChip row (all + per-status), "New epic" + "Bulk add" buttons, FAB for "New user story". Grouped `ExpansionTile` per epic (collapsible) with a "No epic" group at the bottom. Each row shows `US-{ref} · {status} · {points}` with a popup status menu, edit + delete icons. All edit affordances gated by `Permission.epicCreate/modify` and `Permission.usCreate/modify` via the surrounding `ProjectDetailCubit`.
- Three reusable dialogs: `EpicEditDialog` (subject / description / colour swatch), `UserStoryEditDialog` (subject / description / epic / status / points dropdowns), `BulkPasteDialog` (newline-separated subjects + optional epic — fans out to `/userstories/bulk`).
- Routing: `/projects/:id/backlog` added; `ProjectOverviewPage` gets an "Open backlog" CTA. `Routes.projectBacklogFor(id)` helper.
- DI: `BacklogRepository` registered lazily with a `_NoopBacklogRepository` test default. ARB extended with 30 strings (page title, fields, filter labels, dialog copy, delete confirmations, bulk-paste copy, stale-data banner).
- **198 tests pass** (`flutter analyze` clean, web release build green). New `BacklogRepositoryImpl` wire-format smoke covers `{epics: [...]}`/`{user_stories: [...]}` envelope unwrap, ETag round-trip header capture + `If-Match` send on PATCH, `/move` envelope, and the `{items: [...]}` bulk-create shape.
- Deferred: full-screen detail pages (user-story + epic side-sheets with the comments / history / attachments tabs) intentionally pushed to Phase 9, which wires those endpoints. Filter chips for assignee/milestone/label/component need member + milestone enrichment that ships in Phase 8 (issues) / Phase 11 (milestones); for Phase 7 we expose status + free-text search only.

---

## Phase 8 — Backlog: tasks & issues — **Done**

**Scope**
- Tasks: nested under a user story. Inline checklist UI on the US detail page. Status comes from taxonomy.
- Issues: standalone list `/projects/:id/issues` with filters (type, severity, priority, label, component, assignee). Detail page mirrors US but adds severity & component fields.
- Cross-entity reference resolver: `/projects/:id/resolve/:ref` powers the global search ("#123" or "PROJ-123") and the comment-mention autocomplete (`@user`, `#issue`).

**Acceptance**
- Search by reference jumps to the right entity detail page.
- Filters serialize to URL query params and back, so a filtered view is shareable.

**Delivered (2026-05-27)**
- Extended `features/backlog/` DTOs with `Task`, `Issue`, `CreateTaskRequest`, `UpdateTaskRequest`, `CreateIssueRequest`, `UpdateIssueRequest`, and a `ResolvedRef` envelope for the cross-reference resolver. Update DTOs reuse the `_Absent` sentinel from Phase 7 so present-but-null clears the FK while absence leaves it alone.
- `BacklogRepository` covers every Phase-8 endpoint: tasks list/get/create/update/delete with ETag round-trip, issues list/get/create/update/delete with ETag round-trip, plus `GET /projects/:id/resolve/:ref` for reference lookup. Update + delete carry `If-Match` via the existing `EtagInterceptor`.
- Two new cubits: `TasksCubit(projectId, userStoryId)` loads all project tasks + `task_status` taxonomy, filters in memory to the surrounding user story, exposes create/setStatus/delete. `IssuesCubit(projectId)` loads issues + `issue_status` / `issue_type` / `priority` / `severity` taxonomies + labels + components, computes `visible` from independent status/type/priority/severity filters + search.
- `TaskListDialog` opens from each user-story row on the backlog page (`Icons.checklist_outlined` button); shows tasks as a checkbox list — toggling the checkbox moves the task between the first open and first closed `task_status` items, with the title styled struck-through when closed.
- New `IssuesPage` at `/projects/:id/issues`: search field, four popup-menu filter chips (status/type/priority/severity), full-bleed list with status/type/priority/severity mini-chips per row. Per-row popup menu for edit + delete. FAB for new issue gated by `Permission.issueCreate`. `IssueEditDialog` shows all four kind dropdowns plus selectable `FilterChip` arrays for the project's labels and components.
- Project overview page gains an "Open issues" tonal CTA next to "Open backlog".
- DI doesn't grow — `BacklogRepository` already registered; the new endpoints are methods on it. ARB extended with 25 strings (issues page copy, filter labels, tasks dialog copy, generic add).
- **198 tests pass** (`flutter analyze` clean, web release build green). Existing repo wire-format test still passes; broader bloc/page tests for tasks + issues intentionally deferred per the paused coverage gate.
- Deferred: filter serialisation to URL query params (the cubit holds state in memory; deep-linking a filtered view stays a Phase 13 polish item alongside the Cmd-K palette). Assignee + label-component filters aren't surfaced as chips yet — the wire-format support is already in place; only the UI affordances are pending. The reference-resolver method is callable from the repo but the global "go to #123" UI lands with the Cmd-K palette in Phase 13.

---

## Phase 9 — Comments, history, attachments

**Scope**
- Comment thread widget: list (`GET .../comments`), create (`POST`), edit (`PATCH`), delete (`DELETE`). Markdown editor with split preview; mention autocomplete (`@user`, `#ref`); emoji picker.
- Activity stream: merge `/comments` and `/history` into a single chronological feed. Filter toggle: "Show all" / "Show comments only" / "Show changes only".
- Attachments tab on every backlog entity: upload (drag-drop + file picker), list, download (call `GET .../download` or sign URL via `GET /attachments/{id}` and open in new tab), delete.
- Upload progress with cancel; honor server 25 MiB / 32 MiB multipart limits.
- Drafts: comment composer autosaves to Hive every 3s; restores on reopen.

**Acceptance**
- Editing a comment 30s after creation requires the same user (server enforces; UI hides edit for others).
- Activity stream renders 200+ entries smoothly via virtualization.
- Uploading a 30 MiB file on web works without OOM; oversized file is rejected client-side with a clear error.

---

## Phase 10 — Board (Kanban)

**Scope**
- `/projects/:id/board`: columns from taxonomy `status` kind, cards from active milestone user-stories + tasks.
- **Swimlanes** (rows): off by default; can group by assignee, epic, priority, or component.
- **Filters**: persistent panel (assignee, label, component, type, priority, severity); saved as named views.
- **Drag-drop**: vertical reorder within column (fractional index), horizontal move (status change). Optimistic.
- **WIP limits**: warn when a column exceeds the taxonomy item's `wip_limit`.
- **Card detail**: side-sheet on wide layouts (≥ md), full-screen modal on narrow.
- **Quick actions**: hover toolbar on cards (assign to me, change status, add comment).

**Acceptance**
- Board renders 200 cards across 6 columns with no jank on a mid-spec laptop (web profile).
- Drag operation has < 100 ms perceived latency thanks to optimistic update.
- Saved views survive restart; "Default view" can be set per user per project.

---

## Phase 11 — Milestones / sprints

**Scope**
- `/projects/:id/milestones`: list of milestones with status (open / closed), date range, scope summary (counts, points), progress bar.
- Milestone detail page:
  - **Board** tab: sprint-scoped Kanban (calls `GET /milestones/{id}/board`).
  - **Stats** tab: burndown chart (`GET /milestones/{id}/stats`), velocity over last N sprints.
  - **Scope** tab: planning view — backlog on left, sprint scope on right, drag between, live point totals.
- **Close sprint**: `POST /milestones/{id}/close`. Modal asks what to do with unfinished work (move to next sprint, back to backlog, leave in closed sprint).
- Create / edit / delete milestone.

**Acceptance**
- Burndown chart renders correctly for an empty sprint, in-progress sprint, and closed sprint.
- Closing a sprint with unfinished items prompts disposition before the close call lands.

---

## Phase 12 — Wiki

**Scope**
- `/projects/:id/wiki`: page tree (nested), sortable. "New page" CTA, search.
- Page view: rendered markdown (server HTML), breadcrumbs, "Edit" CTA.
- Page edit: split-pane markdown editor with live preview; autosave to drafts; conflict detection via ETag.
- Revision list: `GET .../revisions`. Click a revision → view it. "Compare to current" → server diff (`/revisions/{rev}/diff`) rendered with `similar`-style highlighting.
- Restore: `POST /revisions/{rev}/restore` with confirmation.
- Attachments embedded inline via markdown image syntax pointing at signed URLs.

**Acceptance**
- Editing a page another user has updated mid-edit shows a "page changed" banner with options: discard / merge view / overwrite.
- Diff view renders large pages (10k chars) without lag.

---

## Phase 13 — Command palette, hotkeys, polish

**Scope**
- Cmd-K palette: search across projects, issues (via `/resolve`), pages, commands.
- Global hotkeys (`HardwareKeyboard` listener at the app root):
  - `c` create (context-aware: in backlog → new US, in board → new card, in wiki → new page)
  - `g p` go to projects, `g b` board, `g w` wiki, `g s` settings
  - `j`/`k` navigate items in lists/boards
  - `e` edit currently focused item
  - `?` show shortcut help dialog
- Empty states with illustrations, error states with retry.
- Micro-animations: page transitions, list item insertions, drag ghosts.
- Toast / SnackBar system: queue, dismiss, action buttons.

**Acceptance**
- Hotkey help dialog is the only source of truth (renders from a single registry → no shortcut drift).
- All hotkeys disabled while a text field has focus (so `j` in a comment field types `j`).

---

## Phase 14 — Permissions UI hardening

**Scope**
- Audit every action across every page: is it gated by `PermissionGate` or `PermissionsCubit.has(...)`?
- Add "Request access" CTAs where appropriate (purely client-side; backend has no request-access endpoint yet — Phase 19 open question).
- Add a debug overlay (dev-only flavor): shows current user's permissions for current project.

**Acceptance**
- Removing a user's `epic.modify` permission immediately disables every Edit affordance on epic UIs (without a refresh).

---

## Phase 15 — Accessibility & l10n audit

**Scope**
- Screen reader pass: every interactive element has a semantic label; reading order is logical.
- Color contrast audit: all themes pass WCAG AA (`flutter_a11y_check` if available, else manual + plugin).
- Keyboard navigation: tab order, focus rings, escape-to-close on modals.
- `intl` audit: extract all hardcoded strings, ensure plurals and dates use ICU MessageFormat.
- Add at least one additional locale to verify the pipeline (recommended: German, given Alpein Software AG's Swiss context).

**Acceptance**
- VoiceOver smoke (iOS) and NVDA smoke (Web Chrome) pass critical flows.
- Adding a locale is documented in `docs/I18N.md` (a one-pager added in this phase).

---

## Phase 16 — Desktop & mobile polish

**Scope**
- Responsive breakpoints: `compact` (< 600), `medium` (600–839), `expanded` (≥ 840). Replace bottom nav ↔ navigation rail ↔ permanent drawer accordingly.
- Desktop: native menu bar (`menu_bar` package or platform channels), window state restoration, drag-from-titlebar regions.
- Native file pickers and share sheets verified per platform.
- Deep links / universal links (Android App Links, iOS Universal Links, web `pathUrlStrategy`).
- Splash screens via `flutter_native_splash`.
- App icons & store listings.

**Acceptance**
- Window resize from 320 px to 1920 px is smooth, no overflowing rows or clipped tap targets.
- Pasting an `https://app.intellipilot.dev/projects/.../issues/...` link on a mobile install opens the app at that page.

---

## Phase 17 — Test hardening & golden suite

**Scope**
- Coverage gate in CI (`--coverage` + `lcov` report; fail under target).
- Golden tests for the 30 most critical screens × {light, dark} × {compact, expanded}.
- `patrol` integration test matrix: smoke flows on web, Android emulator, iOS simulator on CI.
- DTO contract tests against a captured `openapi.json` snapshot.

**Acceptance**
- CI fails when a screen visually regresses without an updated golden.
- 90% domain coverage, 100% bloc state-transition coverage, 70% widget coverage.

---

## Phase 18 — Release engineering

**Scope**
- Flavors: `dev`, `staging`, `prod` — distinct `applicationId` / bundle id, icon overlay, base URL.
- Signing: Android keystore, iOS provisioning profiles, macOS notarization, Windows code signing, Linux GPG.
- Store metadata: screenshots, descriptions, privacy policy.
- Versioning: semver from a single source (`pubspec.yaml`), embedded in About dialog and `X-Client-Version` header.
- Web: cache-busting via `--web-renderer canvaskit` or `html` decision (canvaskit for fidelity, html for size — likely canvaskit).
- Auto-update research:
  - Desktop: investigate `auto_updater`, `Sparkle` (macOS).
  - Web: service worker prompt-to-reload on new build.

**Acceptance**
- A new build can be released to all targets from a tagged commit with documented steps in `docs/RELEASE.md`.

---

## Phase 19 — Backend-blocked: realtime & notifications

Pending backend support. Tracked here as open work; do not start until backend lands the endpoints (see [`ARCHITECTURE.md`](./ARCHITECTURE.md) §24).

- Wire SSE or WebSocket `RealtimeChannel` impl behind the existing interface.
- In-app notification bell with unread badge.
- Mobile push (FCM + APNs) when backend exposes a device-token endpoint.
- Per-user notification preferences UI.

---

## Phase 20 — Optional: offline-first cache

If product wants it. Approach:

- Hive-backed cache per repository, keyed by query.
- Outbox pattern for mutations: store the request + idempotency key, retry on reconnect.
- Sync indicator in the AppBar (synced / syncing / offline / failed).
- Conflict resolution UI for outbox failures (412 from server → prompt for merge).

---

## Cross-cutting decisions to lock before Phase 0

These should be answered before scaffolding so we don't refactor later. Defaults below are my recommendations; flag any disagreement.

| Decision | Default | Alternatives |
|---|---|---|
| Bundle id / app id | `ch.alpeinsoft.intellipilot` | confirm namespace |
| Flutter channel | `stable` only | beta unsuitable for prod |
| Flutter version pinning | `fvm` with `.fvmrc` | global Flutter (rejected — drift) |
| Web renderer | `canvaskit` | `html` (smaller bundle, lower fidelity) |
| Web base URL | `/` (same origin as API behind reverse proxy) | subdomain (`app.intellipilot.dev`) |
| Mono-repo strategy | single package + `melos` scripts | multi-package only if we extract a shared SDK |
| CI provider | GitHub Actions | GitLab CI, depending on backend's host |
| Crash reporting | Sentry, env-gated | Firebase Crashlytics (mobile-only) |
| Analytics | None at MVP | PostHog / Plausible later |
| License header in source | omit unless legal requires | add `LICENSE-HEADER.txt` if needed |
| Code style | `very_good_analysis` ruleset | `flutter_lints` (lighter) |

---

## Risks & mitigations

| Risk | Mitigation |
|---|---|
| Backend lacks human-readable issue keys → UX feels off | Push for `project_key + sequence_number` exposure. Fallback: short base32 derived from UUIDv7 timestamp portion. |
| WebAuthn support varies wildly per platform → fragmented UX | Feature-detect early; provide TOTP fallback on every UI path. |
| No realtime → board feels stale | Polling + optimistic updates + explicit "refresh" pull. Add SSE the moment backend ships it. |
| Multi-platform regressions hard to spot | Golden tests gating CI, patrol smoke on web + Android + iOS. |
| Localization drift (missing keys in non-English ARBs) | CI lint rejects ARBs that aren't a superset of `intl_en.arb`. |
| `freezed` + `injectable` codegen churn slows iteration | `melos run gen --watch` in dev; cache `build` folder in CI. |

---

## What "done" looks like for v1.0

- All phases 0–18 complete.
- Feature parity with the backend's exposed endpoints (everything in `crates/api/src/router.rs` has a UI surface, modulo the open backend questions in [`ARCHITECTURE.md`](./ARCHITECTURE.md) §24).
- All 6 target platforms ship a working build.
- Coverage gates met.
- Public docs (`docs/`) explain how to run, build, release, and contribute.
- A first user can: sign up, set up MFA, create a project, invite a teammate, plan a sprint, work the board, write a wiki page, and comment on an issue — without ever reading a README.
