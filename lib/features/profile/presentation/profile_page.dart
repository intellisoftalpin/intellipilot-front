import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/l10n/locale_cubit.dart';
import 'package:intellipilot/core/datetime/timezones.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/io/file_picker.dart';
import 'package:intellipilot/core/widgets/user_avatar.dart';
import 'package:intellipilot/features/profile/domain/profile_repository.dart';
import 'package:intellipilot/features/profile/presentation/cubits/profile_cubit.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// Compact curated emoji sets (avatar + mood) — a full keyboard is overkill.
const _avatarEmojis = [
  '😀',
  '😎',
  '🦊',
  '🐱',
  '🐼',
  '🚀',
  '🌟',
  '🔥',
  '🌸',
  '🐙',
  '🦁',
  '🐲',
  '🍀',
  '🎯',
  '⚡',
  '🧠',
];
const _moodEmojis = [
  '😀',
  '🙂',
  '😐',
  '😴',
  '🤒',
  '🤯',
  '🎉',
  '☕',
  '🔥',
  '💪',
  '🧠',
  '🌴',
];

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ProfileCubit>(
      create: (_) {
        final c = ProfileCubit(
          repo: getIt<ProfileRepository>(),
          locale: getIt<LocaleCubit>(),
        );
        unawaited(c.load());
        return c;
      },
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
  final _mottoController = TextEditingController();
  final _moodTextController = TextEditingController();
  String _moodEmoji = '';
  bool _seeded = false;

  @override
  void dispose() {
    _fullNameController.dispose();
    _timezoneController.dispose();
    _mottoController.dispose();
    _moodTextController.dispose();
    super.dispose();
  }

  void _seedFromState(ProfileLoaded state) {
    if (_seeded) return;
    _fullNameController.text = state.profile.fullName;
    _timezoneController.text = state.profile.timezone;
    _mottoController.text = state.profile.card.motto;
    _moodTextController.text = state.profile.card.moodText;
    _moodEmoji = state.profile.card.moodEmoji;
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
              mottoController: _mottoController,
              moodTextController: _moodTextController,
              moodEmoji: _moodEmoji,
              onMoodEmojiChanged: (e) => setState(() => _moodEmoji = e),
              onSave: () {
                unawaited(
                  context.read<ProfileCubit>().save(
                    fullName: _fullNameController.text.trim(),
                    // Language is driven by the app-wide selector in Settings;
                    // preserve whatever the account already had.
                    lang: state.profile.lang,
                    timezone: _timezoneController.text.trim(),
                    motto: _mottoController.text.trim(),
                    moodEmoji: _moodEmoji,
                    moodText: _moodTextController.text.trim(),
                  ),
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
    required this.mottoController,
    required this.moodTextController,
    required this.moodEmoji,
    required this.onMoodEmojiChanged,
    required this.onSave,
  });
  final ProfileLoaded state;
  final TextEditingController fullNameController;
  final TextEditingController timezoneController;
  final TextEditingController mottoController;
  final TextEditingController moodTextController;
  final String moodEmoji;
  final ValueChanged<String> onMoodEmojiChanged;
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
            _AvatarEditor(state: state),
            const SizedBox(height: 16),
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
            TextField(
              controller: mottoController,
              maxLength: 140,
              decoration: InputDecoration(
                labelText: t.pfMotto,
                prefixIcon: const Icon(Icons.format_quote_outlined),
              ),
            ),
            const SizedBox(height: 4),
            Text(t.pfDailyMood, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(
              children: [
                _MoodEmojiButton(
                  emoji: moodEmoji,
                  onPick: onMoodEmojiChanged,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: moodTextController,
                    maxLength: 16,
                    decoration: InputDecoration(labelText: t.pfMoodStatus),
                  ),
                ),
              ],
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

/// Current avatar + upload / pick-emoji / reset actions.
class _AvatarEditor extends StatelessWidget {
  const _AvatarEditor({required this.state});
  final ProfileLoaded state;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cubit = context.read<ProfileCubit>();
    final busy = state.saving;
    return Row(
      children: [
        UserAvatar(user: state.profile.toRef(), size: 72, enableHover: false),
        const SizedBox(width: 16),
        Expanded(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                icon: const Icon(Icons.upload_outlined, size: 18),
                label: Text(t.pfUpload),
                onPressed: busy ? null : () => _upload(context, cubit),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.emoji_emotions_outlined, size: 18),
                label: Text(t.pfPickEmoji),
                onPressed: busy ? null : () => _pickEmoji(context, cubit),
              ),
              TextButton(
                onPressed: busy ? null : () => cubit.resetAvatar(),
                child: Text(t.pfReset),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _upload(BuildContext context, ProfileCubit cubit) async {
    final picked = await getIt<FilePicker>().pickSingleFile();
    if (picked == null) return;
    await cubit.uploadAvatar(
      filename: picked.name,
      bytes: picked.bytes,
      contentType: picked.contentType,
    );
  }

  Future<void> _pickEmoji(BuildContext context, ProfileCubit cubit) async {
    final t = AppLocalizations.of(context);
    final e = await _showEmojiPicker(context, _avatarEmojis, t.pfPickEmoji);
    if (e != null) await cubit.setEmojiAvatar(e);
  }
}

class _MoodEmojiButton extends StatelessWidget {
  const _MoodEmojiButton({required this.emoji, required this.onPick});
  final String emoji;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return OutlinedButton(
      onPressed: () async {
        final e = await _showEmojiPicker(context, _moodEmojis, t.pfDailyMood);
        if (e != null) onPick(e);
      },
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(56, 56),
        padding: EdgeInsets.zero,
      ),
      child: Text(
        emoji.isEmpty ? '🙂' : emoji,
        style: const TextStyle(fontSize: 24),
      ),
    );
  }
}

Future<String?> _showEmojiPicker(
  BuildContext context,
  List<String> emojis,
  String title,
) {
  final t = AppLocalizations.of(context);
  return showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 320,
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            InkWell(
              onTap: () => Navigator.pop(context, ''),
              borderRadius: BorderRadius.circular(8),
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.block, size: 28),
              ),
            ),
            for (final e in emojis)
              InkWell(
                onTap: () => Navigator.pop(context, e),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(e, style: const TextStyle(fontSize: 28)),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.actionCancel),
        ),
      ],
    ),
  );
}
