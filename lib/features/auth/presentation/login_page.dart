import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intellipilot/app/branding/brand_logo.dart';
import 'package:intellipilot/app/branding/branding_cubit.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/router/app_router.dart';
import 'package:intellipilot/app/session/session_bloc.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/io/url_opener.dart';
import 'package:intellipilot/core/network/api_config.dart';
import 'package:intellipilot/core/network/server_endpoint.dart';
import 'package:intellipilot/core/network/tls/cert_trust.dart';
import 'package:intellipilot/core/ui/full_page_navigation.dart';
import 'package:intellipilot/features/accounts/presentation/add_account_notice.dart';
import 'package:intellipilot/features/accounts/presentation/signed_in_accounts.dart';
import 'package:intellipilot/features/auth/data/dtos/auth_dtos.dart';
import 'package:intellipilot/features/auth/data/dtos/sso_dtos.dart';
import 'package:intellipilot/features/auth/domain/auth_repository.dart';
import 'package:intellipilot/features/auth/presentation/auth_validators.dart';
import 'package:intellipilot/features/auth/presentation/cubits/login_cubit.dart';
import 'package:intellipilot/features/auth/presentation/sso_device_dialog.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';
import 'package:reactive_forms/reactive_forms.dart';

/// Width at/above which the two-pane "split hero" layout is shown.
const double _kWideBreakpoint = 840;

/// Whether to run the continuous (looping) background/logo animations.
///
/// Suppressed under the widget-test binding, where an always-scheduled frame
/// would make `pumpAndSettle` time out. One-shot and implicit animations are
/// unaffected. In the real app the binding is a [WidgetsFlutterBinding].
final bool _kContinuousAnimations =
    WidgetsBinding.instance is WidgetsFlutterBinding;

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<LoginCubit>(
      create: (_) => LoginCubit(
        repo: getIt<AuthRepository>(),
        session: getIt<SessionBloc>(),
      ),
      child: const _LoginView(),
    );
  }
}

class _LoginView extends StatefulWidget {
  const _LoginView();

