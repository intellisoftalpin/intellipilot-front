import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/router/app_router.dart';
import 'package:intellipilot/app/session/session_bloc.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/io/file_picker.dart';
import 'package:intellipilot/core/models/intellibot.dart';
import 'package:intellipilot/core/models/user_ref.dart';
import 'package:intellipilot/core/network/api_config.dart';
import 'package:intellipilot/core/storage/hive_boxes.dart';
import 'package:intellipilot/core/ui/breadcrumb_bar.dart';
import 'package:intellipilot/core/ui/breakpoints.dart';
import 'package:intellipilot/core/ui/issue_chips.dart';
import 'package:intellipilot/core/ui/markdown_text.dart';
import 'package:intellipilot/core/ui/timestamps.dart';
import 'package:intellipilot/core/widgets/user_avatar.dart';
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
import 'package:intellipilot/features/catalog/presentation/widgets/color_swatch_picker.dart';
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
import 'package:intellipilot/features/timesheet/presentation/widgets/log_time_section.dart';
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
    this.onClose,
    this.onOpen,
    this.embeddedWide = false,
    super.key,
  });

  final String projectId;
  final EntityKind kind;
  final String entityId;

  /// When true the page keeps its full two-column wide layout even though
  /// [onClose] is set — used by the wide slide-over detail sheet (as opposed
  /// to the narrow ~420px board panel which stays compact).
  final bool embeddedWide;

  /// When set, the page renders a close (×) button in the app bar
  /// actions slot. Used when the page is embedded as a panel (e.g. the
  /// board's right-side details pane) so the host can dismiss it
  /// without leaving the underlying screen.
  ///
  /// Setting [onClose] also switches the layout to **compact mode**:
  /// the subject becomes a clickable link (firing [onOpen]) instead of
  /// an inline editor, and body / panel paddings shrink so the same
  /// content reads cleanly inside a ~420px panel.
  final VoidCallback? onClose;

  /// Called when the subject is tapped in compact mode. Hosts wire
  /// this to navigate to the standalone detail-page route.
  final VoidCallback? onOpen;

  @override
  State<EntityDetailPage> createState() => _EntityDetailPageState();
}

class _EntityDetailPageState extends State<EntityDetailPage> {
  static const _maxBytes = 25 * 1024 * 1024;

