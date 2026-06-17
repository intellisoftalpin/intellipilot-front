import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/features/admin/domain/admin_repository.dart';
import 'package:intellipilot/features/admin/presentation/admin_branding_page.dart';
import 'package:intellipilot/features/admin/presentation/admin_ldap_page.dart';
import 'package:intellipilot/features/admin/presentation/admin_notifications_page.dart';
import 'package:intellipilot/features/admin/presentation/cubits/admin_settings_cubit.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

class AdminSettingsPage extends StatelessWidget {
  const AdminSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<AdminSettingsCubit>(
      create: (_) => AdminSettingsCubit(getIt<AdminRepository>())..load(),
      child: const _SettingsView(),
    );
  }
}

class _SettingsView extends StatelessWidget {
  const _SettingsView();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.adminSettingsTitle)),
      body: BlocBuilder<AdminSettingsCubit, AdminSettingsState>(
        builder: (context, state) => switch (state) {
          AdminSettingsLoading() => const Center(
            child: CircularProgressIndicator(),
          ),
          AdminSettingsFailed(:final failure) => Center(
            child: Text(l10n.adminSettingsFailed(failure.debugLabel)),
          ),
          AdminSettingsLoaded(:final settings, :final lastError) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SwitchListTile(
                title: Text(l10n.adminSettingsOpenRegistration),
                subtitle: Text(l10n.adminSettingsOpenRegistrationDesc),
                value: settings.openRegistration,
                onChanged: (v) =>
                    context.read<AdminSettingsCubit>().setOpenRegistration(v),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.palette_outlined),
                title: Text(l10n.adminSettingsBranding),
                subtitle: Text(l10n.adminSettingsBrandingDesc),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AdminBrandingPage(),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.account_tree_outlined),
                title: Text(l10n.adminSettingsLdap),
                subtitle: Text(l10n.adminSettingsLdapDesc),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const AdminLdapPage()),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.notifications_outlined),
                title: Text(l10n.adminSettingsNotifications),
                subtitle: Text(l10n.adminSettingsNotificationsDesc),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AdminNotificationsPage(),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                l10n.adminSettingsLastUpdated(
                  settings.updatedAt.toLocal().toString(),
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (lastError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    l10n.adminSettingsUpdateFailed,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        },
      ),
    );
  }
}
