import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/l10n/locale_cubit.dart';
import 'package:intellipilot/core/datetime/timezones.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/features/profile/domain/profile_repository.dart';
import 'package:intellipilot/features/profile/presentation/cubits/profile_cubit.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ProfileCubit>(
      create: (_) => ProfileCubit(
        repo: getIt<ProfileRepository>(),
        locale: getIt<LocaleCubit>(),
      )..load(),
      child: const _ProfileView(),
    );
  }
}

class _ProfileView extends StatefulWidget {
  const _ProfileView();

  @override
  State<_ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<_ProfileView> {
  final _fullNameController = TextEditingController();
  final _timezoneController = TextEditingController();
  bool _seeded = false;

  @override
  void dispose() {
    _fullNameController.dispose();
    _timezoneController.dispose();
    super.dispose();
  }

  void _seedFromState(ProfileLoaded state) {
    if (_seeded) return;
    _fullNameController.text = state.profile.fullName;
    _timezoneController.text = state.profile.timezone;
    _seeded = true;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.profileTitle)),
      body: BlocConsumer<ProfileCubit, ProfileState>(
        listenWhen: (prev, next) =>
            next is ProfileLoaded && next.savedAt != null,
        listener: (context, state) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(t.profileSavedSnack)));
        },
        builder: (context, state) {
          if (state is ProfileLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is ProfileLoadFailed) {
            return _LoadError(failure: state.failure);
          }
          if (state is ProfileLoaded) {
            _seedFromState(state);
            return _ProfileForm(
              state: state,
              fullNameController: _fullNameController,
              timezoneController: _timezoneController,
              onSave: () {
                context.read<ProfileCubit>().save(
                  fullName: _fullNameController.text.trim(),
                  // Language is driven by the app-wide selector in Settings;
                  // preserve whatever the account already had.
                  lang: state.profile.lang,
                  timezone: _timezoneController.text.trim(),
                );
              },
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.failure});
  final AppFailure failure;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(t.profileLoadFailed),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => context.read<ProfileCubit>().load(),
            child: Text(t.actionRetry),
          ),
        ],
      ),
    );
  }
}

class _ProfileForm extends StatelessWidget {
  const _ProfileForm({
    required this.state,
    required this.fullNameController,
    required this.timezoneController,
    required this.onSave,
  });
  final ProfileLoaded state;
  final TextEditingController fullNameController;
  final TextEditingController timezoneController;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.alternate_email),
              title: Text(state.profile.email),
              subtitle: Text('@${state.profile.username}'),
            ),
            const Divider(),
            const SizedBox(height: 8),
            TextField(
              controller: fullNameController,
              decoration: InputDecoration(
                labelText: t.fieldFullName,
                prefixIcon: const Icon(Icons.badge_outlined),
              ),
            ),
            const SizedBox(height: 12),
            DropdownMenu<String>(
              controller: timezoneController,
              initialSelection: kTimezones.contains(timezoneController.text)
                  ? timezoneController.text
                  : null,
              enableFilter: true,
              requestFocusOnTap: true,
              expandedInsets: EdgeInsets.zero,
              menuHeight: 320,
              leadingIcon: const Icon(Icons.public),
              label: Text(t.profileTimezoneLabel),
              helperText: t.profileTimezoneHint,
              dropdownMenuEntries: [
                for (final tz in kTimezones)
                  DropdownMenuEntry<String>(value: tz, label: tz),
              ],
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: state.saving ? null : onSave,
              child: state.saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(t.actionSave),
            ),
            if (state.lastError != null) ...[
              const SizedBox(height: 12),
              Text(
                t.profileSaveFailed,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
