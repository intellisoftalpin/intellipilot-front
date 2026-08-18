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
import 'package:intellipilot/core/models/user_ref.dart';
import 'package:intellipilot/core/network/api_config.dart';
import 'package:intellipilot/core/network/sse/project_events_service.dart';
import 'package:intellipilot/core/storage/hive_boxes.dart';
import 'package:intellipilot/core/ui/breadcrumb_bar.dart';
import 'package:intellipilot/core/ui/breakpoints.dart';
import 'package:intellipilot/core/ui/issue_chips.dart';
import 'package:intellipilot/core/ui/markdown_editor.dart';
import 'package:intellipilot/core/ui/markdown_text.dart';
import 'package:intellipilot/core/ui/timestamps.dart';
import 'package:intellipilot/core/widgets/user_avatar.dart';
import 'package:intellipilot/features/activity/data/dtos/activity_dtos.dart';
import 'package:intellipilot/features/activity/presentation/entity_detail_sheet.dart';
import 'package:intellipilot/features/activity/data/project_lookups_cache.dart';
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
import 'package:intellipilot/features/catalog/presentation/widgets/size_badge.dart';
import 'package:intellipilot/features/links/domain/links_repository.dart';
import 'package:intellipilot/features/links/presentation/cubits/links_cubit.dart';
import 'package:intellipilot/features/links/presentation/widgets/links_panel.dart';
import 'package:intellipilot/features/milestones/data/dtos/milestone_dtos.dart';
import 'package:intellipilot/features/profile/data/dtos/profile_dtos.dart';
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

  /// Why the initial load failed, so the error state can say something useful
  /// instead of one catch-all string. Null while loading or once loaded.
  AppFailure? _failure;

  /// Anchors the activity panel so the action bar's "Comment" button can
  /// scroll straight to it. Owned by the State so it survives rebuilds.
  final GlobalKey _activityAnchor = GlobalKey();

  StreamSubscription<LiveEvent>? _events;

  @override
  void initState() {
    super.initState();
    unawaited(_initialLoad());
    _subscribeToLiveEvents();
  }

  @override
  void dispose() {
    unawaited(_events?.cancel());
    super.dispose();
  }

  Future<void> _initialLoad() async {
    setState(() {
      _initialLoading = true;
      _failure = null;
    });
    final res = await _load();
    if (!mounted) return;
    setState(() {
      _initialLoading = false;
      _data = res.data;
      _failure = res.failure;
    });
  }

  /// Silent refresh of the ENTITY ONLY — one request. Called from every inline
  /// editor when a PATCH succeeds so a field change feels instantaneous.
  ///
  /// This used to re-run the whole page load (profile + project + entity + 13
  /// parallel lookups, one of which listed every issue in the project) for a
  /// single dropdown change. Reference data now comes from
  /// [ProjectLookupsCache] and only the entity is re-fetched.
  Future<void> _reload() async {
    final data = _data;
    if (data == null) return;
    final fresh = await _fetchEntity();
    if (!mounted || fresh == null) return;
    // Keep the project-wide lookup table in step with what we just saved, so
    // sibling panels (links, sub-tasks, epic contents) don't show stale rows.
    final cache = getIt<ProjectLookupsCache>();
    switch (fresh) {
      case _IssueRec(:final issue):
        cache.applyIssue(widget.projectId, issue);
      case _EpicRec(:final epic):
        cache.applyEpic(widget.projectId, epic);
    }
    var next = data.copyWith(entity: fresh);
    // The fix-version picker's candidates depend on the issue's components, so
    // that one lookup genuinely has to be re-fetched when they change.
    if (fresh is _IssueRec &&
        data.entity is _IssueRec &&
        !_sameComponents(
          (data.entity as _IssueRec).issue.components,
          fresh.issue.components,
        )) {
      final versions = await getIt<CatalogRepository>().versionsForComponents(
        widget.projectId,
        fresh.issue.components,
      );
      if (!mounted) return;
      next = next.copyWith(
        releaseVersionCandidates: versions.valueOrNull ?? const [],
      );
    }
    setState(() => _data = next);
  }

  static bool _sameComponents(List<String> a, List<String> b) =>
      a.length == b.length && a.toSet().containsAll(b);

  /// Applies live project events to the open entity.
  ///
  /// Rules: ignore our own echoes (the optimistic cell already shows them),
  /// and only move forward — an event carrying a `version` no newer than what
  /// is on screen is a re-broadcast, not news. Control frames (`connected` /
  /// `resync`) mean the stream may have gaps, so they trigger a real re-fetch.
  void _subscribeToLiveEvents() {
    _events = getIt<ProjectEventsService>()
        .watch(widget.projectId)
        .listen(_onLiveEvent);
  }

  void _onLiveEvent(LiveEvent e) {
    if (!mounted) return;
    final data = _data;
    if (data == null) return;
    final myId = data.profile.id;

    // A gap in the stream: re-read rather than guess.
    if (e.isControl) {
      unawaited(_reload());
      return;
    }
    final p = e.payload;
    if (p['actor_id'] == myId) return;
    final kind = p['event'] as String? ?? '';
    final cache = getIt<ProjectLookupsCache>();

    switch (kind) {
      case 'issue.created' || 'issue.updated':
        final raw = p['issue'];
        if (raw is! Map<String, dynamic>) return;
        final issue = Issue.fromJson(raw);
        cache.applyIssue(widget.projectId, issue);
        if (widget.kind == EntityKind.issue && issue.id == widget.entityId) {
          if (issue.version <= data.entity.version) return;
          setState(() => _data = data.copyWith(entity: _IssueRec(issue)));
        } else {
          // A sibling moved — sub-task rows and epic contents need redrawing.
          setState(() {});
        }
      case 'issue.deleted':
        final id = p['issue_id'] as String?;
        if (id == null) return;
        cache.removeIssue(widget.projectId, id);
        setState(() {});
      case 'epic.created' || 'epic.updated':
        final raw = p['epic'];
        if (raw is! Map<String, dynamic>) return;
        final epic = Epic.fromJson(raw);
        cache.applyEpic(widget.projectId, epic);
        if (widget.kind == EntityKind.epic && epic.id == widget.entityId) {
          if (epic.version <= data.entity.version) return;
          setState(() => _data = data.copyWith(entity: _EpicRec(epic)));
        } else {
          setState(() {});
        }
      case 'epic.deleted':
        final id = p['epic_id'] as String?;
        if (id == null) return;
        cache.removeEpic(widget.projectId, id);
        setState(() {});
      case 'comment.created' || 'comment.updated' || 'comment.deleted':
        // The activity cubit owns the comment list; nudge it to re-read, but
        // only when the comment belongs to the entity we have open.
        if (p['target_id'] == widget.entityId) {
          unawaited(_activityCubit?.load());
        }
      default:
        break;
    }
  }

  ActivityStreamCubit? _activityCubit;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    if (_initialLoading) {
      return _DetailSkeleton(
        compact: widget.onClose != null && !widget.embeddedWide,
        onClose: widget.onClose,
      );
    }
    final data = _data;
    if (data == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(t.entityDetailTitle),
          actions: [
            if (widget.onClose != null)
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: t.actionCancel,
                onPressed: widget.onClose,
              ),
          ],
        ),
        body: _DetailLoadError(
          failure: _failure,
          onRetry: () => unawaited(_initialLoad()),
        ),
      );
    }
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
            // Held so live comment events can ask it to re-read.
            _activityCubit = c;
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
        activityAnchor: _activityAnchor,
      ),
    );
  }

  /// Loads the page. The entity is always fetched fresh; every project-scoped
  /// lookup comes from [ProjectLookupsCache], which fetches once per project
  /// and is kept current by live events.
  Future<({_PageData? data, AppFailure? failure})> _load() async {
    final cache = getIt<ProjectLookupsCache>();
    final profile = await cache.currentProfile();
    if (profile == null) {
      return (data: null, failure: const UnauthorizedFailure());
    }

    final entityRes = await _fetchEntityResult();
    if (entityRes.failure != null) {
      return (data: null, failure: entityRes.failure);
    }
    final entity = entityRes.entity;
    if (entity == null) {
      return (data: null, failure: const NotFoundFailure());
    }

    final lookups = await cache.get(widget.projectId);
    if (lookups == null) {
      return (data: null, failure: const NotFoundFailure());
    }

    // The fix-version picker only offers versions of releases linked to the
    // issue's own components — empty when the issue has none (or for epics,
    // which don't carry a fix version at all).
    final componentIds = entity is _IssueRec
        ? entity.issue.components
        : const <String>[];
    final candidates = await getIt<CatalogRepository>().versionsForComponents(
      widget.projectId,
      componentIds,
    );

    return (
      data: _PageData(
        profile: profile,
        lookups: lookups,
        entity: entity,
        releaseVersionCandidates: candidates.valueOrNull ?? const [],
      ),
      failure: null,
    );
  }

  /// Just the entity — the one request an inline field edit needs.
  Future<_EntityRecord?> _fetchEntity() async =>
      (await _fetchEntityResult()).entity;

  Future<({_EntityRecord? entity, AppFailure? failure})>
  _fetchEntityResult() async {
    final backlog = getIt<BacklogRepository>();
    switch (widget.kind) {
      case EntityKind.epic:
        final res = await backlog.getEpic(widget.projectId, widget.entityId);
        final v = res.valueOrNull;
        return (
          entity: v == null ? null : _EntityRecord.epic(v),
          failure: res.failureOrNull,
        );
      case EntityKind.issue:
        final res = await backlog.getIssue(widget.projectId, widget.entityId);
        final v = res.valueOrNull;
        return (
          entity: v == null ? null : _EntityRecord.issue(v),
          failure: res.failureOrNull,
        );
    }
  }
}

