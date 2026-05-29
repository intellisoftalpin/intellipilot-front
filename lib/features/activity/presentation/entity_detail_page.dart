import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/router/app_router.dart';
import 'package:intellipilot/core/storage/hive_boxes.dart';
import 'package:intellipilot/core/ui/breadcrumb_bar.dart';
import 'package:intellipilot/core/ui/breakpoints.dart';
import 'package:intellipilot/core/ui/markdown_text.dart';
import 'package:intellipilot/core/ui/timestamps.dart';
import 'package:intellipilot/features/activity/data/dtos/activity_dtos.dart';
import 'package:intellipilot/features/activity/domain/activity_repository.dart';
import 'package:intellipilot/features/activity/presentation/cubits/activity_stream_cubit.dart';
import 'package:intellipilot/features/activity/presentation/cubits/attachments_cubit.dart';
import 'package:intellipilot/features/activity/presentation/widgets/activity_stream_view.dart';
import 'package:intellipilot/features/activity/presentation/widgets/attachments_view.dart';
import 'package:intellipilot/features/backlog/data/dtos/backlog_dtos.dart';
import 'package:intellipilot/features/backlog/domain/backlog_repository.dart';
import 'package:intellipilot/features/catalog/data/dtos/catalog_dtos.dart';
import 'package:intellipilot/features/catalog/domain/catalog_repository.dart';
import 'package:intellipilot/features/links/domain/links_repository.dart';
import 'package:intellipilot/features/links/presentation/cubits/links_cubit.dart';
import 'package:intellipilot/features/links/presentation/widgets/links_panel.dart';
import 'package:intellipilot/features/milestones/data/dtos/milestone_dtos.dart';
import 'package:intellipilot/features/milestones/domain/milestones_repository.dart';
import 'package:intellipilot/features/profile/data/dtos/profile_dtos.dart';
import 'package:intellipilot/features/profile/domain/profile_repository.dart';
import 'package:intellipilot/features/projects/data/dtos/project_dtos.dart';
import 'package:intellipilot/features/projects/domain/permission.dart';
import 'package:intellipilot/features/projects/domain/projects_repository.dart';
import 'package:intellipilot/features/projects/presentation/cubits/project_detail_cubit.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// Jira-inspired entity detail page: breadcrumb + title + action bar over a
/// two-column body (wide left with Details / Description / Attachments /
/// Activity, narrow right with People + Dates). Collapses to a single
/// column at compact widths. Same route handles all four backlog entity
/// kinds — content within the panels adapts to the kind.
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
  static const _maxBytes = 25 * 1024 * 1024;

  late Future<_PageData?> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  void _reload() {
    // Block body, not `=> _future = _load()` — that arrow form returns the
    // Future the assignment evaluates to, which setState rejects as
    // "callback returned a Future" in strict mode.
    setState(() {
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return FutureBuilder<_PageData?>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final data = snap.data;
        if (data == null) {
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
                currentUserId: data.profile.id,
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
            BlocProvider<LinksCubit>(
              create: (_) => LinksCubit(
                repo: getIt<LinksRepository>(),
                projectId: widget.projectId,
                kind: widget.kind,
                entityId: widget.entityId,
              )..load(),
            ),
          ],
          child: _DetailView(
            data: data,
            kind: widget.kind,
            entityId: widget.entityId,
            projectId: widget.projectId,
            onChanged: _reload,
          ),
        );
      },
    );
  }

  Future<_PageData?> _load() async {
    final profileRes = await getIt<ProfileRepository>().getProfile();
    final profile = profileRes.valueOrNull;
    if (profile == null) return null;
    final backlog = getIt<BacklogRepository>();
    final catalog = getIt<CatalogRepository>();
    final milestones = getIt<MilestonesRepository>();
    final projects = getIt<ProjectsRepository>();

    // Fetch the entity + project + kind-specific lookups in parallel.
    final project =
        (await projects.getProject(widget.projectId)).valueOrNull;
    if (project == null) return null;

    _EntityRecord? entity;
    switch (widget.kind) {
      case EntityKind.epic:
        final v = (await backlog.getEpic(widget.projectId, widget.entityId))
            .valueOrNull;
        if (v != null) entity = _EntityRecord.epic(v);
      case EntityKind.userStory:
        final v = (await backlog.getUserStory(widget.projectId, widget.entityId))
            .valueOrNull;
        if (v != null) entity = _EntityRecord.userStory(v);
      case EntityKind.task:
        final v = (await backlog.getTask(widget.projectId, widget.entityId))
            .valueOrNull;
        if (v != null) entity = _EntityRecord.task(v);
      case EntityKind.issue:
        final v = (await backlog.getIssue(widget.projectId, widget.entityId))
            .valueOrNull;
        if (v != null) entity = _EntityRecord.issue(v);
    }
    if (entity == null) return null;

    // Resolve every taxonomy item used by the kind so we can render
    // status/type/priority/severity/points names.
    final lookups = <Future<dynamic>>[];
    lookups.add(catalog.listTaxonomy(widget.projectId, TaxonomyKind.usStatus));
    lookups.add(catalog.listTaxonomy(widget.projectId, TaxonomyKind.taskStatus));
    lookups.add(catalog.listTaxonomy(widget.projectId, TaxonomyKind.issueStatus));
    lookups.add(catalog.listTaxonomy(widget.projectId, TaxonomyKind.issueType));
    lookups.add(catalog.listTaxonomy(widget.projectId, TaxonomyKind.priority));
    lookups.add(catalog.listTaxonomy(widget.projectId, TaxonomyKind.severity));
    lookups.add(catalog.listTaxonomy(widget.projectId, TaxonomyKind.point));
    lookups.add(catalog.listLabels(widget.projectId));
    lookups.add(catalog.listComponents(widget.projectId));
    lookups.add(backlog.listEpics(widget.projectId));
    lookups.add(backlog.listUserStories(widget.projectId));
    lookups.add(milestones.list(widget.projectId));
    lookups.add(backlog.listTasks(widget.projectId));
    lookups.add(backlog.listIssues(widget.projectId));
    final results = await Future.wait(lookups);

    List<T> resolve<T>(int i) =>
        (results[i] as dynamic).valueOrNull as List<T>? ?? <T>[];
    final taxonomyAll = <TaxonomyItem>[
      ...resolve<TaxonomyItem>(0),
      ...resolve<TaxonomyItem>(1),
      ...resolve<TaxonomyItem>(2),
      ...resolve<TaxonomyItem>(3),
      ...resolve<TaxonomyItem>(4),
      ...resolve<TaxonomyItem>(5),
      ...resolve<TaxonomyItem>(6),
    ];
    return _PageData(
      profile: profile,
      project: project,
      entity: entity,
      taxonomyById: {for (final t in taxonomyAll) t.id: t},
      labelsById: {for (final l in resolve<Label>(7)) l.id: l},
      componentsById: {for (final c in resolve<Component>(8)) c.id: c},
      epicsById: {for (final e in resolve<Epic>(9)) e.id: e},
      userStoriesById: {for (final u in resolve<UserStory>(10)) u.id: u},
      milestonesById: {for (final m in resolve<Milestone>(11)) m.id: m},
      tasksById: {for (final t in resolve<Task>(12)) t.id: t},
      issuesById: {for (final i in resolve<Issue>(13)) i.id: i},
    );
  }
}

// ---------------------------------------------------------------------------
// Loaded data structures
// ---------------------------------------------------------------------------

class _PageData {
  _PageData({
    required this.profile,
    required this.project,
    required this.entity,
    required this.taxonomyById,
    required this.labelsById,
    required this.componentsById,
    required this.epicsById,
    required this.userStoriesById,
    required this.milestonesById,
    required this.tasksById,
    required this.issuesById,
  });

  final UserProfile profile;
  final Project project;
  final _EntityRecord entity;
  final Map<String, TaxonomyItem> taxonomyById;
  final Map<String, Label> labelsById;
  final Map<String, Component> componentsById;
  final Map<String, Epic> epicsById;
  final Map<String, UserStory> userStoriesById;
  final Map<String, Milestone> milestonesById;
  final Map<String, Task> tasksById;
  final Map<String, Issue> issuesById;
}

