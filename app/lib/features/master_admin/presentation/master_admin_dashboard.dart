import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../domain/tenant.dart';
import 'admin_controller.dart';
import 'create_tenant_dialog.dart';

/// Painel do Administrador Master (SUPER_ADMIN): todas as empresas, status,
/// vencimento da licença, bloqueio/desbloqueio, renovação e novos clientes.
/// Atalhos: Ctrl+N novo cliente · Ctrl+F buscar
class MasterAdminDashboard extends ConsumerStatefulWidget {
  const MasterAdminDashboard({super.key});

  @override
  ConsumerState<MasterAdminDashboard> createState() => _MasterAdminDashboardState();
}

class _MasterAdminDashboardState extends ConsumerState<MasterAdminDashboard> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      ref.read(tenantFilterProvider.notifier).update((f) => f.copyWith(q: v.trim()));
    });
  }

  Future<void> _newTenant() async {
    final input = await showDialog<NewTenantInput>(context: context, builder: (_) => const CreateTenantDialog());
    if (input == null || !mounted) return;
    try {
      await ref.read(tenantsControllerProvider.notifier).create(input);
      if (mounted) showOk(context, 'Cliente ${input.razaoSocial} criado. Usuário: ${input.adminUsername}');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _toggle(Tenant t) async {
    String? reason;
    final blocking = !t.isBlocked;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) {
        final reasonCtrl = TextEditingController();
        return AlertDialog(
          title: Text(blocking ? 'Bloquear acesso?' : 'Reativar acesso?'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${t.displayName}\nCNPJ ${formatCnpj(t.cnpj)}'),
            if (blocking) ...[
              const SizedBox(height: 12),
              const Text('Todos os usuários desta empresa serão desconectados na próxima ação.'),
              const SizedBox(height: 12),
              TextField(
                controller: reasonCtrl,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Motivo (opcional)', hintText: 'Ex.: inadimplência'),
                onChanged: (v) => reason = v,
              ),
            ],
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(
              style: blocking ? FilledButton.styleFrom(backgroundColor: Theme.of(c).colorScheme.error) : null,
              onPressed: () => Navigator.pop(c, true),
              child: Text(blocking ? 'Bloquear' : 'Reativar'),
            ),
          ],
        );
      },
    );
    if (ok != true) return;
    try {
      await ref.read(tenantsControllerProvider.notifier).toggleStatus(t, reason: reason);
      if (mounted) showOk(context, blocking ? 'Acesso bloqueado' : 'Acesso reativado');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _modules(Tenant t) async {
    final selected = await showDialog<List<String>>(context: context, builder: (_) => _ModulesDialog(tenant: t));
    if (selected == null || !mounted) return;
    try {
      await ref.read(tenantsControllerProvider.notifier).setModules(t, selected);
      if (mounted) showOk(context, 'Módulos de ${t.displayName} atualizados');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _renew(Tenant t) async {
    final base = t.isExpired ? DateTime.now() : t.licenseExpiresAt;
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(base.year, base.month + 1, base.day),
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime(2100),
      helpText: 'Nova data de vencimento — ${t.displayName}',
    );
    if (picked == null) return;
    try {
      await ref.read(tenantsControllerProvider.notifier).renew(t, picked);
      if (mounted) showOk(context, 'Licença renovada até ${dateBr(picked)}');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tenants = ref.watch(tenantsControllerProvider);
    final stats = ref.watch(adminStatsProvider).valueOrNull ?? const AdminStats();
    final filter = ref.watch(tenantFilterProvider);
    final compact = Breakpoints.isCompact(context);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): _newTenant,
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () => _searchFocus.requestFocus(),
      },
      child: Scaffold(
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _newTenant,
          icon: const Icon(Icons.add_business),
          label: Text(compact ? 'Novo' : 'Novo cliente (Ctrl+N)'),
        ),
        body: RefreshIndicator(
          onRefresh: () => ref.refresh(tenantsControllerProvider.future),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              Row(children: [
                Expanded(child: Text('Administração Master', style: Theme.of(context).textTheme.headlineSmall)),
                IconButton(
                  tooltip: 'Atualizar',
                  onPressed: () => ref.invalidate(tenantsControllerProvider),
                  icon: const Icon(Icons.refresh),
                ),
              ]),
              const SizedBox(height: 12),
              ResponsiveGrid(maxColumns: 5, children: [
                KpiCard(label: 'Clientes', value: '${stats.total}', icon: Icons.apartment),
                KpiCard(label: 'Ativos', value: '${stats.ativos}', icon: Icons.check_circle, color: Colors.green.shade700),
                KpiCard(label: 'Bloqueados', value: '${stats.bloqueados}', icon: Icons.block, color: Theme.of(context).colorScheme.error),
                KpiCard(label: 'Licença vencida', value: '${stats.vencidos}', icon: Icons.event_busy, color: Colors.orange.shade800),
                KpiCard(label: 'Vence em 7 dias', value: '${stats.vencendo7d}', icon: Icons.schedule, color: Colors.amber.shade800),
              ]),
              const SizedBox(height: 16),
              Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                SizedBox(
                  width: compact ? double.infinity : 360,
                  child: TextField(
                    controller: _search,
                    focusNode: _searchFocus,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Buscar por CNPJ, razão social ou fantasia (Ctrl+F)',
                    ),
                    onChanged: _onSearch,
                  ),
                ),
                for (final s in const [('', 'Todos'), ('ATIVO', 'Ativos'), ('BLOQUEADO', 'Bloqueados')])
                  ChoiceChip(
                    label: Text(s.$2),
                    selected: filter.status == s.$1,
                    onSelected: (_) => ref.read(tenantFilterProvider.notifier).update((f) => f.copyWith(status: s.$1)),
                  ),
              ]),
              const SizedBox(height: 12),
              tenants.when(
                loading: () => const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator())),
                error: (e, _) => Card(child: ListTile(leading: const Icon(Icons.error), title: Text(e.toString()))),
                data: (list) => list.isEmpty
                    ? const Padding(padding: EdgeInsets.all(48), child: Center(child: Text('Nenhuma empresa encontrada')))
                    : compact
                        ? Column(children: [for (final t in list) _TenantCard(t: t, onToggle: _toggle, onRenew: _renew, onModules: _modules)])
                        : _TenantTable(list: list, onToggle: _toggle, onRenew: _renew, onModules: _modules),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip(this.t);
  final Tenant t;

  @override
  Widget build(BuildContext context) {
    final (label, color) = t.isBlocked
        ? ('Bloqueado', Theme.of(context).colorScheme.error)
        : t.isExpired
            ? ('Vencido', Colors.orange.shade800)
            : ('Ativo', Colors.green.shade700);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
    );
  }
}