// ---------------------------------------------------------------------------
// Load / error states
// ---------------------------------------------------------------------------

/// Grey placeholder blocks shaped like the real page, so the layout doesn't
/// jump when data lands. Beats a centred spinner, which tells the user
/// nothing about what is coming.
class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton({required this.compact, this.onClose});
  final bool compact;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const _SkeletonBar(width: 220, height: 14),
        actions: [
          if (onClose != null)
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: t.actionCancel,
              onPressed: onClose,
            ),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(compact ? 44 : 56),
          child: Padding(
            padding: EdgeInsets.fromLTRB(compact ? 12 : 16, 0, 16, 12),
            child: const Align(
              alignment: Alignment.centerLeft,
              child: _SkeletonBar(width: 340, height: 22),
            ),
          ),
        ),
      ),
      body: Padding(
        padding: EdgeInsets.all(compact ? 12 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SkeletonPanel(rows: 5),
            SizedBox(height: compact ? 8 : 12),
            const _SkeletonPanel(rows: 3),
            SizedBox(height: compact ? 8 : 12),
            const _SkeletonPanel(rows: 2),
          ],
        ),
      ),
    );
  }
}

class _SkeletonPanel extends StatelessWidget {
  const _SkeletonPanel({required this.rows});
  final int rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SkeletonBar(width: 90, height: 10),
            const SizedBox(height: 14),
            for (var i = 0; i < rows; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    const _SkeletonBar(width: 110, height: 12),
                    const SizedBox(width: 16),
                    _SkeletonBar(
                      width: 120.0 + (i.isEven ? 60 : 0),
                      height: 12,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SkeletonBar extends StatelessWidget {
  const _SkeletonBar({required this.width, required this.height});
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

/// Failure state with a retry. Says what actually went wrong — a missing
/// permission, a deleted entity and a dead network need different responses
/// from the user, so they get different messages.
class _DetailLoadError extends StatelessWidget {
  const _DetailLoadError({required this.failure, required this.onRetry});
  final AppFailure? failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final (icon, message, retryable) = switch (failure) {
      ForbiddenFailure() => (Icons.lock_outline, t.entityLoadForbidden, false),
      UnauthorizedFailure() => (
        Icons.lock_outline,
        t.entityLoadForbidden,
        false,
      ),
      NotFoundFailure() => (
        Icons.search_off_outlined,
        t.entityLoadNotFound,
        false,
      ),
      NetworkFailure() => (Icons.wifi_off_outlined, t.entityLoadOffline, true),
      _ => (Icons.error_outline, t.entityDetailLoadFailed, true),
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 20),
            if (retryable)
              FilledButton.tonalIcon(
                icon: const Icon(Icons.refresh, size: 18),
                onPressed: onRetry,
                label: Text(t.actionRetry),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Loaded data structures
// ---------------------------------------------------------------------------

/// The page's view of its data: the entity itself plus the shared, cached
/// project lookups. Every accessor the widgets already used is preserved as a
/// pass-through, so only the way the data is *obtained* changed.
class _PageData {
  _PageData({
    required this.profile,
    required this.lookups,
    required this.entity,
    required this.releaseVersionCandidates,
  });

  final UserProfile profile;
  final ProjectLookups lookups;
  final _EntityRecord entity;

  /// Versions of releases linked to the issue's own components — the
  /// fix-version picker's candidate list. Empty (and the picker disabled)
  /// when the issue has no components. Entity-scoped, so not part of the
  /// shared project lookups.
  final List<ReleaseVersionRef> releaseVersionCandidates;

  Project get project => lookups.project;
  Map<String, TaxonomyItem> get taxonomyById => lookups.taxonomyById;
  Map<String, Label> get labelsById => lookups.labelsById;
  Map<String, Component> get componentsById => lookups.componentsById;
  Map<String, Epic> get epicsById => lookups.epicsById;
  Map<String, Milestone> get milestonesById => lookups.milestonesById;
  Map<String, Issue> get issuesById => lookups.issuesById;
  Map<String, Customer> get customersById => lookups.customersById;

  /// Project members keyed by user id — for assignee/reporter avatars + names.
  Map<String, UserRef> get membersById => lookups.membersById;
  Map<String, ReleaseVersionRef> get releaseVersionsById =>
      lookups.releaseVersionsById;

  /// Members keyed by lowercase handle — what `@mention` rendering and the
  /// autocomplete both look up. `/me/issues?role=mentioned` matches on the
  /// same `@username` text, so inserting it has real meaning server-side.
  Map<String, UserRef> get mentionsByHandle => {
    for (final u in lookups.membersById.values)
      if (u.username.isNotEmpty) u.username.toLowerCase(): u,
  };

  _PageData copyWith({
    _EntityRecord? entity,
    List<ReleaseVersionRef>? releaseVersionCandidates,
  }) => _PageData(
    profile: profile,
    lookups: lookups,
    entity: entity ?? this.entity,
    releaseVersionCandidates:
        releaseVersionCandidates ?? this.releaseVersionCandidates,
  );
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

  /// Monotonic revision, used to reject stale live events.
  int get version;

  /// Canonical `"<id>:<version>"` token sent as `If-Match` on updates.
  String? get etag;
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
  @override
  int get version => epic.version;
  @override
  String? get etag => epic.etag;
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
  @override
  int get version => issue.version;
  @override
  String? get etag => issue.etag;
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
    required this.activityAnchor,
    this.onClose,
    this.onOpen,
    this.embeddedWide = false,
  });

  /// Scroll target for the action bar's "Comment" button.
  final GlobalKey activityAnchor;

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

  /// The clean full-screen URL for this entity, by its human-readable key.
  /// Uses the short lowercase project prefix (`/projects/ip/issues/ip-42`)
  /// when the project has one; the UUID form works too but this is the
  /// canonical link users see and share.
  String _fullScreenRoute(String key) => Routes.entityByKeyFor(
    projectId: data.project.id,
    issuePrefix: data.project.issuePrefix,
    kind: kind,
    key: key,
  );

  /// Leaves for [route], dismissing the embedding panel / sheet first so the
  /// user doesn't land on the full page with a stale overlay on top.
  void _leaveFor(BuildContext context, String route) {
    onClose?.call();
    context.go(route);
  }

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
    // An issue that belongs to an epic gets the epic's key as an extra crumb,
    // so the trail mirrors the real hierarchy and the epic is one tap away.
    final parentEpic = entity is _IssueRec && entity.issue.epicId != null
        ? data.epicsById[entity.issue.epicId]
        : null;
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
            if (parentEpic != null)
              Crumb(
                label: epicKeyLabel(
                  data.project.issuePrefix,
                  parentEpic.reference,
                ),
                mono: true,
                onTap: () => _leaveFor(
                  context,
                  Routes.entityByKeyFor(
                    projectId: data.project.id,
                    issuePrefix: data.project.issuePrefix,
                    kind: EntityKind.epic,
                    key: epicKeyLabel(
                      data.project.issuePrefix,
                      parentEpic.reference,
                    ),
                  ),
                ),
              ),
            Crumb(
              label: key,
              mono: true,
              onTap: () => _leaveFor(context, _fullScreenRoute(key)),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.link),
            tooltip: t.copyLink,
            onPressed: () {
              final origin = kIsWeb
                  ? Uri.base.origin
                  : getIt<ApiConfig>().baseUrl;
              final link = '$origin${_fullScreenRoute(key)}';
              unawaited(Clipboard.setData(ClipboardData(text: link)));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(t.copiedToClipboard)),
              );
            },
          ),
          // Embedded panels get a direct click-through to the full-screen
          // view — copy-link alone forces a paste round-trip.
          if (onClose != null)
            IconButton(
              icon: const Icon(Icons.open_in_full),
              tooltip: t.openFullScreen,
              onPressed: () => _leaveFor(context, _fullScreenRoute(key)),
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
                activityAnchor: activityAnchor,
              ),
              const SizedBox(height: 12),
              if (isWide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: _LeftColumn(
                        data: data,
                        kind: kind,
                        entityId: entityId,
                        projectId: projectId,
                        onChanged: onChanged,
                        onClose: onClose,
                        activityAnchor: activityAnchor,
                        compact: _isCompact,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 2,
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
                      onClose: onClose,
                      activityAnchor: activityAnchor,
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
      markdown: true,
      markdownTitle: '${t.panelDescription} — ${data.entity.subject}',
      members: data.mentionsByHandle,
      onUploadImage: (name, bytes) => _uploadInlineImage(
        projectId: projectId,
        kind: kind,
        entityId: entityId,
        filename: name,
        bytes: bytes,
      ),
      placeholder: t.descriptionPlaceholder,
      displayBuilder: (context, beginEdit) => Stack(
        children: [
          Padding(
            // Reserve the corner so text never runs under the buttons.
            padding: const EdgeInsets.only(right: 72),
            child: MarkdownText(
              data.entity.description,
              mentions: data.mentionsByHandle,
              // Not selectable here: the enclosing click-to-edit surface needs
              // the taps. A SelectionArea claims them to place a caret, which
              // is why clicking the text used to do nothing and only the
              // margin around it opened the editor. Copy stays available
              // through the button, and the editor selects freely.
              selectable: false,
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (canEdit)
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    visualDensity: VisualDensity.compact,
                    tooltip: t.actionEdit,
                    onPressed: beginEdit,
                  ),
                if (data.entity.description.trim().isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.copy_outlined, size: 16),
                    visualDensity: VisualDensity.compact,
                    tooltip: t.actionCopy,
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      await Clipboard.setData(
                        ClipboardData(text: data.entity.description),
                      );
                      messenger.showSnackBar(
                        SnackBar(content: Text(t.copiedToClipboard)),
                      );
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
      onSave: (next) => _patchAndReport(
        _reporterOf(context),
        kind: kind,
        projectId: projectId,
        entityId: entityId,
        etag: data.entity.etag,
        onChanged: onChanged,
        epicPatch: () => UpdateEpicRequest(description: next),
        issuePatch: () => UpdateIssueRequest(description: next),
      ),
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
        return _patchAndReport(
          _reporterOf(context),
          kind: kind,
          projectId: projectId,
          entityId: entityId,
          etag: entity.etag,
          onChanged: onChanged,
          epicPatch: () => UpdateEpicRequest(subject: trimmed),
          issuePatch: () => UpdateIssueRequest(subject: trimmed),
        );
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
    required this.activityAnchor,
  });

  /// The activity panel's key — the "Comment" button scrolls to it.
  final GlobalKey activityAnchor;

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
          // Actually take the user there instead of telling them to scroll.
          onPressed: () {
            final target = activityAnchor.currentContext;
            if (target == null) return;
            unawaited(
              Scrollable.ensureVisible(
                target,
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                alignment: 0.1,
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
        // Everything else the entity can do, in one place. Actions that also
        // live further down the page are repeated here on purpose: the point
        // of the menu is that nothing has to be hunted for.
        _EntityActionsMenu(
          data: data,
          kind: kind,
          entityId: entityId,
          projectId: projectId,
          onChanged: onChanged,
          activityAnchor: activityAnchor,
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
    required this.activityAnchor,
    this.onClose,
    this.compact = false,
  });
  final _PageData data;
  final EntityKind kind;
  final String entityId;
  final String projectId;
  final VoidCallback onChanged;
  final GlobalKey activityAnchor;
  final VoidCallback? onClose;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final gap = SizedBox(height: compact ? 8 : 12);
    final includedIssues =
        data.issuesById.values.where((i) => i.epicId == entityId).toList()
          ..sort((a, b) => a.reference.compareTo(b.reference));
    // Children of this issue. The lookup table already holds every issue in
    // the project, so this is a filter rather than a fetch.
    final subtasks =
        data.issuesById.values.where((i) => i.parentId == entityId).toList()
          ..sort((a, b) => a.reference.compareTo(b.reference));
    // A progress bar, so it follows counts_as_done rather than is_closed.
    final closedSubtasks = subtasks
        .where((i) => data.taxonomyById[i.statusId]?.countsAsDone ?? false)
        .length;
    final canEdit = context.select<ProjectDetailCubit, bool>((c) {
      final st = c.state;
      return st is ProjectDetailLoaded && st.has(Permission.issueCreate);
    });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Panel(
          compact: compact,
          icon: Icons.list_alt_outlined,
          panelId: 'details',
          title: t.panelDetails,
          trailing: _TimestampsStamp(data: data),
          child: _DetailsTable(
            data: data,
            kind: kind,
            entityId: entityId,
            projectId: projectId,
            onChanged: onChanged,
            compact: compact,
          ),
        ),
        if (kind == EntityKind.issue) ...[
          gap,
          _Panel(
            compact: compact,
            icon: Icons.widgets_outlined,
            panelId: 'delivery',
            title: t.panelComponentVersions,
            child: _ComponentVersionsTable(
              data: data,
              entityId: entityId,
              projectId: projectId,
              onChanged: onChanged,
            ),
          ),
        ],
        gap,
        _Panel(
          compact: compact,
          icon: Icons.subject_outlined,
          panelId: 'description',
          title: t.panelDescription,
          child: _DescriptionEditor(
            data: data,
            kind: kind,
            entityId: entityId,
            projectId: projectId,
            onChanged: onChanged,
          ),
        ),
        if (kind == EntityKind.issue && (subtasks.isNotEmpty || canEdit)) ...[
          gap,
          _Panel(
            compact: compact,
            icon: Icons.account_tree_outlined,
            panelId: 'subtasks',
            title: subtasks.isEmpty
                ? t.panelSubtasks
                : '${t.panelSubtasks} · $closedSubtasks/${subtasks.length}',
            trailing: subtasks.isEmpty
                ? null
                : _MiniProgress(
                    value: closedSubtasks / subtasks.length,
                  ),
            child: _SubtasksPanel(
              parentId: entityId,
              subtasks: subtasks,
              taxonomyById: data.taxonomyById,
              membersById: data.membersById,
              project: data.project,
              parentEpicId: data.entity is _IssueRec
                  ? (data.entity as _IssueRec).issue.epicId
                  : null,
              canEdit: canEdit,
              onChanged: onChanged,
              onClose: onClose,
            ),
          ),
        ],
        if (kind == EntityKind.epic) ...[
          gap,
          _Panel(
            compact: compact,
            icon: Icons.checklist_outlined,
            panelId: 'included',
            title: includedIssues.isEmpty
                ? t.panelIncludedIssues
                : '${t.panelIncludedIssues} · ${includedIssues.length}',
            child: _IncludedIssuesPanel(
              issues: includedIssues,
              taxonomyById: data.taxonomyById,
              membersById: data.membersById,
              project: data.project,
              onChanged: onChanged,
            ),
          ),
        ],
        gap,
        _Panel(
          key: activityAnchor,
          compact: compact,
          icon: Icons.forum_outlined,
          panelId: 'activity',
          title: t.panelActivity,
          child: ActivityStreamView(
            draftKey: '${kind.wire}:$entityId',
            shrinkWrap: true,
            membersById: data.membersById,
            mentions: data.mentionsByHandle,
            onUploadImage: (name, bytes) => _uploadInlineImage(
              projectId: projectId,
              kind: kind,
              entityId: entityId,
              filename: name,
              bytes: bytes,
            ),
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
            icon: Icons.flag_outlined,
            panelId: 'epic',
            title: t.panelEpic,
            child: _EpicPropertiesTable(
              epic: (data.entity as _EpicRec).epic,
              milestonesById: data.milestonesById,
              projectId: projectId,
              entityId: entityId,
              onChanged: onChanged,
            ),
          ),
          gap,
        ],
        _Panel(
          compact: compact,
          icon: Icons.people_outline,
          panelId: 'people',
          title: t.panelPeople,
          child: _PeopleTable(
            data: data,
            kind: kind,
            entityId: entityId,
            projectId: projectId,
            onChanged: onChanged,
          ),
        ),
        // Links only exist between issues (the backend model is issue-scoped),
        // so epics don't get a permanently-empty panel with no add button.
        if (kind == EntityKind.issue) ...[
          gap,
          _Panel(
            compact: compact,
            icon: Icons.link_outlined,
            panelId: 'links',
            title: t.panelLinks,
            child: LinksPanelContent(
              projectId: data.project.id,
              sourceKind: kind,
              sourceId: entityId,
              modifyPermission: _modifyPermissionFor(kind),
              onNavigate: onClose,
              lookup: LinksLookup(
                epics: data.epicsById,
                issues: data.issuesById,
                prefix: data.project.issuePrefix,
              ),
            ),
          ),
        ],
        gap,
        _Panel(
          compact: compact,
          icon: Icons.attach_file_outlined,
          panelId: 'attachments',
          // Narrow board panel: fold the secondary panels away by default so
          // the content people came for is reachable without a long scroll.
          initiallyExpanded: !compact,
          title: t.panelAttachments,
          child: const AttachmentsView(shrinkWrap: true),
        ),
        if (kind == EntityKind.issue) ...[
          gap,
          LogTimeSection(projectId: projectId, issueId: entityId),
          gap,
          _Panel(
            compact: compact,
            icon: Icons.visibility_outlined,
            panelId: 'watchers',
            initiallyExpanded: !compact,
            title: t.panelWatchers,
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
            icon: Icons.warning_amber_outlined,
            panelId: 'danger',
            initiallyExpanded: false,
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

/// A titled card section on the detail page.
///
/// Panels can be collapsed, and the choice sticks: with five or six panels in
/// the right column — and everything stacked into one scroll inside the 420px
/// board panel — being able to fold away what you don't use matters. Collapsed
/// panels keep their [trailing] summary visible, so folding hides detail, not
/// information.
class _Panel extends StatefulWidget {
  const _Panel({
    required this.title,
    required this.child,
    this.icon,
    this.trailing,
    this.compact = false,
    this.panelId,
    this.initiallyExpanded = true,
    super.key,
  });
  final String title;
  final Widget child;

  /// Optional glyph rendered before the title — makes a long column of
  /// panels scannable at a glance.
  final IconData? icon;

  /// Optional secondary content pinned to the right of the header row (e.g.
  /// the Details panel's created / updated stamp). Wraps onto its own line in
  /// compact mode, where the header has no spare width.
  final Widget? trailing;
  final bool compact;

  /// Stable id used to persist the collapsed state. Null = not collapsible.
  final String? panelId;

  /// Default when nothing has been persisted yet.
  final bool initiallyExpanded;

  @override
  State<_Panel> createState() => _PanelState();
}

/// Lets the actions menu jump to a panel by its id.
///
/// A registry rather than GlobalKeys threaded down the tree: the same panel
/// ids render in the full page, the slide-over sheet and the board side panel,
/// and a GlobalKey shared between two live subtrees would throw. The last
/// panel to mount wins, which is the one on screen.
abstract final class _PanelAnchors {
  static final Map<String, _PanelState> _live = {};

  /// Expand the panel if it is folded, then scroll it into view. Returns false
  /// when no such panel is mounted, so callers can fall back.
  static bool reveal(String panelId) {
    final panel = _live[panelId];
    if (panel == null || !panel.mounted) return false;
    panel.expand();
    unawaited(
      Scrollable.ensureVisible(
        panel.context,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        alignment: 0.1,
      ),
    );
    return true;
  }
}

class _PanelState extends State<_Panel> {
  late bool _expanded = widget.initiallyExpanded;
  KeyValueStorage? _store;

  /// Open a folded panel so a jump from the actions menu lands on content
  /// rather than on a collapsed header.
  void expand() {
    if (_expanded || !mounted) return;
    setState(() => _expanded = true);
    unawaited(_store?.set<bool>(_storeKey, true));
  }

  /// Compact (board panel) and roomy (full page / sheet) layouts keep separate
  /// preferences — folding Attachments away in a 420px panel shouldn't fold it
  /// on the full page, where there's room for it.
  String get _storeKey =>
      'detail.panel.${widget.panelId}.${widget.compact ? 'compact' : 'wide'}';

  @override
  void initState() {
    super.initState();
    if (widget.panelId == null) return;
    _PanelAnchors._live[widget.panelId!] = this;
    if (getIt.isRegistered<KeyValueStorage>(instanceName: HiveBoxes.ui)) {
      _store = getIt<KeyValueStorage>(instanceName: HiveBoxes.ui);
      final saved = _store?.get<bool>(_storeKey);
      if (saved != null) _expanded = saved;
    }
  }

  @override
  void dispose() {
    final id = widget.panelId;
    if (id != null && identical(_PanelAnchors._live[id], this)) {
      _PanelAnchors._live.remove(id);
    }
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    unawaited(_store?.set<bool>(_storeKey, _expanded));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final collapsible = widget.panelId != null;
    final compact = widget.compact;
    final titleStyle = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      letterSpacing: 0.4,
      fontWeight: FontWeight.w700,
    );
    final titleRow = Row(
      children: [
        if (collapsible)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: AnimatedRotation(
              turns: _expanded ? 0.25 : 0,
              duration: const Duration(milliseconds: 150),
              child: Icon(
                Icons.chevron_right,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        if (widget.icon != null) ...[
          Icon(
            widget.icon,
            size: 14,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
          ),
          const SizedBox(width: 6),
        ],
        Expanded(child: Text(widget.title, style: titleStyle)),
        if (widget.trailing != null && !compact)
          Flexible(child: widget.trailing!),
      ],
    );
    final header = Padding(
      padding: EdgeInsets.fromLTRB(
        compact ? 12 : 16,
        compact ? 8 : 12,
        compact ? 12 : 16,
        compact ? 6 : 8,
      ),
      child: widget.trailing != null && compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                titleRow,
                const SizedBox(height: 4),
                widget.trailing!,
              ],
            )
          : titleRow,
    );
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (collapsible)
            Material(
              type: MaterialType.transparency,
              child: InkWell(onTap: _toggle, child: header),
            )
          else
            header,
          if (_expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? 12 : 16,
                compact ? 8 : 12,
                compact ? 12 : 16,
                compact ? 12 : 16,
              ),
              child: widget.child,
            ),
          ],
        ],
      ),
    );
  }
}

/// The `Created … · Updated …` stamp that replaces the old DATES panel. Lives
/// in the Details panel header; full timestamps are one hover away.
class _TimestampsStamp extends StatelessWidget {
  const _TimestampsStamp({required this.data});
  final _PageData data;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final created = formatTimestamp(context, data.entity.createdAt);
    final updated = formatTimestamp(context, data.entity.modifiedAt);
    return Tooltip(
      message:
          '${t.detailFieldCreated}: ${data.entity.createdAt.toLocal()}\n'
          '${t.detailFieldUpdated}: ${data.entity.modifiedAt.toLocal()}',
      child: Text(
        '${t.detailFieldCreated} $created  ·  ${t.detailFieldUpdated} $updated',
        textAlign: TextAlign.right,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.outline,
          fontWeight: FontWeight.w500,
        ),
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
    // No "Type: Issue" row — the breadcrumb, the key and the whole route
    // already say which kind this is.
    // Epic sits above the grid and spans it: an epic key plus subject is far
    // too long for a half-width cell.
    final leading = <Widget>[];
    // Labels close the block on a full row for the same reason — there can be
    // many of them and they wrap.
    final trailing = <Widget>[];
    final rows = <Widget>[
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
              _reporterOf(context),
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
              _reporterOf(context),
              issuePatch: () => UpdateIssueRequest(priorityId: id),
            ),
          ),
          // The cell shows just the letter as a scaled badge; the numeric
          // weight stays in the picker, where choosing a size is the task.
          _taxonomyRow(
            context,
            label: t.detailFieldSize,
            currentId: issue.sizeId,
            kind: TaxonomyKind.size,
            canEdit: canEdit,
            asSizeBadge: true,
            pickerLabelBuilder: (item) =>
                item.value == null ? item.name : '${item.name} (${item.value})',
            patch: (id) => _patchEntity(
              _reporterOf(context),
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
            t.ttStartDate,
            _DateValue(
              value: issue.startDate,
              canEdit: canEdit,
              onTap: () => _pickIssueDate(context, isStart: true),
            ),
          ),
          _kvRowWith(
            context,
            t.issueFieldDueDate,
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
            _kvRow(context, t.detailFieldResolvedAt, issue.resolvedAt!),
          _inheritedMilestoneRow(context, issue: issue),
          _parentRow(context, currentId: issue.parentId, canEdit: canEdit),
        ]);
        leading.add(
          _epicRow(context, currentId: issue.epicId, canEdit: canEdit),
        );
        trailing.add(
          _labelsRow(context, currentIds: issue.labels, canEdit: canEdit),
        );
      case _EpicRec():
        break;
    }
    // Two columns when there's genuinely room for them. Measured with
    // LayoutBuilder, NOT Breakpoints/MediaQuery: this table also renders
    // inside the ~420px board side panel and the 72%-wide slide-over sheet,
    // where the screen width says nothing about the space actually available.
    return LayoutBuilder(
      builder: (context, constraints) {
        final splitCols = !compact && constraints.maxWidth >= 560;
        Widget wrap(Widget grid) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final row in leading) _detailRowPad(row),
            grid,
            for (final row in trailing) _detailRowPad(row),
          ],
        );
        if (!splitCols || rows.length < 4) {
          return wrap(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [for (final row in rows) _detailRowPad(row)],
            ),
          );
        }
        // Column-major halves keep each column readable top-to-bottom, rather
        // than making the eye zig-zag across the pair as round-robin would.
        final half = (rows.length + 1) ~/ 2;
        return _KvLabelWidth(
          width: 110,
          child: wrap(
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final row in rows.take(half)) _detailRowPad(row),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final row in rows.skip(half)) _detailRowPad(row),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _detailRowPad(Widget row) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: row,
  );

  // ---- row builders ------------------------------------------------------

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
        _reporterOf(context),
        epicPatch: () => UpdateEpicRequest(statusId: id),
        issuePatch: () => UpdateIssueRequest(statusId: id),
      ),
    );
  }

  /// A taxonomy-backed row. Taxonomy items carry a colour, so the value cell
  /// renders as a tinted badge rather than plain text — status, issue type,
  /// priority and size all read as pills.
  ///
  /// [pickerLabelBuilder] only affects the picker list; the cell always shows
  /// the bare item name. That split is what keeps `M (3)` in the dropdown
  /// (where the weight helps you choose) and plain `M` in the row.
  Widget _taxonomyRow(
    BuildContext context, {
    required String label,
    required String? currentId,
    required TaxonomyKind kind,
    required bool canEdit,
    required Future<bool> Function(String? newId) patch,
    String Function(TaxonomyItem)? pickerLabelBuilder,
    bool asSizeBadge = false,
  }) {
    final t = AppLocalizations.of(context);
    final all = data.taxonomyById.values.where((tx) => tx.kind == kind).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    final current = currentId == null ? null : data.taxonomyById[currentId];
    final pickerLabel = pickerLabelBuilder ?? (TaxonomyItem item) => item.name;
    return _editableRow(
      context,
      label: label,
      displayText: current?.name ?? '—',
      colorHex: current?.color,
      sizeItem: asSizeBadge ? current : null,
      currentId: currentId,
      noneLabel: t.statusValueNone,
      canEdit: canEdit,
      candidates: [
        for (final item in all)
          _Candidate(
            id: item.id,
            label: pickerLabel(item),
            badgeLabel: item.name,
            colorHex: item.color,
            sizeItem: asSizeBadge ? item : null,
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
        _reporterOf(context),
        issuePatch: () => UpdateIssueRequest(epicId: id),
      ),
    );
  }

  /// Milestone as seen from an issue: **read-only**, resolved through the
  /// issue's epic. Issues are never assigned to a milestone directly — a
  /// milestone is composed of epics (see the milestone detail page), so the
  /// only honest thing to show here is what the parent epic inherits.
  Widget _inheritedMilestoneRow(
    BuildContext context, {
    required Issue issue,
  }) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final epic = issue.epicId == null ? null : data.epicsById[issue.epicId];
    final milestoneId = epic?.milestoneId;
    final milestone = milestoneId == null
        ? null
        : data.milestonesById[milestoneId];
    final style = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return _kvRowWith(
      context,
      t.detailFieldMilestone,
      Tooltip(
        message: t.detailMilestoneViaEpicHint,
        child: milestone == null
            ? Text('—', style: style)
            : Material(
                type: MaterialType.transparency,
                child: InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: () => context.go(
                    Routes.milestoneDetailFor(data.project.id, milestone.id),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    child: Text(
                      milestone.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: style?.copyWith(
                        color: theme.colorScheme.primary,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
              ),
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
    // Any issue may become the parent (multi-level nesting) except this one
    // and its own descendants — those would close a cycle, which the backend
    // rejects with a 422.
    final descendants = <String>{entityId};
    var grew = true;
    while (grew) {
      grew = false;
      for (final i in data.issuesById.values) {
        if (i.parentId != null &&
            descendants.contains(i.parentId) &&
            descendants.add(i.id)) {
          grew = true;
        }
      }
    }
    final candidates =
        data.issuesById.values
            .where((i) => !descendants.contains(i.id))
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
        _reporterOf(context),
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
        _reporterOf(context),
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
          _reporterOf(context),
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
        _reporterOf(context),
        issuePatch: () => UpdateIssueRequest(resolution: id),
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
          _reporterOf(context),
          issuePatch: () => UpdateIssueRequest(labels: next),
        ),
      ),
    );
  }

  /// Top-level patch dispatcher used by every editable row. The caller
  /// passes only the builder for its kind; others are null. Fetches the
  /// fresh entity for its etag, runs the PATCH, and triggers `onChanged`
  /// on success so the page reloads.
  Future<bool> _patchEntity(
    _Reporter reporter, {
    UpdateEpicRequest Function()? epicPatch,
    UpdateIssueRequest Function()? issuePatch,
  }) async {
    return _patchAndReport(
      reporter,
      kind: kind,
      projectId: projectId,
      entityId: entityId,
      etag: data.entity.etag,
      onChanged: onChanged,
      epicPatch: epicPatch,
      issuePatch: issuePatch,
    );
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
    String? colorHex,
    TaxonomyItem? sizeItem,
  }) {
    return _kvRowWith(
      context,
      label,
      _ClickToEditCell(
        displayText: displayText,
        colorHex: colorHex,
        sizeItem: sizeItem,
        candidates: candidates,
        currentId: currentId,
        noneLabel: noneLabel,
        canEdit: canEdit,
        onPicked: onPicked,
      ),
    );
  }

  String _labelList(List<String> ids, Map<String, Label> by) =>
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
    // Captured before the picker await — the context must not be used after.
    final reporter = _reporterOf(context);
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
      reporter,
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
    this.badgeLabel,
    this.colorHex,
    this.sizeItem,
    this.icon,
    this.pinned = false,
  });
  final String id;

  /// What the picker list shows — may carry extra context the row doesn't
  /// need (e.g. a size's numeric weight, `M (3)`).
  final String label;

  /// Short form shown in the value cell once picked. Falls back to [label].
  final String? badgeLabel;
  final String? colorHex;

  /// When set the cell renders a [SizeBadge] (scaled by the item's ordinal)
  /// instead of the generic tinted pill.
  final TaxonomyItem? sizeItem;

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
    this.colorHex,
    this.sizeItem,
  });

  final String displayText;
  final List<_Candidate> candidates;
  final String? currentId;
  final String noneLabel;
  final bool canEdit;
  final Future<bool> Function(String? newId) onPicked;

  /// When set (and the shown value isn't [noneLabel]), the value renders as
  /// a tinted badge in this color instead of plain text — status, issue type,
  /// priority, size and the release fix-version all use this.
  final String? colorHex;

  /// Size taxonomy item: renders the purpose-built [SizeBadge] (font and
  /// padding scale with the ordinal) instead of the generic pill.
  final TaxonomyItem? sizeItem;

  @override
  State<_ClickToEditCell> createState() => _ClickToEditCellState();
}