  @override
  State<_LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<_LoginView>
    with SingleTickerProviderStateMixin {
  late final FormGroup _form;
  late final AnimationController _entrance;

  /// Public auth configuration, for the single-sign-on buttons and whether the
  /// password form is offered. Fetched here rather than read from
  /// [BrandingCubit] — that one loads once for the app's lifetime, and a
  /// provider an administrator enabled after startup must still show up on the
  /// next visit to this screen.
  AuthConfig? _config;

  /// Set when the user asks for the password form on a deployment that hides
  /// it. The form is never removed outright: a superadmin holding a local
  /// password is the way back in when the identity provider is misconfigured,
  /// and the server lets them through regardless of this switch.
  bool _passwordFormRevealed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadConfig());
    _form = FormGroup({
      'email': FormControl<String>(validators: AuthValidators.loginIdentifier),
      'password': FormControl<String>(validators: AuthValidators.password),
    });
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    // Kick off the staggered entrance after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _entrance.forward();
    });
  }

  Future<void> _loadConfig() async {
    final res = await getIt<AuthRepository>().authConfig();
    if (!mounted) return;
    res.when(
      // A failure here leaves `_config` null, which renders exactly as a
      // server with no providers: the password form, and nothing else. The
      // login screen must not go blank because one extra call did not answer.
      ok: (c) => setState(() => _config = c),
      err: (_) {},
    );
  }

  /// Start a sign-in with [provider].
  ///
  /// On web this leaves the app: the browser has to visit the identity
  /// provider and return to the server's callback, which sets the session
  /// cookie before handing control back. On desktop and mobile there is no
  /// redirect to come back to, so the device-code flow is used instead.
  Future<void> _startSso(SsoProvider provider) async {
    if (kIsWeb) {
      final base = getIt<ApiConfig>().baseUrl.replaceAll(RegExp(r'/+$'), '');
      navigateWholePage('$base/api/v1/auth/oidc/${provider.slug}/start');
      return;
    }
    final outcome = await showSsoDeviceDialog(context, provider: provider);
    if (!mounted) return;
    switch (outcome) {
      case SsoDeviceOutcomeSignedIn(:final tokens):
        getIt<SessionBloc>().add(SessionEstablished(tokens));
        if (_isAddAccountMode(context)) context.go(Routes.projects);
      case SsoDeviceOutcomeAbandoned() || SsoDeviceOutcomeLinked() || null:
        break;
    }
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_form.valid) {
      _form.markAllAsTouched();
      return;
    }
    unawaited(
      context.read<LoginCubit>().submit(
        email: _form.control('email').value as String,
        password: _form.control('password').value as String,
      ),
    );
  }

  /// Fade + slide-up entrance for [child], staggered by [order]. A no-op when
  /// the OS requests reduced motion.
  Widget _entranceItem(int order, bool reduceMotion, Widget child) {
    if (reduceMotion) return child;
    final start = (order * 0.09).clamp(0.0, 0.5);
    final anim = CurvedAnimation(
      parent: _entrance,
      curve: Interval(
        start,
        (start + 0.5).clamp(0.0, 1.0),
        curve: Curves.easeOutCubic,
      ),
    );
    return FadeTransition(
      opacity: anim,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.08),
          end: Offset.zero,
        ).animate(anim),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (reduceMotion) _entrance.value = 1;
    return BlocBuilder<BrandingCubit, Branding>(
      bloc: getIt<BrandingCubit>(),
      builder: (context, branding) {
        final title = branding.appName ?? t.appTitle;
        return Scaffold(
          body: BlocListener<LoginCubit, LoginState>(
            listener: (context, state) {
              if (state is LoginSucceeded) {
                // Normally the guard redirects an authenticated user off
                // /login, which is what moves us on. In add-account mode the
                // guard deliberately lets us stay, so nothing would navigate —
                // this has to do it explicitly.
                if (_isAddAccountMode(context)) {
                  context.go(Routes.projects);
                }
              }
            },
            child: Stack(
              children: [
                Positioned.fill(
                  child: _AnimatedBlobBackground(reduceMotion: reduceMotion),
                ),
                Positioned.fill(
                  child: ReactiveForm(
                    formGroup: _form,
                    child: AutofillGroup(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final wide = constraints.maxWidth >= _kWideBreakpoint;
                          return wide
                              ? _wideLayout(
                                  context,
                                  t,
                                  branding,
                                  title,
                                  reduceMotion,
                                )
                              : _narrowLayout(
                                  context,
                                  t,
                                  branding,
                                  title,
                                  reduceMotion,
                                );
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---- Wide: two-pane split hero --------------------------------------------
  Widget _wideLayout(
    BuildContext context,
    AppLocalizations t,
    Branding branding,
    String title,
    bool reduceMotion,
  ) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(48),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _entranceItem(
                    0,
                    reduceMotion,
                    _FloatingLogo(size: 104, reduceMotion: reduceMotion),
                  ),
                  const SizedBox(height: 28),
                  _entranceItem(
                    1,
                    reduceMotion,
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _entranceItem(
                    2,
                    reduceMotion,
                    Text(
                      t.loginSubtitle,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Form panel: opaque surface so the form stays crisp over the blobs.
        DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 32,
                offset: const Offset(-8, 0),
              ),
            ],
          ),
          child: SizedBox(
            width: 460,
            height: double.infinity,
            child: _ScrollableCenter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _entranceItem(
                    2,
                    reduceMotion,
                    Text(
                      t.actionSignIn,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  ..._formChildren(context, t, branding, reduceMotion),
                  const SizedBox(height: 24),
                  const _LoginFooter(),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ---- Narrow: centered card over the blobs ---------------------------------
  Widget _narrowLayout(
    BuildContext context,
    AppLocalizations t,
    Branding branding,
    String title,
    bool reduceMotion,
  ) {
    final theme = Theme.of(context);
    return _ScrollableCenter(
      maxWidth: 440,
      child: _entranceItem(
        0,
        reduceMotion,
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: theme.colorScheme.outlineVariant),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 28,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: _FloatingLogo(size: 84, reduceMotion: reduceMotion),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                t.loginSubtitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              ..._formChildren(context, t, branding, reduceMotion),
              const SizedBox(height: 16),
              const _LoginFooter(),
            ],
          ),
        ),
      ),
    );
  }

  /// The shared form fields (email, password, actions). Each row is wrapped in
  /// the staggered entrance so it cascades in on open.
  List<Widget> _formChildren(
    BuildContext context,
    AppLocalizations t,
    Branding branding,
    bool reduceMotion,
  ) {
    final addingAccount = _isAddAccountMode(context);
    return [
      // Adding a second account: make it obvious this is not a re-login, and
      // give a way out — the user is still signed in, so being stranded on a
      // login screen with no exit would be a trap.
      if (addingAccount) ...[
        const AddAccountNotice(),
        const SizedBox(height: 16),
      ],
      // Which server this is, and the way back to step ① of the wizard.
      // Deliberately the first thing in the form: it lived in the legal footer
      // at first, which put it below the fold inside a scroll view and made it
      // one of five similar links — unfindable exactly when someone has
      // mistyped their server and needs it.
      //
      // Desktop/mobile only: on web the origin IS the server, and a build
      // pinned via --dart-define is not the user's to change.
      if (!kIsWeb && !getIt<ServerEndpoint>().isPinnedAtBuildTime) ...[
        const _ServerBanner(),
        const SizedBox(height: 16),
      ],
      // Accounts already signed in on this device. Above the credential fields
      // because on this screen it is usually the answer: the login screen is
      // reachable mid-add-account, after a session expired, and after a cold
      // start whose stored token was dead — in all three the other accounts
      // still work, and re-typing a password is the long way round.
      const SignedInAccounts(),
      if (branding.appMessage != null) ...[
        _entranceItem(
          3,
          reduceMotion,
          _AuthInfoBanner(text: branding.appMessage!),
        ),
        const SizedBox(height: 16),
      ],
      // A failure from the redirect flow comes back as a query parameter,
      // because the browser is mid-navigation and cannot be handed a problem
      // document to read.
      if (_ssoErrorCode(context) != null) ...[
        _AuthErrorBanner.message(_ssoErrorMessage(t, _ssoErrorCode(context)!)),
        const SizedBox(height: 12),
      ],
      // Sign-in buttons first: on a deployment with single sign-on they are
      // the intended route, and burying them under the form they replace would
      // be an odd thing to do.
      ..._ssoChildren(context, t, reduceMotion),
      if (!_showPasswordForm) ...[
        _entranceItem(
          6,
          reduceMotion,
          Center(
            child: TextButton(
              onPressed: () => setState(() => _passwordFormRevealed = true),
              child: Text(t.ssoAdministratorSignIn),
            ),
          ),
        ),
        const SizedBox(height: 4),
        _entranceItem(6, reduceMotion, const _RegisterLink()),
      ],
      if (_showPasswordForm) ...[
        // Stable keys: the rows above these fields can appear asynchronously
        // (branding banner), and keyless fields would then be re-matched to each
        // other's element/state by position, cross-binding the two controls.
        _entranceItem(
          3,
          reduceMotion,
          _GlowField(
            key: const ValueKey('login-email-field'),
            child: ReactiveTextField<String>(
              formControlName: 'email',
              autofillHints: const [AutofillHints.username],
              decoration: InputDecoration(
                labelText: t.fieldEmailOrUsername,
                prefixIcon: const Icon(Icons.person_outline),
              ),
              validationMessages: {
                ValidationMessage.required: (_) => t.errFieldRequired,
                ValidationMessage.maxLength: (_) => t.errTooLong,
              },
            ),
          ),
        ),
        const SizedBox(height: 12),
        _entranceItem(
          4,
          reduceMotion,
          _GlowField(
            key: const ValueKey('login-password-field'),
            child: ReactiveTextField<String>(
              formControlName: 'password',
              obscureText: true,
              autofillHints: const [AutofillHints.password],
              decoration: InputDecoration(
                labelText: t.fieldPassword,
                prefixIcon: const Icon(Icons.lock_outline),
              ),
              validationMessages: {
                ValidationMessage.required: (_) => t.errFieldRequired,
                ValidationMessage.minLength: (_) => t.errPasswordMinLength,
              },
            ),
          ),
        ),
        _entranceItem(
          4,
          reduceMotion,
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => context.goNamed('forgot_password'),
              child: Text(t.linkForgotPassword),
            ),
          ),
        ),
        const SizedBox(height: 8),
        _entranceItem(
          5,
          reduceMotion,
          BlocBuilder<LoginCubit, LoginState>(
            builder: (context, state) => _SubmitButton(
              busy: state is LoginSubmitting,
              label: t.actionSignIn,
              onPressed: _submit,
            ),
          ),
        ),
        const SizedBox(height: 16),
        BlocBuilder<LoginCubit, LoginState>(
          builder: (_, state) {
            if (state is LoginFailed) {
              return _AuthErrorBanner(failure: state.failure);
            }
            if (state is LoginMfaChallenged) {
              return _AuthInfoBanner(text: t.loginMfaNotice);
            }
            return const SizedBox.shrink();
          },
        ),
        const SizedBox(height: 8),
        _entranceItem(
          6,
          reduceMotion,
          TextButton.icon(
            icon: const Icon(Icons.fingerprint, size: 18),
            onPressed: () => context.goNamed('passkey_sign_in'),
            label: Text(t.linkSignInWithPasskey),
          ),
        ),
        const SizedBox(height: 4),
        _entranceItem(6, reduceMotion, const _RegisterLink()),
      ],
    ];
  }

  /// Whether the email/password fields are shown.
  ///
  /// Hidden only when the deployment asked for it *and* it has a provider to
  /// offer instead — a server that switched password login off but has no
  /// working provider would otherwise render a login screen with no way to log
  /// in.
  bool get _showPasswordForm {
    final c = _config;
    if (c == null) return true;
    if (!c.localPasswordLoginDisabled) return true;
    // Judged on the providers *this client* can actually use, not on the ones
    // the server has configured: a native app faced with a web-only provider
    // would otherwise get a screen with no buttons and no form.
    if (_usableProviders.isEmpty) return true;
    return _passwordFormRevealed;
  }

  /// Providers this client can offer.
  ///
  /// The redirect flow needs a browser to come back to, which desktop and
  /// mobile do not have — so off the web, only providers whose device flow is
  /// available are shown.
  List<SsoProvider> get _usableProviders {
    final all = _config?.ssoProviders ?? const <SsoProvider>[];
    return kIsWeb
        ? all
        : all.where((p) => p.deviceFlowEnabled).toList(growable: false);
  }

  /// The sign-in buttons, one per usable provider.
  List<Widget> _ssoChildren(
    BuildContext context,
    AppLocalizations t,
    bool reduceMotion,
  ) {
    final usable = _usableProviders;
    if (usable.isEmpty) return const [];
    return [
      for (final p in usable) ...[
        _entranceItem(
          3,
          reduceMotion,
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            icon: const Icon(Icons.shield_outlined, size: 18),
            label: Text(t.ssoSignInWith(p.displayName)),
            onPressed: () => unawaited(_startSso(p)),
          ),
        ),
        const SizedBox(height: 8),
      ],
      if (_showPasswordForm) ...[
        const SizedBox(height: 4),
        _entranceItem(3, reduceMotion, _OrDivider(label: t.ssoOrDivider)),
        const SizedBox(height: 12),
      ],
    ];
  }

  String? _ssoErrorCode(BuildContext context) {
    final code = GoRouterState.of(context).uri.queryParameters['sso_error'];
    return (code == null || code.isEmpty) ? null : code;
  }

  /// Turn a server error code into something a person can act on.
  ///
  /// The conflict case carries the actual instruction — sign in normally and
  /// connect from Security — because that is a dead end otherwise: the user
  /// has a working account and an identity provider that will never reach it.
  String _ssoErrorMessage(AppLocalizations t, String code) => switch (code) {
    'email_conflict' => t.ssoErrorEmailConflict,
    'email_unverified' => t.ssoErrorEmailUnverified,
    'provisioning_disabled' => t.ssoErrorProvisioningDisabled,
    'already_linked' => t.ssoErrorAlreadyLinked,
    'account_banned' => t.ssoErrorAccountBanned,
    'account_inactive' => t.ssoErrorAccountInactive,
    'oidc_unavailable' => t.ssoErrorUnavailable,
    'oidc_misconfigured' => t.ssoErrorMisconfigured,
    'invalid_state' => t.ssoErrorExpired,
    'provider_refused' => t.ssoErrorRefused,
    _ => t.ssoErrorGeneric,
  };
}

/// A horizontal rule with a word in the middle, separating the single-sign-on
/// buttons from the credential form.
class _OrDivider extends StatelessWidget {
  const _OrDivider({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        const Expanded(child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const Expanded(child: Divider()),
      ],
    );
  }
}

/// A vertically-centered, scrollable column for one of the login panels.
class _ScrollableCenter extends StatelessWidget {
  const _ScrollableCenter({required this.child, this.maxWidth = 360});
  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      ),
    );
  }
}

/// Slowly drifting, theme-coloured radial "blobs". CPU-cheap: three filled
/// radial gradients on a single slow loop, isolated in a [RepaintBoundary] and
/// with no backdrop blur. Renders statically when reduced motion is requested.
class _AnimatedBlobBackground extends StatefulWidget {
  const _AnimatedBlobBackground({required this.reduceMotion});
  final bool reduceMotion;

  @override
  State<_AnimatedBlobBackground> createState() =>
      _AnimatedBlobBackgroundState();
}

class _AnimatedBlobBackgroundState extends State<_AnimatedBlobBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  bool get _animate => !widget.reduceMotion && _kContinuousAnimations;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    );
    if (_animate) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final a = dark ? 0.34 : 0.28;
    final colors = [
      scheme.primary.withValues(alpha: a),
      scheme.tertiary.withValues(alpha: a * 0.9),
      scheme.secondary.withValues(alpha: a * 0.8),
    ];
    final painter = _BlobPainter(t: _animate ? _c.value : 0.12, colors: colors);
    return RepaintBoundary(
      child: _animate
          ? AnimatedBuilder(
              animation: _c,
              builder: (context, _) => CustomPaint(
                painter: _BlobPainter(t: _c.value, colors: colors),
                size: Size.infinite,
              ),
            )
          : CustomPaint(painter: painter, size: Size.infinite),
    );
  }
}

