import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/app/branding/branding_cubit.dart';
import 'package:intellipilot/app/di/injection.dart';

/// The app logo, honouring the white-label override. Renders the admin-set
/// custom icon when one is configured, falling back to the bundled asset both
/// when no override exists and when the network image fails to load.
///
/// Reads the branding singleton from the service locator (not the widget tree)
/// so it works on any route, mirroring how the shell resolves session state.
class BrandLogo extends StatelessWidget {
  const BrandLogo({required this.size, super.key, this.borderRadius = 6});

  final double size;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final fallback = Image.asset(
      'assets/images/app-logo.png',
      width: size,
      height: size,
      fit: BoxFit.cover,
    );
    return BlocBuilder<BrandingCubit, Branding>(
      bloc: getIt<BrandingCubit>(),
      builder: (context, branding) => ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: branding.iconUrl == null
            ? fallback
            : Image.network(
                branding.iconUrl!,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
              ),
      ),
    );
  }
}
