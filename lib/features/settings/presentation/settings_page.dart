import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intellipilot/app/l10n/locale_cubit.dart';
import 'package:intellipilot/app/router/app_router.dart';
import 'package:intellipilot/app/theme/app_theme.dart';
import 'package:intellipilot/app/theme/theme_cubit.dart';
import 'package:intellipilot/core/widgets/app_scaffold.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppScaffold(
      title: Text(l10n.settingsTitle),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: const [
          _ThemeSection(),
          SizedBox(height: 16),
          _LocaleSection(),
          SizedBox(height: 16),
          _SecuritySection(),
        ],
      ),
    );
  }
}

class _ThemeSection extends StatelessWidget {
  const _ThemeSection();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, state) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.settingsAppearance,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                SegmentedButton<ThemeMode>(
                  segments: [
                    ButtonSegment(
                      value: ThemeMode.light,
                      label: Text(l10n.themeLight),
                      icon: const Icon(Icons.light_mode_outlined),
                    ),
                    ButtonSegment(
                      value: ThemeMode.system,
                      label: Text(l10n.themeSystem),
                      icon: const Icon(Icons.brightness_auto_outlined),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      label: Text(l10n.themeDark),
                      icon: const Icon(Icons.dark_mode_outlined),
                    ),
                  ],
                  selected: {state.mode},
                  onSelectionChanged: (s) =>
                      context.read<ThemeCubit>().setMode(s.first),
                ),
                const SizedBox(height: 20),
                Text(l10n.themeSeedColor, style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final opt in SeedPalette.options)
                      _SeedSwatch(
                        color: opt.color,
                        label: opt.name,
                        selected:
                            opt.color.toARGB32() == state.seedColor.toARGB32(),
                        onTap: () =>
                            context.read<ThemeCubit>().setSeedColor(opt.color),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.themeUseDynamic),
                  subtitle: Text(l10n.themeUseDynamicHint),
                  value: state.useDynamic,
                  onChanged: (v) => context.read<ThemeCubit>().setUseDynamic(v),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SeedSwatch extends StatelessWidget {
  const _SeedSwatch({
    required this.color,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: InkResponse(
        onTap: onTap,
        radius: 28,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: selected
                ? Border.all(
                    color: Theme.of(context).colorScheme.onSurface,
                    width: 3,
                  )
                : null,
          ),
          child: selected
              ? const Icon(Icons.check, color: Colors.white, size: 20)
              : null,
        ),
      ),
    );
  }
}

class _SecuritySection extends StatelessWidget {
  const _SecuritySection();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Card(
      child: ListTile(
        leading: const Icon(Icons.shield_outlined),
        title: Text(l10n.settingsSecurityTitle),
        subtitle: Text(l10n.settingsSecuritySubtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.go(Routes.security),
      ),
    );
  }
}

class _LocaleSection extends StatelessWidget {
  const _LocaleSection();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return BlocBuilder<LocaleCubit, Locale?>(
      builder: (context, locale) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.settingsLanguage, style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                DropdownButton<String?>(
                  value: locale?.languageCode,
                  hint: Text(l10n.localeSystem),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text(l10n.localeSystem),
                    ),
                    const DropdownMenuItem<String?>(
                      value: 'en',
                      child: Text('English'),
                    ),
                  ],
                  onChanged: (code) {
                    context.read<LocaleCubit>().setLocale(
                      code == null ? null : Locale(code),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
