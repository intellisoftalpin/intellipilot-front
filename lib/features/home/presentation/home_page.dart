import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/router/app_router.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/network/api_client.dart';
import 'package:intellipilot/core/widgets/app_scaffold.dart';
import 'package:intellipilot/core/widgets/error_view.dart';
import 'package:intellipilot/core/widgets/loading_indicator.dart';
import 'package:intellipilot/core/widgets/primary_button.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// Phase-1 placeholder home page. Demonstrates the foundation layers
/// end-to-end by running a real `GET /health/live` through the interceptor
/// pipeline. Replaced in later phases by the project-list home.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  _HealthStatus _status = const _HealthStatus.idle();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return AppScaffold(
      title: Text(l10n.appTitle),
      actions: [
        IconButton(
          icon: const Icon(Icons.settings_outlined),
          tooltip: l10n.settingsTitle,
          onPressed: () => context.push(Routes.settings),
        ),
      ],
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.homeWelcomeTitle, style: theme.textTheme.headlineMedium),
            const SizedBox(height: 12),
            Text(l10n.homeWelcomeBody, style: theme.textTheme.bodyLarge),
            const SizedBox(height: 24),
            Text(
              l10n.homeHealthCheckSection,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            PrimaryButton(
              label: l10n.homePingButton,
              icon: Icons.cloud_outlined,
              loading: _status.loading,
              onPressed: _ping,
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _StatusView(status: _status, onRetry: _ping),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _ping() async {
    setState(() => _status = const _HealthStatus.loading());
    final client = getIt<ApiClient>();
    final result = await client.get('/health/live');
    if (!mounted) return;
    setState(() {
      _status = result.when(
        ok: (response) => _HealthStatus.ok(response.statusCode ?? 0),
        err: (failure) => _HealthStatus.error(failure),
      );
    });
  }
}

class _StatusView extends StatelessWidget {
  const _StatusView({required this.status, required this.onRetry});
  final _HealthStatus status;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    if (status.idle) {
      return Text(
        l10n.homePingHint,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }
    if (status.loading) return const LoadingIndicator();
    if (status.failure != null) {
      return ErrorView(failure: status.failure!, onRetry: onRetry);
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.check_circle, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(child: Text(l10n.homePingOk(status.statusCode ?? 0))),
          ],
        ),
      ),
    );
  }
}

class _HealthStatus {
  const _HealthStatus._({
    required this.idle,
    required this.loading,
    this.statusCode,
    this.failure,
  });

  const _HealthStatus.idle() : this._(idle: true, loading: false);

  const _HealthStatus.loading() : this._(idle: false, loading: true);

  const _HealthStatus.ok(int code)
    : this._(idle: false, loading: false, statusCode: code);

  const _HealthStatus.error(AppFailure f)
    : this._(idle: false, loading: false, failure: f);

  final bool idle;
  final bool loading;
  final int? statusCode;
  final AppFailure? failure;
}