class _ClickToEditCellState extends State<_ClickToEditCell> {
  /// Display override for the optimistic-update window: shows the just-picked
  /// value until the PATCH resolves; on failure we revert. Held as a whole
  /// candidate (not just its text) so the badge's colour and shape swap
  /// together with the label instead of lagging a frame behind.
  _Candidate? _optimisticPick;

  /// Distinguishes "nothing picked yet" from "picked None" — the latter has a
  /// null candidate but must still override the widget's display text.
  bool _optimisticCleared = false;
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
    final chosen = newId == null
        ? null
        : widget.candidates
              .where((c) => c.id == newId)
              .cast<_Candidate?>()
              .firstOrNull;
    setState(() {
      _optimisticPick = chosen;
      _optimisticCleared = true;
      _saving = true;
    });
    final ok = await widget.onPicked(newId);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (!ok) {
        _optimisticPick = null;
        _optimisticCleared = false;
      }
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
    // During the optimistic window the picked candidate wins; otherwise the
    // widget's own (server-backed) value does.
    final pick = _optimisticPick;
    final shownText = _optimisticCleared
        ? (pick?.badgeLabel ?? pick?.label ?? '—')
        : widget.displayText;
    final shownColor = _optimisticCleared ? pick?.colorHex : widget.colorHex;
    final shownSize = _optimisticCleared ? pick?.sizeItem : widget.sizeItem;
    Widget value() => _tintedValue(
      shownText,
      widget.noneLabel,
      shownColor,
      shownSize,
      textStyle,
    );
    if (!widget.canEdit) {
      return MouseRegion(
        cursor: SystemMouseCursors.basic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _showReadOnlyToast(context),
          child: Tooltip(
            message: shownText,
            waitDuration: const Duration(milliseconds: 600),
            child: value(),
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
                  child: value(),
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
    ];
    for (final c in regular) {
      out.add(_PickerRow.candidate(c));
    }
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

/// Epic properties: cover image, colour swatch, milestone and start / end
/// dates. Every field PATCHes the epic via the shared dispatcher then
/// triggers a reload.
///
/// Milestone lives here, not on the issue: a milestone is composed of epics,
/// so the epic is the only place the assignment can be made.
class _EpicPropertiesTable extends StatelessWidget {
  const _EpicPropertiesTable({
    required this.epic,
    required this.milestonesById,
    required this.projectId,
    required this.entityId,
    required this.onChanged,
  });
  final Epic epic;
  final Map<String, Milestone> milestonesById;
  final String projectId;
  final String entityId;
  final VoidCallback onChanged;

  Future<void> _patch(_Reporter reporter, UpdateEpicRequest body) async {
    await _patchAndReport(
      reporter,
      kind: EntityKind.epic,
      projectId: projectId,
      entityId: entityId,
      etag: epic.etag,
      onChanged: onChanged,
      epicPatch: () => body,
    );
  }

  Future<void> _pickDate(BuildContext context, {required bool isStart}) async {
    final reporter = _reporterOf(context);
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
      reporter,
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
                    onChanged: (hex) => unawaited(
                      _patch(
                        _reporterOf(context),
                        UpdateEpicRequest(color: hex),
                      ),
                    ),
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
          t.detailFieldMilestone,
          _ClickToEditCell(
            displayText:
                (epic.milestoneId == null
                    ? null
                    : milestonesById[epic.milestoneId]?.name) ??
                '—',
            currentId: epic.milestoneId,
            noneLabel: t.statusValueNone,
            canEdit: canEdit,
            candidates: [
              for (final m
                  in milestonesById.values.toList()
                    ..sort((a, b) => a.name.compareTo(b.name)))
                _Candidate(id: m.id, label: m.name),
            ],
            onPicked: (id) async {
              await _patch(
                _reporterOf(context),
                UpdateEpicRequest(milestoneId: id),
              );
              return true;
            },
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
/// Thin progress bar shown in a panel header (sub-task completion).
class _MiniProgress extends StatelessWidget {
  const _MiniProgress({required this.value});
  final double value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 72,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: LinearProgressIndicator(
          value: value.clamp(0, 1),
          minHeight: 5,
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
        ),
      ),
    );
  }
}

/// An issue's children. Mirrors the epic's included-issues list, plus inline
/// quick-add: a new sub-task inherits the parent's epic so it lands in the
/// same place on the board.
class _SubtasksPanel extends StatefulWidget {
  const _SubtasksPanel({
    required this.parentId,
    required this.subtasks,
    required this.taxonomyById,
    required this.membersById,
    required this.project,
    required this.parentEpicId,
    required this.canEdit,
    required this.onChanged,
    this.onClose,
  });

  final String parentId;
  final List<Issue> subtasks;
  final Map<String, TaxonomyItem> taxonomyById;
  final Map<String, UserRef> membersById;
  final Project project;
  final String? parentEpicId;
  final bool canEdit;
  final VoidCallback onChanged;
  final VoidCallback? onClose;

  @override
  State<_SubtasksPanel> createState() => _SubtasksPanelState();
}

class _SubtasksPanelState extends State<_SubtasksPanel> {
  final _controller = TextEditingController();
  bool _adding = false;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final subject = _controller.text.trim();
    if (subject.isEmpty || _saving) return;
    setState(() => _saving = true);
    final res = await getIt<BacklogRepository>().createIssue(
      widget.project.id,
      CreateIssueRequest(
        subject: subject,
        parentId: widget.parentId,
        epicId: widget.parentEpicId,
      ),
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (res.isOk) {
        _controller.clear();
        _adding = false;
      }
    });
    if (res.isOk) {
      // The new child lives in the shared lookup table the panel reads from.
      getIt<ProjectLookupsCache>().invalidate(widget.project.id);
      widget.onChanged();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).entitySaveFailed)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.subtasks.isEmpty && !_adding)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              t.subtasksEmpty,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
                fontStyle: FontStyle.italic,
              ),
            ),
          )
        else
          for (final i in widget.subtasks)
            _IncludedIssueRow(
              issue: i,
              status: widget.taxonomyById[i.statusId],
              assignee: i.assignedTo == null
                  ? null
                  : widget.membersById[i.assignedTo],
              keyLabel: issueKeyLabel(widget.project.issuePrefix, i.reference),
              // Same gesture as everywhere else: the subtask opens over this
              // panel and closing it comes straight back here.
              onTap: () async {
                await showEntityDetailSheet(
                  context,
                  projectId: widget.project.id,
                  kind: EntityKind.issue,
                  entityId: i.id,
                );
                widget.onChanged();
              },
            ),
        if (widget.canEdit) ...[
          const SizedBox(height: 4),
          if (_adding)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    autofocus: true,
                    enabled: !_saving,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: t.subtaskSubjectHint,
                      border: const OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => unawaited(_create()),
                  ),
                ),
                const SizedBox(width: 8),
                if (_saving)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else ...[
                  IconButton(
                    icon: const Icon(Icons.check, size: 18),
                    tooltip: t.actionSave,
                    onPressed: () => unawaited(_create()),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    tooltip: t.actionCancel,
                    onPressed: () => setState(() {
                      _adding = false;
                      _controller.clear();
                    }),
                  ),
                ],
              ],
            )
          else
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.add, size: 16),
                label: Text(t.actionAddSubtask),
                onPressed: () => setState(() => _adding = true),
              ),
            ),
        ],
      ],
    );
  }
}

