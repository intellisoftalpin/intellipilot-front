import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/features/projects/domain/permission.dart';
import 'package:intellipilot/features/projects/presentation/cubits/project_detail_cubit.dart';
import 'package:intellipilot/features/projects/presentation/widgets/request_access_card.dart';

/// Renders [child] when the current user has [permission] in the
/// surrounding [ProjectDetailCubit]'s project. Otherwise hides the child
/// (default) or shows [orElse] (e.g. a "request access" CTA).
///
/// Set [showRequestAccess] when this gate sits at page level: instead of
/// silently hiding the body, a [RequestAccessCard] surfaces what's
/// missing so the user knows whom to ask.
class PermissionGate extends StatelessWidget {
  const PermissionGate({
    required this.permission,
    required this.child,
    this.orElse,
    this.showRequestAccess = false,
    super.key,
  });

  final Permission permission;
  final Widget child;
  final Widget? orElse;
  final bool showRequestAccess;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProjectDetailCubit, ProjectDetailState>(
      builder: (context, state) {
        if (state is! ProjectDetailLoaded) {
          return orElse ?? const SizedBox.shrink();
        }
        if (!state.has(permission)) {
          if (orElse != null) return orElse!;
          if (showRequestAccess) {
            return RequestAccessCard(missing: permission);
          }
          return const SizedBox.shrink();
        }
        return child;
      },
    );
  }
}
