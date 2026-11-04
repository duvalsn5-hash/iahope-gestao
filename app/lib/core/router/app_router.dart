import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/about/presentation/about_screen.dart';
import '../../features/auth/domain/session.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/session_controller.dart';
import '../../features/company/presentation/company_settings_screen.dart';
import '../../features/master_admin/presentation/master_admin_dashboard.dart';
import '../../features/pos/presentation/pos_screen.dart';
import '../../features/productivity/presentation/productivity_dashboard.dart';
import '../widgets/app_shell.dart';

class Routes {
  static const login = '/login';
  static const masterAdmin = '/master';
  static const pos = '/pdv';
  static const productivity = '/produtividade';
  static const company = '/empresa';
  static const about = '/sobre';
}

String homeFor(Session s) {
  if (s.isSuperAdmin) return Routes.masterAdmin;
  if (s.user.role == UserRole.caixa) return Routes.pos;
  return Routes.productivity;
}

/// Regras de acesso por rota (o servidor também valida — esta é só a camada de UI).
bool canAccess(Session s, String path) => switch (path) {
      Routes.masterAdmin => s.isSuperAdmin,
      Routes.pos => s.canSell,
      Routes.company => s.canManageCompany,
      _ => true,
    };

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(sessionControllerProvider, (_, __) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: Routes.login,
    refreshListenable: refresh,
    redirect: (context, state) {
      final session = ref.read(sessionControllerProvider);
      final atLogin = state.matchedLocation == Routes.login;
      if (session == null) return atLogin ? null : Routes.login;
      if (atLogin) return homeFor(session);
      if (!canAccess(session, state.matchedLocation)) return homeFor(session);
      return null;
    },
    routes: [
      GoRoute(path: Routes.login, builder: (_, __) => const LoginScreen()),
      ShellRoute(
        builder: (_, state, child) => AppShell(location: state.matchedLocation, child: child),
        routes: [
          GoRoute(path: Routes.masterAdmin, pageBuilder: (_, __) => const NoTransitionPage(child: MasterAdminDashboard())),
          GoRoute(path: Routes.pos, pageBuilder: (_, __) => const NoTransitionPage(child: PosScreen())),
          GoRoute(path: Routes.productivity, pageBuilder: (_, __) => const NoTransitionPage(child: ProductivityDashboard())),
          GoRoute(path: Routes.company, pageBuilder: (_, __) => const NoTransitionPage(child: CompanySettingsScreen())),
          GoRoute(path: Routes.about, pageBuilder: (_, __) => const NoTransitionPage(child: AboutScreen())),
        ],
      ),
    ],
  );
});
