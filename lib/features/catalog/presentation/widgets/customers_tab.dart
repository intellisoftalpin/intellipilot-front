import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/features/catalog/data/dtos/catalog_dtos.dart';
import 'package:intellipilot/features/catalog/domain/catalog_repository.dart';
import 'package:intellipilot/features/catalog/presentation/cubits/customers_cubit.dart';
import 'package:intellipilot/features/catalog/presentation/widgets/repositories_tab.dart'
    show failureText;
import 'package:intellipilot/features/projects/domain/permission.dart';
import 'package:intellipilot/features/projects/presentation/cubits/project_detail_cubit.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// Project-settings tab managing the per-project customer directory.
class CustomersTab extends StatelessWidget {
  const CustomersTab({required this.projectId, super.key});

  final String projectId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<CustomersCubit>(
      create: (_) {
        final c = CustomersCubit(
          repo: getIt<CatalogRepository>(),
          projectId: projectId,
        );
        unawaited(c.load());
        return c;
      },
      child: const _CustomersView(),
    );
  }
}

class _CustomersView extends StatelessWidget {
  const _CustomersView();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final detail = context.watch<ProjectDetailCubit>().state;
    final canEdit =
        detail is ProjectDetailLoaded &&
        detail.hasAny(const [
          Permission.customerCreate,
          Permission.customerModify,
          Permission.customerDelete,
        ]);
    return BlocBuilder<CustomersCubit, CustomersState>(
      builder: (context, state) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Text(
                  t.permDomainCustomers,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                if (canEdit)
                  FilledButton.icon(
                    icon: const Icon(Icons.add),
                    label: Text(t.catCustomerNew),
                    onPressed: () => _showDialog(context, null),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (state is CustomersLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (state is CustomersLoadFailed)
              Text(failureText(state.failure))
            else if (state is CustomersLoaded)
              if (state.customers.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(t.catCustomerEmpty),
                )
              else
                for (final c in state.customers)
                  _CustomerCard(customer: c, canEdit: canEdit),
          ],
        );
      },
    );
  }
}

class _CustomerCard extends StatelessWidget {
  const _CustomerCard({required this.customer, required this.canEdit});
  final Customer customer;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final lines = <String>[
      if (customer.companyName != null && customer.companyName!.isNotEmpty)
        customer.companyName!,
      if (customer.contactEmail != null && customer.contactEmail!.isNotEmpty)
        customer.contactEmail!,
      if (customer.phone != null && customer.phone!.isNotEmpty) customer.phone!,
    ];
    return Card(
      child: ListTile(
        leading: const Icon(Icons.business_outlined),
        title: Text(customer.name),
        subtitle: lines.isEmpty ? null : Text(lines.join('\n')),
        isThreeLine: lines.length > 1,
        trailing: canEdit
            ? Wrap(
                spacing: 4,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: t.actionEdit,
                    onPressed: () => _showDialog(context, customer),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: t.actionDelete,
                    onPressed: () => _confirmDelete(context, customer),
                  ),
                ],
              )
            : null,
      ),
    );
  }
}

Future<void> _confirmDelete(BuildContext context, Customer customer) async {
  final t = AppLocalizations.of(context);
  final cubit = context.read<CustomersCubit>();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(t.catCustomerDelete),
      content: Text(
        t.catCustomerDeleteBody(customer.name),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(t.actionCancel),
        ),
        FilledButton.tonal(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(t.actionDelete),
        ),
      ],
    ),
  );
  if ((ok ?? false) && context.mounted) {
    await cubit.delete(customer.id);
  }
}

Future<void> _showDialog(BuildContext context, Customer? existing) async {
  final t = AppLocalizations.of(context);
  final cubit = context.read<CustomersCubit>();
  final nameCtrl = TextEditingController(text: existing?.name ?? '');
  final companyCtrl = TextEditingController(text: existing?.companyName ?? '');
  final emailCtrl = TextEditingController(text: existing?.contactEmail ?? '');
  final phoneCtrl = TextEditingController(text: existing?.phone ?? '');
  final notesCtrl = TextEditingController(text: existing?.notes ?? '');

  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(existing == null ? 'New customer' : 'Edit customer'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: InputDecoration(labelText: t.fieldName),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: companyCtrl,
                decoration: InputDecoration(labelText: t.catFieldCompany),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: emailCtrl,
                decoration: InputDecoration(
                  labelText: t.catFieldContactEmail,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneCtrl,
                decoration: InputDecoration(labelText: t.catFieldPhone),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesCtrl,
                maxLines: 3,
                decoration: InputDecoration(labelText: t.catFieldNotes),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(t.actionCancel),
        ),
        FilledButton(
          onPressed: () async {
            final name = nameCtrl.text.trim();
            if (name.isEmpty) return;
            String? orNull(TextEditingController c) {
              final v = c.text.trim();
              return v.isEmpty ? null : v;
            }

            final ok = existing == null
                ? await cubit.create(
                    CreateCustomerRequest(
                      name: name,
                      companyName: orNull(companyCtrl),
                      contactEmail: orNull(emailCtrl),
                      phone: orNull(phoneCtrl),
                      notes: orNull(notesCtrl),
                    ),
                  )
                : await cubit.update(
                    existing.id,
                    UpdateCustomerRequest(
                      name: name,
                      companyName: companyCtrl.text.trim(),
                      contactEmail: emailCtrl.text.trim(),
                      phone: phoneCtrl.text.trim(),
                      notes: notesCtrl.text.trim(),
                    ),
                  );
            if (!ctx.mounted) return;
            if (ok) {
              Navigator.of(ctx).pop();
            } else {
              final s = cubit.state;
              if (s is CustomersLoaded && s.lastError != null) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text(failureText(s.lastError!))),
                );
              }
            }
          },
          child: Text(t.actionSaveShort),
        ),
      ],
    ),
  );
}
