import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/domain/session.dart';
import '../../features/auth/presentation/session_controller.dart';
import '../../features/users/presentation/change_password_dialog.dart';
import '../router/app_router.dart';
import 'common_widgets.dart';

class _NavItem {
  const _NavItem(this.path, this.label, this.icon, this.shortcut, this.hint);
  final String path;
  final String label;
  final IconData icon;
  final SingleActivator shortcut;
  final String hint;
}

/// Atalhos globais (Windows/Web). F5, F11 e F12 ficam livres para o navegador.
const _allItems = [
  _NavItem(Routes.pos, 'PDV', Icons.point_of_sale, SingleActivator(LogicalKeyboardKey.f2), 'F2'),
  _NavItem(Routes.workshop, 'Oficina', Icons.two_wheeler, SingleActivator(LogicalKeyboardKey.keyO, alt: true), 'Alt+O'),
  _NavItem(Routes.productivity, 'Produtividade', Icons.local_shipping, SingleActivator(LogicalKeyboardKey.f3), 'F3'),
  _NavItem(Routes.products, 'Produtos', Icons.inventory_2_outlined, SingleActivator(LogicalKeyboardKey.keyP, alt: true), 'Alt+P'),
  _NavItem(Routes.partners, 'Clientes e fornecedores', Icons.contacts_outlined,
      SingleActivator(LogicalKeyboardKey.keyC, alt: true), 'Alt+C'),
  _NavItem(Routes.finance, 'Financeiro', Icons.account_balance_wallet_outlined,
      SingleActivator(LogicalKeyboardKey.keyF, alt: true), 'Alt+F'),
  _NavItem(Routes.purchases, 'Compras (NF-e)', Icons.receipt_long_outlined,
      SingleActivator(LogicalKeyboardKey.keyN, alt: true), 'Alt+N'),
  _NavItem(Routes.users, 'Usuários', Icons.manage_accounts_outlined, SingleActivator(LogicalKeyboardKey.keyU, alt: true), 'Alt+U'),
  _NavItem(Routes.company, 'Empresa', Icons.business, SingleActivator(LogicalKeyboardKey.f4), 'F4'),
  _NavItem(Routes.masterAdmin, 'Master', Icons.admin_panel_settings, SingleActivator(LogicalKeyboardKey.f6), 'F6'),
  _NavItem(Routes.about, 'Sobre / Ajuda', Icons.help_outline, SingleActivator(LogicalKeyboardKey.f1), 'F1'),
];

/// Estrutura principal: cabeçalho com a logo da empresa, menu adaptativo
/// (lateral no desktop, gaveta no celular) e rodapé com créditos.
/// O menu mostra só o que o perfil e os módulos contratados permitem.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);
    if (session == null) return const SizedBox.shrink();

    final items = _allItems.where((i) => canAccess(session, i.path)).toList();
    final selected = items.indexWhere((i) => location.startsWith(i.path));
    final compact = Breakpoints.isCompact(context);
    final wide = Breakpoints.isExpanded(context);

    final shortcuts = <ShortcutActivator, VoidCallback>{
      for (final i in items) i.shortcut: () => context.go(i.path),
    };

    final appBar = AppBar(
      titleSpacing: compact ? 0 : 12,
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
        if ((session.licenseDaysLeft ?? 99) <= 7 && !session.isSuperAdmin && !compact)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Chip(
              avatar: const Icon(Icons.warning_amber, size: 16),
              label: Text('Licença: ${session.licenseDaysLeft} dia(s)'),
            ),
          ),
        PopupMenuButton<String>(
          tooltip: 'Minha conta',
          icon: const Icon(Icons.account_circle_outlined),
          onSelected: (v) {
            if (v == 'pw') {
              showChangePasswordDialog(context);
            } else {
              ref.read(sessionControllerProvider.notifier).logout();
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'pw', child: ListTile(leading: Icon(Icons.lock_reset), title: Text('Trocar minha senha'))),
            PopupMenuItem(value: 'out', child: ListTile(leading: Icon(Icons.logout), title: Text('Sair'))),
          ],
        ),
      ],
    );

    final body = Column(children: [
      Expanded(child: child),
      const Divider(height: 1),
      const CreditsFooter(dense: true), // rodapé principal com créditos (todas as plataformas)
    ]);

    Widget navList({required bool showLabels, VoidCallback? afterTap}) => ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            for (var i = 0; i < items.length; i++)
              _NavTile(
                item: items[i],
                selected: i == selected,
                showLabel: showLabels,
                onTap: () {
                  afterTap?.call();
                  context.go(items[i].path);
                },
              ),
          ],
        );

    return CallbackShortcuts(
      bindings: shortcuts,
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: appBar,
          drawer: compact
              ? Drawer(
                  child: SafeArea(
                    child: Builder(
                      builder: (ctx) => navList(showLabels: true, afterTap: () => Navigator.of(ctx).pop()),
                    ),
                  ),
                )
              : null,
          body: compact
              ? body
              : Row(children: [
                  SizedBox(width: wide ? 248 : 88, child: navList(showLabels: wide)),
                  const VerticalDivider(width: 1),
                  Expanded(child: body),
                ]),
        ),
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({required this.item, required this.selected, required this.showLabel, required this.onTap});
  final _NavItem item;
  final bool selected;
  final bool showLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final color = selected ? t.colorScheme.onSecondaryContainer : t.colorScheme.onSurfaceVariant;
    final tile = Material(
      color: selected ? t.colorScheme.secondaryContainer : Colors.transparent,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: showLabel ? 16 : 0, vertical: 12),
          child: showLabel
              ? Row(children: [
                  Icon(item.icon, color: color),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(item.label,
                        style: TextStyle(color: color, fontWeight: selected ? FontWeight.w600 : FontWeight.normal)),
                  ),
                  Text(item.hint, style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.outline)),
                ])
              : Center(child: Icon(item.icon, color: color)),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: showLabel ? tile : Tooltip(message: '${item.label} (${item.hint})', child: tile),
    );
  }
}
