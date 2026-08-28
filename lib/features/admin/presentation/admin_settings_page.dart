import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/router/app_router.dart';
import 'package:intellipilot/features/admin/domain/admin_repository.dart';
import 'package:intellipilot/features/admin/presentation/admin_branding_page.dart';
import 'package:intellipilot/features/admin/presentation/admin_geoip_page.dart';
import 'package:intellipilot/features/admin/presentation/admin_ldap_page.dart';
import 'package:intellipilot/features/admin/presentation/admin_notifications_page.dart';
import 'package:intellipilot/features/admin/presentation/admin_short_links_page.dart';
import 'package:intellipilot/features/admin/presentation/admin_sso_page.dart';
import 'package:intellipilot/features/admin/presentation/cubits/admin_settings_cubit.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

class AdminSettingsPage extends StatelessWidget {
  const AdminSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<AdminSettingsCubit>(
      create: (_) {
        final c = AdminSettingsCubit(getIt<AdminRepository>());
        unawaited(c.load());
        return c;
      },
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
                  MaterialPageRoute<void>(
                    builder: (_) => const AdminLdapPage(),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.shield_outlined),
                title: Text(l10n.adminSettingsSso),
                subtitle: Text(l10n.adminSettingsSsoDesc),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AdminSsoPage(),
                  ),
                ),
              ),
              SwitchListTile(
                title: Text(l10n.adminSettingsDisablePasswordLogin),
                // Says explicitly that a superadmin with a password still gets
                // in: without that, this reads like a switch that can lock the
                // operator out of their own deployment, and nobody would touch
                // it.
                subtitle: Text(l10n.adminSettingsDisablePasswordLoginDesc),
                value: settings.localPasswordLoginDisabled,
                onChanged: (v) => context
                    .read<AdminSettingsCubit>()
                    .setLocalPasswordLoginDisabled(v),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.link_outlined),
                title: Text(l10n.adminShortLinksTitle),
                subtitle: Text(l10n.adminShortLinksDesc),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AdminShortLinksPage(),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.public),
                title: Text(l10n.adminGeoipTitle),
                subtitle: Text(l10n.adminGeoipSubtitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AdminGeoipPage(),
                  ),
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
              ListTile(
                leading: const Icon(Icons.history),
                title: Text(l10n.adminActivityTitle),
                subtitle: Text(l10n.adminSettingsActivitySubtitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go(Routes.adminActivity),
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