  _PageData? _data;
  bool _initialLoading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_initialLoad());
  }

  Future<void> _initialLoad() async {
    final data = await _load();
    if (!mounted) return;
    setState(() {
      _initialLoading = false;
      _data = data;
      _failed = data == null;
    });
  }

  /// Silent refresh — re-fetches the page data and swaps it in WITHOUT
  /// rebuilding the scaffold / showing a loading spinner. Called from
  /// every inline editor when a PATCH succeeds so a field change feels
  /// instantaneous (Jira-style). The optimistic cell display already
  /// shows the new value, so even the brief network round-trip is
  /// invisible to the user.
  Future<void> _reload() async {
    final data = await _load();
    if (!mounted) return;
    if (data != null) {
      setState(() => _data = data);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    if (_initialLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_failed || _data == null) {
      return Scaffold(
        appBar: AppBar(title: Text(t.entityDetailTitle)),
        body: Center(child: Text(t.entityDetailLoadFailed)),
      );
    }
    final data = _data!;
    return MultiBlocProvider(
      providers: [
        BlocProvider<ProjectDetailCubit>(
          create: (_) {
            final c = ProjectDetailCubit(
              repo: getIt<ProjectsRepository>(),
              projectId: widget.projectId,
              currentUserId: data.profile.id,
            );
            unawaited(c.load());
            return c;
          },
        ),
        BlocProvider<ActivityStreamCubit>(
          create: (_) {
            final c = ActivityStreamCubit(
              repo: getIt<ActivityRepository>(),
              projectId: widget.projectId,
              kind: widget.kind,
              entityId: widget.entityId,
            );
            unawaited(c.load());
            return c;
          },
        ),
        BlocProvider<AttachmentsCubit>(
          create: (_) {
            final c = AttachmentsCubit(
              repo: getIt<ActivityRepository>(),
              projectId: widget.projectId,
              kind: widget.kind,
              entityId: widget.entityId,
              maxBytes: _maxBytes,
            );
            unawaited(c.load());
            return c;
          },
        ),
        BlocProvider<LinksCubit>(
          create: (_) {
            final c = LinksCubit(
              repo: getIt<LinksRepository>(),
              projectId: widget.projectId,
              kind: widget.kind,
              entityId: widget.entityId,
            );
            unawaited(c.load());
            return c;
          },
        ),
      ],
      child: _DetailView(
        data: data,
        kind: widget.kind,
        entityId: widget.entityId,
        projectId: widget.projectId,
        onChanged: _reload,
        onClose: widget.onClose,
        onOpen: widget.onOpen,
        embeddedWide: widget.embeddedWide,
      ),
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
    final project = (await projects.getProject(widget.projectId)).valueOrNull;
    if (project == null) return null;

    _EntityRecord? entity;
    switch (widget.kind) {
      case EntityKind.epic:
        final v = (await backlog.getEpic(
          widget.projectId,
          widget.entityId,
        )).valueOrNull;
        if (v != null) entity = _EntityRecord.epic(v);
      case EntityKind.issue:
        final v = (await backlog.getIssue(
          widget.projectId,
          widget.entityId,
        )).valueOrNull;
        if (v != null) entity = _EntityRecord.issue(v);
    }
    if (entity == null) return null;

    // Resolve every taxonomy item used by the kind so we can render
    // status/type/priority/size names.
    final lookups = <Future<dynamic>>[];
    lookups.add(
      catalog.listTaxonomy(widget.projectId, TaxonomyKind.issueStatus),
    );
    lookups.add(catalog.listTaxonomy(widget.projectId, TaxonomyKind.issueType));
    lookups.add(catalog.listTaxonomy(widget.projectId, TaxonomyKind.priority));
    lookups.add(catalog.listTaxonomy(widget.projectId, TaxonomyKind.size));
    lookups.add(catalog.listLabels(widget.projectId));
    lookups.add(catalog.listComponents(widget.projectId));
    lookups.add(backlog.listEpics(widget.projectId));
    lookups.add(milestones.list(widget.projectId));
    lookups.add(backlog.listIssues(widget.projectId));
    lookups.add(catalog.listCustomers(widget.projectId));
    lookups.add(projects.listMembers(widget.projectId));
    final results = await Future.wait(lookups);

    List<T> resolve<T>(int i) =>
        (results[i] as dynamic).valueOrNull as List<T>? ?? <T>[];
    final taxonomyAll = <TaxonomyItem>[
      ...resolve<TaxonomyItem>(0),
      ...resolve<TaxonomyItem>(1),
      ...resolve<TaxonomyItem>(2),
      ...resolve<TaxonomyItem>(3),
    ];
    return _PageData(
      profile: profile,
      project: project,
      entity: entity,
      taxonomyById: {for (final t in taxonomyAll) t.id: t},
      labelsById: {for (final l in resolve<Label>(4)) l.id: l},
      componentsById: {for (final c in resolve<Component>(5)) c.id: c},
      epicsById: {for (final e in resolve<Epic>(6)) e.id: e},
      milestonesById: {for (final m in resolve<Milestone>(7)) m.id: m},
      issuesById: {for (final i in resolve<Issue>(8)) i.id: i},
      customersById: {for (final c in resolve<Customer>(9)) c.id: c},
      membersById: {
        for (final m in resolve<Membership>(10)) m.userId: m.toRef(),
        // INTELLIBOT is the actor for app-token actions but never a project
        // member — inject it so owner/author rows resolve to its identity.
        kIntellibotUserId: intellibotRef(),
      },
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
    required this.milestonesById,
    required this.issuesById,
    required this.customersById,
    required this.membersById,
  });

  final UserProfile profile;
  final Project project;
  final _EntityRecord entity;
  final Map<String, TaxonomyItem> taxonomyById;
  final Map<String, Label> labelsById;
  final Map<String, Component> componentsById;
  final Map<String, Epic> epicsById;
  final Map<String, Milestone> milestonesById;
  final Map<String, Issue> issuesById;
  final Map<String, Customer> customersById;

  /// Project members keyed by user id — for assignee/reporter avatars + names.
  final Map<String, UserRef> membersById;
}

sealed class _EntityRecord {
  const _EntityRecord();
  factory _EntityRecord.epic(Epic e) = _EpicRec;
  factory _EntityRecord.issue(Issue i) = _IssueRec;

  String get subject;
  String get description;
  int get reference;
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
    this.onClose,
    this.onOpen,
    this.embeddedWide = false,
  });

  final _PageData data;
  final EntityKind kind;
  final String entityId;
  final String projectId;
  final VoidCallback onChanged;
  final VoidCallback? onClose;
  final VoidCallback? onOpen;
  final bool embeddedWide;

  /// The narrow ~420px board panel is compact; the wide slide-over sheet
  /// ([embeddedWide]) and the full-page route keep the roomy layout.
  bool get _isCompact => onClose != null && !embeddedWide;

  @override
  Widget build(BuildContext context) {
    final entity = data.entity;
    final t = AppLocalizations.of(context);
    // Compact (panel-embed) mode never has room for a two-column layout
    // even on expanded screens — Breakpoints.of(context) reads the full
    // screen width, not the panel's. Force a single column there.
    final isWide = Breakpoints.of(context).isExpanded && !_isCompact;
    final key = kind == EntityKind.epic
        ? epicKeyLabel(data.project.issuePrefix, entity.reference)
        : issueKeyLabel(data.project.issuePrefix, entity.reference);
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
              onTap: () => context.go(Routes.projectDetailFor(data.project.id)),
            ),
            Crumb(
              label: kind == EntityKind.epic ? t.railEpics : t.issuesTitle,
              onTap: () => context.go(
                kind == EntityKind.epic
                    ? Routes.projectEpicsFor(data.project.id)
                    : Routes.projectIssuesFor(data.project.id),
              ),
            ),
            Crumb(
              label: key,
              mono: true,
              onTap: kind == EntityKind.issue
                  ? () => context.go(
                      Routes.issueByKeyFor(data.project.id, key),
                    )
                  : null,
            ),
          ],
        ),
        actions: [
          if (kind == EntityKind.issue)
            IconButton(
              icon: const Icon(Icons.link),
              tooltip: t.copyLink,
              onPressed: () {
                final origin = kIsWeb
                    ? Uri.base.origin
                    : getIt<ApiConfig>().baseUrl;
                final link = '$origin/projects/${data.project.id}/issues/$key';
                unawaited(Clipboard.setData(ClipboardData(text: link)));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(t.copiedToClipboard)),
                );
              },
            ),
          if (onClose != null)
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: t.actionCancel,
              onPressed: onClose,
            ),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(_isCompact ? 44 : 56),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              _isCompact ? 12 : 16,
              0,
              _isCompact ? 12 : 16,
              _isCompact ? 8 : 12,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: _isCompact && onOpen != null
                  ? _SubjectLink(
                      subject: entity.subject,
                      onTap: onOpen!,
                    )
                  : _SubjectEditor(
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
      body: _KvLabelWidth(
        width: _isCompact ? 96 : 140,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            _isCompact ? 12 : 16,
            _isCompact ? 8 : 12,
            _isCompact ? 12 : 16,
            _isCompact ? 16 : 32,
          ),
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
                    Expanded(
                      flex: 5,
                      child: _LeftColumn(
                        data: data,
                        kind: kind,
                        entityId: entityId,
                        projectId: projectId,
                        onChanged: onChanged,
                        compact: _isCompact,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 3,
                      child: _RightColumn(
                        data: data,
                        kind: kind,
                        entityId: entityId,
                        projectId: projectId,
                        onChanged: onChanged,
                        onClose: onClose,
                        compact: _isCompact,
                      ),
                    ),
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
                      compact: _isCompact,
                    ),
                    SizedBox(height: _isCompact ? 8 : 12),
                    _RightColumn(
                      data: data,
                      kind: kind,
                      entityId: entityId,
                      projectId: projectId,
                      onChanged: onChanged,
                      onClose: onClose,
                      compact: _isCompact,
                    ),
                  ],
                ),
            ],
          ),
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
/// Subject rendered as a clickable link — used in compact mode (panel
/// embed). Tapping calls [onTap] which is wired to navigate to the
/// standalone detail page. Multi-line capable with ellipsis fallback
/// so long titles never blow the panel's width.
class _SubjectLink extends StatelessWidget {
  const _SubjectLink({required this.subject, required this.onTap});
  final String subject;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          child: Text(
            subject,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.primary,
              decoration: TextDecoration.underline,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

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
          _StatusPill(
            status: status,
            onChanged: onChanged,
            kind: kind,
            entityId: entityId,
            projectId: projectId,
            data: data,
          ),
      ],
    );
  }
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
    final foreground = c.computeLuminance() > 0.5
        ? Colors.black87
        : Colors.white;
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
            Icon(
              Icons.arrow_drop_down,
              size: 16,
              color: foreground.withValues(alpha: 0.7),
            ),
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
    EntityKind.issue => Permission.issueModify,
  };

  List<TaxonomyItem> _statusCandidates(
    EntityKind kind,
    Map<String, TaxonomyItem> taxonomy,
  ) {
    final target = switch (kind) {
      EntityKind.epic => TaxonomyKind.issueStatus, // unified issue status
      EntityKind.issue => TaxonomyKind.issueStatus,
    };
    final list = taxonomy.values.where((t) => t.kind == target).toList()
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
    this.compact = false,
  });
  final _PageData data;
  final EntityKind kind;
  final String entityId;
  final String projectId;
  final VoidCallback onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final gap = SizedBox(height: compact ? 8 : 12);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Panel(
          compact: compact,
          title: AppLocalizations.of(context).panelDetails,
          child: _DetailsTable(
            data: data,
            kind: kind,
            entityId: entityId,
            projectId: projectId,
            onChanged: onChanged,
            compact: compact,
          ),
        ),
        gap,
        _Panel(
          compact: compact,
          title: AppLocalizations.of(context).panelDescription,
          child: _DescriptionEditor(
            data: data,
            kind: kind,
            entityId: entityId,
            projectId: projectId,
            onChanged: onChanged,
          ),
        ),
        gap,
        _Panel(
          compact: compact,
          title: AppLocalizations.of(context).panelLinks,
          child: LinksPanelContent(
            projectId: data.project.id,
            sourceKind: kind,
            sourceId: entityId,
            modifyPermission: _modifyPermissionFor(kind),
            lookup: LinksLookup(
              epics: data.epicsById,
              issues: data.issuesById,
              prefix: data.project.issuePrefix,
            ),
          ),
        ),
        if (kind == EntityKind.epic) ...[
          gap,
          _Panel(
            compact: compact,
            title: AppLocalizations.of(context).panelIncludedIssues,
            child: _IncludedIssuesPanel(
              issues:
                  data.issuesById.values
                      .where((i) => i.epicId == entityId)
                      .toList()
                    ..sort((a, b) => a.reference.compareTo(b.reference)),
              taxonomyById: data.taxonomyById,
              keyPrefix: data.project.issuePrefix,
            ),
          ),
        ],
        if (kind == EntityKind.issue) ...[
          gap,
          _Panel(
            compact: compact,
            title: 'Relationships',
            child: _RelationshipsPanel(
              projectId: projectId,
              issueId: entityId,
              canEdit: canEdit(context),
              issuesById: data.issuesById,
              keyPrefix: data.project.issuePrefix,
            ),
          ),
          gap,
          LogTimeSection(projectId: projectId, issueId: entityId),
        ],
        gap,
        _Panel(
          compact: compact,
          title: AppLocalizations.of(context).panelAttachments,
          child: const AttachmentsView(shrinkWrap: true),
        ),
        gap,
        _Panel(
          compact: compact,
          title: AppLocalizations.of(context).panelActivity,
          child: ActivityStreamView(
            draftKey: '${kind.wire}:$entityId',
            shrinkWrap: true,
            membersById: data.membersById,
          ),
        ),
      ],
    );
  }

  bool canEdit(BuildContext context) {
    final s = context.read<ProjectDetailCubit>().state;
    return s is ProjectDetailLoaded && s.has(_modifyPermissionFor(kind));
  }
}