class _IncludedIssuesPanel extends StatelessWidget {
  const _IncludedIssuesPanel({
    required this.issues,
    required this.taxonomyById,
    required this.membersById,
    required this.project,
    this.onChanged,
  });
  final List<Issue> issues;
  final Map<String, TaxonomyItem> taxonomyById;
  final Map<String, UserRef> membersById;
  final Project project;

  /// Reload the epic after a nested issue sheet closes — its status, and so
  /// this epic's progress, may have changed while it was open.
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    if (issues.isEmpty) {
      return Text(
        t.epicNoIssues,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.outline,
          fontStyle: FontStyle.italic,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final i in issues)
          _IncludedIssueRow(
            issue: i,
            status: taxonomyById[i.statusId],
            assignee: i.assignedTo == null ? null : membersById[i.assignedTo],
            keyLabel: issueKeyLabel(project.issuePrefix, i.reference),
            // Layer the issue over this panel instead of replacing it, so
            // closing it returns to the epic (and to whatever opened that).
            onTap: () async {
              await showEntityDetailSheet(
                context,
                projectId: project.id,
                kind: EntityKind.issue,
                entityId: i.id,
              );
              onChanged?.call();
            },
          ),
      ],
    );
  }
}

class _IncludedIssueRow extends StatelessWidget {
  const _IncludedIssueRow({
    required this.issue,
    required this.status,
    required this.assignee,
    required this.keyLabel,
    required this.onTap,
  });
  final Issue issue;
  final TaxonomyItem? status;
  final UserRef? assignee;
  final String keyLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        hoverColor: theme.colorScheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            children: [
              IssueKeyChip(text: keyLabel),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  issue.subject,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              if (assignee != null) ...[
                const SizedBox(width: 8),
                UserAvatar(user: assignee!, size: 20),
              ],
              if (status != null) ...[
                const SizedBox(width: 8),
                StatusPill(
                  label: status!.name,
                  colorHex: status!.color,
                  dense: true,
                ),
              ],
            ],
          ),
        ),
      ),
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

