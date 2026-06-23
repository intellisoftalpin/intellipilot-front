import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/router/app_router.dart';
import 'package:intellipilot/core/io/file_downloader.dart';
import 'package:intellipilot/core/models/user_ref.dart';
import 'package:intellipilot/core/ui/breadcrumb_bar.dart';
import 'package:intellipilot/core/ui/breakpoints.dart';
import 'package:intellipilot/core/ui/empty_state.dart';
import 'package:intellipilot/core/widgets/members_scope.dart';
import 'package:intellipilot/core/widgets/user_avatar.dart';
import 'package:intellipilot/features/activity/data/dtos/activity_dtos.dart';
import 'package:intellipilot/features/activity/presentation/entity_detail_page.dart';
import 'package:intellipilot/features/backlog/data/dtos/backlog_dtos.dart';
import 'package:intellipilot/features/backlog/domain/backlog_repository.dart';
import 'package:intellipilot/features/backlog/presentation/cubits/issues_cubit.dart';
import 'package:intellipilot/features/backlog/presentation/widgets/issue_edit_dialog.dart';
import 'package:intellipilot/features/catalog/data/dtos/catalog_dtos.dart';
import 'package:intellipilot/features/catalog/domain/catalog_repository.dart';
import 'package:intellipilot/features/catalog/presentation/widgets/color_swatch_picker.dart';
import 'package:intellipilot/features/catalog/presentation/widgets/size_badge.dart';
import 'package:intellipilot/features/issues_io/data/dtos/issues_io_dtos.dart';
import 'package:intellipilot/features/issues_io/domain/issues_io_repository.dart';
import 'package:intellipilot/features/issues_io/presentation/import_dialog.dart';
import 'package:intellipilot/features/profile/data/dtos/profile_dtos.dart';
import 'package:intellipilot/features/profile/domain/profile_repository.dart';
import 'package:intellipilot/features/projects/data/dtos/project_dtos.dart';
import 'package:intellipilot/features/projects/domain/permission.dart';
import 'package:intellipilot/features/projects/domain/projects_repository.dart';
import 'package:intellipilot/features/projects/presentation/cubits/project_detail_cubit.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

class IssuesPage extends StatelessWidget {
  const IssuesPage({required this.projectId, super.key});
  final String projectId;

  Future<(UserProfile?, Map<String, UserRef>)> _loadContext() async {
    final p = await getIt<ProfileRepository>().getProfile();
    final m = await getIt<ProjectsRepository>().listMembers(projectId);
    final map = {
      for (final mem in (m.valueOrNull ?? const <Membership>[]))
        mem.userId: mem.toRef(),
    };
    return (p.valueOrNull, map);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(UserProfile?, Map<String, UserRef>)>(
      future: _loadContext(),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final (profile, members) = snap.data ?? (null, const <String, UserRef>{});
        if (profile == null) {
          return Scaffold(
            body: Center(
              child: Text(AppLocalizations.of(context).errUnknown),
            ),
          );
        }
        return MembersScope(
          membersById: members,
          child: MultiBlocProvider(
            providers: [
            BlocProvider<ProjectDetailCubit>(
              create: (_) {
                final c = ProjectDetailCubit(
                  repo: getIt<ProjectsRepository>(),
                  projectId: projectId,
                  currentUserId: profile.id,
                );
                unawaited(c.load());
                return c;
              },
            ),
            BlocProvider<IssuesCubit>(
              create: (_) {
                final c = IssuesCubit(
                  repo: getIt<BacklogRepository>(),
                  catalog: getIt<CatalogRepository>(),
                  projectId: projectId,
                );
                unawaited(c.load());
                return c;
              },
            ),
            ],
            child: _IssuesView(projectId: projectId),
          ),
        );
      },
    );
  }
}

class _IssuesView extends StatefulWidget {
  const _IssuesView({required this.projectId});
  final String projectId;

  @override
  State<_IssuesView> createState() => _IssuesViewState();
}