class _BlobPainter extends CustomPainter {
  _BlobPainter({required this.t, required this.colors});
  final double t;
  final List<Color> colors;

  // baseX, baseY (fraction of size), radius factor (× shortest side), phase.
  static const _base = [
    [0.18, 0.22, 0.95, 0.0],
    [0.84, 0.30, 0.85, 2.1],
    [0.55, 0.85, 1.05, 4.2],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final shortest = math.min(size.width, size.height);
    final tau = t * 2 * math.pi;
    for (var i = 0; i < _base.length; i++) {
      final b = _base[i];
      final cx = (b[0] + 0.06 * math.sin(tau + b[3])) * size.width;
      final cy = (b[1] + 0.06 * math.cos(tau * 0.8 + b[3])) * size.height;
      final radius = b[2] * shortest * (0.55 + 0.05 * math.sin(tau + b[3]));
      final center = Offset(cx, cy);
      final color = colors[i % colors.length];
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [color, color.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: center, radius: radius));
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(_BlobPainter old) => old.t != t || old.colors != colors;
}

/// The app logo with a gentle, continuous "float" (tiny vertical bob + scale).
/// Static when reduced motion is requested.
class _FloatingLogo extends StatefulWidget {
  const _FloatingLogo({required this.size, required this.reduceMotion});
  final double size;
  final bool reduceMotion;