/// Uploads an image pasted into a markdown editor as an attachment of the
/// entity being edited, and returns the stable download path to reference it
/// by. `/attachments/{id}/download` is session-authenticated, so a same-origin
/// web request carries the cookie without extra plumbing.
Future<String?> _uploadInlineImage({
  required String projectId,
  required EntityKind kind,
  required String entityId,
  required String filename,
  required Uint8List bytes,
}) async {
  final res = await getIt<ActivityRepository>().uploadAttachment(
    projectId,
    kind,
    entityId,
    filename: filename,
    bytes: bytes,
    contentType: 'image/png',
  );
  final a = res.valueOrNull;
  if (a == null) return null;
  return '/api/v1/projects/$projectId/attachments/${a.id}/download';
}

/// Outcome of a field PATCH, so callers can tell "someone else got there
/// first" apart from a plain failure.
enum _PatchOutcome { ok, conflict, failed }

/// Shared PATCH dispatcher for any field on the entity detail page. The caller
/// passes only the builder matching the active kind.
///
/// [etag] MUST be the token captured when the entity was loaded. This function
/// used to re-fetch the entity to obtain a *fresh* etag right before the PATCH,
/// which made the `If-Match` precondition unconditionally pass and silently
/// clobbered concurrent edits — exactly the thing the backend's 412 exists to
/// prevent. Passing the loaded token restores that protection (and drops a
/// request per edit).
Future<_PatchOutcome> _patchEntityKind({
  required EntityKind kind,
  required String projectId,
  required String entityId,
  required String? etag,
  UpdateEpicRequest Function()? epicPatch,
  UpdateIssueRequest Function()? issuePatch,
}) async {
  if (etag == null || etag.isEmpty) return _PatchOutcome.failed;
  final backlog = getIt<BacklogRepository>();
  switch (kind) {
    case EntityKind.epic:
      if (epicPatch == null) return _PatchOutcome.failed;
      final res = await backlog.updateEpic(
        projectId,
        entityId,
        body: epicPatch(),
        etag: etag,
      );
      return _outcomeOf(res.isOk, res.failureOrNull);
    case EntityKind.issue:
      if (issuePatch == null) return _PatchOutcome.failed;
      final res = await backlog.updateIssue(
        projectId,
        entityId,
        body: issuePatch(),
        etag: etag,
      );
      return _outcomeOf(res.isOk, res.failureOrNull);
  }
}