sealed class _EntityRecord {
  const _EntityRecord();
  factory _EntityRecord.epic(Epic e) = _EpicRec;
  factory _EntityRecord.userStory(UserStory u) = _UsRec;
  factory _EntityRecord.task(Task t) = _TaskRec;
  factory _EntityRecord.issue(Issue i) = _IssueRec;

  String get subject;
  String get description;
  int get reference;
  String get prefix;
  String? get statusId;
  String? get assignedTo;
  String? get ownerId;
  DateTime get createdAt;
  DateTime get modifiedAt;
  String get kindLabelKey;
}

class _EpicRec extends _EntityRecord {
  _EpicRec(this.epic);
  final Epic epic;
  @override
  String get subject => epic.subject;
  @override
  String get description => epic.description;
  @override
  int get reference => epic.reference;
  @override
  String get prefix => 'EPIC';
  @override
  String? get statusId => epic.statusId;
  @override
  String? get assignedTo => epic.assignedTo;
  @override
  String? get ownerId => epic.ownerId;
  @override
  DateTime get createdAt => epic.createdAt;
  @override
  DateTime get modifiedAt => epic.modifiedAt;
  @override
  String get kindLabelKey => 'Epic';
}

class _UsRec extends _EntityRecord {
  _UsRec(this.us);
  final UserStory us;
  @override
  String get subject => us.subject;
  @override
  String get description => us.description;
  @override
  int get reference => us.reference;
  @override
  String get prefix => 'US';
  @override
  String? get statusId => us.statusId;
  @override
  String? get assignedTo => us.assignedTo;
  @override
  String? get ownerId => us.ownerId;
  @override
  DateTime get createdAt => us.createdAt;
  @override
  DateTime get modifiedAt => us.modifiedAt;
  @override
  String get kindLabelKey => 'User story';
}

class _TaskRec extends _EntityRecord {
  _TaskRec(this.task);
  final Task task;
  @override
  String get subject => task.subject;
  @override
  String get description => task.description;
  @override
  int get reference => task.reference;
  @override
  String get prefix => 'T';
  @override
  String? get statusId => task.statusId;
  @override
  String? get assignedTo => task.assignedTo;
  @override
  String? get ownerId => task.ownerId;
  @override
  DateTime get createdAt => task.createdAt;
  @override
  DateTime get modifiedAt => task.modifiedAt;
  @override
  String get kindLabelKey => 'Task';
}

class _IssueRec extends _EntityRecord {
  _IssueRec(this.issue);
  final Issue issue;
  @override
  String get subject => issue.subject;
  @override
  String get description => issue.description;
  @override
  int get reference => issue.reference;
  @override
  String get prefix => 'ISSUE';
  @override
  String? get statusId => issue.statusId;
  @override
  String? get assignedTo => issue.assignedTo;
  @override
  String? get ownerId => issue.ownerId;
  @override
  DateTime get createdAt => issue.createdAt;
  @override
  DateTime get modifiedAt => issue.modifiedAt;
  @override
  String get kindLabelKey => 'Issue';
}

// ---------------------------------------------------------------------------
// The Jira-style detail view
// ---------------------------------------------------------------------------

class _DetailView extends StatelessWidget {
  const _DetailView({
    required this.data,
    required this.kind,
    required this.entityId,
    required this.projectId,
    required this.onChanged,
  });

