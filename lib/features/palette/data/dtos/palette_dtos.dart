import 'package:intellipilot/features/activity/data/dtos/activity_dtos.dart';

/// One row in the command palette. Sealed: each subtype renders/navigates
/// differently.
sealed class PaletteResult {
  const PaletteResult({required this.label, required this.subtitle});
  final String label;
  final String subtitle;
}

class ProjectResult extends PaletteResult {
  const ProjectResult({
    required this.projectId,
    required super.label,
    required super.subtitle,
  });
  final String projectId;
}

class WikiResult extends PaletteResult {
  const WikiResult({
    required this.projectId,
    required this.pageId,
    required super.label,
    required super.subtitle,
  });
  final String projectId;
  final String pageId;
}

class EntityResult extends PaletteResult {
  const EntityResult({
    required this.projectId,
    required this.kind,
    required this.entityId,
    required super.label,
    required super.subtitle,
  });
  final String projectId;
  final EntityKind kind;
  final String entityId;
}

class CommandResult extends PaletteResult {
  const CommandResult({
    required this.id,
    required super.label,
    required super.subtitle,
    required this.run,
  });
  final String id;
  final void Function() run;
}