_PatchOutcome _outcomeOf(bool ok, AppFailure? failure) {
  if (ok) return _PatchOutcome.ok;
  return failure is ConflictFailure
      ? _PatchOutcome.conflict
      : _PatchOutcome.failed;
}

/// Runs a field PATCH and reports the result to the user.
///
/// Returns true only on success. On a conflict it leaves the typed value alone
/// and offers a reload, rather than silently dropping the edit.
/// Everything [_patchAndReport] needs from the widget tree, captured up front
/// so callers can await a picker first without holding a `BuildContext`
/// across the gap.
typedef _Reporter = ({ScaffoldMessengerState messenger, AppLocalizations t});

_Reporter _reporterOf(BuildContext context) => (
  messenger: ScaffoldMessenger.of(context),
  t: AppLocalizations.of(context),
);

Future<bool> _patchAndReport(
  _Reporter reporter, {
  required EntityKind kind,
  required String projectId,
  required String entityId,
  required String? etag,
  required VoidCallback onChanged,
  UpdateEpicRequest Function()? epicPatch,
  UpdateIssueRequest Function()? issuePatch,
}) async {
  final messenger = reporter.messenger;
  final t = reporter.t;
  final outcome = await _patchEntityKind(
    kind: kind,
    projectId: projectId,
    entityId: entityId,
    etag: etag,
    epicPatch: epicPatch,
    issuePatch: issuePatch,
  );
  switch (outcome) {
    case _PatchOutcome.ok:
      onChanged();
      return true;
    case _PatchOutcome.conflict:
      messenger.showSnackBar(
        SnackBar(
          content: Text(t.entityChangedElsewhere),
          duration: const Duration(seconds: 6),
          action: SnackBarAction(label: t.actionReload, onPressed: onChanged),
        ),
      );
      return false;
    case _PatchOutcome.failed:
      messenger.showSnackBar(SnackBar(content: Text(t.entitySaveFailed)));
      return false;
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
    this.markdown = false,
    this.markdownTitle = '',
    this.members = const {},
    this.onUploadImage,
  });

  final String value;
  final bool canEdit;
  final Future<bool> Function(String value) onSave;
  final String? placeholder;

  /// Builds the read-only view. Receives a callback that switches the field
  /// into edit mode, so the display can offer its own edit affordance
  /// alongside whatever else it renders.
  final Widget Function(BuildContext context, VoidCallback beginEdit)?
  displayBuilder;
  final TextStyle? displayStyle;
  final bool multiline;

  /// Swaps the bare TextField for the full markdown editor (toolbar, preview,
  /// mentions, image paste) and offers the expanded full-window mode.
  final bool markdown;
  final String markdownTitle;
  final Map<String, UserRef> members;
  final ImageUploader? onUploadImage;

  @override
  State<_InlineTextEditor> createState() => _InlineTextEditorState();
}