  final _PageData data;
  final EntityKind kind;
  final String entityId;
  final String projectId;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final entity = data.entity;
    final t = AppLocalizations.of(context);
    final isWide = Breakpoints.of(context).isExpanded;
    final key = '${entity.prefix}-${entity.reference}';
    return Scaffold(
      appBar: AppBar(
        title: BreadcrumbBar(
          crumbs: [
            Crumb(
              label: t.projectsTitle,
              onTap: () => context.go(Routes.projects),
            ),
            Crumb(
              label: data.project.name,
              onTap: () =>
                  context.go(Routes.projectDetailFor(data.project.id)),
            ),
            Crumb(label: key, mono: true),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: _SubjectEditor(
                entity: entity,
                kind: kind,
                projectId: projectId,
                entityId: entityId,
                onChanged: onChanged,
              ),
            ),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ActionBar(
              data: data,
              kind: kind,
              entityId: entityId,
              projectId: projectId,
              onChanged: onChanged,
            ),
            const SizedBox(height: 12),
            if (isWide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 5, child: _LeftColumn(
                    data: data,
                    kind: kind,
                    entityId: entityId,
                    projectId: projectId,
                    onChanged: onChanged,
                  )),
                  const SizedBox(width: 16),
                  Expanded(flex: 3, child: _RightColumn(
                    data: data,
                    kind: kind,
                    entityId: entityId,
                    projectId: projectId,
                    onChanged: onChanged,
                  )),
                ],
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _LeftColumn(
                    data: data,
                    kind: kind,
                    entityId: entityId,
                    projectId: projectId,
                    onChanged: onChanged,
                  ),
                  const SizedBox(height: 12),
                  _RightColumn(
                    data: data,
                    kind: kind,
                    entityId: entityId,
                    projectId: projectId,
                    onChanged: onChanged,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Action bar
// ---------------------------------------------------------------------------

/// Click-to-edit description panel — Jira-style. Display renders the
/// stored markdown; tap switches to a multiline text field for raw
/// markdown editing. Save PATCHes via the shared dispatcher.
class _DescriptionEditor extends StatelessWidget {
  const _DescriptionEditor({
    required this.data,
    required this.kind,
    required this.entityId,
    required this.projectId,
    required this.onChanged,
  });

  final _PageData data;
  final EntityKind kind;
  final String entityId;
  final String projectId;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final canEdit = context.select<ProjectDetailCubit, bool>((c) {
      final s = c.state;
      return s is ProjectDetailLoaded && s.has(_modifyPermissionFor(kind));
    });
    return _InlineTextEditor(
      value: data.entity.description,
      canEdit: canEdit,
      multiline: true,
      placeholder: t.descriptionPlaceholder,
      displayBuilder: (_) => MarkdownText(data.entity.description),
      onSave: (next) async {
        final ok = await _patchEntityKind(
          kind: kind,
          projectId: projectId,
          entityId: entityId,
          epicPatch: () => UpdateEpicRequest(description: next),
          usPatch: () => UpdateUserStoryRequest(description: next),
          taskPatch: () => UpdateTaskRequest(description: next),
          issuePatch: () => UpdateIssueRequest(description: next),
        );
        if (ok) onChanged();
        return ok;
      },
    );
  }
}

/// Inline-editable title in the app bar. Renders the entity subject
/// as a bold heading; click-to-edit switches to a TextField. Save
/// PATCHes the subject for any kind via the shared dispatcher.
class _SubjectEditor extends StatelessWidget {
  const _SubjectEditor({
    required this.entity,
    required this.kind,
    required this.projectId,
    required this.entityId,
    required this.onChanged,
  });

  final _EntityRecord entity;
  final EntityKind kind;
  final String projectId;
  final String entityId;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canEdit = context.select<ProjectDetailCubit, bool>((c) {
      final s = c.state;
      return s is ProjectDetailLoaded && s.has(_modifyPermissionFor(kind));
    });
    return _InlineTextEditor(
      value: entity.subject,
      canEdit: canEdit,
      displayStyle: theme.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
      ),
      onSave: (next) async {
        final trimmed = next.trim();
        if (trimmed.isEmpty) return false;
        final ok = await _patchEntityKind(
          kind: kind,
          projectId: projectId,
          entityId: entityId,
          epicPatch: () => UpdateEpicRequest(subject: trimmed),
          usPatch: () => UpdateUserStoryRequest(subject: trimmed),
          taskPatch: () => UpdateTaskRequest(subject: trimmed),
          issuePatch: () => UpdateIssueRequest(subject: trimmed),
        );
        if (ok) onChanged();
        return ok;
      },
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.data,
    required this.kind,
    required this.entityId,
    required this.projectId,
    required this.onChanged,
  });

  final _PageData data;
  final EntityKind kind;
  final String entityId;
  final String projectId;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final status = data.entity.statusId == null
        ? null
        : data.taxonomyById[data.entity.statusId!];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        BlocBuilder<ProjectDetailCubit, ProjectDetailState>(
          builder: (context, state) {
            if (state is! ProjectDetailLoaded ||
                !state.has(_modifyPermission(kind))) {
              return const SizedBox.shrink();
            }
            return FilledButton.tonalIcon(
              icon: const Icon(Icons.edit_outlined, size: 16),
              onPressed: () => context.go(
                Routes.entityEditFor(projectId, kind, entityId),
              ),
              label: Text(t.actionEdit),
            );
          },
        ),
        FilledButton.tonalIcon(
          icon: const Icon(Icons.chat_bubble_outline, size: 16),
          onPressed: () {
            // Best effort: surface the activity tab area via scroll;
            // the composer focuses on its own when tapped.
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(t.entityActionScrollHint),
                duration: const Duration(seconds: 1),
              ),
            );
          },
          label: Text(t.entityActionComment),
        ),
        if (status != null)
          _StatusPill(status: status, onChanged: onChanged, kind: kind, entityId: entityId, projectId: projectId, data: data),
      ],
    );
  }

  Permission _modifyPermission(EntityKind kind) => switch (kind) {
    EntityKind.epic => Permission.epicModify,
    EntityKind.userStory => Permission.usModify,
    EntityKind.task => Permission.taskModify,
    EntityKind.issue => Permission.issueModify,
  };
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.status,
    required this.onChanged,
    required this.kind,
    required this.entityId,
    required this.projectId,
    required this.data,
  });

  final TaxonomyItem status;
  final VoidCallback onChanged;
  final EntityKind kind;
  final String entityId;
  final String projectId;
  final _PageData data;

  @override
  Widget build(BuildContext context) {
    final c = _hexToColor(status.color);
    final foreground =
        c.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;
    final perm = _statusChangePermission(kind);
    final canChange = context.select<ProjectDetailCubit, bool>((cubit) {
      final s = cubit.state;
      return s is ProjectDetailLoaded && s.has(perm);
    });
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            status.name.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
              color: foreground.withValues(alpha: 0.9),
            ),
          ),
          if (canChange) ...[
            const SizedBox(width: 6),
            Icon(Icons.arrow_drop_down,
                size: 16, color: foreground.withValues(alpha: 0.7)),
          ],
        ],
      ),
    );
    if (!canChange) return pill;
    return PopupMenuButton<String?>(
      tooltip: AppLocalizations.of(context).entityChangeStatusTooltip,
      itemBuilder: (_) {
        final candidates = _statusCandidates(kind, data.taxonomyById);
        return [
          for (final s in candidates)
            PopupMenuItem<String?>(
              value: s.id,
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: _hexToColor(s.color),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(s.name),
                ],
              ),
            ),
        ];
      },
      onSelected: (newStatusId) async {
        if (newStatusId == null) return;
        await _patchStatus(newStatusId);
        onChanged();
      },
      child: pill,
    );
  }

  Permission _statusChangePermission(EntityKind kind) => switch (kind) {
    EntityKind.epic => Permission.epicModify,
    EntityKind.userStory => Permission.usModify,
    EntityKind.task => Permission.taskModify,
    EntityKind.issue => Permission.issueModify,
  };

  List<TaxonomyItem> _statusCandidates(
    EntityKind kind,
    Map<String, TaxonomyItem> taxonomy,
  ) {
    final target = switch (kind) {
      EntityKind.epic => TaxonomyKind.usStatus, // epics share US statuses
      EntityKind.userStory => TaxonomyKind.usStatus,
      EntityKind.task => TaxonomyKind.taskStatus,
      EntityKind.issue => TaxonomyKind.issueStatus,
    };
    final list =
        taxonomy.values.where((t) => t.kind == target).toList()
          ..sort((a, b) => a.order.compareTo(b.order));
    return list;
  }

  Future<void> _patchStatus(String targetStatusId) async {
    final backlog = getIt<BacklogRepository>();
    switch (kind) {
      case EntityKind.epic:
        final fresh = (await backlog.getEpic(projectId, entityId)).valueOrNull;
        if (fresh?.etag == null) return;
        await backlog.updateEpic(
          projectId,
          entityId,
          body: UpdateEpicRequest(statusId: targetStatusId),
          etag: fresh!.etag!,
        );
      case EntityKind.userStory:
        final fresh =
            (await backlog.getUserStory(projectId, entityId)).valueOrNull;
        if (fresh?.etag == null) return;
        await backlog.updateUserStory(
          projectId,
          entityId,
          body: UpdateUserStoryRequest(statusId: targetStatusId),
          etag: fresh!.etag!,
        );
      case EntityKind.task:
        final fresh = (await backlog.getTask(projectId, entityId)).valueOrNull;
        if (fresh?.etag == null) return;
        await backlog.updateTask(
          projectId,
          entityId,
          body: UpdateTaskRequest(statusId: targetStatusId),
          etag: fresh!.etag!,
        );
      case EntityKind.issue:
        final fresh = (await backlog.getIssue(projectId, entityId)).valueOrNull;
        if (fresh?.etag == null) return;
        await backlog.updateIssue(
          projectId,
          entityId,
          body: UpdateIssueRequest(statusId: targetStatusId),
          etag: fresh!.etag!,
        );
    }
  }
}

// ---------------------------------------------------------------------------
// Columns + panels
// ---------------------------------------------------------------------------

class _LeftColumn extends StatelessWidget {
  const _LeftColumn({
    required this.data,
    required this.kind,
    required this.entityId,
    required this.projectId,
    required this.onChanged,
  });
  final _PageData data;
  final EntityKind kind;
  final String entityId;
  final String projectId;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Panel(
          title: AppLocalizations.of(context).panelDetails,
          child: _DetailsTable(
            data: data,
            kind: kind,
            entityId: entityId,
            projectId: projectId,
            onChanged: onChanged,
          ),
        ),
        const SizedBox(height: 12),
        _Panel(
          title: AppLocalizations.of(context).panelDescription,
          child: _DescriptionEditor(
            data: data,
            kind: kind,
            entityId: entityId,
            projectId: projectId,
            onChanged: onChanged,
          ),
        ),
        const SizedBox(height: 12),
        _Panel(
          title: AppLocalizations.of(context).panelLinks,
          child: LinksPanelContent(
            projectId: data.project.id,
            sourceKind: kind,
            sourceId: entityId,
            modifyPermission: _modifyPermissionFor(kind),
            lookup: LinksLookup(
              epics: data.epicsById,
              userStories: data.userStoriesById,
              tasks: data.tasksById,
              issues: data.issuesById,
            ),
          ),
        ),
        const SizedBox(height: 12),
        _Panel(
          title: AppLocalizations.of(context).panelAttachments,
          child: const AttachmentsView(shrinkWrap: true),
        ),
        const SizedBox(height: 12),
        _Panel(
          title: AppLocalizations.of(context).panelActivity,
          child: ActivityStreamView(
            draftKey: '${kind.wire}:$entityId',
            shrinkWrap: true,
          ),
        ),
      ],
    );
  }
}

class _RightColumn extends StatelessWidget {
  const _RightColumn({
    required this.data,
    required this.kind,
    required this.entityId,
    required this.projectId,
    required this.onChanged,
  });
  final _PageData data;
  final EntityKind kind;
  final String entityId;
  final String projectId;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Panel(
          title: AppLocalizations.of(context).panelPeople,
          child: _PeopleTable(
            data: data,
            kind: kind,
            entityId: entityId,
            projectId: projectId,
            onChanged: onChanged,
          ),
        ),
        const SizedBox(height: 12),
        _Panel(
          title: AppLocalizations.of(context).panelDates,
          child: _DatesTable(data: data),
        ),
      ],
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              title,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                letterSpacing: 0.4,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: child,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Details / People / Dates rendering
// ---------------------------------------------------------------------------

