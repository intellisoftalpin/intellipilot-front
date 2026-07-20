import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/features/catalog/domain/catalog_repository.dart';
import 'package:intellipilot/features/projects/domain/projects_repository.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

final _uuidRe = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// Whether a path segment is a raw entity id (legacy deep link) rather than
/// a short prefix/key.
bool looksLikeUuid(String s) => _uuidRe.hasMatch(s);

/// Resolves short deep-link segments (project prefix, board key) to entity
/// ids and back, with a session-lifetime cache so repeated navigations don't
/// refetch. Registered as a lazy singleton.
class ShortLinkResolver {
  final Map<String, String> _projectIdByPrefix = {}; // lower prefix → id
  final Map<String, String> _prefixById = {}; // id → lower prefix
  final Map<String, String> _boardIdByRef = {}; // "pid/lower key" → id
  final Map<String, String> _boardKeyById = {}; // "pid/id" → key

  /// (projectId, lowercase canonical prefix) for a UUID or prefix segment;
  /// null when it resolves to nothing the caller may see.
  Future<(String, String)?> project(String ref) async {
    final raw = ref.trim();
    if (looksLikeUuid(raw)) {
      final cached = _prefixById[raw];
      if (cached != null) return (raw, cached);
      final res = await getIt<ProjectsRepository>().getProject(raw);
      final p = res.valueOrNull;
      if (p == null) return null;
      return _remember(p.id, p.issuePrefix);
    }
    final lower = raw.toLowerCase();
    final cached = _projectIdByPrefix[lower];
    if (cached != null) return (cached, _prefixById[cached] ?? lower);
    final res = await getIt<ProjectsRepository>().getProjectByPrefix(raw);
    final p = res.valueOrNull;
    if (p == null) return null;
    return _remember(p.id, p.issuePrefix);
  }

  (String, String) _remember(String id, String prefix) {
    final lower = prefix.toLowerCase();
    if (lower.isNotEmpty) {
      _projectIdByPrefix[lower] = id;
      _prefixById[id] = lower;
    }
    return (id, lower);
  }

  /// (boardId, canonical key) for a UUID or key segment within a project.
  /// The backend board endpoint accepts either form, so one call resolves
  /// both directions (renamed-away keys included).
  Future<(String, String)?> board(String projectId, String ref) async {
    final raw = ref.trim();
    final cacheKey = '$projectId/${raw.toLowerCase()}';
    final byRef = _boardIdByRef[cacheKey];
    if (byRef != null) {
      final key = _boardKeyById['$projectId/$byRef'];
      if (key != null) return (byRef, key);
    }
    final res = await getIt<CatalogRepository>().getBoard(projectId, raw);
    final b = res.valueOrNull;
    if (b == null) return null;
    _boardIdByRef['$projectId/${b.key.toLowerCase()}'] = b.id;
    _boardIdByRef['$projectId/${b.id}'] = b.id;
    // The queried (possibly historic) key also maps to this board.
    _boardIdByRef[cacheKey] = b.id;
    _boardKeyById['$projectId/${b.id}'] = b.key;
    return (b.id, b.key);
  }
}

/// Route wrapper for `/projects/:id/...` paths: accepts a UUID (legacy) or a
/// project prefix in any letter-case, resolves it, then builds the page with
/// the real project id — and ALWAYS rewrites the address bar to the
/// canonical short URL (lowercase prefix, and the board key when
/// [boardRef] is given), so users end up seeing the short link no matter
/// which form they entered.
class ShortLinkGate extends StatefulWidget {
  const ShortLinkGate({
    required this.state,
    required this.builder,
    this.boardRef,
    this.lowercaseTail = false,
    super.key,
  });

  /// The router state of the matched route (provides the raw segments and
  /// the full current location incl. query).
  final GoRouterState state;

  /// Builds the page once refs are resolved. `boardId` is null unless
  /// [boardRef] was provided.
  final Widget Function(BuildContext context, String projectId, String? boardId)
  builder;

  /// The raw `:boardId` segment to resolve alongside the project.
  final String? boardRef;

  /// Lowercase the segment after the section name (issue/epic keys such as
  /// `IP-42`) when canonicalising, e.g. `/projects/ip/issues/ip-42`.
  final bool lowercaseTail;

  @override
  State<ShortLinkGate> createState() => _ShortLinkGateState();
}

class _ShortLinkGateState extends State<ShortLinkGate> {
  String? _projectId;
  String? _boardId;
  bool _failed = false;

  /// Guards against an older in-flight resolve overwriting a newer one.
  int _generation = 0;

  String _projectRefOf(GoRouterState s) =>
      s.pathParameters['id'] ?? s.pathParameters['projectId'] ?? '';

  @override
  void initState() {
    super.initState();
    unawaited(_resolve());
  }

  @override
  void didUpdateWidget(covariant ShortLinkGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Same-route navigations (board → board, project → project) update this
    // widget in place — go_router keys pages per route, not per parameters —
    // so initState never re-runs. Without this, the first resolved ids stay
    // latched and every board picked from the side menu renders the first
    // one. Re-resolve whenever a raw ref changed; the previously resolved
    // page stays on screen meanwhile (the resolver's session cache makes the
    // swap near-instant, no spinner flash).
    if (_projectRefOf(oldWidget.state) != _projectRefOf(widget.state) ||
        oldWidget.boardRef != widget.boardRef) {
      unawaited(_resolve());
    }
  }

  Future<void> _resolve() async {
    final generation = ++_generation;
    final resolver = getIt<ShortLinkResolver>();
    final projectRef = _projectRefOf(widget.state);
    final project = await resolver.project(projectRef);
    if (!mounted || generation != _generation) return;
    if (project == null) {
      setState(() => _failed = true);
      return;
    }
    final (projectId, prefixLower) = project;

    String? boardId;
    String? boardKey;
    final boardRef = widget.boardRef;
    if (boardRef != null) {
      final board = await resolver.board(projectId, boardRef);
      if (!mounted || generation != _generation) return;
      if (board == null) {
        setState(() => _failed = true);
        return;
      }
      (boardId, boardKey) = board;
    }

    setState(() {
      _projectId = projectId;
      _boardId = boardId;
      _failed = false;
    });
    _rewriteToCanonical(prefixLower, boardKey);
  }

  /// Replace the address bar with the canonical short URL when the current
  /// one differs (legacy UUID, odd casing, or a renamed-away key).
  void _rewriteToCanonical(String prefixLower, String? boardKey) {
    if (prefixLower.isEmpty) return;
    final uri = widget.state.uri;
    final segments = [...uri.pathSegments];
    // Shape: projects / <ref> / <section> / <tail...>
    if (segments.length < 2 || segments[0] != 'projects') return;
    segments[1] = prefixLower;
    if (boardKey != null && segments.length >= 4) {
      segments[3] = boardKey;
    }
    if (widget.lowercaseTail && segments.length >= 4) {
      segments[3] = segments[3].toLowerCase();
    }
    final canonical = Uri(
      pathSegments: ['', ...segments],
      query: uri.hasQuery ? uri.query : null,
    ).toString();
    final current = uri.toString();
    if (canonical == current) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // `replace` keeps history clean: back returns to the previous page,
      // not to the long form of the same page.
      context.replace(canonical);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(AppLocalizations.of(context).errUnknown)),
      );
    }
    final projectId = _projectId;
    if (projectId == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return widget.builder(context, projectId, _boardId);
  }
}