class _RightColumn extends StatelessWidget {
  const _RightColumn({
    required this.data,
    required this.kind,
    required this.entityId,
    required this.projectId,
    required this.onChanged,
    this.onClose,
    this.compact = false,
  });
  final _PageData data;
  final EntityKind kind;
  final String entityId;
  final String projectId;
  final VoidCallback onChanged;
  final VoidCallback? onClose;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final gap = SizedBox(height: compact ? 8 : 12);
    final s = context.watch<ProjectDetailCubit>().state;
    final canDeleteEpic =
        s is ProjectDetailLoaded && s.has(Permission.epicDelete);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (kind == EntityKind.epic) ...[
          _Panel(
            compact: compact,
            title: t.panelEpic,
            child: _EpicPropertiesTable(
              epic: (data.entity as _EpicRec).epic,
              projectId: projectId,
              entityId: entityId,
              onChanged: onChanged,
            ),
          ),
          gap,
        ],
        _Panel(
          compact: compact,
          title: t.panelPeople,
          child: _PeopleTable(
            data: data,
            kind: kind,
            entityId: entityId,
            projectId: projectId,
            onChanged: onChanged,
          ),
        ),
        gap,
        _Panel(
          compact: compact,
          title: t.panelDates,
          child: _DatesTable(data: data),
        ),
        if (kind == EntityKind.issue) ...[
          gap,
          _Panel(
            compact: compact,
            title: 'Watchers',
            child: _WatchersPanel(
              projectId: projectId,
              issueId: entityId,
              myId: data.profile.id,
              membersById: data.membersById,
            ),
          ),
        ],
        if (kind == EntityKind.epic && canDeleteEpic) ...[
          gap,
          _Panel(
            compact: compact,
            title: t.tabDangerZone,
            child: _EpicDangerZone(
              projectId: projectId,
              entityId: entityId,
              subject: data.entity.subject,
              onClose: onClose,
            ),
          ),
        ],
      ],
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.title,
    required this.child,
    this.compact = false,
  });
  final String title;
  final Widget child;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 12 : 16,
              compact ? 8 : 12,
              compact ? 12 : 16,
              compact ? 6 : 8,
            ),
            child: Text(
              title,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                letterSpacing: 0.4,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 12 : 16,
              compact ? 8 : 12,
              compact ? 12 : 16,
              compact ? 12 : 16,
            ),
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
    this.compact = false,
  });
  final _PageData data;
  final EntityKind kind;
  final String entityId;
  final String projectId;
  final VoidCallback onChanged;
  final bool compact;

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
            label: 'Size',
            currentId: issue.sizeId,
            kind: TaxonomyKind.size,
            canEdit: canEdit,
            displayBuilder: (item) =>
                item.value == null ? item.name : '${item.name} (${item.value})',
            patch: (id) => _patchEntity(
              issuePatch: () => UpdateIssueRequest(sizeId: id),
            ),
          ),
          _categoryRow(context, current: issue.category, canEdit: canEdit),
          if (issue.category == IssueCategory.customerRequest.wire)
            _customerRow(
              context,
              currentIds: issue.customerIds,
              canEdit: canEdit,
            ),
          _kvRowWith(
            context,
            'Start date',
            _DateValue(
              value: issue.startDate,
              canEdit: canEdit,
              onTap: () => _pickIssueDate(context, isStart: true),
            ),
          ),
          _kvRowWith(
            context,
            'Due date',
            _DateValue(
              value: issue.dueDate,
              canEdit: canEdit,
              onTap: () => _pickIssueDate(context, isStart: false),
            ),
          ),
          _resolutionRow(
            context,
            current: issue.resolution,
            canEdit: canEdit,
          ),
          if (issue.resolvedAt != null)
            _kvRow(context, 'Resolved at', issue.resolvedAt!),
          _kvRow(context, 'Fix version', _fixVersionLabel(issue)),
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
          _epicRow(context, currentId: issue.epicId, canEdit: canEdit),
          _milestoneRow(
            context,
            currentId: issue.milestoneId,
            canEdit: canEdit,
          ),
          _parentRow(context, currentId: issue.parentId, canEdit: canEdit),
        ]);
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
      EntityKind.epic => TaxonomyKind.issueStatus, // unified issue status
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
    final all = data.taxonomyById.values.where((tx) => tx.kind == kind).toList()
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
    final pfx = data.project.issuePrefix;
    final epics = data.epicsById.values.toList()
      ..sort((a, b) => a.reference.compareTo(b.reference));
    final current = currentId == null ? null : data.epicsById[currentId];
    return _editableRow(
      context,
      label: t.detailFieldEpic,
      displayText: current == null
          ? '—'
          : '${epicKeyLabel(pfx, current.reference)} · ${current.subject}',
      currentId: currentId,
      noneLabel: t.backlogNoEpic,
      canEdit: canEdit,
      candidates: [
        for (final e in epics)
          _Candidate(
            id: e.id,
            label: '${epicKeyLabel(pfx, e.reference)} · ${e.subject}',
            colorHex: e.color,
          ),
      ],
      onPicked: (id) => _patchEntity(
        issuePatch: () => UpdateIssueRequest(epicId: id),
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
    final current = currentId == null ? null : data.milestonesById[currentId];
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
        issuePatch: () => UpdateIssueRequest(milestoneId: id),
      ),
    );
  }

  Widget _parentRow(
    BuildContext context, {
    required String? currentId,
    required bool canEdit,
  }) {
    final t = AppLocalizations.of(context);
    final pfx = data.project.issuePrefix;
    final candidates =
        data.issuesById.values
            .where((i) => i.id != entityId && i.parentId == null)
            .toList()
          ..sort((a, b) => a.reference.compareTo(b.reference));
    final current = currentId == null ? null : data.issuesById[currentId];
    return _editableRow(
      context,
      label: t.detailFieldParent,
      displayText: current == null
          ? '—'
          : '${issueKeyLabel(pfx, current.reference)} · ${current.subject}',
      currentId: currentId,
      noneLabel: t.taskNoParent,
      canEdit: canEdit,
      candidates: [
        for (final u in candidates)
          _Candidate(
            id: u.id,
            label: '${issueKeyLabel(pfx, u.reference)} · ${u.subject}',
          ),
      ],
      onPicked: (id) => _patchEntity(
        issuePatch: () => UpdateIssueRequest(parentId: id),
      ),
    );
  }

  Widget _categoryRow(
    BuildContext context, {
    required String? current,
    required bool canEdit,
  }) {
    final selected = IssueCategory.fromWire(current);
    return _editableRow(
      context,
      label: 'Category',
      displayText: selected?.label ?? '—',
      currentId: current,
      noneLabel: '—',
      canEdit: canEdit,
      candidates: [
        for (final c in IssueCategory.values)
          _Candidate(id: c.wire, label: c.label),
      ],
      onPicked: (id) => _patchEntity(
        issuePatch: () => id == IssueCategory.customerRequest.wire
            ? UpdateIssueRequest(category: id)
            // Leaving customer_request clears any linked customers.
            : UpdateIssueRequest(category: id, customerIds: const []),
      ),
    );
  }

  Widget _customerRow(
    BuildContext context, {
    required List<String> currentIds,
    required bool canEdit,
  }) {
    final all = data.customersById.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return _kvRowWith(
      context,
      'Customers',
      _MultiSelectCell(
        displayText: _customerList(currentIds, data.customersById),
        candidates: [
          for (final c in all) _MultiCandidate(id: c.id, label: c.name),
        ],
        selectedIds: currentIds,
        title: 'Customers',
        emptyLabel: '—',
        canEdit: canEdit,
        onSaved: (next) => _patchEntity(
          issuePatch: () => UpdateIssueRequest(customerIds: next),
        ),
      ),
    );
  }

  Widget _resolutionRow(
    BuildContext context, {
    required String? current,
    required bool canEdit,
  }) {
    final selected = IssueResolution.fromWire(current);
    return _editableRow(
      context,
      label: 'Resolution',
      displayText: selected?.label ?? '—',
      currentId: current,
      noneLabel: '—',
      canEdit: canEdit,
      candidates: [
        for (final r in IssueResolution.values)
          _Candidate(id: r.wire, label: r.label),
      ],
      onPicked: (id) => _patchEntity(
        issuePatch: () => UpdateIssueRequest(resolution: id),
      ),
    );
  }

  String _fixVersionLabel(Issue issue) {
    if (issue.releaseText != null && issue.releaseText!.isNotEmpty) {
      return issue.releaseText!;
    }
    if (issue.releaseVersionId != null) return issue.releaseVersionId!;
    return '—';
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
    UpdateIssueRequest Function()? issuePatch,
  }) async {
    final backlog = getIt<BacklogRepository>();
    var ok = false;
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
        ok = res.isOk;
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
    _IssueRec() => t.kindLabelIssue,
  };

  String _labelList(List<String> ids, Map<String, Label> by) =>
      ids.isEmpty ? '—' : ids.map((id) => by[id]?.name ?? id).join(', ');
  String _componentList(List<String> ids, Map<String, Component> by) =>
      ids.isEmpty ? '—' : ids.map((id) => by[id]?.name ?? id).join(', ');
  String _customerList(List<String> ids, Map<String, Customer> by) =>
      ids.isEmpty ? '—' : ids.map((id) => by[id]?.name ?? id).join(', ');

  /// Opens a date picker for the issue's start / due date and PATCHes the
  /// chosen `YYYY-MM-DD` value (mirrors the epic date editing flow).
  Future<void> _pickIssueDate(
    BuildContext context, {
    required bool isStart,
  }) async {
    final entity = data.entity;
    if (entity is! _IssueRec) return;
    final raw = isStart ? entity.issue.startDate : entity.issue.dueDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(raw ?? '') ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    final s =
        '${picked.year.toString().padLeft(4, '0')}-'
        '${picked.month.toString().padLeft(2, '0')}-'
        '${picked.day.toString().padLeft(2, '0')}';
    await _patchEntity(
      issuePatch: () => isStart
          ? UpdateIssueRequest(startDate: s)
          : UpdateIssueRequest(dueDate: s),
    );
  }
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
    // Hover is rendered by InkWell.hoverColor — synchronised with the
    // Flutter mouse tracker internally, so we don't need our own
    // setState-driven hover state (which raced between cells and left
    // multiple rows stuck "hovered" when the mouse moved quickly).
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: _saving ? null : _open,
        borderRadius: BorderRadius.circular(4),
        hoverColor: theme.colorScheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
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
                  color: theme.colorScheme.outline.withValues(alpha: 0.4),
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
///
/// Implemented with [OverlayEntry] rather than `showMenu` because the
/// stock `_PopupMenuRoute` wraps every entry in `IntrinsicWidth`, and
/// our picker body has a TextField + ListView that can't compute an
/// intrinsic width — during the popup's open animation Flutter would
/// emit `Cannot hit test a render box with no size` errors.
Future<String?> _showSearchablePicker(
  BuildContext anchorContext, {
  required List<_Candidate> candidates,
  required String? currentId,
  required String noneLabel,
}) async {
  final anchor = anchorContext.findRenderObject() as RenderBox?;
  final overlayState = Overlay.of(anchorContext);
  final overlay = overlayState.context.findRenderObject() as RenderBox?;
  if (anchor == null || overlay == null) return null;

  const popupWidth = 280.0;
  const popupHeight = 340.0;
  const gap = 4.0;

  final anchorTopLeft = anchor.localToGlobal(Offset.zero, ancestor: overlay);
  final anchorSize = anchor.size;
  final overlaySize = overlay.size;

  var left = anchorTopLeft.dx;
  if (left + popupWidth > overlaySize.width - 8) {
    left = overlaySize.width - popupWidth - 8;
  }
  if (left < 8) left = 8;

  var top = anchorTopLeft.dy + anchorSize.height + gap;
  if (top + popupHeight > overlaySize.height - 8) {
    // Not enough room below — flip above the anchor.
    top = anchorTopLeft.dy - popupHeight - gap;
  }
  if (top < 8) top = 8;

  final completer = Completer<String?>();
  late OverlayEntry entry;
  void close([String? value]) {
    if (!completer.isCompleted) completer.complete(value);
    if (entry.mounted) entry.remove();
  }

  entry = OverlayEntry(
    builder: (ctx) => _PickerOverlay(
      left: left,
      top: top,
      width: popupWidth,
      height: popupHeight,
      candidates: candidates,
      currentId: currentId,
      noneLabel: noneLabel,
      onPicked: close,
      onDismiss: close,
    ),
  );
  overlayState.insert(entry);
  return completer.future;
}