class _DetailsTable extends StatelessWidget {
  const _DetailsTable({
    required this.data,
    required this.kind,
    required this.entityId,
    required this.projectId,
    required this.onChanged,
  });
  final _PageData data;
  final EntityKind kind;
  final String entityId;
  final String projectId;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final entity = data.entity;
    final canEdit = context.select<ProjectDetailCubit, bool>((c) {
      final s = c.state;
      return s is ProjectDetailLoaded && s.has(_modifyPermissionFor(kind));
    });
    final rows = <Widget>[
      _readonlyRow(context, t.detailFieldType, _kindLabel(t, entity)),
      _statusRow(context, canEdit: canEdit),
    ];
    switch (entity) {
      case _IssueRec(:final issue):
        rows.addAll([
          _taxonomyRow(
            context,
            label: t.detailFieldIssueType,
            currentId: issue.typeId,
            kind: TaxonomyKind.issueType,
            canEdit: canEdit,
            patch: (id) => _patchEntity(
              issuePatch: () => UpdateIssueRequest(typeId: id),
            ),
          ),
          _taxonomyRow(
            context,
            label: t.detailFieldPriority,
            currentId: issue.priorityId,
            kind: TaxonomyKind.priority,
            canEdit: canEdit,
            patch: (id) => _patchEntity(
              issuePatch: () => UpdateIssueRequest(priorityId: id),
            ),
          ),
          _taxonomyRow(
            context,
            label: t.detailFieldSeverity,
            currentId: issue.severityId,
            kind: TaxonomyKind.severity,
            canEdit: canEdit,
            patch: (id) => _patchEntity(
              issuePatch: () => UpdateIssueRequest(severityId: id),
            ),
          ),
          _labelsRow(
            context,
            currentIds: issue.labels,
            canEdit: canEdit,
          ),
          _componentsRow(
            context,
            currentIds: issue.components,
            canEdit: canEdit,
          ),
        ]);
      case _UsRec(:final us):
        rows.addAll([
          _epicRow(context, currentId: us.epicId, canEdit: canEdit),
          _milestoneRow(context, currentId: us.milestoneId, canEdit: canEdit),
          _taxonomyRow(
            context,
            label: t.detailFieldPoints,
            currentId: us.pointsId,
            kind: TaxonomyKind.point,
            canEdit: canEdit,
            displayBuilder: (item) => item.value == null
                ? item.name
                : '${item.name} (${item.value})',
            patch: (id) => _patchEntity(
              usPatch: () => UpdateUserStoryRequest(pointsId: id),
            ),
          ),
        ]);
      case _TaskRec(:final task):
        rows.add(_parentUsRow(
          context,
          currentId: task.userStoryId,
          canEdit: canEdit,
        ));
      case _EpicRec():
        break;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: row,
          ),
      ],
    );
  }

  // ---- row builders ------------------------------------------------------

  Widget _readonlyRow(BuildContext context, String label, String value) =>
      _kvRow(context, label, value);

  Widget _statusRow(BuildContext context, {required bool canEdit}) {
    final t = AppLocalizations.of(context);
    final entity = data.entity;
    final taxonomyKind = switch (kind) {
      EntityKind.epic => TaxonomyKind.usStatus, // epics share US statuses
      EntityKind.userStory => TaxonomyKind.usStatus,
      EntityKind.task => TaxonomyKind.taskStatus,
      EntityKind.issue => TaxonomyKind.issueStatus,
    };
    return _taxonomyRow(
      context,
      label: t.detailFieldStatus,
      currentId: entity.statusId,
      kind: taxonomyKind,
      canEdit: canEdit,
      patch: (id) => _patchEntity(
        epicPatch: () => UpdateEpicRequest(statusId: id),
        usPatch: () => UpdateUserStoryRequest(statusId: id),
        taskPatch: () => UpdateTaskRequest(statusId: id),
        issuePatch: () => UpdateIssueRequest(statusId: id),
      ),
    );
  }

  Widget _taxonomyRow(
    BuildContext context, {
    required String label,
    required String? currentId,
    required TaxonomyKind kind,
    required bool canEdit,
    required Future<bool> Function(String? newId) patch,
    String Function(TaxonomyItem)? displayBuilder,
  }) {
    final t = AppLocalizations.of(context);
    final all = data.taxonomyById.values
        .where((tx) => tx.kind == kind)
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    final current = currentId == null ? null : data.taxonomyById[currentId];
    final renderLabel = displayBuilder ?? (TaxonomyItem item) => item.name;
    return _editableRow(
      context,
      label: label,
      displayText: current == null ? '—' : renderLabel(current),
      currentId: currentId,
      noneLabel: t.statusValueNone,
      canEdit: canEdit,
      candidates: [
        for (final item in all)
          _Candidate(
            id: item.id,
            label: renderLabel(item),
            colorHex: item.color,
          ),
      ],
      onPicked: patch,
    );
  }

  Widget _epicRow(
    BuildContext context, {
    required String? currentId,
    required bool canEdit,
  }) {
    final t = AppLocalizations.of(context);
    final epics = data.epicsById.values.toList()
      ..sort((a, b) => a.reference.compareTo(b.reference));
    final current = currentId == null ? null : data.epicsById[currentId];
    return _editableRow(
      context,
      label: t.detailFieldEpic,
      displayText:
          current == null ? '—' : 'EPIC-${current.reference} · ${current.subject}',
      currentId: currentId,
      noneLabel: t.backlogNoEpic,
      canEdit: canEdit,
      candidates: [
        for (final e in epics)
          _Candidate(
            id: e.id,
            label: 'EPIC-${e.reference} · ${e.subject}',
            colorHex: e.color,
          ),
      ],
      onPicked: (id) => _patchEntity(
        usPatch: () => UpdateUserStoryRequest(epicId: id),
      ),
    );
  }

  Widget _milestoneRow(
    BuildContext context, {
    required String? currentId,
    required bool canEdit,
  }) {
    final t = AppLocalizations.of(context);
    final milestones = data.milestonesById.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final current =
        currentId == null ? null : data.milestonesById[currentId];
    return _editableRow(
      context,
      label: t.detailFieldMilestone,
      displayText: current?.name ?? '—',
      currentId: currentId,
      noneLabel: t.statusValueNone,
      canEdit: canEdit,
      candidates: [
        for (final m in milestones) _Candidate(id: m.id, label: m.name),
      ],
      onPicked: (id) => _patchEntity(
        usPatch: () => UpdateUserStoryRequest(milestoneId: id),
      ),
    );
  }

  Widget _parentUsRow(
    BuildContext context, {
    required String? currentId,
    required bool canEdit,
  }) {
    final t = AppLocalizations.of(context);
    final stories = data.userStoriesById.values.toList()
      ..sort((a, b) => a.reference.compareTo(b.reference));
    final current =
        currentId == null ? null : data.userStoriesById[currentId];
    return _editableRow(
      context,
      label: t.detailFieldParent,
      displayText: current == null
          ? '—'
          : 'US-${current.reference} · ${current.subject}',
      currentId: currentId,
      noneLabel: t.taskNoParent,
      canEdit: canEdit,
      candidates: [
        for (final u in stories)
          _Candidate(
            id: u.id,
            label: 'US-${u.reference} · ${u.subject}',
          ),
      ],
      onPicked: (id) => _patchEntity(
        taskPatch: () => UpdateTaskRequest(userStoryId: id),
      ),
    );
  }

  Widget _labelsRow(
    BuildContext context, {
    required List<String> currentIds,
    required bool canEdit,
  }) {
    final t = AppLocalizations.of(context);
    final all = data.labelsById.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return _kvRowWith(
      context,
      t.detailFieldLabels,
      _MultiSelectCell(
        displayText: _labelList(currentIds, data.labelsById),
        candidates: [
          for (final l in all)
            _MultiCandidate(id: l.id, label: l.name, colorHex: l.color),
        ],
        selectedIds: currentIds,
        title: t.detailFieldLabels,
        emptyLabel: '—',
        canEdit: canEdit,
        onSaved: (next) => _patchEntity(
          issuePatch: () => UpdateIssueRequest(labels: next),
        ),
      ),
    );
  }

  Widget _componentsRow(
    BuildContext context, {
    required List<String> currentIds,
    required bool canEdit,
  }) {
    final t = AppLocalizations.of(context);
    final all = data.componentsById.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return _kvRowWith(
      context,
      t.detailFieldComponents,
      _MultiSelectCell(
        displayText: _componentList(currentIds, data.componentsById),
        candidates: [
          for (final c in all) _MultiCandidate(id: c.id, label: c.name),
        ],
        selectedIds: currentIds,
        title: t.detailFieldComponents,
        emptyLabel: '—',
        canEdit: canEdit,
        onSaved: (next) => _patchEntity(
          issuePatch: () => UpdateIssueRequest(components: next),
        ),
      ),
    );
  }

  /// Top-level patch dispatcher used by every editable row. The caller
  /// passes only the builder for its kind; others are null. Fetches the
  /// fresh entity for its etag, runs the PATCH, and triggers `onChanged`
  /// on success so the page reloads.
  Future<bool> _patchEntity({
    UpdateEpicRequest Function()? epicPatch,
    UpdateUserStoryRequest Function()? usPatch,
    UpdateTaskRequest Function()? taskPatch,
    UpdateIssueRequest Function()? issuePatch,
  }) async {
    final backlog = getIt<BacklogRepository>();
    var ok = false;
    switch (kind) {
      case EntityKind.epic:
        if (epicPatch == null) return false;
        final fresh =
            (await backlog.getEpic(projectId, entityId)).valueOrNull;
        if (fresh?.etag == null) return false;
        final res = await backlog.updateEpic(
          projectId,
          entityId,
          body: epicPatch(),
          etag: fresh!.etag!,
        );
        ok = res.isOk;
      case EntityKind.userStory:
        if (usPatch == null) return false;
        final fresh =
            (await backlog.getUserStory(projectId, entityId)).valueOrNull;
        if (fresh?.etag == null) return false;
        final res = await backlog.updateUserStory(
          projectId,
          entityId,
          body: usPatch(),
          etag: fresh!.etag!,
        );
        ok = res.isOk;
      case EntityKind.task:
        if (taskPatch == null) return false;
        final fresh =
            (await backlog.getTask(projectId, entityId)).valueOrNull;
        if (fresh?.etag == null) return false;
        final res = await backlog.updateTask(
          projectId,
          entityId,
          body: taskPatch(),
          etag: fresh!.etag!,
        );
        ok = res.isOk;
      case EntityKind.issue:
        if (issuePatch == null) return false;
        final fresh =
            (await backlog.getIssue(projectId, entityId)).valueOrNull;
        if (fresh?.etag == null) return false;
        final res = await backlog.updateIssue(
          projectId,
          entityId,
          body: issuePatch(),
          etag: fresh!.etag!,
        );
        ok = res.isOk;
    }
    if (ok) onChanged();
    return ok;
  }

  Widget _editableRow(
    BuildContext context, {
    required String label,
    required String displayText,
    required String? currentId,
    required String noneLabel,
    required bool canEdit,
    required List<_Candidate> candidates,
    required Future<bool> Function(String? newId) onPicked,
  }) {
    return _kvRowWith(
      context,
      label,
      _ClickToEditCell(
        displayText: displayText,
        candidates: candidates,
        currentId: currentId,
        noneLabel: noneLabel,
        canEdit: canEdit,
        onPicked: onPicked,
      ),
    );
  }

  String _kindLabel(AppLocalizations t, _EntityRecord e) => switch (e) {
    _EpicRec() => t.kindLabelEpic,
    _UsRec() => t.kindLabelUserStory,
    _TaskRec() => t.kindLabelTask,
    _IssueRec() => t.kindLabelIssue,
  };

  String _labelList(List<String> ids, Map<String, Label> by) =>
      ids.isEmpty ? '—' : ids.map((id) => by[id]?.name ?? id).join(', ');
  String _componentList(List<String> ids, Map<String, Component> by) =>
      ids.isEmpty ? '—' : ids.map((id) => by[id]?.name ?? id).join(', ');
}

