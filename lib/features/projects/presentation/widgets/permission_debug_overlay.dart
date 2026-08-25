import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/features/projects/domain/permission.dart';
import 'package:intellipilot/features/projects/presentation/cubits/project_detail_cubit.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// Debug-only floating panel that lists the permissions the current user
/// holds in the active project. Hidden in release builds.
class PermissionDebugOverlay extends StatefulWidget {
  const PermissionDebugOverlay({super.key});

  @override
  State<PermissionDebugOverlay> createState() => _PermissionDebugOverlayState();
}

class _PermissionDebugOverlayState extends State<PermissionDebugOverlay> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    if (kReleaseMode) return const SizedBox.shrink();
    return Positioned(
      right: 12,
      bottom: 12,
      child: Material(
        color: Colors.transparent,
        child: _open
            ? _Panel(onClose: () => setState(() => _open = false))
            : _Toggle(onOpen: () => setState(() => _open = true)),
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({required this.onOpen});
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: AppLocalizations.of(context).permOverlayTitle,
      child: FloatingActionButton.small(
        heroTag: 'perm-debug-toggle',
        onPressed: onOpen,
        child: const Icon(Icons.shield_outlined),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.onClose});
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320, maxHeight: 480),
      child: Card(
        elevation: 6,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: BlocBuilder<ProjectDetailCubit, ProjectDetailState>(
            builder: (context, state) {
              if (state is! ProjectDetailLoaded) {
                return Row(
                  children: [
                    Text(AppLocalizations.of(context).permOverlayNoProject),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      visualDensity: VisualDensity.compact,
                      onPressed: onClose,
                    ),
                  ],
                );
              }
              final held = Permission.values
                  .where(state.has)
                  .map((p) => p.wire)
                  .toList();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text(
                        AppLocalizations.of(
                          context,
                        ).permOverlayFor(state.project.name),
                        style: theme.textTheme.titleSmall,
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        visualDensity: VisualDensity.compact,
                        onPressed: onClose,
                      ),
                    ],
                  ),
                  const Divider(height: 12),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final p in held)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text(
                              p,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