class _InlineTextEditorState extends State<_InlineTextEditor> {
  late TextEditingController _ctrl;
  bool _editing = false;

  void _beginEdit() {
    if (widget.canEdit && !_editing) setState(() => _editing = true);
  }

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

  /// Hands the current text to the expanded editor and saves what comes back.
  Future<void> _openExpanded() async {
    final next = await showExpandedMarkdownEditor(
      context,
      title: widget.markdownTitle,
      initialValue: _ctrl.text,
      members: widget.members,
      onUploadImage: widget.onUploadImage,
    );
    if (next == null || !mounted) return;
    _ctrl.text = next;
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = AppLocalizations.of(context);
    if (_editing) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.markdown)
            MarkdownEditor(
              controller: _ctrl,
              members: widget.members,
              onUploadImage: widget.onUploadImage,
              autofocus: true,
              onSubmitShortcut: _saving ? null : _save,
            )
          else
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
              if (widget.markdown) ...[
                // Editing markdown in a 420px panel is miserable; this opens
                // a full-window editor with a side-by-side preview.
                TextButton.icon(
                  icon: const Icon(Icons.open_in_full, size: 16),
                  onPressed: _saving ? null : () => unawaited(_openExpanded()),
                  label: Text(t.editorExpand),
                ),
                const Spacer(),
              ],
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
        ? (widget.displayBuilder?.call(context, _beginEdit) ??
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

/// Renders a click-to-edit cell's current value.
///
/// Unset values stay plain text. A [sizeItem] renders the purpose-built
/// [SizeBadge] (scaled by its ordinal); anything else carrying a colour
/// becomes a tinted [StatusPill], so status / issue type / priority / size
/// read as one consistent badge column. Items with no colour configured fall
/// back to plain text.
Widget _tintedValue(
  String text,
  String neutralText,
  String? colorHex,
  TaxonomyItem? sizeItem,
  TextStyle? style,
) {
  if (text.isEmpty || text == '—' || text == neutralText) {
    return Text(text, style: style, overflow: TextOverflow.ellipsis);
  }
  if (sizeItem != null) {
    return Align(
      alignment: Alignment.centerLeft,
      child: SizeBadge(item: sizeItem),
    );
  }
  if (colorHex == null || colorHex.isEmpty) {
    return Text(text, style: style, overflow: TextOverflow.ellipsis);
  }
  // Same tinted-pill look as the board card / issues list release badge.
  return Align(
    alignment: Alignment.centerLeft,
    child: StatusPill(label: text, colorHex: colorHex, dense: true),
  );
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

/// The "Components & versions" panel.
///
/// A change can ship in a different version of each component it touches, so
/// the version belongs to the (issue, component) pair rather than to the issue
/// as a whole. The block therefore pairs the component picker with one version
/// dropdown per chosen component.
///
/// Each dropdown offers only versions of releases that component actually
/// ships in, which is what makes the choice meaningful — and why the
/// candidates are fetched per component rather than once for the union.
class _ComponentVersionsTable extends StatefulWidget {
  const _ComponentVersionsTable({
    required this.data,
    required this.entityId,
    required this.projectId,
    required this.onChanged,
  });

  final _PageData data;
  final String entityId;
  final String projectId;
  final VoidCallback onChanged;

  @override
  State<_ComponentVersionsTable> createState() =>
      _ComponentVersionsTableState();
}

class _ComponentVersionsTableState extends State<_ComponentVersionsTable> {
  /// Candidate versions per component id, populated on demand and kept for
  /// the life of the panel — the links behind them rarely change while a
  /// single issue is open.
  final Map<String, List<ReleaseVersionRef>> _candidates = {};
  final Set<String> _loading = {};
  bool _saving = false;

  Issue? get _issue {
    final e = widget.data.entity;
    return e is _IssueRec ? e.issue : null;
  }

  @override
  void initState() {
    super.initState();
    _ensureCandidates();
  }

  @override
  void didUpdateWidget(_ComponentVersionsTable old) {
    super.didUpdateWidget(old);
    _ensureCandidates();
  }

  void _ensureCandidates() {
    for (final id in _issue?.components ?? const <String>[]) {
      if (_candidates.containsKey(id) || _loading.contains(id)) continue;
      _loading.add(id);
      unawaited(_fetch(id));
    }
  }

  Future<void> _fetch(String componentId) async {
    final res = await getIt<CatalogRepository>().versionsForComponents(
      widget.projectId,
      [componentId],
    );
    if (!mounted) return;
    setState(() {
      _loading.remove(componentId);
      _candidates[componentId] = res.valueOrNull ?? const [];
    });
  }

  Future<void> _save(
    List<ComponentVersion> next, {
    List<String>? components,
  }) async {
    final issue = _issue;
    if (issue == null || _saving) return;
    setState(() => _saving = true);
    final res = await getIt<BacklogRepository>().updateIssue(
      widget.projectId,
      widget.entityId,
      body: UpdateIssueRequest(
        components: components,
        componentVersions: next,
      ),
      etag: issue.etag ?? '',
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (res.isOk) {
      widget.onChanged();
      return;
    }
    final t = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(res.failureOrNull?.serverMessage ?? t.errUnknown),
      ),
    );
  }

  /// Replace the component set, dropping any version whose component went
  /// away so the request never contradicts itself.
  Future<void> _setComponents(List<String> next) async {
    final issue = _issue;
    if (issue == null) return;
    final kept = [
      for (final cv in issue.componentVersions)
        if (next.contains(cv.componentId)) cv,
    ];
    await _save(kept, components: next);
  }

  Future<void> _setVersion(String componentId, String? versionId) async {
    final issue = _issue;
    if (issue == null) return;
    final next = [
      for (final cv in issue.componentVersions)
        if (cv.componentId != componentId) cv,
      if (versionId != null)
        ComponentVersion(
          componentId: componentId,
          releaseVersionId: versionId,
        ),
    ];
    await _save(next);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final issue = _issue;
    if (issue == null) return const SizedBox.shrink();

    final canEdit = context.select<ProjectDetailCubit, bool>((c) {
      final s = c.state;
      return s is ProjectDetailLoaded && s.has(Permission.issueModify);
    });
    final all = widget.data.componentsById.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final chosen =
        issue.components
            .map((id) => widget.data.componentsById[id])
            .whereType<Component>()
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _kvRowWith(
          context,
          t.detailFieldComponents,
          _MultiSelectCell(
            displayText: componentListLabel(
              issue.components,
              widget.data.componentsById,
            ),
            candidates: [
              for (final c in all) _MultiCandidate(id: c.id, label: c.name),
            ],
            selectedIds: issue.components,
            title: t.detailFieldComponents,
            emptyLabel: '—',
            canEdit: canEdit && !_saving,
            onSaved: (next) async {
              await _setComponents(next);
              return true;
            },
          ),
        ),
        if (chosen.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              t.detailNoComponentsYet,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          )
        else ...[
          const SizedBox(height: 12),
          const Divider(height: 1),
          for (final c in chosen)
            _ComponentVersionRow(
              component: c,
              versionId: issue.versionFor(c.id),
              candidates: _candidates[c.id],
              loading: _loading.contains(c.id),
              canEdit: canEdit && !_saving,
              onPicked: (v) => unawaited(_setVersion(c.id, v)),
            ),
        ],
      ],
    );
  }
}

/// One row of the versions table: the component on the left, the version it
/// ships the fix in on the right.
class _ComponentVersionRow extends StatelessWidget {
  const _ComponentVersionRow({
    required this.component,
    required this.versionId,
    required this.candidates,
    required this.loading,
    required this.canEdit,
    required this.onPicked,
  });

  final Component component;
  final String? versionId;