class _Candidate {
  const _Candidate({
    required this.id,
    required this.label,
    this.colorHex,
    this.icon,
    this.pinned = false,
  });
  final String id;
  final String label;
  final String? colorHex;

  /// Optional Material icon used in place of the colored bullet. Useful
  /// for shortcuts like "Assign to me" that aren't taxonomy items.
  final IconData? icon;

  /// Pinned candidates render at the very top of the picker, above the
  /// search results, separated by a divider. Use for shortcuts.
  final bool pinned;
}

/// Sentinel value popped from the searchable picker when the user
/// chooses the "None" row. Translated back to `null` before invoking
/// the caller's handler (PopupMenu routes don't carry nullable values
/// cleanly — null pops are treated as cancellations).
const String _kNoneSentinel = '__none__';

/// Click-to-edit value cell, Jira-style.
///
/// - **Hover reveal**: caret + subtle background only appear on mouse hover.
/// - **Truncation tooltip**: long display text surfaces the full value.
/// - **Searchable picker**: tap → custom MenuAnchor with a filter field at
///   the top and keyboard navigation (↑/↓/Enter/Esc).
/// - **Permission gate**: when [canEdit] is false the row stays tappable
///   so we can surface a SnackBar explaining why nothing happened.
/// - **Optimistic update**: the new value renders immediately with a small
///   spinner overlay during the PATCH; reverts on failure.
class _ClickToEditCell extends StatefulWidget {
  const _ClickToEditCell({
    required this.displayText,
    required this.candidates,
    required this.currentId,
    required this.noneLabel,
    required this.canEdit,
    required this.onPicked,
  });

  final String displayText;
  final List<_Candidate> candidates;
  final String? currentId;
  final String noneLabel;
  final bool canEdit;
  final Future<bool> Function(String? newId) onPicked;

  @override
  State<_ClickToEditCell> createState() => _ClickToEditCellState();
}

class _ClickToEditCellState extends State<_ClickToEditCell> {
  bool _hovering = false;

  /// Display override for the optimistic-update window: shows the
  /// just-picked label until the PATCH resolves; on failure we revert.
  String? _optimisticDisplay;
  bool _saving = false;

