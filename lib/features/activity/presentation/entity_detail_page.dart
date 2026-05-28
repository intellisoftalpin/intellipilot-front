import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/features/activity/data/dtos/activity_dtos.dart';
import 'package:intellipilot/features/activity/domain/activity_repository.dart';
import 'package:intellipilot/features/activity/presentation/cubits/activity_stream_cubit.dart';
import 'package:intellipilot/features/activity/presentation/cubits/attachments_cubit.dart';
import 'package:intellipilot/features/activity/presentation/widgets/activity_stream_view.dart';
import 'package:intellipilot/features/activity/presentation/widgets/attachments_view.dart';
import 'package:intellipilot/features/backlog/data/dtos/backlog_dtos.dart';
import 'package:intellipilot/features/backlog/domain/backlog_repository.dart';
import 'package:intellipilot/features/backlog/presentation/cubits/issues_cubit.dart';
import 'package:intellipilot/features/backlog/presentation/widgets/epic_edit_dialog.dart';
import 'package:intellipilot/features/backlog/presentation/widgets/issue_edit_dialog.dart';
import 'package:intellipilot/features/backlog/presentation/widgets/task_edit_dialog.dart';
import 'package:intellipilot/features/backlog/presentation/widgets/user_story_edit_dialog.dart';
import 'package:intellipilot/features/catalog/data/dtos/catalog_dtos.dart';
import 'package:intellipilot/features/catalog/domain/catalog_repository.dart';
import 'package:intellipilot/features/profile/domain/profile_repository.dart';
import 'package:intellipilot/features/projects/domain/permission.dart';
import 'package:intellipilot/features/projects/domain/projects_repository.dart';
import 'package:intellipilot/features/projects/presentation/cubits/project_detail_cubit.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// Generic entity detail page: fetches the entity header, then renders
/// description + an Activity tab + an Attachments tab. The kind comes from
/// the URL so a single route serves all four backlog entity kinds.
///
/// Stateful so the header can refresh after an edit without forcing a
/// route navigation.
class EntityDetailPage extends StatefulWidget {
  const EntityDetailPage({
    required this.projectId,
    required this.kind,
    required this.entityId,
    super.key,
  });

  final String projectId;
  final EntityKind kind;
  final String entityId;

  @override
  State<EntityDetailPage> createState() => _EntityDetailPageState();
}

class _EntityDetailPageState extends State<EntityDetailPage> {
  // Client-side cap. Server default is 25 MiB; we mirror it.
  static const _maxBytes = 25 * 1024 * 1024;

  late Future<_Header?> _headerFuture;

  @override
  void initState() {
    super.initState();
    _headerFuture = _loadHeader();
  }

  void _reloadHeader() {
    setState(() => _headerFuture = _loadHeader());
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return FutureBuilder<_Header?>(
      future: _headerFuture,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final header = snap.data;
        if (header == null) {
          return Scaffold(
            appBar: AppBar(title: Text(t.entityDetailTitle)),
            body: Center(child: Text(t.entityDetailLoadFailed)),
          );
        }
        return MultiBlocProvider(
          providers: [
            BlocProvider<ProjectDetailCubit>(
              create: (_) => ProjectDetailCubit(
                repo: getIt<ProjectsRepository>(),
                projectId: widget.projectId,
                currentUserId: header.userId,
              )..load(),
            ),
            BlocProvider<ActivityStreamCubit>(
              create: (_) => ActivityStreamCubit(
                repo: getIt<ActivityRepository>(),
                projectId: widget.projectId,
                kind: widget.kind,
                entityId: widget.entityId,
              )..load(),
            ),
            BlocProvider<AttachmentsCubit>(
              create: (_) => AttachmentsCubit(
                repo: getIt<ActivityRepository>(),
                projectId: widget.projectId,
                kind: widget.kind,
                entityId: widget.entityId,
                maxBytes: _maxBytes,
              )..load(),
            ),
          ],
          child: _DetailView(
            header: header,
            kind: widget.kind,
            entityId: widget.entityId,
            projectId: widget.projectId,
            onEdited: _reloadHeader,
          ),
        );
      },
    );
  }

  Future<_Header?> _loadHeader() async {
    final profileRes = await getIt<ProfileRepository>().getProfile();
    final profile = profileRes.valueOrNull;
    if (profile == null) return null;
    final repo = getIt<BacklogRepository>();
    _EntityHeader? header;
    switch (widget.kind) {
      case EntityKind.epic:
        final v = (await repo.getEpic(widget.projectId, widget.entityId))
            .valueOrNull;
        if (v != null) {
          header = _EntityHeader(
            subject: v.subject,
            description: v.description,
            reference: v.reference,
            prefix: 'EPIC',
          );
        }
      case EntityKind.userStory:
        final v = (await repo.getUserStory(widget.projectId, widget.entityId))
            .valueOrNull;
        if (v != null) {
          header = _EntityHeader(
            subject: v.subject,
            description: v.description,
            reference: v.reference,
            prefix: 'US',
          );
        }
      case EntityKind.task:
        final v = (await repo.getTask(widget.projectId, widget.entityId))
            .valueOrNull;
        if (v != null) {
          header = _EntityHeader(
            subject: v.subject,
            description: v.description,
            reference: v.reference,
            prefix: 'T',
          );
        }
      case EntityKind.issue:
        final v = (await repo.getIssue(widget.projectId, widget.entityId))
            .valueOrNull;
        if (v != null) {
          header = _EntityHeader(
            subject: v.subject,
            description: v.description,
            reference: v.reference,
            prefix: 'ISSUE',
          );
        }
    }
    if (header == null) return null;
    return _Header(profile.id, header);
  }
}

