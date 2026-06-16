import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/app/branding/branding_cubit.dart';

/// The app logo, honouring the white-label override. Renders the admin-set
/// custom icon when one is configured, falling back to the bundled asset both
/// when no override exists and when the network image fails to load.
class BrandLogo extends StatelessWidget {
  const BrandLogo({required this.size, super.key, this.borderRadius = 6});

  final double size;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final iconUrl = context.watch<BrandingCubit>().state.iconUrl;
    final fallback = Image.asset(
      'assets/images/app-logo.png',
      width: size,
      height: size,
      fit: BoxFit.cover,
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: iconUrl == null
          ? fallback
          : Image.network(
              iconUrl,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => fallback,
            ),
    );
  }
}