  @override
  State<_FloatingLogo> createState() => _FloatingLogoState();
}

class _FloatingLogoState extends State<_FloatingLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  bool get _animate => !widget.reduceMotion && _kContinuousAnimations;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    );
    if (_animate) _c.repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final logo = BrandLogo(size: widget.size, borderRadius: 20);
    if (!_animate) return logo;
    return AnimatedBuilder(
      animation: CurvedAnimation(parent: _c, curve: Curves.easeInOut),
      builder: (context, child) {
        final v = Curves.easeInOut.transform(_c.value);
        return Transform.translate(
          offset: Offset(0, -3 + v * 6),
          child: Transform.scale(scale: 1.0 + v * 0.03, child: child),
        );
      },
      child: logo,
    );
  }
}

/// Wraps an input field with a soft accent glow while any descendant is focused.
class _GlowField extends StatefulWidget {
  const _GlowField({required this.child, super.key});
  final Widget child;

  @override
  State<_GlowField> createState() => _GlowFieldState();
}

class _GlowFieldState extends State<_GlowField> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (f) {
        if (f != _focused) setState(() => _focused = f);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: _focused
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.26),
                    blurRadius: 16,
                    spreadRadius: 1,
                  ),
                ]
              : const [],
        ),
        child: widget.child,
      ),
    );
  }
}

