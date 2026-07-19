import 'package:flutter/material.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/features/activity/data/dtos/activity_dtos.dart';
import 'package:intellipilot/features/activity/presentation/entity_detail_page.dart';
import 'package:intellipilot/features/backlog/data/dtos/backlog_dtos.dart';
import 'package:intellipilot/features/backlog/domain/backlog_repository.dart';

/// Full-page epic view reached by a human-readable key URL
/// (`/projects/{id}/epics/PS-E-7`). Resolves the trailing numeric ref to the
/// epic id via the project's epic list, then renders the same
/// [EntityDetailPage] used by the side sheet — the epic mirror of
/// `IssueKeyPage`.
class EpicKeyPage extends StatefulWidget {
  const EpicKeyPage({
    required this.projectId,
    required this.epicKey,
    super.key,
  });

  final String projectId;

  /// The key as it appears in the URL, e.g. `PS-E-7` (or just `7`).
  final String epicKey;

  @override
  State<EpicKeyPage> createState() => _EpicKeyPageState();
}

class _EpicKeyPageState extends State<EpicKeyPage> {
  late Future<Epic?> _future;

  @override
  void initState() {
    super.initState();
    _future = _resolve();
  }

  /// Extract the trailing numeric ref from a key like `PS-E-7` / `7`.
  int? get _ref => int.tryParse(widget.epicKey.split('-').last.trim());

  Future<Epic?> _resolve() async {
    final ref = _ref;
    if (ref == null) return null;
    final res = await getIt<BacklogRepository>().listEpics(widget.projectId);
    final epics = res.valueOrNull;
    if (epics == null) return null;
    for (final e in epics) {
      if (e.reference == ref) return e;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Epic?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final epic = snapshot.data;
        if (epic == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('Epic not found')),
          );
        }
        return EntityDetailPage(
          projectId: widget.projectId,
          kind: EntityKind.epic,
          entityId: epic.id,
        );
      },
    );
  }
}