class _IssuesViewState extends State<_IssuesView> {
  /// Selected issue id — when set on a wide screen the detail panel shows on
  /// the right. On narrow screens selection navigates to the full route
  /// instead (so we never cram a two-pane layout onto a phone).
  String? _selectedId;

  void _onSelect(BuildContext context, String id) {
    if (Breakpoints.of(context).isExpanded) {
      setState(() => _selectedId = id);
    } else {
      context.go(
        Routes.entityDetailFor(widget.projectId, EntityKind.issue, id),
      );
    }
  }

  void _openFull(BuildContext context, String id) {
    context.go(Routes.entityDetailFor(widget.projectId, EntityKind.issue, id));
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final isWide = Breakpoints.of(context).isExpanded;
    return Scaffold(
      appBar: AppBar(
        title: ProjectSectionBreadcrumb(
          projectId: widget.projectId,
          currentLabel: t.issuesTitle,
        ),
        actions: [
          BlocBuilder<ProjectDetailCubit, ProjectDetailState>(
            builder: (context, detail) {
              if (detail is! ProjectDetailLoaded) {
                return const SizedBox.shrink();
              }
              return Row(
                children: [
                  if (detail.has(Permission.issueView))
                    PopupMenuButton<ExportFormat>(
                      icon: const Icon(Icons.download),
                      tooltip: t.exportTitle,
                      onSelected: (f) => _export(context, f),
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: ExportFormat.csv,
                          child: Text(t.exportCsv),
                        ),
                        PopupMenuItem(
                          value: ExportFormat.xlsx,
                          child: Text(t.exportXlsx),
                        ),
                      ],
                    ),
                  if (detail.has(Permission.issueCreate))
                    IconButton(
                      icon: const Icon(Icons.upload),
                      tooltip: t.importTitle,
                      onPressed: () => _import(context),
                    ),
                ],
              );
            },
          ),
        ],
      ),
      floatingActionButton:
          BlocBuilder<ProjectDetailCubit, ProjectDetailState>(
        builder: (context, detail) {
          if (detail is! ProjectDetailLoaded ||
              !detail.has(Permission.issueCreate)) {
            return const SizedBox.shrink();
          }
          return FloatingActionButton.extended(
            icon: const Icon(Icons.add),
            label: Text(t.actionNewIssue),
            onPressed: () => _create(context),
          );
        },
      ),
      body: Row(
        children: [
          Expanded(
            child: BlocBuilder<IssuesCubit, IssuesState>(
              builder: (context, state) {
                if (state is IssuesLoading) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (state is IssuesFailed) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(t.issuesLoadFailed),
                        const SizedBox(height: 8),
                        FilledButton(
                          onPressed: () => context.read<IssuesCubit>().load(),
                          child: Text(t.actionRetry),
                        ),
                      ],
                    ),
                  );
                }
                if (state is IssuesLoaded) {
                  return _Loaded(
                    state: state,
                    selectedId: isWide ? _selectedId : null,
                    onSelect: (id) => _onSelect(context, id),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
          if (isWide && _selectedId != null) ...[
            const VerticalDivider(width: 1),
            SizedBox(
              width: 420,
              child: EntityDetailPage(
                key: ValueKey('issue:$_selectedId'),
                projectId: widget.projectId,
                kind: EntityKind.issue,
                entityId: _selectedId!,
                onClose: () => setState(() => _selectedId = null),
                onOpen: () => _openFull(context, _selectedId!),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _create(BuildContext context) async {
    final cubit = context.read<IssuesCubit>();
    final s = cubit.state;
    if (s is! IssuesLoaded) return;
    final body = await showIssueEditDialog(context, state: s);
    if (body != null) await cubit.create(body);
  }

  Future<void> _export(BuildContext context, ExportFormat format) async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final res =
        await getIt<IssuesIoRepository>().export(widget.projectId, format);
    final bytes = res.valueOrNull;
    if (bytes == null) {
      messenger.showSnackBar(SnackBar(content: Text(t.exportFailed)));
      return;
    }
    final ok = await getIt<FileDownloader>().downloadBytes(
      filename: 'issues.${format.extension}',
      mimeType: format.mimeType,
      bytes: bytes,
    );
    if (!ok) {
      messenger.showSnackBar(SnackBar(content: Text(t.exportUnsupported)));
    }
  }

  Future<void> _import(BuildContext context) async {
    final cubit = context.read<IssuesCubit>();
    final s = cubit.state;
    if (s is! IssuesLoaded) return;
    final imported = await showIssueImportDialog(
      context,
      projectId: widget.projectId,
      state: s,
    );
    if (imported) await cubit.load();
  }
}

class _Loaded extends StatelessWidget {
  const _Loaded({
    required this.state,
    required this.selectedId,
    required this.onSelect,
  });
  final IssuesLoaded state;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final detail = context.watch<ProjectDetailCubit>().state;
    final canEdit =
        detail is ProjectDetailLoaded && detail.has(Permission.issueModify);
    final visible = state.visible;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                decoration: InputDecoration(
                  hintText: t.issuesSearchHint,
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) => context.read<IssuesCubit>().setSearch(v),
              ),
            ),
            _FilterRow(state: state),
            const Divider(height: 16),
            Expanded(
              child: visible.isEmpty
                  ? _EmptyIssues(state: state)
                  : ListView.builder(
                      itemCount: visible.length,
                      itemBuilder: (context, i) {
                        final issue = visible[i];
                        return _IssueRow(
                          issue: issue,
                          state: state,
                          canEdit: canEdit,
                          selected: issue.id == selectedId,
                          onSelect: onSelect,
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

/// Empty state for the issue list. Always renders the bug icon + headline;
/// adds an inline "New issue" CTA when the viewer has `issue:create`.
/// Without that fallback the only entry point is the Scaffold FAB, which
/// users on tight viewports or with a scroll-wheel hovering elsewhere
/// frequently miss.
class _EmptyIssues extends StatelessWidget {
  const _EmptyIssues({required this.state});
  final IssuesLoaded state;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final detail = context.watch<ProjectDetailCubit>().state;
    final canCreate =
        detail is ProjectDetailLoaded && detail.has(Permission.issueCreate);
    return EmptyState(
      icon: Icons.bug_report_outlined,
      title: t.issuesTitle,
      body: t.issuesEmpty,
      action: canCreate
          ? FilledButton.icon(
              icon: const Icon(Icons.add),
              onPressed: () async {
                final cubit = context.read<IssuesCubit>();
                final body = await showIssueEditDialog(context, state: state);
                if (body != null) await cubit.create(body);
              },
              label: Text(t.actionNewIssue),
            )
          : null,
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({required this.state});
  final IssuesLoaded state;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _menu(
            label: state.statusFilter == null
                ? t.issuesFilterStatus
                : state.statuses
                      .firstWhere((s) => s.id == state.statusFilter)
                      .name,
            items: state.statuses,
            current: state.statusFilter,
            onSelected: context.read<IssuesCubit>().setStatusFilter,
          ),
          const SizedBox(width: 8),
          _menu(
            label: state.typeFilter == null
                ? t.issuesFilterType
                : state.types.firstWhere((s) => s.id == state.typeFilter).name,
            items: state.types,
            current: state.typeFilter,
            onSelected: context.read<IssuesCubit>().setTypeFilter,
          ),
          const SizedBox(width: 8),
          _menu(
            label: state.priorityFilter == null
                ? t.issuesFilterPriority
                : state.priorities
                      .firstWhere((s) => s.id == state.priorityFilter)
                      .name,
            items: state.priorities,
            current: state.priorityFilter,
            onSelected: context.read<IssuesCubit>().setPriorityFilter,
          ),
          const SizedBox(width: 8),
          _menu(
            label: state.sizeFilter == null
                ? 'Size'
                : state.sizes
                      .firstWhere((s) => s.id == state.sizeFilter)
                      .name,
            items: state.sizes,
            current: state.sizeFilter,
            onSelected: context.read<IssuesCubit>().setSizeFilter,
          ),
        ],
      ),
    );
  }

  Widget _menu({
    required String label,
    required List<TaxonomyItem> items,
    required String? current,
    required ValueChanged<String?> onSelected,
  }) {
    return Builder(
      builder: (context) {
        final t = AppLocalizations.of(context);
        return PopupMenuButton<String?>(
          tooltip: label,
          itemBuilder: (_) => [
            PopupMenuItem<String?>(
              value: null,
              child: Text(t.issuesFilterClear),
            ),
            ...items.map(
              (it) => PopupMenuItem<String?>(
                value: it.id,
                child: Row(
                  children: [
                    HexColorDot(hex: it.color, size: 10),
                    const SizedBox(width: 8),
                    Text(it.name),
                  ],
                ),
              ),
            ),
          ],
          onSelected: onSelected,
          child: Chip(
            avatar: const Icon(Icons.filter_list, size: 16),
            label: Text(label),
          ),
        );
      },
    );
  }
}

class _IssueRow extends StatelessWidget {
  const _IssueRow({
    required this.issue,
    required this.state,
    required this.canEdit,
    required this.selected,
    required this.onSelect,
  });
  final Issue issue;
  final IssuesLoaded state;
  final bool canEdit;
  final bool selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final status =
        state.statuses.where((s) => s.id == issue.statusId).cast<TaxonomyItem?>().firstOrNull;
    final type =
        state.types.where((s) => s.id == issue.typeId).cast<TaxonomyItem?>().firstOrNull;
    final priority = state.priorities
        .where((s) => s.id == issue.priorityId)
        .cast<TaxonomyItem?>()
        .firstOrNull;
    final size = state.sizes
        .where((s) => s.id == issue.sizeId)
        .cast<TaxonomyItem?>()
        .firstOrNull;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      shape: selected
          ? RoundedRectangleBorder(
              side: BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: 2,
              ),
              borderRadius: BorderRadius.circular(12),
            )
          : null,
      child: ListTile(
        selected: selected,
        leading: HexColorDot(hex: status?.color ?? '', size: 14),
        title: Row(
          children: [
            Expanded(child: Text(issue.subject)),
            if (MembersScope.user(context, issue.assignedTo) != null) ...[
              const SizedBox(width: 8),
              UserAvatar(
                user: MembersScope.user(context, issue.assignedTo)!,
                size: 26,
              ),
            ],
          ],
        ),
        onTap: () => onSelect(issue.id),
        subtitle: Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            Text('ISSUE-${issue.reference}'),
            if (status != null) _MiniChip(label: status.name, color: status.color),
            if (type != null) _MiniChip(label: type.name, color: type.color),
            if (priority != null) _MiniChip(label: priority.name, color: priority.color),
            if (size != null) SizeBadge(item: size),
          ],
        ),
        trailing: canEdit
            ? PopupMenuButton<String>(
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'edit', child: Text(t.actionEdit)),
                  PopupMenuItem(value: 'delete', child: Text(t.actionDelete)),
                ],
                onSelected: (v) async {
                  if (v == 'edit') {
                    final body = await showIssueEditDialog(
                      context,
                      state: state,
                      existing: issue,
                    );
                    if (body == null || !context.mounted) return;
                    await context.read<IssuesCubit>().update(
                      issue.id,
                      UpdateIssueRequest(
                        subject: body.subject,
                        description: body.description,
                        statusId: body.statusId,
                        typeId: body.typeId,
                        priorityId: body.priorityId,
                        sizeId: body.sizeId,
                        labels: body.labels,
                        components: body.components,
                      ),
                    );
                  } else if (v == 'delete') {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text(t.issueDeleteTitle),
                        content: Text(t.issueDeleteConfirm(issue.subject)),
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
                      await context.read<IssuesCubit>().delete(issue.id);
                    }
                  }
                },
              )
            : null,
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.label, required this.color});
  final String label;
  final String color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          HexColorDot(hex: color, size: 8),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}