/// Primary sign-in button: scales slightly on press and cross-fades into a
/// spinner while submitting.
class _SubmitButton extends StatefulWidget {
  const _SubmitButton({
    required this.busy,
    required this.label,
    required this.onPressed,
  });
  final bool busy;
  final String label;
  final VoidCallback onPressed;

  @override
  State<_SubmitButton> createState() => _SubmitButtonState();
}

class _SubmitButtonState extends State<_SubmitButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) {
        if (!widget.busy) setState(() => _pressed = true);
      },
      onPointerUp: (_) {
        if (_pressed) setState(() => _pressed = false);
      },
      onPointerCancel: (_) {
        if (_pressed) setState(() => _pressed = false);
      },
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        child: FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: widget.busy ? null : widget.onPressed,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: widget.busy
                ? const SizedBox.square(
                    key: ValueKey('busy'),
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(widget.label, key: const ValueKey('label')),
          ),
        ),
      ),
    );
  }
}

/// Self-service signup link, shown only when the server reports open
/// registration is enabled. Hidden while loading or on error, so a closed
/// instance never advertises a signup path that the backend would reject.
class _RegisterLink extends StatefulWidget {
  const _RegisterLink();

  @override
  State<_RegisterLink> createState() => _RegisterLinkState();
}

class _RegisterLinkState extends State<_RegisterLink> {
  bool _open = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final res = await getIt<AuthRepository>().authConfig();
    if (!mounted) return;
    res.when(
      ok: (c) => setState(() => _open = c.openRegistration),
      err: (_) {},
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_open) return const SizedBox.shrink();
    final t = AppLocalizations.of(context);
    return TextButton(
      onPressed: () => context.goNamed('register'),
      child: Text(t.linkCreateAccount),
    );
  }
}

