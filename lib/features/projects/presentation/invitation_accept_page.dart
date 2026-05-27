import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/router/app_router.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/features/projects/domain/projects_repository.dart';
import 'package:intellipilot/features/projects/presentation/cubits/accept_invitation_cubit.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

class InvitationAcceptPage extends StatelessWidget {
  const InvitationAcceptPage({required this.token, super.key});

  final String token;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<AcceptInvitationCubit>(
      create: (_) =>
          AcceptInvitationCubit(getIt<ProjectsRepository>())..accept(token),
      child: const _AcceptView(),
    );
  }
}

class _AcceptView extends StatelessWidget {
  const _AcceptView();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.invitationAcceptTitle)),
      body: BlocConsumer<AcceptInvitationCubit, AcceptInvitationState>(
        listenWhen: (prev, next) => next is AcceptInvitationAccepted,
        listener: (context, state) {
          if (state is AcceptInvitationAccepted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(t.invitationAcceptSuccessSnack)),
            );
            context.go(Routes.projectDetailFor(state.projectId));
          }
        },
        builder: (context, state) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: switch (state) {
                AcceptInvitationRunning() => const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Accepting…'),
                  ],
                ),
                AcceptInvitationAccepted() => const SizedBox.shrink(),
                AcceptInvitationFailed(:final failure) =>
                  _FailureView(failure: failure),
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _FailureView extends StatelessWidget {
  const _FailureView({required this.failure});
  final AppFailure failure;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final message = switch (failure) {
      ConflictFailure() => t.invitationAcceptExpired,
      NotFoundFailure() => t.invitationAcceptNotFound,
      _ => t.errUnknown,
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.error_outline,
          size: 48,
          color: Theme.of(context).colorScheme.error,
        ),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => context.go(Routes.projects),
          child: Text(t.actionGoToProjects),
        ),
      ],
    );
  }
}
