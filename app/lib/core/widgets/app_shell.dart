import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/domain/session.dart';
import '../../features/auth/presentation/session_controller.dart';
import '../router/app_router.dart';
import 'common_widgets.dart';

class _NavItem {
  const _NavItem(this.path, this.label, this.icon, this.key);
  final String path;
  final String label;
  final IconData icon;
  final LogicalKeyboardKey key;
}

/// Atalhos globais (Windows/Web). F5, F11 e F12 ficam livres para o navegador.
const _allItems = [
  _NavItem(Routes.pos, 'PDV', Icons.point_of_sale, LogicalKeyboardKey.f2),
  _NavItem(Routes.productivity, 'Produtividade', Icons.local_shipping, LogicalKeyboardKey.f3),
  _NavItem(Routes.company, 'Empresa', Icons.business, LogicalKeyboardKey.f4),
  _NavItem(Routes.masterAdmin, 'Master', Icons.admin_panel_settings, LogicalKeyboardKey.f6),
  _NavItem(Routes.about, 'Sobre / Ajuda', Icons.help_outline, LogicalKeyboardKey.f1),
];

/// Estrutura principal: cabeçalho com a logo da empresa, navegação adaptativa
/// (NavigationRail no desktop, NavigationBar no celular) e rodapé com créditos.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);
    if (session == null) return const SizedBox.shrink();

    final items = _allItems.where((i) => canAccess(session, i.path)).toList();
    final index = items.indexWhere((i) => location.startsWith(i.path)).clamp(0, items.length - 1).toInt();
    final compact = Breakpoints.isCompact(context);

    final shortcuts = <ShortcutActivator, VoidCallback>{
      for (final i in items) SingleActivator(i.key): () => context.go(i.path),
    };

    final appBar = AppBar(
      titleSpacing: 12,
      title: Row(children: [
        CompanyLogo(url: session.tenant.logoUrl, name: session.tenant.nomeFantasia, size: 36),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(session.tenant.nomeFantasia, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16)),
            Text('${session.user.fullName} · ${roleLabel(session.user.role)}',
                overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
      ]),
      actions: [
        if ((session.licenseDaysLeft ?? 99) <= 7 && !session.isSuperAdmin)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Chip(
              avatar: const Icon(Icons.warning_amber, size: 16),
              label: Text('Licença: ${session.licenseDaysLeft} dia(s)'),
            ),
          ),
        IconButton(
          tooltip: 'Sair',
          icon: const Icon(Icons.logout),
          onPressed: () => ref.read(sessionControllerProvider.notifier).logout(),
        ),
      ],
    );

    final body = Column(children: [
      Expanded(child: child),
      const Divider(height: 1),
      const CreditsFooter(dense: true), // rodapé principal com créditos (todas as plataformas)
    ]);

    return CallbackShortcuts(
      bindings: shortcuts,
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: appBar,
          body: compact
              ? body
              : Row(children: [
                  NavigationRail(
                    selectedIndex: index,
                    extended: Breakpoints.isExpanded(context),
                    labelType: Breakpoints.isExpanded(context) ? null : NavigationRailLabelType.all,
                    onDestinationSelected: (i) => context.go(items[i].path),
                    destinations: [
                      for (final i in items)
                        NavigationRailDestination(
                          icon: Icon(i.icon),
                          label: Text('${i.label}  (${i.key.keyLabel})'),
                        ),
                    ],
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: body),
                ]),
          bottomNavigationBar: compact && items.length >= 2
              ? NavigationBar(
                  selectedIndex: index,
                  onDestinationSelected: (i) => context.go(items[i].path),
                  destinations: [for (final i in items) NavigationDestination(icon: Icon(i.icon), label: i.label)],
                )
              : null,
        ),
      ),
    );
  }
}
