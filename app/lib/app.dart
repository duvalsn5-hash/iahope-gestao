import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/app_config.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/session_controller.dart';

class IaHopeApp extends ConsumerWidget {
  const IaHopeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    // White-Label: o tema acompanha a cor da marca da empresa logada
    final seed = AppTheme.parseHex(ref.watch(sessionControllerProvider.select((s) => s?.tenant.primaryColor)));

    return MaterialApp.router(
      title: '${AppConfig.appName} — ${AppConfig.credits}',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(seed: seed),
      darkTheme: AppTheme.build(seed: seed, brightness: Brightness.dark),
      themeMode: ThemeMode.light,
      routerConfig: router,
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}