class _AuthErrorBanner extends StatelessWidget {
  const _AuthErrorBanner({required this.failure}) : text = null;

  /// For a failure that arrives as text rather than as an [AppFailure] — the
  /// single-sign-on redirect reports itself through a query parameter, since
  /// the browser is mid-navigation and has no response body to read.
  const _AuthErrorBanner.message(String message)
    : failure = null,
      text = message;

  final AppFailure? failure;
  final String? text;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context).colorScheme;
    final message =
        text ??
        switch (failure) {
          UnauthorizedFailure() => t.errInvalidCredentials,
          NetworkFailure() => t.errNetwork,
          RateLimitedFailure() => t.errTooManyAttempts,
          ValidationFailure() => t.errValidation,
          ServerFailure() => t.errServer,
          _ => t.errUnknown,
        };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: theme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: theme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthInfoBanner extends StatelessWidget {
  const _AuthInfoBanner({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: theme.onSecondaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: theme.onSecondaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}

/// Developer attribution footer, shown on the login screen only. Links open in
/// a new tab via [openExternalUrl]; native targets degrade to a no-op.
class _LoginFooter extends StatelessWidget {
  const _LoginFooter();

  static const _website = 'https://intellisoftalpin.com';
  static const _repo = 'https://github.com/intellisoftalpin/intellipilot';
  static const _license =
      'https://github.com/intellisoftalpin/intellipilot/blob/main/LICENSE';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final year = DateTime.now().year;
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 4,
      children: [
        Text('© 2025–$year IntelliSoftAlpin', style: muted),
        _FooterLink(
          label: 'intellisoftalpin.com',
          onTap: () => openExternalUrl(_website),
        ),
        _FooterLink(label: 'GitHub', onTap: () => openExternalUrl(_repo)),
        _FooterLink(
          label: 'MIT License',
          onTap: () => openExternalUrl(_license),
        ),
      ],
    );
  }
}

