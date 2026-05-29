import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/router/app_router.dart';
import 'package:intellipilot/core/ui/issue_chips.dart';
import 'package:intellipilot/features/projects/data/dtos/project_dtos.dart';
import 'package:intellipilot/features/projects/domain/projects_repository.dart';
import 'package:intellipilot/features/projects/presentation/cubits/projects_list_cubit.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

class ProjectsListPage extends StatelessWidget {
  const ProjectsListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ProjectsListCubit>(
      create: (_) => ProjectsListCubit(getIt<ProjectsRepository>())..load(),
      child: const _ProjectsListView(),
    );
  }
}

class _ProjectsListView extends StatelessWidget {
  const _ProjectsListView();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.projectsTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: t.settingsTitle,
            onPressed: () => context.go(Routes.settings),
          ),
        ],
      ),
      floatingActionButton: BlocBuilder<ProjectsListCubit, ProjectsListState>(
        builder: (context, state) {
          if (state is! ProjectsListLoaded) return const SizedBox.shrink();
          return FloatingActionButton.extended(
            icon: const Icon(Icons.add),
            label: Text(t.actionNewProject),
            onPressed: () => _showCreateDialog(context),
          );
        },
      ),
      body: BlocConsumer<ProjectsListCubit, ProjectsListState>(
        listenWhen: (prev, next) =>
            next is ProjectsListLoaded && next.lastError != null,
        listener: (context, state) {
          if (state is ProjectsListLoaded && state.lastError != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(t.projectCreateFailed)),
            );
          }
        },
        builder: (context, state) {
          if (state is ProjectsListLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is ProjectsListLoadFailed) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(t.projectsLoadFailed),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: () =>
                        context.read<ProjectsListCubit>().load(),
                    child: Text(t.actionRetry),
                  ),
                ],
              ),
            );
          }
          if (state is ProjectsListLoaded) {
            return _Loaded(state: state);
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }
}

class _Loaded extends StatefulWidget {
  const _Loaded({required this.state});
  final ProjectsListLoaded state;

  @override
  State<_Loaded> createState() => _LoadedState();
}

class _LoadedState extends State<_Loaded> {
  late final TextEditingController _search;

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(text: widget.state.search);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final visible = widget.state.visible;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                controller: _search,
                decoration: InputDecoration(
                  hintText: t.projectsSearchHint,
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) =>
                    context.read<ProjectsListCubit>().setSearch(v),
              ),
            ),
            Expanded(
              child: visible.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          widget.state.search.isEmpty
                              ? t.projectsEmpty
                              : t.projectsNoMatch,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: visible.length,
                      itemBuilder: (context, i) {
                        final p = visible[i];
                        return Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          child: ListTile(
                            leading: Icon(
                              Icons.folder_outlined,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    p.name,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IssueKeyChip(text: p.slug),
                              ],
                            ),
                            subtitle: p.description.isEmpty
                                ? null
                                : Padding(
                                    padding:
                                        const EdgeInsets.only(top: 2),
                                    child: Text(
                                      p.description,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => context.go(
                              Routes.projectDetailFor(p.id),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showCreateDialog(BuildContext context) async {
  final t = AppLocalizations.of(context);
  final nameController = TextEditingController();
  final descController = TextEditingController();
  var visibility = ProjectVisibility.private;
  final cubit = context.read<ProjectsListCubit>();

  final created = await showDialog<Project?>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        return AlertDialog(
          title: Text(t.actionNewProject),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: true,
                  decoration: InputDecoration(labelText: t.projectFieldName),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: t.projectFieldDescription,
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<ProjectVisibility>(
                  initialValue: visibility,
                  decoration: InputDecoration(
                    labelText: t.projectFieldVisibility,
                  ),
                  items: [
                    DropdownMenuItem(
                      value: ProjectVisibility.private,
                      child: Text(t.projectVisibilityPrivate),
                    ),
                    DropdownMenuItem(
                      value: ProjectVisibility.internal,
                      child: Text(t.projectVisibilityInternal),
                    ),
                    DropdownMenuItem(
                      value: ProjectVisibility.publicReadonly,
                      child: Text(t.projectVisibilityPublicReadonly),
                    ),
                  ],
                  onChanged: (v) =>
                      setState(() => visibility = v ?? visibility),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: Text(t.actionCancel),
            ),
            FilledButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) return;
                final created = await cubit.create(
                  CreateProjectRequest(
                    name: name,
                    description: descController.text.trim(),
                    visibility: visibility,
                  ),
                );
                if (ctx.mounted) Navigator.of(ctx).pop(created);
              },
              child: Text(t.actionCreate),
            ),
          ],
        );
      },
    ),
  );
  if (created != null && context.mounted) {
    context.go(Routes.projectDetailFor(created.id));
  }
}
