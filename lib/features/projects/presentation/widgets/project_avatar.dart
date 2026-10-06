import 'package:flutter/material.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/session/session_bloc.dart';
import 'package:intellipilot/core/network/api_config.dart';
import 'package:intellipilot/features/projects/data/dtos/project_dtos.dart';

/// Circular project marker: the uploaded icon image when set, otherwise the
/// issue-key prefix initials on the project's color.
class ProjectAvatar extends StatelessWidget {
  ProjectAvatar({required Project project, this.size = 40, super.key})
    : projectId = project.id,
      name = project.name,
      issuePrefix = project.issuePrefix,
      color = project.color,
      hasIcon = project.hasIcon,
      iconImageUpdatedAt = project.iconImageUpdatedAt;

  /// From the icon fields alone, for lists that do not carry a full
  /// [Project] — the home dashboard's projects, for one.
  const ProjectAvatar.fromParts({
    required this.projectId,
    required this.name,
    required this.issuePrefix,
    required this.color,
    required this.hasIcon,
    this.iconImageUpdatedAt,
    this.size = 40,
    super.key,
  });

  final String projectId;
  final String name;
  final String issuePrefix;
  final String color;
  final bool hasIcon;
  final DateTime? iconImageUpdatedAt;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (hasIcon) {
      final base = getIt<ApiConfig>().baseUrl;
      final token = getIt<SessionBloc>().currentAccessToken;
      final v = Uri.encodeQueryComponent(
        iconImageUpdatedAt?.toIso8601String() ?? '',
      );
      final url = '$base/api/v1/projects/$projectId/icon?v=$v';
      return ClipOval(
        child: Image.network(
          url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          headers: token == null ? null : {'Authorization': 'Bearer $token'},
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => _initials(context),
        ),
      );
    }
    return _initials(context);
  }

  Widget _initials(BuildContext context) {
    final fill = _parseColor(color) ?? Theme.of(context).colorScheme.primary;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
      child: Text(
        _initialsText(),
        style: TextStyle(
          color: _onColor(fill),
          fontWeight: FontWeight.w700,
          fontSize: size * 0.38,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  String _initialsText() {
    final p = issuePrefix.trim();
    if (p.isNotEmpty) return p.length <= 3 ? p : p.substring(0, 3);
    final n = name.trim();
    return n.isEmpty ? '?' : n.substring(0, 1).toUpperCase();
  }
}

/// The project's card color, or the theme primary when unset/invalid.
Color projectColorOrPrimary(BuildContext context, String hex) =>
    _parseColor(hex) ?? Theme.of(context).colorScheme.primary;

/// Parse a `#rrggbb` / `#aarrggbb` hex string, or null when blank/invalid.
Color? _parseColor(String hex) {
  var t = hex.trim();
  if (t.isEmpty) return null;
  if (t.startsWith('#')) t = t.substring(1);
  if (t.length == 6) t = 'ff$t';
  if (t.length != 8) return null;
  final v = int.tryParse(t, radix: 16);
  return v == null ? null : Color(v);
}

/// Black or white, whichever contrasts better with [bg].
Color _onColor(Color bg) =>
    bg.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;
