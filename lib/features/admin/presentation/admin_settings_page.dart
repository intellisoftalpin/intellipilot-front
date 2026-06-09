import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/features/admin/domain/admin_repository.dart';
import 'package:intellipilot/features/admin/presentation/admin_ldap_page.dart';
import 'package:intellipilot/features/admin/presentation/cubits/admin_settings_cubit.dart';

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
    return Scaffold(
      appBar: AppBar(title: const Text('Platform settings')),
      body: BlocBuilder<AdminSettingsCubit, AdminSettingsState>(
        builder: (context, state) => switch (state) {
          AdminSettingsLoading() =>
            const Center(child: CircularProgressIndicator()),
          AdminSettingsFailed(:final failure) => Center(
            child: Text('Failed: ${failure.debugLabel}'),
          ),
          AdminSettingsLoaded(:final settings, :final lastError) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SwitchListTile(
                title: const Text('Open registration'),
                subtitle: const Text(
                  'When off, the public /register endpoint requires a valid '
                  'platform invitation token. Default: off.',
                ),
                value: settings.openRegistration,
                onChanged: (v) => context
                    .read<AdminSettingsCubit>()
                    .setOpenRegistration(v),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.account_tree_outlined),
                title: const Text('LDAP / Directory'),
                subtitle: const Text(
                  'Authenticate users against an LDAP/Active Directory server.',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AdminLdapPage(),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Last updated: ${settings.updatedAt.toLocal()}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (lastError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    'Last update failed.',
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
