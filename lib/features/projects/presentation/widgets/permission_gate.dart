import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/features/projects/domain/permission.dart';
import 'package:intellipilot/features/projects/presentation/cubits/project_detail_cubit.dart';

/// Renders [child] when the current user has [permission] in the
/// surrounding [ProjectDetailCubit]'s project. Otherwise either hides the
/// child entirely (default) or shows [orElse] (e.g. a "request access" CTA).
class PermissionGate extends StatelessWidget {
  const PermissionGate({
    required this.permission,
    required this.child,
    this.orElse,
    super.key,
  });

  final Permission permission;
  final Widget child;
  final Widget? orElse;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProjectDetailCubit, ProjectDetailState>(
      builder: (context, state) {
        if (state is! ProjectDetailLoaded) {
          return orElse ?? const SizedBox.shrink();
        }
        if (!state.has(permission)) {
          return orElse ?? const SizedBox.shrink();
        }
        return child;
      },
    );
  }
}
