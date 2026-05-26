import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/l10n/locale_cubit.dart';
import 'package:intellipilot/app/router/app_router.dart';
import 'package:intellipilot/app/theme/app_theme.dart';
import 'package:intellipilot/app/theme/theme_cubit.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

class IntelliPilotApp extends StatefulWidget {
  const IntelliPilotApp({super.key});

  @override
  State<IntelliPilotApp> createState() => _IntelliPilotAppState();
}

class _IntelliPilotAppState extends State<IntelliPilotApp> {
  late final _router = buildRouter();

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<ThemeCubit>.value(value: getIt<ThemeCubit>()),
        BlocProvider<LocaleCubit>.value(value: getIt<LocaleCubit>()),
      ],
      child: BlocBuilder<ThemeCubit, ThemeState>(
        builder: (context, themeState) {
          return BlocBuilder<LocaleCubit, Locale?>(
            builder: (context, locale) {
              return DynamicColorBuilder(
                builder: (lightDynamic, darkDynamic) {
                  final useDynamic = themeState.useDynamic;
                  return MaterialApp.router(
                    onGenerateTitle: (ctx) => AppLocalizations.of(ctx).appTitle,
                    debugShowCheckedModeBanner: false,
                    theme: AppTheme.light(
                      seedColor: themeState.seedColor,
                      dynamicScheme: useDynamic ? lightDynamic : null,
                    ),
                    darkTheme: AppTheme.dark(
                      seedColor: themeState.seedColor,
                      dynamicScheme: useDynamic ? darkDynamic : null,
                    ),
                    themeMode: themeState.mode,
                    locale: locale,
                    localizationsDelegates:
                        AppLocalizations.localizationsDelegates,
                    supportedLocales: AppLocalizations.supportedLocales,
                    routerConfig: _router,
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