/// Whether the login screen is in "add another account" mode.
///
/// Tolerates the absence of a GoRouter ancestor: the auth pages are pumped
/// directly inside a bare Navigator by the widget tests, and
/// `GoRouterState.of` requires a router. No router means no add-account flag,
/// which is the correct answer for a standalone LoginPage.
bool _isAddAccountMode(BuildContext context) {
  final router = GoRouter.maybeOf(context);
  if (router == null) return false;
  return Routes.isAddAccount(
    router.routerDelegate.currentConfiguration.uri,
  );
}

/// The server this app is pointed at, with a way back to the connect step.
///
/// Rendered as a tonal row at the top of the sign-in form rather than a link in
/// the footer: the single most likely reason to want it is having just typed the
/// wrong address, and at that moment it has to be impossible to miss.
///
/// Also surfaces when the connection rests on a certificate the user chose to
/// trust — that decision bypasses CA validation for this host, so it stays
/// visible rather than being made once and forgotten.
class _ServerBanner extends StatelessWidget {
  const _ServerBanner();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final endpoint = getIt<ServerEndpoint>();
    final url = endpoint.effective;
    if (url.isEmpty) return const SizedBox.shrink();
    final uri = Uri.tryParse(url);
    final host = uri == null
        ? url
        : '${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
    final pinned =
        uri != null &&
        getIt<CertPinStore>().hasPinFor(
          uri.host,
          uri.hasPort ? uri.port : 443,
        );
    final cleartext = uri?.scheme == 'http';

    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
        child: Row(
          children: [
            Icon(
              Icons.dns_outlined,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                t.connectConnectedTo(host),
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (cleartext)
              Tooltip(
                message: t.connectCleartextWarning,
                child: Icon(
                  Icons.lock_open_outlined,
                  size: 14,
                  color: theme.colorScheme.error,
                ),
              ),
            if (pinned)
              Tooltip(
                message: t.connectTrustedCertNotice,
                child: Icon(
                  Icons.verified_user_outlined,
                  size: 14,
                  color: theme.colorScheme.tertiary,
                ),
              ),
            const SizedBox(width: 4),
            TextButton(
              // Stay inside an add-account run: dropping the flag here would
              // leave the previous account suspended with no way back, and the
              // next connect would wipe caches it must preserve.
              onPressed: () => context.go(
                _isAddAccountMode(context)
                    ? Routes.addAccount()
                    : Routes.connect,
              ),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: Text(t.connectChange),
            ),
          ],
        ),
      ),
    );
  }
}

class _FooterLink extends StatelessWidget {
  const _FooterLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
      ),
    );
  }
}