/// Modal-style overlay that hosts the searchable picker body. A
/// full-screen translucent barrier captures outside taps; the picker
/// itself is positioned and sized by the caller.
class _PickerOverlay extends StatelessWidget {
  const _PickerOverlay({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.candidates,
    required this.currentId,
    required this.noneLabel,
    required this.onPicked,
    required this.onDismiss,
  });

  final double left;
  final double top;
  final double width;
  final double height;
  final List<_Candidate> candidates;
  final String? currentId;
  final String noneLabel;
  final ValueChanged<String?> onPicked;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Outside-tap barrier (transparent — Jira-style popups don't
        // dim the page behind them).
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onDismiss,
            child: const SizedBox.expand(),
          ),
        ),
        Positioned(
          left: left,
          top: top,
          width: width,
          height: height,
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(8),
            clipBehavior: Clip.antiAlias,
            color: Theme.of(context).colorScheme.surface,
            child: _SearchablePickerBody(
              candidates: candidates,
              currentId: currentId,
              noneLabel: noneLabel,
              onPicked: onPicked,
              onDismiss: onDismiss,
            ),
          ),
        ),
      ],
    );
  }
}

/// Body of the searchable picker — TextField at the top, filtered list
/// below. Pops the hosting overlay via [onPicked] / [onDismiss].
class _SearchablePickerBody extends StatefulWidget {
  const _SearchablePickerBody({
    required this.candidates,
    required this.currentId,
    required this.noneLabel,
    required this.onPicked,
    required this.onDismiss,
  });

