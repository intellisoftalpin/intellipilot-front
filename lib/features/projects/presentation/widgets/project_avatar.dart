import 'package:flutter/material.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/session/session_bloc.dart';
import 'package:intellipilot/core/network/api_config.dart';
import 'package:intellipilot/features/projects/data/dtos/project_dtos.dart';

/// Circular project marker: the uploaded icon image when set, otherwise the
/// issue-key prefix initials on the project's color.
class ProjectAvatar extends StatelessWidget {
  const ProjectAvatar({required this.project, this.size = 40, super.key});

  final Project project;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (project.hasIcon) {
      final base = getIt<ApiConfig>().baseUrl;
      final token = getIt<SessionBloc>().currentAccessToken;
      final v = Uri.encodeQueryComponent(
        project.iconImageUpdatedAt?.toIso8601String() ?? '',
      );
      final url = '$base/api/v1/projects/${project.id}/icon?v=$v';
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
    final color =
        _parseColor(project.color) ?? Theme.of(context).colorScheme.primary;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Text(
        _initialsText(),
        style: TextStyle(
          color: _onColor(color),
          fontWeight: FontWeight.w700,
          fontSize: size * 0.38,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  String _initialsText() {
    final p = project.issuePrefix.trim();
    if (p.isNotEmpty) return p.length <= 3 ? p : p.substring(0, 3);
    final n = project.name.trim();
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
