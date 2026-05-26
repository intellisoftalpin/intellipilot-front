import 'package:flutter/material.dart';
import 'package:intellipilot/core/error/app_failure.dart';

class ErrorView extends StatelessWidget {
  const ErrorView({
    required this.failure,
    this.onRetry,
    this.retryLabel,
    super.key,
  });

  final AppFailure failure;
  final VoidCallback? onRetry;
  final String? retryLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = _titleFor(failure);
    final detail = failure.problem?.detail ?? failure.problem?.title;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 56,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              if (detail != null) ...[
                const SizedBox(height: 8),
                Text(
                  detail,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              if (onRetry != null) ...[
                const SizedBox(height: 16),
                FilledButton.tonal(
                  onPressed: onRetry,
                  child: Text(retryLabel ?? 'Retry'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _titleFor(AppFailure f) => switch (f) {
    NetworkFailure() => 'You appear to be offline',
    UnauthorizedFailure() => 'Your session has expired',
    ForbiddenFailure() => "You don't have permission to do that",
    NotFoundFailure() => "We couldn't find that",
    ValidationFailure() => 'Please correct the highlighted fields',
    ConflictFailure() => 'Someone else changed this — please reload',
    RateLimitedFailure() => "You're going a bit too fast",
    ServerFailure() => 'Something went wrong on our end',
    UnknownFailure() => 'Something went wrong',
  };
}