String _licenseText(Tenant t) {
  if (t.isPlatform) return 'Plataforma';
  final d = t.daysLeft;
  final when = d < 0 ? 'venceu há ${-d} d' : d == 0 ? 'vence hoje' : 'em $d d';
  return '${dateBr(t.licenseExpiresAt)} ($when)';
}

class _TenantTable extends StatelessWidget {
  const _TenantTable({required this.list, required this.onToggle, required this.onRenew, required this.onModules});
  final List<Tenant> list;
  final void Function(Tenant) onToggle;
  final void Function(Tenant) onRenew;
  final void Function(Tenant) onModules;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Empresa')),
            DataColumn(label: Text('CNPJ')),
            DataColumn(label: Text('Status')),
            DataColumn(label: Text('Licença')),
            DataColumn(label: Text('Usuários'), numeric: true),
            DataColumn(label: Text('Ações')),
          ],
          rows: [
            for (final t in list)
              DataRow(cells: [
                DataCell(Row(children: [
                  CompanyLogo(url: t.logoUrl, name: t.displayName, size: 32),
                  const SizedBox(width: 10),
                  Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t.displayName, style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(t.razaoSocial, style: Theme.of(context).textTheme.bodySmall),
                  ]),
                ])),
                DataCell(Text(formatCnpj(t.cnpj))),
                DataCell(Tooltip(message: t.blockedReason ?? '', child: _StatusChip(t))),
                DataCell(Text(_licenseText(t))),
                DataCell(Text('${t.usersCount}/${t.maxUsers}')),
                DataCell(t.isPlatform
                    ? const SizedBox.shrink()
                    : Row(children: [
                        TextButton.icon(
                          onPressed: () => onToggle(t),
                          icon: Icon(t.isBlocked ? Icons.lock_open : Icons.block),
                          label: Text(t.isBlocked ? 'Ativar' : 'Bloquear'),
                        ),
                        TextButton.icon(
                          onPressed: () => onRenew(t),
                          icon: const Icon(Icons.event_repeat),
                          label: const Text('Renovar'),
                        ),
                        TextButton.icon(
                          onPressed: () => onModules(t),
                          icon: const Icon(Icons.extension_outlined),
                          label: Text('Módulos (${t.modules.length})'),
                        ),
                      ])),
              ]),
          ],
        ),
      ),
    );
  }
}

class _TenantCard extends StatelessWidget {
  const _TenantCard({required this.t, required this.onToggle, required this.onRenew, required this.onModules});
  final Tenant t;
  final void Function(Tenant) onToggle;
  final void Function(Tenant) onRenew;
  final void Function(Tenant) onModules;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CompanyLogo(url: t.logoUrl, name: t.displayName, size: 40),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t.displayName, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(formatCnpj(t.cnpj), style: Theme.of(context).textTheme.bodySmall),
              ]),
            ),
            _StatusChip(t),
          ]),
          const SizedBox(height: 8),
          Text('Licença: ${_licenseText(t)} · Usuários ${t.usersCount}/${t.maxUsers}'),
          if (t.isBlocked && (t.blockedReason?.isNotEmpty ?? false)) Text('Motivo: ${t.blockedReason}'),
          if (!t.isPlatform)
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(onPressed: () => onModules(t), child: Text('Módulos (${t.modules.length})')),
              TextButton(onPressed: () => onRenew(t), child: const Text('Renovar')),
              FilledButton.tonal(onPressed: () => onToggle(t), child: Text(t.isBlocked ? 'Ativar' : 'Bloquear')),
            ]),
        ]),
      ),
    );
  }
}

/// Liga/desliga os módulos contratados pela empresa (base para planos de venda).
class _ModulesDialog extends StatefulWidget {
  const _ModulesDialog({required this.tenant});
  final Tenant tenant;

  @override
  State<_ModulesDialog> createState() => _ModulesDialogState();
}

class _ModulesDialogState extends State<_ModulesDialog> {
  late final Set<String> _sel = {...widget.tenant.modules};

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Módulos · ${widget.tenant.displayName}'),
      content: SizedBox(
        width: 440,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.verified_outlined),
            title: Text('Sempre incluídos'),
            subtitle: Text('Produtos e estoque, clientes e fornecedores, empresa e logo'),
          ),
          const Divider(),
          for (final m in kModules)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _sel.contains(m.$1),
              title: Text(m.$2),
              subtitle: Text(m.$3),
              onChanged: (v) => setState(() => v == true ? _sel.add(m.$1) : _sel.remove(m.$1)),
            ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () => Navigator.pop(context, [for (final m in kModules) if (_sel.contains(m.$1)) m.$1]),
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}