  Future<void> _open() async {
    final picked = await _showSearchablePicker(
      context,
      candidates: widget.candidates,
      currentId: widget.currentId,
      noneLabel: widget.noneLabel,
    );
    if (picked == null || !mounted) return;
    final newId = picked == _kNoneSentinel ? null : picked;
    // Optimistic display: figure out what the next display text would be
    final newDisplay = newId == null
        ? '—'
        : widget.candidates
                .where((c) => c.id == newId)
                .cast<_Candidate?>()
                .firstOrNull
                ?.label ??
            '—';
    setState(() {
      _optimisticDisplay = newDisplay;
      _saving = true;
    });
    final ok = await widget.onPicked(newId);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (!ok) _optimisticDisplay = null;
    });
  }

  void _showReadOnlyToast(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).fieldReadOnlyToast),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textStyle = theme.textTheme.bodyMedium;
    final shownText = _optimisticDisplay ?? widget.displayText;
    if (!widget.canEdit) {
      return MouseRegion(
        cursor: SystemMouseCursors.basic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _showReadOnlyToast(context),
          child: Tooltip(
            message: shownText,
            waitDuration: const Duration(milliseconds: 600),
            child: Text(
              shownText,
              style: textStyle,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      );
    }
    final caretVisible = _hovering || _saving;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _saving ? null : _open,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: _hovering
                ? theme.colorScheme.surfaceContainerHighest
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Tooltip(
                  message: shownText,
                  waitDuration: const Duration(milliseconds: 600),
                  child: Text(
                    shownText,
                    style: textStyle,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              if (_saving)
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: theme.colorScheme.primary,
                  ),
                )
              else
                Icon(
                  Icons.unfold_more,
                  size: 14,
                  color: caretVisible
                      ? theme.colorScheme.outline
                      : Colors.transparent,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens the inline searchable picker anchored below [anchorContext].
/// Returns the picked id, the [_kNoneSentinel] for "None", or null if
/// the user dismissed the popup.
Future<String?> _showSearchablePicker(
  BuildContext anchorContext, {
  required List<_Candidate> candidates,
  required String? currentId,
  required String noneLabel,
}) async {
  final anchor = anchorContext.findRenderObject() as RenderBox?;
  final overlay = Overlay.of(anchorContext).context.findRenderObject()
      as RenderBox?;
  if (anchor == null || overlay == null) return null;
  final topLeft = anchor.localToGlobal(Offset.zero, ancestor: overlay);
  final bottomRight =
      anchor.localToGlobal(anchor.size.bottomRight(Offset.zero), ancestor: overlay);
  final position = RelativeRect.fromLTRB(
    topLeft.dx,
    bottomRight.dy + 4,
    overlay.size.width - bottomRight.dx,
    overlay.size.height - bottomRight.dy,
  );
  return showMenu<String>(
    context: anchorContext,
    position: position,
    constraints: const BoxConstraints(minWidth: 240, maxWidth: 320),
    items: [
      _SearchablePickerEntry(
        candidates: candidates,
        currentId: currentId,
        noneLabel: noneLabel,
      ),
    ],
  );
}

/// Custom PopupMenuEntry that hosts the entire searchable picker UI
/// (search field + filtered candidate list with keyboard navigation).
/// The State pops the surrounding popup menu with the chosen id when
/// the user commits.
class _SearchablePickerEntry extends PopupMenuEntry<String> {
  const _SearchablePickerEntry({
    required this.candidates,
    required this.currentId,
    required this.noneLabel,
  });

  final List<_Candidate> candidates;
  final String? currentId;
  final String noneLabel;

  @override
  double get height => 340;

  @override
  bool represents(String? value) => false;

  @override
  State<_SearchablePickerEntry> createState() =>
      _SearchablePickerEntryState();
}

class _SearchablePickerEntryState extends State<_SearchablePickerEntry> {
  late final TextEditingController _searchCtrl;
  late final FocusNode _searchFocus;
  int _highlight = 0;

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController();
    _searchFocus = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  List<_PickerRow> _rows() {
    final q = _searchCtrl.text.trim().toLowerCase();
    bool matches(_Candidate c) =>
        q.isEmpty || c.label.toLowerCase().contains(q);
    final pinned = widget.candidates.where((c) => c.pinned && matches(c));
    final regular = widget.candidates.where((c) => !c.pinned && matches(c));
    final out = <_PickerRow>[
      for (final c in pinned) _PickerRow.candidate(c),
      if (pinned.isNotEmpty) const _PickerRow.divider(),
      const _PickerRow.none(),
      for (final c in regular) _PickerRow.candidate(c),
    ];
    return out;
  }

  void _move(int delta) {
    final rows = _rows();
    final n = rows.length;
    if (n == 0) return;
    var next = _highlight + delta;
    // Skip dividers in both directions.
    while (next >= 0 && next < n && !rows[next].isSelectable) {
      next += delta;
    }
    if (next < 0 || next >= n) return;
    setState(() => _highlight = next);
  }

  void _commitIndex(int index) {
    final rows = _rows();
    if (index < 0 || index >= rows.length) return;
    final row = rows[index];
    if (!row.isSelectable) return;
    Navigator.of(context).pop(
      row.isNone ? _kNoneSentinel : row.candidate!.id,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final rows = _rows();
    if (_highlight >= rows.length) _highlight = rows.length - 1;
    if (_highlight < 0) _highlight = 0;
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.arrowDown): _MoveDownIntent(),
        SingleActivator(LogicalKeyboardKey.arrowUp): _MoveUpIntent(),
        SingleActivator(LogicalKeyboardKey.enter): _CommitIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): _CommitIntent(),
        SingleActivator(LogicalKeyboardKey.escape): _DismissIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _MoveDownIntent: CallbackAction<_MoveDownIntent>(
            onInvoke: (_) {
              _move(1);
              return null;
            },
          ),
          _MoveUpIntent: CallbackAction<_MoveUpIntent>(
            onInvoke: (_) {
              _move(-1);
              return null;
            },
          ),
          _CommitIntent: CallbackAction<_CommitIntent>(
            onInvoke: (_) {
              _commitIndex(_highlight);
              return null;
            },
          ),
          _DismissIntent: CallbackAction<_DismissIntent>(
            onInvoke: (_) {
              Navigator.of(context).pop();
              return null;
            },
          ),
        },
        child: SizedBox(
          height: 340,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: TextField(
                  controller: _searchCtrl,
                  focusNode: _searchFocus,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    hintText: t.pickerSearchHint,
                    prefixIcon: const Icon(Icons.search, size: 16),
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onChanged: (_) => setState(() => _highlight = 0),
                  onSubmitted: (_) => _commitIndex(_highlight),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: rows.length == 1 && rows.first.isNone
                    // Only the None row remains — show "No matches"
                    // alongside it so users know the filter is active.
                    ? _NoMatchesBody(noneRow: rows.first, onTap: () => _commitIndex(0))
                    : ListView.builder(
                        padding: EdgeInsets.zero,
                        itemCount: rows.length,
                        itemBuilder: (context, i) {
                          final row = rows[i];
                          if (row.isDivider) {
                            return const Divider(height: 8, thickness: 1);
                          }
                          final selected = i == _highlight;
                          final isCurrent =
                              row.candidate?.id == widget.currentId;
                          final candidate = row.candidate;
                          return Container(
                            color: selected
                                ? theme.colorScheme.primaryContainer
                                    .withValues(alpha: 0.5)
                                : null,
                            child: InkWell(
                              onTap: () => _commitIndex(i),
                              onHover: (h) {
                                if (h) setState(() => _highlight = i);
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                child: Row(
                                  children: [
                                    if (row.isNone)
                                      Icon(
                                        Icons.block_outlined,
                                        size: 14,
                                        color: theme.colorScheme.outline,
                                      )
                                    else if (candidate?.icon != null)
                                      Icon(
                                        candidate!.icon,
                                        size: 14,
                                        color: theme.colorScheme.primary,
                                      )
                                    else if (candidate?.colorHex != null)
                                      Container(
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(
                                          color: _hexToColor(
                                            candidate!.colorHex!,
                                          ),
                                          shape: BoxShape.circle,
                                        ),
                                      )
                                    else
                                      const SizedBox(width: 10),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        row.isNone
                                            ? widget.noneLabel
                                            : candidate!.label,
                                        style: theme.textTheme.bodyMedium,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (isCurrent) ...[
                                      const SizedBox(width: 8),
                                      Icon(
                                        Icons.check,
                                        size: 14,
                                        color: theme.colorScheme.primary,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoMatchesBody extends StatelessWidget {
  const _NoMatchesBody({required this.noneRow, required this.onTap});
  final _PickerRow noneRow;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(
                  Icons.block_outlined,
                  size: 14,
                  color: theme.colorScheme.outline,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    t.statusValueNone,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: Center(
            child: Text(
              t.pickerNoMatch,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PickerRow {
  const _PickerRow.none()
      : isNone = true,
        isDivider = false,
        candidate = null;
  const _PickerRow.candidate(_Candidate this.candidate)
      : isNone = false,
        isDivider = false;
  const _PickerRow.divider()
      : isNone = false,
        isDivider = true,
        candidate = null;
  final bool isNone;
  final bool isDivider;
  final _Candidate? candidate;

  bool get isSelectable => !isDivider;
}

class _MoveDownIntent extends Intent {
  const _MoveDownIntent();
}

class _MoveUpIntent extends Intent {
  const _MoveUpIntent();
}

class _CommitIntent extends Intent {
  const _CommitIntent();
}

class _DismissIntent extends Intent {
  const _DismissIntent();
}

class _MultiCandidate {
  const _MultiCandidate({
    required this.id,
    required this.label,
    this.colorHex,
  });
  final String id;
  final String label;
  final String? colorHex;
}

/// Click-to-edit cell for multi-select fields (Labels / Components).
/// Tapping opens a dialog of checkboxes; Save PATCHes the full new id
/// list. Read-only fallback when [canEdit] is false.
/// Multi-select inline editor — Jira-style. Renders each selected value
/// as an `InputChip` with a delete (×) icon. Tapping the × removes
/// just that one with an optimistic PATCH. Tapping the "+ Add" affix
/// (or anywhere in the row when nothing is selected) opens the full
/// checkbox dialog.
class _MultiSelectCell extends StatefulWidget {
  const _MultiSelectCell({
    required this.displayText,
    required this.candidates,
    required this.selectedIds,
    required this.title,
    required this.emptyLabel,
    required this.canEdit,
    required this.onSaved,
  });

  final String displayText;
  final List<_MultiCandidate> candidates;
  final List<String> selectedIds;
  final String title;
  final String emptyLabel;
  final bool canEdit;
  final Future<bool> Function(List<String> nextIds) onSaved;

  @override
  State<_MultiSelectCell> createState() => _MultiSelectCellState();
}

class _MultiSelectCellState extends State<_MultiSelectCell> {
  /// Optimistic display state — the in-flight new id list. Replaces
  /// `widget.selectedIds` until the PATCH resolves; reverts on failure.
  List<String>? _optimistic;
  bool _hovering = false;
  bool _saving = false;

  Future<void> _commit(List<String> next) async {
    setState(() {
      _optimistic = next;
      _saving = true;
    });
    final ok = await widget.onSaved(next);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (!ok) _optimistic = null;
    });
  }

  Future<void> _openDialog() async {
    final visible = _optimistic ?? widget.selectedIds;
    final picked = await showDialog<List<String>>(
      context: context,
      builder: (ctx) => _MultiSelectDialog(
        title: widget.title,
        candidates: widget.candidates,
        initial: visible,
        emptyLabel: widget.emptyLabel,
      ),
    );
    if (picked != null) await _commit(picked);
  }

  void _removeOne(String id) {
    final current = _optimistic ?? widget.selectedIds;
    _commit(current.where((x) => x != id).toList());
  }

  void _showReadOnlyToast() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).fieldReadOnlyToast),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textStyle = theme.textTheme.bodyMedium;
    final visibleIds = _optimistic ?? widget.selectedIds;
    final byId = {for (final c in widget.candidates) c.id: c};
    final chips = [
      for (final id in visibleIds)
        if (byId[id] != null) byId[id]!,
    ];

    if (!widget.canEdit) {
      // Read-only: plain text + permission toast on tap.
      return MouseRegion(
        cursor: SystemMouseCursors.basic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _showReadOnlyToast,
          child: Text(
            widget.displayText,
            style: textStyle,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }

    if (chips.isEmpty) {
      // Empty state — clicking anywhere on the row opens the dialog.
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _saving ? null : _openDialog,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 80),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: _hovering
                  ? theme.colorScheme.surfaceContainerHighest
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '—',
                  style: textStyle?.copyWith(color: theme.colorScheme.outline),
                ),
                const SizedBox(width: 4),
                if (_saving)
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: theme.colorScheme.primary,
                    ),
                  )
                else
                  Icon(
                    Icons.add,
                    size: 14,
                    color: _hovering
                        ? theme.colorScheme.outline
                        : Colors.transparent,
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final c in chips)
            InputChip(
              avatar: c.colorHex == null
                  ? null
                  : Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _hexToColor(c.colorHex!),
                        shape: BoxShape.circle,
                      ),
                    ),
              label: Text(c.label),
              onDeleted: _saving ? null : () => _removeOne(c.id),
              deleteIcon: const Icon(Icons.close, size: 14),
              labelPadding:
                  const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _saving ? null : _openDialog,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_saving)
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: theme.colorScheme.primary,
                        ),
                      )
                    else
                      Icon(
                        Icons.add,
                        size: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MultiSelectDialog extends StatefulWidget {
  const _MultiSelectDialog({
    required this.title,
    required this.candidates,
    required this.initial,
    required this.emptyLabel,
  });

  final String title;
  final List<_MultiCandidate> candidates;
  final List<String> initial;
  final String emptyLabel;

  @override
  State<_MultiSelectDialog> createState() => _MultiSelectDialogState();
}

class _MultiSelectDialogState extends State<_MultiSelectDialog> {
  late final Set<String> _picked;

  @override
  void initState() {
    super.initState();
    _picked = widget.initial.toSet();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 360,
        height: 360,
        child: widget.candidates.isEmpty
            ? Center(child: Text(widget.emptyLabel))
            : ListView.builder(
                itemCount: widget.candidates.length,
                itemBuilder: (context, i) {
                  final c = widget.candidates[i];
                  return CheckboxListTile(
                    dense: true,
                    title: Row(
                      children: [
                        if (c.colorHex != null) ...[
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: _hexToColor(c.colorHex!),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Expanded(child: Text(c.label)),
                      ],
                    ),
                    value: _picked.contains(c.id),
                    onChanged: (v) => setState(() {
                      if (v ?? false) {
                        _picked.add(c.id);
                      } else {
                        _picked.remove(c.id);
                      }
                    }),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.actionCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_picked.toList()),
          child: Text(t.actionSave),
        ),
      ],
    );
  }
}

class _PeopleTable extends StatelessWidget {
  const _PeopleTable({
    required this.data,
    required this.kind,
    required this.entityId,
    required this.projectId,
    required this.onChanged,
  });
  final _PageData data;
  final EntityKind kind;
  final String entityId;
  final String projectId;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final me = data.profile.id;
    final canEdit = context.select<ProjectDetailCubit, bool>((c) {
      final s = c.state;
      return s is ProjectDetailLoaded && s.has(_modifyPermissionFor(kind));
    });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _kvRowWith(
          context,
          t.detailFieldAssignee,
          _ClickToEditCell(
            displayText: _userLabel(data.entity.assignedTo, me, t),
            candidates: _assigneeCandidates(t, me),
            currentId: data.entity.assignedTo,
            noneLabel: '—',
            canEdit: canEdit,
            onPicked: (id) async {
              final ok = await _patchAssignee(id);
              if (ok && id != null) {
                await _RecentAssignees.push(projectId, id);
              }
              return ok;
            },
          ),
        ),
        const SizedBox(height: 4),
        // Reporter (ownerId) is read-only at the API layer — none of
        // the UpdateXxxRequest DTOs expose an ownerId field. The
        // creator stays immutable. Surface it as plain text so users
        // don't expect a click-to-edit affordance that the backend
        // would reject.
        _kvRow(
          context,
          t.detailFieldReporter,
          _userLabel(data.entity.ownerId, me, t),
        ),
      ],
    );
  }

  String _userLabel(String? id, String me, AppLocalizations t) {
    if (id == null) return '—';
    if (id == me) return '${t.detailValueYou} ($id)';
    return id;
  }

  /// Build the assignee picker's candidate list:
  /// - "Assign to me" pinned at the top with a person icon (always
  ///   the current user — the most-used Jira shortcut).
  /// - Recent assignees for this project (persisted in the UI Hive
  ///   box). Shows raw user ids today — once the backend exposes
  ///   member display names the labels can swap to those.
  List<_Candidate> _assigneeCandidates(AppLocalizations t, String me) {
    final recent = _RecentAssignees.read(projectId)
        .where((id) => id != me)
        .take(5)
        .toList();
    return [
      _Candidate(
        id: me,
        label: t.assigneeAssignToMe,
        icon: Icons.person_outline,
        pinned: true,
      ),
      for (final id in recent) _Candidate(id: id, label: id),
    ];
  }

  Future<bool> _patchAssignee(String? assigneeId) async {
    final backlog = getIt<BacklogRepository>();
    var ok = false;
    switch (kind) {
      case EntityKind.epic:
        final fresh =
            (await backlog.getEpic(projectId, entityId)).valueOrNull;
        if (fresh?.etag == null) return false;
        final res = await backlog.updateEpic(
          projectId,
          entityId,
          body: UpdateEpicRequest(assignedTo: assigneeId),
          etag: fresh!.etag!,
        );
        ok = res.isOk;
      case EntityKind.userStory:
        final fresh =
            (await backlog.getUserStory(projectId, entityId)).valueOrNull;
        if (fresh?.etag == null) return false;
        final res = await backlog.updateUserStory(
          projectId,
          entityId,
          body: UpdateUserStoryRequest(assignedTo: assigneeId),
          etag: fresh!.etag!,
        );
        ok = res.isOk;
      case EntityKind.task:
        final fresh =
            (await backlog.getTask(projectId, entityId)).valueOrNull;
        if (fresh?.etag == null) return false;
        final res = await backlog.updateTask(
          projectId,
          entityId,
          body: UpdateTaskRequest(assignedTo: assigneeId),
          etag: fresh!.etag!,
        );
        ok = res.isOk;
      case EntityKind.issue:
        final fresh =
            (await backlog.getIssue(projectId, entityId)).valueOrNull;
        if (fresh?.etag == null) return false;
        final res = await backlog.updateIssue(
          projectId,
          entityId,
          body: UpdateIssueRequest(assignedTo: assigneeId),
          etag: fresh!.etag!,
        );
        ok = res.isOk;
    }
    if (ok) onChanged();
    return ok;
  }
}

class _DatesTable extends StatelessWidget {
  const _DatesTable({required this.data});
  final _PageData data;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _kvRow(
          context,
          t.detailFieldCreated,
          formatTimestamp(context, data.entity.createdAt),
        ),
        const SizedBox(height: 4),
        _kvRow(
          context,
          t.detailFieldUpdated,
          formatTimestamp(context, data.entity.modifiedAt),
        ),
      ],
    );
  }
}

Widget _kvRow(BuildContext context, String label, String value) {
  return _kvRowWith(
    context,
    label,
    SelectableText(value, style: Theme.of(context).textTheme.bodyMedium),
  );
}

Widget _kvRowWith(BuildContext context, String label, Widget value) {
  final theme = Theme.of(context);
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 140,
        child: Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      ),
      Expanded(child: value),
    ],
  );
}

Permission _modifyPermissionFor(EntityKind kind) => switch (kind) {
      EntityKind.epic => Permission.epicModify,
      EntityKind.userStory => Permission.usModify,
      EntityKind.task => Permission.taskModify,
      EntityKind.issue => Permission.issueModify,
    };

/// Shared PATCH dispatcher for any field on the entity detail page.
/// The caller passes only the builder matching the active kind; the
/// helper fetches the fresh entity for its etag, runs the PATCH, and
/// returns true on success. Pages are responsible for calling
/// `onChanged()` themselves on the result.
Future<bool> _patchEntityKind({
  required EntityKind kind,
  required String projectId,
  required String entityId,
  UpdateEpicRequest Function()? epicPatch,
  UpdateUserStoryRequest Function()? usPatch,
  UpdateTaskRequest Function()? taskPatch,
  UpdateIssueRequest Function()? issuePatch,
}) async {
  final backlog = getIt<BacklogRepository>();
  switch (kind) {
    case EntityKind.epic:
      if (epicPatch == null) return false;
      final fresh = (await backlog.getEpic(projectId, entityId)).valueOrNull;
      if (fresh?.etag == null) return false;
      final res = await backlog.updateEpic(
        projectId,
        entityId,
        body: epicPatch(),
        etag: fresh!.etag!,
      );
      return res.isOk;
    case EntityKind.userStory:
      if (usPatch == null) return false;
      final fresh =
          (await backlog.getUserStory(projectId, entityId)).valueOrNull;
      if (fresh?.etag == null) return false;
      final res = await backlog.updateUserStory(
        projectId,
        entityId,
        body: usPatch(),
        etag: fresh!.etag!,
      );
      return res.isOk;
    case EntityKind.task:
      if (taskPatch == null) return false;
      final fresh = (await backlog.getTask(projectId, entityId)).valueOrNull;
      if (fresh?.etag == null) return false;
      final res = await backlog.updateTask(
        projectId,
        entityId,
        body: taskPatch(),
        etag: fresh!.etag!,
      );
      return res.isOk;
    case EntityKind.issue:
      if (issuePatch == null) return false;
      final fresh = (await backlog.getIssue(projectId, entityId)).valueOrNull;
      if (fresh?.etag == null) return false;
      final res = await backlog.updateIssue(
        projectId,
        entityId,
        body: issuePatch(),
        etag: fresh!.etag!,
      );
      return res.isOk;
  }
}

/// Reusable click-to-edit text widget. Click on the rendered display
/// (`displayBuilder` or plain text) → switches into a `TextField` with
/// inline Save / Cancel. `onSave` returns `true` to commit + collapse,
/// `false` to keep the editor open with the typed text intact.
class _InlineTextEditor extends StatefulWidget {
  const _InlineTextEditor({
    required this.value,
    required this.canEdit,
    required this.onSave,
    this.placeholder,
    this.displayBuilder,
    this.displayStyle,
    this.multiline = false,
  });

  final String value;
  final bool canEdit;
  final Future<bool> Function(String value) onSave;
  final String? placeholder;
  final Widget Function(BuildContext)? displayBuilder;
  final TextStyle? displayStyle;
  final bool multiline;

  @override
  State<_InlineTextEditor> createState() => _InlineTextEditorState();
}

class _InlineTextEditorState extends State<_InlineTextEditor> {
  late TextEditingController _ctrl;
  bool _editing = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant _InlineTextEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_editing && oldWidget.value != widget.value) {
      _ctrl.text = widget.value;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final ok = await widget.onSave(_ctrl.text);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (ok) _editing = false;
    });
  }

  void _cancel() {
    setState(() {
      _ctrl.text = widget.value;
      _editing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = AppLocalizations.of(context);
    if (_editing) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _ctrl,
            autofocus: true,
            maxLines: widget.multiline ? null : 1,
            minLines: widget.multiline ? 3 : null,
            onSubmitted: widget.multiline ? null : (_) => _save(),
            style: widget.multiline ? null : widget.displayStyle,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _saving ? null : _cancel,
                child: Text(t.actionCancel),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(t.actionSave),
              ),
            ],
          ),
        ],
      );
    }
    final hasValue = widget.value.isNotEmpty;
    final display = hasValue
        ? (widget.displayBuilder?.call(context) ??
            Text(widget.value, style: widget.displayStyle))
        : Text(
            widget.placeholder ?? '—',
            style: (widget.displayStyle ?? theme.textTheme.bodyMedium)?.copyWith(
              color: theme.colorScheme.outline,
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.normal,
            ),
          );
    if (!widget.canEdit) return display;
    return InkWell(
      onTap: () => setState(() => _editing = true),
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: display,
      ),
    );
  }
}