  final List<_Candidate> candidates;
  final String? currentId;
  final String noneLabel;
  final ValueChanged<String?> onPicked;
  final VoidCallback onDismiss;

  @override
  State<_SearchablePickerBody> createState() => _SearchablePickerBodyState();
}

class _SearchablePickerBodyState extends State<_SearchablePickerBody> {
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
    widget.onPicked(row.isNone ? _kNoneSentinel : row.candidate!.id);
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
              widget.onDismiss();
              return null;
            },
          ),
        },
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
                  ? _NoMatchesBody(
                      noneRow: rows.first,
                      onTap: () => _commitIndex(0),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.zero,
                      itemCount: rows.length,
                      itemBuilder: (context, i) {
                        final row = rows[i];
                        if (row.isDivider) {
                          return const Divider(height: 8, thickness: 1);
                        }
                        final selected = i == _highlight;
                        final isCurrent = row.candidate?.id == widget.currentId;
                        final candidate = row.candidate;
                        return Container(
                          color: selected
                              ? theme.colorScheme.primaryContainer.withValues(
                                  alpha: 0.5,
                                )
                              : null,
                          child: InkWell(
                            onTap: () => _commitIndex(i),
                            onHover: (h) {
                              if (!h || _highlight == i) return;
                              // Defer to avoid retriggering the
                              // mouse-tracker mid-update.
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (mounted && _highlight != i) {
                                  setState(() => _highlight = i);
                                }
                              });
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
  const _PickerRow.none() : isNone = true, isDivider = false, candidate = null;
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
    unawaited(_commit(current.where((x) => x != id).toList()));
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
      // Hover bg / cursor / ripple all come from InkWell — no manual
      // hover state needed.
      return Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: _saving ? null : _openDialog,
          borderRadius: BorderRadius.circular(4),
          hoverColor: theme.colorScheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
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
                    color: theme.colorScheme.outline.withValues(alpha: 0.4),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return Wrap(
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
            labelPadding: const EdgeInsets.symmetric(
              horizontal: 4,
              vertical: 0,
            ),
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
          _withAvatar(
            data.entity.assignedTo,
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
        ),
        const SizedBox(height: 4),
        _kvRowWith(
          context,
          t.detailFieldReporter,
          _withAvatar(
            data.entity.ownerId,
            _ClickToEditCell(
              displayText: _userLabel(data.entity.ownerId, me, t),
              candidates: _reporterCandidates(t, me),
              currentId: data.entity.ownerId,
              noneLabel: '—',
              canEdit: canEdit,
              onPicked: (id) async {
                final ok = await _patchReporter(id);
                if (ok && id != null) {
                  await _RecentAssignees.push(projectId, id);
                }
                return ok;
              },
            ),
          ),
        ),
        // QA + Reviewer are issue-only accountability roles (informational).
        if (_issue != null) ...[
          const SizedBox(height: 4),
          _kvRowWith(
            context,
            t.detailFieldQaAssignee,
            _withAvatar(
              _issue!.qaAssigneeId,
              _ClickToEditCell(
                displayText: _userLabel(_issue!.qaAssigneeId, me, t),
                candidates: _assigneeCandidates(t, me),
                currentId: _issue!.qaAssigneeId,
                noneLabel: '—',
                canEdit: canEdit,
                onPicked: (id) async {
                  final ok = await _patchQaAssignee(id);
                  if (ok && id != null) {
                    await _RecentAssignees.push(projectId, id);
                  }
                  return ok;
                },
              ),
            ),
          ),
          const SizedBox(height: 4),
          _kvRowWith(
            context,
            t.detailFieldReviewer,
            _withAvatar(
              _issue!.reviewerId,
              _ClickToEditCell(
                displayText: _userLabel(_issue!.reviewerId, me, t),
                candidates: _assigneeCandidates(t, me),
                currentId: _issue!.reviewerId,
                noneLabel: '—',
                canEdit: canEdit,
                onPicked: (id) async {
                  final ok = await _patchReviewer(id);
                  if (ok && id != null) {
                    await _RecentAssignees.push(projectId, id);
                  }
                  return ok;
                },
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// The wrapped issue when this entity is an issue (else null — epics have no
  /// QA/Reviewer roles).
  Issue? get _issue {
    final e = data.entity;
    return e is _IssueRec ? e.issue : null;
  }

  String _userLabel(String? id, String me, AppLocalizations t) {
    if (id == null) return '—';
    final name = data.membersById[id]?.displayName ?? id;
    if (id == me) return '${t.detailValueYou} · $name';
    return name;
  }

  /// Prefix a person field with their avatar (+ hover card) when the id
  /// resolves to a known project member.
  Widget _withAvatar(String? id, Widget child) {
    final ref = id == null ? null : data.membersById[id];
    if (ref == null) return child;
    return Row(
      children: [
        UserAvatar(user: ref, size: 24),
        const SizedBox(width: 8),
        Expanded(child: child),
      ],
    );
  }

  /// Build the assignee picker: "Assign to me" pinned on top, then every
  /// project member by display name.
  List<_Candidate> _assigneeCandidates(AppLocalizations t, String me) {
    final others = data.membersById.values.where((r) => r.id != me).toList()
      ..sort(
        (a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
      );
    return [
      _Candidate(
        id: me,
        label: t.assigneeAssignToMe,
        icon: Icons.person_outline,
        pinned: true,
      ),
      for (final r in others) _Candidate(id: r.id, label: r.displayName),
    ];
  }

  Future<bool> _patchAssignee(String? assigneeId) async {
    final backlog = getIt<BacklogRepository>();
    var ok = false;
    switch (kind) {
      case EntityKind.epic:
        final fresh = (await backlog.getEpic(projectId, entityId)).valueOrNull;
        if (fresh?.etag == null) return false;
        final res = await backlog.updateEpic(
          projectId,
          entityId,
          body: UpdateEpicRequest(assignedTo: assigneeId),
          etag: fresh!.etag!,
        );
        ok = res.isOk;
      case EntityKind.issue:
        final fresh = (await backlog.getIssue(projectId, entityId)).valueOrNull;
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

  /// Same shape as the assignee picker, with "Set me as reporter" as the
  /// pinned shortcut and the same per-project recent-user history.
  List<_Candidate> _reporterCandidates(AppLocalizations t, String me) {
    final others = data.membersById.values.where((r) => r.id != me).toList()
      ..sort(
        (a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
      );
    return [
      _Candidate(
        id: me,
        label: t.reporterSetMe,
        icon: Icons.person_outline,
        pinned: true,
      ),
      for (final r in others) _Candidate(id: r.id, label: r.displayName),
    ];
  }

  Future<bool> _patchReporter(String? ownerId) async {
    final backlog = getIt<BacklogRepository>();
    var ok = false;
    switch (kind) {
      case EntityKind.epic:
        final fresh = (await backlog.getEpic(projectId, entityId)).valueOrNull;
        if (fresh?.etag == null) return false;
        final res = await backlog.updateEpic(
          projectId,
          entityId,
          body: UpdateEpicRequest(ownerId: ownerId),
          etag: fresh!.etag!,
        );
        ok = res.isOk;
      case EntityKind.issue:
        final fresh = (await backlog.getIssue(projectId, entityId)).valueOrNull;
        if (fresh?.etag == null) return false;
        final res = await backlog.updateIssue(
          projectId,
          entityId,
          body: UpdateIssueRequest(ownerId: ownerId),
          etag: fresh!.etag!,
        );
        ok = res.isOk;
    }
    if (ok) onChanged();
    return ok;
  }

  /// Issue-only: set/clear the QA assignee.
  Future<bool> _patchQaAssignee(String? id) =>
      _patchIssueUser(UpdateIssueRequest(qaAssigneeId: id));

  /// Issue-only: set/clear the reviewer.
  Future<bool> _patchReviewer(String? id) =>
      _patchIssueUser(UpdateIssueRequest(reviewerId: id));

  /// Shared body for the issue-only people patches: re-fetch for a fresh ETag,
  /// PATCH, and notify on success.
  Future<bool> _patchIssueUser(UpdateIssueRequest body) async {
    final backlog = getIt<BacklogRepository>();
    final fresh = (await backlog.getIssue(projectId, entityId)).valueOrNull;
    if (fresh?.etag == null) return false;
    final res = await backlog.updateIssue(
      projectId,
      entityId,
      body: body,
      etag: fresh!.etag!,
    );
    final ok = res.isOk;
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
    Text(
      value,
      style: Theme.of(context).textTheme.bodyMedium,
      overflow: TextOverflow.ellipsis,
      maxLines: 2,
    ),
  );
}

Widget _kvRowWith(BuildContext context, String label, Widget value) {
  final theme = Theme.of(context);
  final labelWidth = _KvLabelWidth.of(context);
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: labelWidth,
        child: Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      Expanded(child: value),
    ],
  );
}

/// Tightens the label column of every nested `_kvRow` / `_kvRowWith`. The
/// detail page sets a wider value (140) by default; compact mode (panel
/// embed) drops to 96 so the value side gets the headroom it needs at
/// 420px panel width without overflowing.
class _KvLabelWidth extends InheritedWidget {
  const _KvLabelWidth({required super.child, required this.width});
  final double width;

  static double of(BuildContext context) {
    final w = context.dependOnInheritedWidgetOfExactType<_KvLabelWidth>();
    return w?.width ?? 140;
  }

  @override
  bool updateShouldNotify(_KvLabelWidth oldWidget) => oldWidget.width != width;
}

// ---------------------------------------------------------------------------
// Epic-only panels (cover image, colour, dates, included issues, danger zone)
// ---------------------------------------------------------------------------

/// Epic properties: cover image, colour swatch, and start / end dates. Every
/// field PATCHes the epic via the shared dispatcher then triggers a reload.
class _EpicPropertiesTable extends StatelessWidget {
  const _EpicPropertiesTable({
    required this.epic,
    required this.projectId,
    required this.entityId,
    required this.onChanged,
  });
  final Epic epic;
  final String projectId;
  final String entityId;
  final VoidCallback onChanged;

  Future<void> _patch(UpdateEpicRequest body) async {
    final ok = await _patchEntityKind(
      kind: EntityKind.epic,
      projectId: projectId,
      entityId: entityId,
      epicPatch: () => body,
    );
    if (ok) onChanged();
  }

  Future<void> _pickDate(BuildContext context, {required bool isStart}) async {
    final raw = isStart ? epic.startDate : epic.endDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(raw ?? '') ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    final s =
        '${picked.year.toString().padLeft(4, '0')}-'
        '${picked.month.toString().padLeft(2, '0')}-'
        '${picked.day.toString().padLeft(2, '0')}';
    await _patch(
      isStart ? UpdateEpicRequest(startDate: s) : UpdateEpicRequest(endDate: s),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final canEdit = context.select<ProjectDetailCubit, bool>((c) {
      final s = c.state;
      return s is ProjectDetailLoaded && s.has(Permission.epicModify);
    });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _EpicCoverField(
          epic: epic,
          projectId: projectId,
          entityId: entityId,
          canEdit: canEdit,
          onChanged: onChanged,
        ),
        const SizedBox(height: 10),
        _kvRowWith(
          context,
          t.fieldColor,
          canEdit
              ? Align(
                  alignment: Alignment.centerLeft,
                  child: ColorSwatchPicker(
                    selectedHex: epic.color,
                    onChanged: (hex) =>
                        unawaited(_patch(UpdateEpicRequest(color: hex))),
                  ),
                )
              : Align(
                  alignment: Alignment.centerLeft,
                  child: HexColorDot(hex: epic.color, size: 14),
                ),
        ),
        const SizedBox(height: 8),
        _kvRowWith(
          context,
          t.ttStartDate,
          _DateValue(
            value: epic.startDate,
            canEdit: canEdit,
            onTap: () => _pickDate(context, isStart: true),
          ),
        ),
        const SizedBox(height: 4),
        _kvRowWith(
          context,
          t.ttEndDate,
          _DateValue(
            value: epic.endDate,
            canEdit: canEdit,
            onTap: () => _pickDate(context, isStart: false),
          ),
        ),
      ],
    );
  }
}

/// A date value cell: shows `YYYY-MM-DD` (or em-dash); tap opens a date picker
/// when editable.
class _DateValue extends StatelessWidget {
  const _DateValue({
    required this.value,
    required this.canEdit,
    required this.onTap,
  });
  final String? value;
  final bool canEdit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = (value == null || value!.isEmpty) ? '—' : value!;
    final text = Text(label, style: theme.textTheme.bodyMedium);
    if (!canEdit) return text;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
        child: Row(
          children: [
            Expanded(child: text),
            Icon(
              Icons.edit_calendar_outlined,
              size: 16,
              color: theme.colorScheme.outline,
            ),
          ],
        ),
      ),
    );
  }
}

/// Cover image preview + upload / remove, mirroring the avatar upload flow.
class _EpicCoverField extends StatefulWidget {
  const _EpicCoverField({
    required this.epic,
    required this.projectId,
    required this.entityId,
    required this.canEdit,
    required this.onChanged,
  });
  final Epic epic;
  final String projectId;
  final String entityId;
  final bool canEdit;
  final VoidCallback onChanged;

  @override
  State<_EpicCoverField> createState() => _EpicCoverFieldState();
}

class _EpicCoverFieldState extends State<_EpicCoverField> {
  bool _busy = false;

  Future<void> _upload() async {
    final picked = await getIt<FilePicker>().pickSingleFile();
    if (picked == null) return;
    setState(() => _busy = true);
    final res = await getIt<BacklogRepository>().uploadEpicCover(
      widget.projectId,
      widget.entityId,
      filename: picked.name,
      bytes: picked.bytes,
      contentType: picked.contentType,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    res.when(ok: (_) => widget.onChanged(), err: _showError);
  }

  Future<void> _remove() async {
    setState(() => _busy = true);
    final res = await getIt<BacklogRepository>().deleteEpicCover(
      widget.projectId,
      widget.entityId,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    res.when(ok: (_) => widget.onChanged(), err: _showError);
  }

  void _showError(AppFailure f) {
    final t = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(f.serverMessage ?? t.attachmentsUploadFailed)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final canPick = widget.canEdit && getIt<FilePicker>().isSupported;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: widget.epic.hasCover
              ? _EpicCoverImage(epic: widget.epic)
              : Container(
                  height: 120,
                  color: theme.colorScheme.surfaceContainerHighest,
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.image_outlined,
                    size: 36,
                    color: theme.colorScheme.outline,
                  ),
                ),
        ),
        if (canPick) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              FilledButton.tonalIcon(
                onPressed: _busy ? null : () => unawaited(_upload()),
                icon: _busy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.upload_outlined, size: 18),
                label: Text(t.pfUpload),
              ),
              if (widget.epic.hasCover) ...[
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _busy ? null : () => unawaited(_remove()),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: Text(t.actionRemove),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

/// Authenticated cover image fetched from the backend (mirrors [UserAvatar]).
class _EpicCoverImage extends StatelessWidget {
  const _EpicCoverImage({required this.epic});
  final Epic epic;

  @override
  Widget build(BuildContext context) {
    final base = getIt<ApiConfig>().baseUrl;
    final token = getIt<SessionBloc>().currentAccessToken;
    final v = Uri.encodeQueryComponent(epic.coverImageUpdatedAt ?? '');
    final url =
        '$base/api/v1/projects/${epic.projectId}/epics/${epic.id}/cover-image?v=$v';
    return Image.network(
      url,
      height: 120,
      width: double.infinity,
      fit: BoxFit.cover,
      headers: token == null ? null : {'Authorization': 'Bearer $token'},
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => Container(
        height: 120,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        alignment: Alignment.center,
        child: Icon(
          Icons.broken_image_outlined,
          color: Theme.of(context).colorScheme.outline,
        ),
      ),
    );
  }
}

/// The issues grouped under this epic (read-only list).
class _IncludedIssuesPanel extends StatelessWidget {
  const _IncludedIssuesPanel({
    required this.issues,
    required this.taxonomyById,
    required this.keyPrefix,
  });
  final List<Issue> issues;
  final Map<String, TaxonomyItem> taxonomyById;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    if (issues.isEmpty) {
      return Text(
        t.epicNoIssues,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.outline,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final i in issues)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                IssueKeyChip(text: issueKeyLabel(keyPrefix, i.reference)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    i.subject,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                if (i.statusId != null && taxonomyById[i.statusId] != null) ...[
                  const SizedBox(width: 8),
                  StatusPill(
                    label: taxonomyById[i.statusId]!.name,
                    colorHex: taxonomyById[i.statusId]!.color,
                    dense: true,
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// Danger zone: permanently delete the epic (with confirmation). On success it
/// closes the sheet so the host reloads its list.
class _EpicDangerZone extends StatelessWidget {
  const _EpicDangerZone({
    required this.projectId,
    required this.entityId,
    required this.subject,
    this.onClose,
  });
  final String projectId;
  final String entityId;
  final String subject;
  final VoidCallback? onClose;

  Future<void> _delete(BuildContext context) async {
    final t = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.backlogDeleteEpicTitle),
        content: Text(t.backlogDeleteEpicConfirm(subject)),
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
    if (ok != true) return;
    final backlog = getIt<BacklogRepository>();
    final fresh = (await backlog.getEpic(projectId, entityId)).valueOrNull;
    if (fresh?.etag == null) return;
    final res = await backlog.deleteEpic(
      projectId,
      entityId,
      etag: fresh!.etag!,
    );
    if (!res.isOk) return;
    if (onClose != null) {
      onClose!();
    } else {
      unawaited(navigator.maybePop());
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          t.epicDangerZoneBody,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonalIcon(
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.errorContainer,
              foregroundColor: theme.colorScheme.onErrorContainer,
            ),
            onPressed: () => unawaited(_delete(context)),
            icon: const Icon(Icons.delete_forever, size: 18),
            label: Text(t.epicDeleteAction),
          ),
        ),
      ],
    );
  }
}

Permission _modifyPermissionFor(EntityKind kind) => switch (kind) {
  EntityKind.epic => Permission.epicModify,
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
            style: (widget.displayStyle ?? theme.textTheme.bodyMedium)
                ?.copyWith(
                  color: theme.colorScheme.outline,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.normal,
                ),
          );
    if (!widget.canEdit) return display;
    // Give the click-to-edit affordance a generous, full-width hit area with a
    // hover tint — the multiline (description) variant also reserves a minimum
    // height so short/empty descriptions stay easy to click.
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: InkWell(
        onTap: () => setState(() => _editing = true),
        borderRadius: BorderRadius.circular(4),
        hoverColor: theme.colorScheme.onSurface.withValues(alpha: 0.04),
        child: Container(
          width: double.infinity,
          alignment: Alignment.topLeft,
          constraints: BoxConstraints(
            minHeight: widget.multiline ? 48 : 0,
          ),
          padding: EdgeInsets.all(widget.multiline ? 10 : 2),
          child: display,
        ),
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

// ---------------------------------------------------------------------------
// Issue relationships
// ---------------------------------------------------------------------------

/// Lists an issue's relationship links (in/out), with add-via-picker and
/// remove. Talks to [CatalogRepository] directly and refreshes locally.
class _RelationshipsPanel extends StatefulWidget {
  const _RelationshipsPanel({
    required this.projectId,
    required this.issueId,
    required this.canEdit,
    required this.issuesById,
    required this.keyPrefix,
  });

  final String projectId;
  final String issueId;
  final bool canEdit;
  final Map<String, Issue> issuesById;
  final String keyPrefix;

  @override
  State<_RelationshipsPanel> createState() => _RelationshipsPanelState();
}

class _RelationshipsPanelState extends State<_RelationshipsPanel> {
  late Future<List<IssueLink>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<IssueLink>> _load() async {
    final res = await getIt<CatalogRepository>().listIssueLinks(
      widget.projectId,
      widget.issueId,
    );
    return res.valueOrNull ?? <IssueLink>[];
  }

  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<List<IssueLink>>(
      future: _future,
      builder: (context, snap) {
        final links = snap.data ?? const <IssueLink>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (snap.connectionState != ConnectionState.done)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else if (links.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  'No relationships.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              )
            else
              for (final link in links)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.link, size: 18),
                  title: Text(
                    '${link.relationLabel} '
                    '${issueKeyLabel(widget.keyPrefix, link.otherRef)} · ${link.otherSubject}',
                    style: theme.textTheme.bodyMedium,
                  ),
                  trailing: widget.canEdit
                      ? IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          tooltip: 'Remove',
                          onPressed: () async {
                            await getIt<CatalogRepository>().deleteIssueLink(
                              widget.projectId,
                              widget.issueId,
                              link.id,
                            );
                            _reload();
                          },
                        )
                      : null,
                ),
            if (widget.canEdit)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add relationship'),
                  onPressed: _addLink,
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _addLink() async {
    final candidates =
        widget.issuesById.values.where((i) => i.id != widget.issueId).toList()
          ..sort((a, b) => a.reference.compareTo(b.reference));
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No other issues to link.')),
      );
      return;
    }
    var targetId = candidates.first.id;
    var type = IssueLinkType.blocks;
    final result = await showDialog<({String target, String type})>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Add relationship'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<IssueLinkType>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: [
                    for (final t in IssueLinkType.values)
                      DropdownMenuItem<IssueLinkType>(
                        value: t,
                        child: Text(t.label),
                      ),
                  ],
                  onChanged: (v) => setState(() => type = v ?? type),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: targetId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Issue'),
                  items: [
                    for (final i in candidates)
                      DropdownMenuItem<String>(
                        value: i.id,
                        child: Text(
                          '${issueKeyLabel(widget.keyPrefix, i.reference)} · ${i.subject}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => targetId = v ?? targetId),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(ctx).pop((target: targetId, type: type.wire)),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    await getIt<CatalogRepository>().createIssueLink(
      widget.projectId,
      widget.issueId,
      result.target,
      result.type,
    );
    _reload();
  }
}

// ---------------------------------------------------------------------------
// Watchers
// ---------------------------------------------------------------------------

/// Shows the issue's watcher list with a watch/unwatch-self toggle.
class _WatchersPanel extends StatefulWidget {
  const _WatchersPanel({
    required this.projectId,
    required this.issueId,
    required this.myId,
    required this.membersById,
  });

  final String projectId;
  final String issueId;
  final String myId;
  final Map<String, UserRef> membersById;

  @override
  State<_WatchersPanel> createState() => _WatchersPanelState();
}

class _WatchersPanelState extends State<_WatchersPanel> {
  late Future<List<String>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<String>> _load() async {
    final res = await getIt<CatalogRepository>().listWatchers(
      widget.projectId,
      widget.issueId,
    );
    return res.valueOrNull ?? <String>[];
  }

  void _reload() => setState(() => _future = _load());

  /// Resolve a watcher's user id to a display name (falling back to the id),
  /// tagging the current user with "(you)".
  String _watcherLabel(String id) {
    final name = widget.membersById[id]?.displayName ?? id;
    return id == widget.myId ? '$name (you)' : name;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<List<String>>(
      future: _future,
      builder: (context, snap) {
        final watchers = snap.data ?? const <String>[];
        final watching = watchers.contains(widget.myId);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (snap.connectionState != ConnectionState.done)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else ...[
              FilledButton.tonalIcon(
                icon: Icon(
                  watching
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 18,
                ),
                label: Text(watching ? 'Unwatch' : 'Watch'),
                onPressed: () async {
                  final repo = getIt<CatalogRepository>();
                  if (watching) {
                    await repo.removeWatcher(
                      widget.projectId,
                      widget.issueId,
                      widget.myId,
                    );
                  } else {
                    await repo.addWatcher(widget.projectId, widget.issueId);
                  }
                  _reload();
                },
              ),
              const SizedBox(height: 8),
              if (watchers.isEmpty)
                Text(
                  'No watchers.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                )
              else
                for (final w in watchers)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        const Icon(Icons.person_outline, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _watcherLabel(w),
                            style: theme.textTheme.bodyMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
            ],
          ],
        );
      },
    );
  }
}
