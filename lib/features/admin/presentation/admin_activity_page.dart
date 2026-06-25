import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/features/admin/data/dtos/admin_dtos.dart';
import 'package:intellipilot/features/admin/domain/admin_repository.dart';
import 'package:intellipilot/features/admin/presentation/cubits/admin_activity_cubit.dart';

/// Friendly label, icon and accent colour for a known activity action. Unknown
/// actions fall back to the raw action string with a neutral icon.
class _ActionStyle {
  const _ActionStyle(this.label, this.icon, this.color);
  final String label;
  final IconData icon;
  final Color? color;
}

_ActionStyle _styleFor(BuildContext context, String action) {
  final scheme = Theme.of(context).colorScheme;
  switch (action) {
    case 'login_success':
      return const _ActionStyle('Login', Icons.check_circle, Colors.green);
    case 'login_failure':
      return _ActionStyle('Failed login', Icons.error, scheme.error);
    case 'login_first':
      return const _ActionStyle('First login', Icons.star, Colors.amber);
    case 'password_changed':
      return _ActionStyle('Password changed', Icons.key, scheme.primary);
    case _:
      return _ActionStyle(action, Icons.bolt, scheme.onSurfaceVariant);
  }
}

/// Filter options exposed by the dropdown. `null` value means "All".
const _filters = <(String, String?)>[
  ('All', null),
  ('Logins', 'login_success'),
  ('Failed logins', 'login_failure'),
  ('First logins', 'login_first'),
  ('Password changes', 'password_changed'),
];

class AdminActivityPage extends StatelessWidget {
  const AdminActivityPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<AdminActivityCubit>(
      create: (_) {
        final c = AdminActivityCubit(getIt<AdminRepository>());
        unawaited(c.load());
        return c;
      },
      child: const _ActivityView(),
    );
  }
}

class _ActivityView extends StatelessWidget {
  const _ActivityView();

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<AdminActivityCubit>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Activity log'),
        actions: [
          IconButton(
            onPressed: () => unawaited(cubit.load()),
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: BlocBuilder<AdminActivityCubit, AdminActivityState>(
              buildWhen: (a, b) =>
                  a.runtimeType != b.runtimeType || b is AdminActivityLoaded,
              builder: (context, state) {
                final current = state is AdminActivityLoaded
                    ? state.actionFilter
                    : null;
                return DropdownButtonFormField<String?>(
                  initialValue: current,
                  decoration: const InputDecoration(
                    labelText: 'Filter',
                    prefixIcon: Icon(Icons.filter_list),
                  ),
                  items: [
                    for (final (label, value) in _filters)
                      DropdownMenuItem<String?>(
                        value: value,
                        child: Text(label),
                      ),
                  ],
                  onChanged: (v) => unawaited(cubit.setFilter(v)),
                );
              },
            ),
          ),
          Expanded(
            child: BlocBuilder<AdminActivityCubit, AdminActivityState>(
              builder: (context, state) => switch (state) {
                AdminActivityLoading() => const Center(
                  child: CircularProgressIndicator(),
                ),
                AdminActivityFailed(:final failure) => Center(
                  child: Text('Failed to load activity: ${failure.debugLabel}'),
                ),
                AdminActivityLoaded(:final items) =>
                  items.isEmpty
                      ? const Center(child: Text('No activity yet.'))
                      : ListView.separated(
                          itemBuilder: (_, i) => _EventTile(event: items[i]),
                          separatorBuilder: (_, _) => const Divider(height: 0),
                          itemCount: items.length,
                        ),
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event});
  final ActivityEvent event;

  @override
  Widget build(BuildContext context) {
    final style = _styleFor(context, event.action);
    final reason = event.metadata['reason']?.toString();
    final via = event.metadata['via']?.toString();
    final actor =
        event.actorEmail ??
        event.metadata['identifier']?.toString() ??
        event.actorUsername ??
        '—';

    return ListTile(
      leading: Icon(style.icon, color: style.color),
      title: Row(
        children: [
          Expanded(
            child: Text(
              style.label,
              style: TextStyle(
                color: style.color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (via != null && via.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Chip(
                label: Text(via),
                visualDensity: VisualDensity.compact,
              ),
            ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(actor),
          if (event.action == 'login_failure' &&
              reason != null &&
              reason.isNotEmpty)
            Text(
              reason,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          Text(
            [
              if (event.ip != null && event.ip!.isNotEmpty) event.ip!,
              event.createdAt.toLocal().toString(),
            ].join(' · '),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      isThreeLine: true,
    );
  }
}