/// Recent-assignees memory backed by the UI Hive box. Tracks the last
/// few user ids that the current viewer has assigned anything to on a
/// given project so the assignee picker can surface them above the
/// (future) full member list. IDs only — display name resolution is a
/// separate concern that depends on the backend exposing a member
/// directory.
class _RecentAssignees {
  static const _prefix = 'assignee.recent.';
  static const _max = 5;

  static List<String> read(String projectId) {
    final box = getIt<KeyValueStorage>(instanceName: HiveBoxes.ui);
    final raw = box.get<List<dynamic>>('$_prefix$projectId');
    if (raw == null) return const [];
    return raw.whereType<String>().toList();
  }

  static Future<void> push(String projectId, String userId) async {
    final box = getIt<KeyValueStorage>(instanceName: HiveBoxes.ui);
    final current = read(projectId);
    final next = <String>[
      userId,
      for (final id in current)
        if (id != userId) id,
    ].take(_max).toList();
    await box.set<List<dynamic>>('$_prefix$projectId', next);
  }
}

Color _hexToColor(String hex) {
  var h = hex.replaceAll('#', '');
  if (h.length == 6) h = 'FF$h';
  if (h.length != 8) return const Color(0xFF64748B);
  final v = int.tryParse(h, radix: 16);
  return v == null ? const Color(0xFF64748B) : Color(v);
}