class _DetailView extends StatelessWidget {
  const _DetailView({
    required this.header,
    required this.kind,
    required this.entityId,
    required this.projectId,
    required this.onEdited,
  });

  final _Header header;
  final EntityKind kind;
  final String entityId;
  final String projectId;
  final VoidCallback onEdited;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            '${header.entity.prefix}-${header.entity.reference} '
            '· ${header.entity.subject}',
          ),
          actions: [
            BlocBuilder<ProjectDetailCubit, ProjectDetailState>(
              builder: (context, detail) {
                if (detail is! ProjectDetailLoaded ||
                    !detail.has(_modifyPermission(kind))) {
                  return const SizedBox.shrink();
                }
                return IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: t.actionEdit,
                  onPressed: () => _openEditor(context),
                );
              },
            ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(text: t.entityTabActivity),
              Tab(text: t.entityTabAttachments),
            ],
          ),
        ),
        body: Column(
          children: [
            if (header.entity.description.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: SelectableText(header.entity.description),
                  ),
                ),
              ),
            Expanded(
              child: TabBarView(
                children: [
                  ActivityStreamView(
                    draftKey: '${kind.wire}:$entityId',
                  ),
                  const AttachmentsView(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Permission _modifyPermission(EntityKind kind) => switch (kind) {
    EntityKind.epic => Permission.epicModify,
    EntityKind.userStory => Permission.usModify,
    EntityKind.task => Permission.taskModify,
    EntityKind.issue => Permission.issueModify,
  };

  Future<void> _openEditor(BuildContext context) async {
    final backlog = getIt<BacklogRepository>();
    final catalog = getIt<CatalogRepository>();

    switch (kind) {
      case EntityKind.epic:
        await _editEpic(context, backlog);
      case EntityKind.userStory:
        await _editUserStory(context, backlog, catalog);
      case EntityKind.task:
        await _editTask(context, backlog, catalog);
      case EntityKind.issue:
        await _editIssue(context, backlog, catalog);
    }
  }

  Future<void> _editEpic(
    BuildContext context,
    BacklogRepository backlog,
  ) async {
    final epic = (await backlog.getEpic(projectId, entityId)).valueOrNull;
    if (epic == null || !context.mounted) return;
    final body = await showEpicEditDialog(context, existing: epic);
    if (body == null || epic.etag == null) return;
    await backlog.updateEpic(
      projectId,
      entityId,
      body: UpdateEpicRequest(
        subject: body.subject,
        description: body.description,
        statusId: body.statusId,
        color: body.color,
        assignedTo: body.assignedTo,
      ),
      etag: epic.etag!,
    );
    onEdited();
  }

  Future<void> _editUserStory(
    BuildContext context,
    BacklogRepository backlog,
    CatalogRepository catalog,
  ) async {
    final us =
        (await backlog.getUserStory(projectId, entityId)).valueOrNull;
    if (us == null || !context.mounted) return;
    final epics = (await backlog.listEpics(projectId)).valueOrNull ?? [];
    final statuses = (await catalog.listTaxonomy(
              projectId,
              TaxonomyKind.usStatus,
            ))
            .valueOrNull ??
        [];
    final points = (await catalog.listTaxonomy(
              projectId,
              TaxonomyKind.point,
            ))
            .valueOrNull ??
        [];
    if (!context.mounted) return;
    final body = await showUserStoryEditDialog(
      context,
      epics: epics,
      statuses: statuses,
      points: points,
      existing: us,
    );
    if (body == null || us.etag == null) return;
    await backlog.updateUserStory(
      projectId,
      entityId,
      body: UpdateUserStoryRequest(
        subject: body.subject,
        description: body.description,
        statusId: body.statusId,
        epicId: body.epicId,
        pointsId: body.pointsId,
        assignedTo: body.assignedTo,
      ),
      etag: us.etag!,
    );
    onEdited();
  }

  Future<void> _editTask(
    BuildContext context,
    BacklogRepository backlog,
    CatalogRepository catalog,
  ) async {
    final task = (await backlog.getTask(projectId, entityId)).valueOrNull;
    if (task == null || !context.mounted) return;
    final stories =
        (await backlog.listUserStories(projectId)).valueOrNull ?? [];
    final statuses = (await catalog.listTaxonomy(
              projectId,
              TaxonomyKind.taskStatus,
            ))
            .valueOrNull ??
        [];
    if (!context.mounted) return;
    final body = await showTaskEditDialog(
      context,
      userStories: stories,
      statuses: statuses,
      existing: task,
    );
    if (body == null || task.etag == null) return;
    await backlog.updateTask(
      projectId,
      entityId,
      body: UpdateTaskRequest(
        subject: body.subject,
        description: body.description,
        statusId: body.statusId,
        userStoryId: body.userStoryId,
        assignedTo: body.assignedTo,
      ),
      etag: task.etag!,
    );
    onEdited();
  }

  Future<void> _editIssue(
    BuildContext context,
    BacklogRepository backlog,
    CatalogRepository catalog,
  ) async {
    final issue = (await backlog.getIssue(projectId, entityId)).valueOrNull;
    if (issue == null || !context.mounted) return;
    final statuses = (await catalog.listTaxonomy(
              projectId,
              TaxonomyKind.issueStatus,
            ))
            .valueOrNull ??
        [];
    final types = (await catalog.listTaxonomy(
              projectId,
              TaxonomyKind.issueType,
            ))
            .valueOrNull ??
        [];
    final priorities = (await catalog.listTaxonomy(
              projectId,
              TaxonomyKind.priority,
            ))
            .valueOrNull ??
        [];
    final severities = (await catalog.listTaxonomy(
              projectId,
              TaxonomyKind.severity,
            ))
            .valueOrNull ??
        [];
    final labels = (await catalog.listLabels(projectId)).valueOrNull ?? [];
    final components =
        (await catalog.listComponents(projectId)).valueOrNull ?? [];
    if (!context.mounted) return;
    final state = IssuesLoaded(
      issues: const [],
      statuses: statuses,
      types: types,
      priorities: priorities,
      severities: severities,
      labels: labels,
      components: components,
    );
    final body = await showIssueEditDialog(
      context,
      state: state,
      existing: issue,
    );
    if (body == null || issue.etag == null) return;
    await backlog.updateIssue(
      projectId,
      entityId,
      body: UpdateIssueRequest(
        subject: body.subject,
        description: body.description,
        statusId: body.statusId,
        typeId: body.typeId,
        priorityId: body.priorityId,
        severityId: body.severityId,
        assignedTo: body.assignedTo,
        labels: body.labels,
        components: body.components,
      ),
      etag: issue.etag!,
    );
    onEdited();
  }
}

class _EntityHeader {
  const _EntityHeader({
    required this.subject,
    required this.description,
    required this.reference,
    required this.prefix,
  });
  final String subject;
  final String description;
  final int reference;
  final String prefix;
}

class _Header {
  _Header(this.userId, this.entity);
  final String userId;
  final _EntityHeader entity;
}
