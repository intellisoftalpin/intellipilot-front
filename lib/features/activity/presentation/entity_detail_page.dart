import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/router/app_router.dart';
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
    final theme = Theme.of(context);
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
          preferredSize: const Size.fromHeight(40),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                entity.subject,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
                  Expanded(flex: 5, child: _LeftColumn(data: data, kind: kind, entityId: entityId)),
                  const SizedBox(width: 16),
                  Expanded(flex: 3, child: _RightColumn(data: data)),
                ],
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _LeftColumn(data: data, kind: kind, entityId: entityId),
                  const SizedBox(height: 12),
                  _RightColumn(data: data),
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
  });
  final _PageData data;
  final EntityKind kind;
  final String entityId;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Panel(
          title: AppLocalizations.of(context).panelDetails,
          child: _DetailsTable(data: data),
        ),
        const SizedBox(height: 12),
        _Panel(
          title: AppLocalizations.of(context).panelDescription,
          child: data.entity.description.isEmpty
              ? Text(
                  AppLocalizations.of(context).descriptionPlaceholder,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.outline,
                    fontStyle: FontStyle.italic,
                  ),
                )
              : MarkdownText(data.entity.description),
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
  const _RightColumn({required this.data});
  final _PageData data;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Panel(
          title: AppLocalizations.of(context).panelPeople,
          child: _PeopleTable(data: data),
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
  const _DetailsTable({required this.data});
  final _PageData data;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final entity = data.entity;
    final rows = <_DetailRow>[
      _DetailRow(t.detailFieldType, _kindLabel(t, entity)),
      _DetailRow(t.detailFieldStatus,
          _taxonomyName(entity.statusId, data.taxonomyById) ?? '—'),
    ];
    switch (entity) {
      case _IssueRec(:final issue):
        rows.addAll([
          _DetailRow(t.detailFieldIssueType,
              _taxonomyName(issue.typeId, data.taxonomyById) ?? '—'),
          _DetailRow(t.detailFieldPriority,
              _taxonomyName(issue.priorityId, data.taxonomyById) ?? '—'),
          _DetailRow(t.detailFieldSeverity,
              _taxonomyName(issue.severityId, data.taxonomyById) ?? '—'),
          _DetailRow(t.detailFieldLabels,
              _labelList(issue.labels, data.labelsById)),
          _DetailRow(t.detailFieldComponents,
              _componentList(issue.components, data.componentsById)),
        ]);
      case _UsRec(:final us):
        rows.addAll([
          _DetailRow(t.detailFieldEpic,
              _epicLabel(us.epicId, data.epicsById)),
          _DetailRow(t.detailFieldMilestone,
              _milestoneLabel(us.milestoneId, data.milestonesById)),
          _DetailRow(t.detailFieldPoints,
              _pointsLabel(us.pointsId, data.taxonomyById)),
        ]);
      case _TaskRec(:final task):
        rows.add(_DetailRow(
            t.detailFieldParent,
            _userStoryLabel(task.userStoryId, data.userStoriesById)));
      case _EpicRec():
        break;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: _kvRow(context, row.label, row.value),
          ),
      ],
    );
  }

  String _kindLabel(AppLocalizations t, _EntityRecord e) => switch (e) {
    _EpicRec() => t.kindLabelEpic,
    _UsRec() => t.kindLabelUserStory,
    _TaskRec() => t.kindLabelTask,
    _IssueRec() => t.kindLabelIssue,
  };

  String? _taxonomyName(String? id, Map<String, TaxonomyItem> by) =>
      id == null ? null : by[id]?.name;
  String _labelList(List<String> ids, Map<String, Label> by) =>
      ids.isEmpty ? '—' : ids.map((id) => by[id]?.name ?? id).join(', ');
  String _componentList(List<String> ids, Map<String, Component> by) =>
      ids.isEmpty ? '—' : ids.map((id) => by[id]?.name ?? id).join(', ');
  String _epicLabel(String? id, Map<String, Epic> by) {
    if (id == null) return '—';
    final e = by[id];
    return e == null ? id : 'EPIC-${e.reference} · ${e.subject}';
  }

  String _userStoryLabel(String? id, Map<String, UserStory> by) {
    if (id == null) return '—';
    final u = by[id];
    return u == null ? id : 'US-${u.reference} · ${u.subject}';
  }

  String _milestoneLabel(String? id, Map<String, Milestone> by) =>
      id == null ? '—' : (by[id]?.name ?? id);
  String _pointsLabel(String? id, Map<String, TaxonomyItem> by) {
    if (id == null) return '—';
    final p = by[id];
    if (p == null) return id;
    return p.value == null ? p.name : '${p.name} (${p.value})';
  }
}

class _PeopleTable extends StatelessWidget {
  const _PeopleTable({required this.data});
  final _PageData data;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final me = data.profile.id;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _kvRow(
          context,
          t.detailFieldAssignee,
          _userLabel(data.entity.assignedTo, me, t),
        ),
        const SizedBox(height: 4),
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

class _DetailRow {
  const _DetailRow(this.label, this.value);
  final String label;
  final String value;
}

Widget _kvRow(BuildContext context, String label, String value) {
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
      Expanded(
        child: SelectableText(
          value,
          style: theme.textTheme.bodyMedium,
        ),
      ),
    ],
  );
}

Permission _modifyPermissionFor(EntityKind kind) => switch (kind) {
      EntityKind.epic => Permission.epicModify,
      EntityKind.userStory => Permission.usModify,
      EntityKind.task => Permission.taskModify,
      EntityKind.issue => Permission.issueModify,
    };

Color _hexToColor(String hex) {
  var h = hex.replaceAll('#', '');
  if (h.length == 6) h = 'FF$h';
  if (h.length != 8) return const Color(0xFF64748B);
  final v = int.tryParse(h, radix: 16);
  return v == null ? const Color(0xFF64748B) : Color(v);
}
