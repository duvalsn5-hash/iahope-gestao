import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/about/presentation/about_screen.dart';
import '../../features/auth/domain/session.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/session_controller.dart';
import '../../features/company/presentation/company_settings_screen.dart';
import '../../features/fashion/presentation/fashion_screen.dart';
import '../../features/finance/presentation/finance_screen.dart';
import '../../features/master_admin/presentation/master_admin_dashboard.dart';
import '../../features/partners/presentation/partners_screen.dart';
import '../../features/pos/presentation/pos_screen.dart';
import '../../features/printshop/presentation/printshop_screen.dart';
import '../../features/productivity/presentation/productivity_dashboard.dart';
import '../../features/products/presentation/products_screen.dart';
import '../../features/purchases/presentation/purchases_screen.dart';
import '../../features/users/presentation/users_screen.dart';
import '../../features/workshop/presentation/workshop_screen.dart';
import '../widgets/app_shell.dart';

class Routes {
  static const login = '/login';
  static const masterAdmin = '/master';
  static const pos = '/pdv';
  static const productivity = '/produtividade';
  static const products = '/produtos';
  static const partners = '/clientes-fornecedores';
  static const finance = '/financeiro';
  static const purchases = '/compras';
  static const workshop = '/oficina';
  static const fashion = '/loja';
  static const printshop = '/estamparia';
  static const users = '/usuarios';
  static const company = '/empresa';
  static const about = '/sobre';
}

/// Tela inicial conforme perfil e módulos contratados.
String homeFor(Session s) {
  if (s.isSuperAdmin) return Routes.masterAdmin;
  if (s.user.role == UserRole.caixa && s.canSell) return Routes.pos;
  if (s.user.role == UserRole.mecanico && s.canUseWorkshop) return Routes.workshop;
  if (s.user.role == UserRole.operador && s.canSeeProductivity) return Routes.productivity;
  if (s.user.role == UserRole.operador && s.canUsePrintshop) return Routes.printshop;
  if (s.canUseWorkshop && !s.canSell) return Routes.workshop;
  if (s.canSell) return Routes.pos;
  if (s.canSeeProductivity) return Routes.productivity;
  return Routes.products;
}

/// Regras de acesso por rota (o servidor também valida — esta é só a camada de UI).
bool canAccess(Session s, String path) => switch (path) {
      Routes.masterAdmin => s.isSuperAdmin,
      Routes.pos => s.canSell,
      Routes.productivity => s.canSeeProductivity,
      Routes.finance => s.canUseFinance,
      Routes.purchases => s.canUsePurchases,
      Routes.partners => s.canSeePartners,
      Routes.products => !s.isSuperAdmin && s.user.role != UserRole.mecanico,
      Routes.workshop => s.canUseWorkshop,
      Routes.fashion => s.canUseFashion,
      Routes.printshop => s.canUsePrintshop,
      Routes.users => s.canManageUsers,
      Routes.company => s.canManageCompany,
      _ => true,
    };

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(sessionControllerProvider, (_, __) => refresh.value++);
  ref.onDispose(refresh.dispose);

  GoRoute page(String path, Widget child) =>
      GoRoute(path: path, pageBuilder: (_, __) => NoTransitionPage(child: child));

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
          page(Routes.masterAdmin, const MasterAdminDashboard()),
          page(Routes.pos, const PosScreen()),
          page(Routes.productivity, const ProductivityDashboard()),
          page(Routes.products, const ProductsScreen()),
          page(Routes.partners, const PartnersScreen()),
          page(Routes.finance, const FinanceScreen()),
          page(Routes.purchases, const PurchasesScreen()),
          page(Routes.workshop, const WorkshopScreen()),
          page(Routes.fashion, const FashionScreen()),
          page(Routes.printshop, const PrintshopScreen()),
          page(Routes.users, const UsersScreen()),
          page(Routes.company, const CompanySettingsScreen()),
          page(Routes.about, const AboutScreen()),
        ],
      ),
    ],
  );
});