  /// Null until the component's candidate versions have been fetched.
  final List<ReleaseVersionRef>? candidates;
  final bool loading;
  final bool canEdit;
  final void Function(String? versionId) onPicked;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final options = candidates ?? const <ReleaseVersionRef>[];
    // A component nobody linked a release to has nothing to offer, which is a
    // configuration gap rather than an error — say which one it is.
    final unlinked = !loading && candidates != null && options.isEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Row(
              children: [
                _ComponentDot(hex: component.color),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    component.name,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 200,
            child: loading
                ? const Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : unlinked
                ? Tooltip(
                    message: t.detailComponentNoReleaseHint,
                    child: Text(
                      t.detailComponentNoRelease,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  )
                : DropdownButtonFormField<String?>(
                    initialValue: options.any((o) => o.id == versionId)
                        ? versionId
                        : null,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                    ),
                    items: [
                      DropdownMenuItem<String?>(child: Text(t.statusValueNone)),
                      for (final v in options)
                        DropdownMenuItem<String?>(
                          value: v.id,
                          child: Text('${v.releaseName} · ${v.version}'),
                        ),
                    ],
                    onChanged: canEdit ? onPicked : null,
                  ),
          ),
        ],
      ),
    );
  }
}

/// Comma-joined component names, or an em dash when there are none.
String componentListLabel(List<String> ids, Map<String, Component> by) =>
    ids.isEmpty ? '—' : ids.map((id) => by[id]?.name ?? id).join(', ');

/// A small tinted dot identifying a component in the versions table.
class _ComponentDot extends StatelessWidget {
  const _ComponentDot({required this.hex});
  final String hex;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parsed = _parseHexColor(hex);
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: parsed ?? theme.colorScheme.outlineVariant,
        shape: BoxShape.circle,
      ),
    );
  }
}

/// `#rrggbb` to a [Color]; null when unset or malformed.
Color? _parseHexColor(String hex) {
  final raw = hex.replaceFirst('#', '').trim();
  if (raw.length != 6) return null;
  final value = int.tryParse(raw, radix: 16);
  return value == null ? null : Color(0xFF000000 | value);
}

/// Everything an issue or epic can have done to it, in one menu.
///
/// Some of these also exist elsewhere on the page — the copy-link icon, the
/// comment button, the panels further down. They are repeated here
/// deliberately: the menu is the one place that answers "what can I do with
/// this?", and splitting the answer across the page is what made deleting an
/// issue impossible to find.
class _EntityActionsMenu extends StatelessWidget {
  const _EntityActionsMenu({
    required this.data,
    required this.kind,
    required this.entityId,
    required this.projectId,
    required this.onChanged,
    required this.activityAnchor,
  });

  final _PageData data;
  final EntityKind kind;
  final String entityId;
  final String projectId;
  final VoidCallback onChanged;
  final GlobalKey activityAnchor;

  bool get _isIssue => kind == EntityKind.issue;
  Issue? get _issue {
    final e = data.entity;
    return e is _IssueRec ? e.issue : null;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final perms = context.select<ProjectDetailCubit, (bool, bool, bool)>((c) {
      final s = c.state;
      if (s is! ProjectDetailLoaded) return (false, false, false);
      return (
        s.has(_modifyPermissionFor(kind)),
        s.has(_isIssue ? Permission.issueDelete : Permission.epicDelete),
        s.has(Permission.issueCreate),
      );
    });
    final (canEdit, canDelete, canCreate) = perms;

    return MenuAnchor(
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.chat_bubble_outline, size: 18),
          onPressed: () => _scrollTo(activityAnchor),
          child: Text(t.entityActionComment),
        ),
        if (_isIssue)
          MenuItemButton(
            leadingIcon: const Icon(Icons.schedule_outlined, size: 18),
            onPressed: () => _PanelAnchors.reveal('log_time'),
            child: Text(t.ttLogTime),
          ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.attach_file_outlined, size: 18),
          onPressed: () => _PanelAnchors.reveal('attachments'),
          child: Text(t.panelAttachments),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.link_outlined, size: 18),
          onPressed: () => _PanelAnchors.reveal('links'),
          child: Text(t.panelLinks),
        ),
        const Divider(height: 8),
        if (_isIssue && canEdit)
          MenuItemButton(
            leadingIcon: const Icon(Icons.drive_file_move_outlined, size: 18),
            onPressed: () => unawaited(_moveToEpic(context)),
            child: Text(t.entityActionMoveToEpic),
          ),
        if (_isIssue && canCreate)
          MenuItemButton(
            leadingIcon: const Icon(Icons.copy_all_outlined, size: 18),
            onPressed: () => unawaited(_clone(context)),
            child: Text(t.entityActionClone),
          ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.link, size: 18),
          onPressed: () => unawaited(_copyLink(context)),
          child: Text(t.copyLink),
        ),
        if (canDelete) ...[
          const Divider(height: 8),
          MenuItemButton(
            leadingIcon: Icon(
              Icons.delete_outline,
              size: 18,
              color: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => unawaited(_delete(context)),
            child: Text(
              t.actionDelete,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ],
      builder: (context, controller, _) => FilledButton.tonalIcon(
        icon: const Icon(Icons.more_horiz, size: 18),
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        label: Text(t.entityActionsMenu),
      ),
    );
  }

  void _scrollTo(GlobalKey key) {
    final target = key.currentContext;
    if (target == null) return;
    unawaited(
      Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        alignment: 0.1,
      ),
    );
  }

  Future<void> _copyLink(BuildContext context) async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final origin = kIsWeb ? Uri.base.origin : getIt<ApiConfig>().baseUrl;
    final pfx = data.project.issuePrefix;
    final key = kind == EntityKind.epic
        ? epicKeyLabel(pfx, data.entity.reference)
        : issueKeyLabel(pfx, data.entity.reference);
    final route = Routes.entityByKeyFor(
      projectId: projectId,
      issuePrefix: pfx,
      kind: kind,
      key: key,
    );
    await Clipboard.setData(ClipboardData(text: '$origin$route'));
    messenger.showSnackBar(SnackBar(content: Text(t.copiedToClipboard)));
  }

  /// Re-point the issue at a different epic. The milestone follows the epic by
  /// database trigger, so this is the only move an issue needs.
  Future<void> _moveToEpic(BuildContext context) async {
    final t = AppLocalizations.of(context);
    final issue = _issue;
    if (issue == null) return;
    final pfx = data.project.issuePrefix;
    final epics = data.epicsById.values.toList()
      ..sort((a, b) => a.reference.compareTo(b.reference));

    final picked = await showDialog<_EpicChoice>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(t.entityActionMoveToEpic),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(const _EpicChoice(null)),
            child: Text(t.backlogNoEpic),
          ),
          for (final e in epics)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(_EpicChoice(e.id)),
              child: Text(
                '${epicKeyLabel(pfx, e.reference)} · ${e.subject}',
              ),
            ),
        ],
      ),
    );
    if (picked == null || !context.mounted) return;
    await _patchAndReport(
      _reporterOf(context),
      kind: kind,
      projectId: projectId,
      entityId: entityId,
      etag: issue.etag,
      onChanged: onChanged,
      epicPatch: () => const UpdateEpicRequest(),
      issuePatch: () => UpdateIssueRequest(epicId: picked.id),
    );
  }

  /// Copy the issue into a new one. Done client-side from the loaded entity —
  /// there is no clone endpoint, and everything a clone needs is already here.
  /// Deliberately NOT copied: status, resolution and time logs, which belong
  /// to the original's history rather than to a fresh piece of work.
  Future<void> _clone(BuildContext context) async {
    final t = AppLocalizations.of(context);
    final issue = _issue;
    if (issue == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final res = await getIt<BacklogRepository>().createIssue(
      projectId,
      CreateIssueRequest(
        subject: t.entityCloneSubject(issue.subject),
        description: issue.description,
        typeId: issue.typeId,
        priorityId: issue.priorityId,
        sizeId: issue.sizeId,
        epicId: issue.epicId,
        parentId: issue.parentId,
        assignedTo: issue.assignedTo,
        category: issue.category,
        customerIds: issue.customerIds,
        startDate: issue.startDate,
        dueDate: issue.dueDate,
        labels: issue.labels,
        components: issue.components,
        componentVersions: issue.componentVersions,
      ),
    );
    final created = res.valueOrNull;
    if (created == null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(res.failureOrNull?.serverMessage ?? t.errUnknown),
        ),
      );
      return;
    }
    messenger.showSnackBar(SnackBar(content: Text(t.entityCloneCreated)));
    router.go(
      Routes.entityDetailFor(projectId, EntityKind.issue, created.id),
    );
  }

  Future<void> _delete(BuildContext context) async {
    final t = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final subject = data.entity.subject;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.entityDeleteTitle),
        content: Text(t.entityDeleteConfirm(subject)),
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
    // Re-read for a current ETag: the page may have been open a while.
    final etag = kind == EntityKind.issue
        ? (await backlog.getIssue(projectId, entityId)).valueOrNull?.etag
        : (await backlog.getEpic(projectId, entityId)).valueOrNull?.etag;
    if (etag == null) return;
    final res = kind == EntityKind.issue
        ? await backlog.deleteIssue(projectId, entityId, etag: etag)
        : await backlog.deleteEpic(projectId, entityId, etag: etag);
    if (!res.isOk) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(res.failureOrNull?.serverMessage ?? t.errUnknown),
        ),
      );
      return;
    }
    unawaited(navigator.maybePop());
  }
}

/// Wrapper so "no epic" is distinguishable from "cancelled" in the dialog's
/// result, which a bare `String?` could not express.
class _EpicChoice {
  const _EpicChoice(this.id);
  final String? id;
}
