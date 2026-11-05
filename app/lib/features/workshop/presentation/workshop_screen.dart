import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/utils/whatsapp.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../auth/domain/session.dart';
import '../../auth/presentation/session_controller.dart';
import '../../partners/domain/partner.dart';
import '../../partners/presentation/partner_picker_dialog.dart';
import '../data/workshop_repository.dart';
import '../domain/workshop.dart';
import 'new_order_dialog.dart';
import 'vehicle_form_dialog.dart';
import 'work_order_page.dart';

final osFilterProvider = StateProvider.autoDispose<(String, String)>((_) => ('ABERTAS', ''));
final osListProvider = FutureProvider.autoDispose<List<WorkOrderRow>>((ref) {
  final f = ref.watch(osFilterProvider);
  return ref.read(workshopRepositoryProvider).orders(status: f.$1, q: f.$2);
});
final osSummaryProvider = FutureProvider.autoDispose((ref) => ref.read(workshopRepositoryProvider).summary());

/// Oficina de motos. Atalho: Ctrl+N nova OS (receber moto).
class WorkshopScreen extends ConsumerWidget {
  const WorkshopScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sessionControllerProvider);
    final manager = s?.isManager ?? false;
    final tabs = [
      const Tab(icon: Icon(Icons.assignment_outlined), text: 'Ordens de serviço'),
      const Tab(icon: Icon(Icons.two_wheeler), text: 'Motos'),
      const Tab(icon: Icon(Icons.handyman_outlined), text: 'Mão de obra'),
      const Tab(icon: Icon(Icons.event_repeat), text: 'Revisões'),
      if (manager) const Tab(icon: Icon(Icons.percent), text: 'Comissões'),
    ];
    return DefaultTabController(
      length: tabs.length,
      child: Column(children: [
        TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: tabs),
        Expanded(
          child: TabBarView(children: [
            const _OrdersTab(),
            const _VehiclesTab(),
            _ServicesTab(canEdit: manager),
            const _RemindersTab(),
            if (manager) const _CommissionsTab(),
          ]),
        ),
      ]),
    );
  }
}

// =================================================================== ORDENS
class _OrdersTab extends ConsumerStatefulWidget {
  const _OrdersTab();

  @override
  ConsumerState<_OrdersTab> createState() => _OrdersTabState();
}

class _OrdersTabState extends ConsumerState<_OrdersTab> {
  final _q = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  void _refresh() {
    ref.invalidate(osListProvider);
    ref.invalidate(osSummaryProvider);
  }

  Future<void> _new() async {
    final o = await showDialog<WorkOrder>(context: context, builder: (_) => const NewOrderDialog());
    if (o == null || !mounted) return;
    _refresh();
    await _open(o.id);
  }

  Future<void> _open(String id) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => WorkOrderPage(orderId: id)));
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final f = ref.watch(osFilterProvider);
    final list = ref.watch(osListProvider);
    final summary = ref.watch(osSummaryProvider).valueOrNull ?? const {};
    final role = ref.watch(sessionControllerProvider)?.user.role;
    final compact = Breakpoints.isCompact(context);

    void setStatus(String st) => ref.read(osFilterProvider.notifier).state = (st, f.$2);

    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.keyN, control: true): _new},
      child: Scaffold(
        floatingActionButton: role == UserRole.mecanico
            ? null
            : FloatingActionButton.extended(
                heroTag: 'os-new',
                onPressed: _new,
                icon: const Icon(Icons.add),
                label: Text(compact ? 'Receber moto' : 'Receber moto — nova OS (Ctrl+N)'),
              ),
        body: RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              // quadro: quantas OS em cada passo (toque para filtrar)
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final st in kOsFlow.take(5))
                  FilterChip(
                    avatar: Icon(st.icon, size: 18, color: st.color(t.colorScheme)),
                    label: Text('${st.label} · ${summary[st.api] ?? 0}'),
                    selected: f.$1 == st.api,
                    onSelected: (v) => setStatus(v ? st.api : 'ABERTAS'),
                  ),
                ChoiceChip(label: const Text('Todas em aberto'), selected: f.$1 == 'ABERTAS', onSelected: (_) => setStatus('ABERTAS')),
                ChoiceChip(label: const Text('Entregues'), selected: f.$1 == 'ENTREGUES', onSelected: (_) => setStatus('ENTREGUES')),
              ]),
              const SizedBox(height: 12),
              SizedBox(
                width: compact ? double.infinity : 420,
                child: TextField(
                  controller: _q,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Placa, cliente, modelo ou nº da OS'),
                  onChanged: (v) {
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 300), () => ref.read(osFilterProvider.notifier).state = (f.$1, v.trim()));
                  },
                ),
              ),
              const SizedBox(height: 12),
              list.when(
                loading: () => const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator())),
                error: (e, _) => Card(child: ListTile(leading: const Icon(Icons.error), title: Text(e.toString()))),
                data: (items) => items.isEmpty && f.$1 == 'ABERTAS' && f.$2.isEmpty
                    ? _WorkshopGuide(role: role, onNew: role == UserRole.mecanico ? null : _new)
                    : items.isEmpty
                        ? const Padding(padding: EdgeInsets.all(48), child: Center(child: Text('Nenhuma OS encontrada')))
                        : Column(children: [for (final o in items) _OrderCard(o: o, onTap: () => _open(o.id))]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.o, required this.onTap});
  final WorkOrderRow o;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = o.status.color(t.colorScheme);
    final plate = o.plate.length == 7 ? '${o.plate.substring(0, 3)}-${o.plate.substring(3)}' : o.plate;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Container(
              width: 56,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(color: c.withValues(alpha: .12), borderRadius: BorderRadius.circular(10)),
              child: Column(children: [
                Icon(o.status.icon, color: c),
                Text('${o.number}', style: TextStyle(fontWeight: FontWeight.bold, color: c)),
              ]),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('$plate · ${o.vehicleLabel}', style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(o.customerName),
                Text(
                  [
                    o.status.label,
                    if (o.mechanicName != null) o.mechanicName!,
                    if (o.complaint != null) o.complaint!,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.textTheme.bodySmall,
                ),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              if (o.total != null && o.total! > 0) Text(money(o.total!), style: const TextStyle(fontWeight: FontWeight.w700)),
              if (o.promisedAt != null)
                Text(
                  o.late ? 'atrasada' : 'prev. ${dateTimeBr(o.promisedAt)}',
                  style: TextStyle(fontSize: 12, color: o.late ? t.colorScheme.error : t.colorScheme.outline, fontWeight: o.late ? FontWeight.bold : null),
                ),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// Passo a passo da oficina — aparece quando ainda não há OS em aberto.
class _WorkshopGuide extends StatelessWidget {
  const _WorkshopGuide({required this.role, this.onNew});
  final UserRole? role;
  final VoidCallback? onNew;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    const steps = [
      (Icons.login, 'Receber a moto', 'Toque em "Receber moto": escolha o cliente, a moto, anote o relato, km, combustível e faça o checklist com o cliente olhando.'),
      (Icons.request_quote_outlined, 'Montar o orçamento', 'Na OS, adicione as peças (do estoque, com foto) e a mão de obra (da tabela). Toque em "Enviar orçamento" — o WhatsApp abre com tudo escrito.'),
      (Icons.thumb_up_alt_outlined, 'Cliente aprovou', 'Quando o cliente responder SIM, toque em "Cliente aprovou". Se ele recusar, cancele a OS com o motivo.'),
      (Icons.build_outlined, 'Fazer o serviço', 'O mecânico toca em "Iniciar serviço", anota o diagnóstico e ajusta peças se precisar. Quando terminar, "Moto pronta" — o app oferece avisar o cliente.'),
      (Icons.point_of_sale, 'Receber e entregar', 'Com o caixa aberto no PDV, toque em "Receber e entregar": à vista, PIX, cartão ou fiado. A peça sai do estoque e você marca a próxima revisão.'),
      (Icons.event_repeat, 'Chamar para a revisão', 'Na aba Revisões aparecem as motos que estão para voltar, com botão para chamar o cliente no WhatsApp.'),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.two_wheeler, size: 32, color: t.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(child: Text('Como funciona a oficina', style: t.textTheme.titleLarge)),
          ]),
          const SizedBox(height: 4),
          Text(workshopRoleHelp(role ?? UserRole.admin), style: t.textTheme.bodyMedium),
          const SizedBox(height: 16),
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                CircleAvatar(radius: 14, child: Text('${i + 1}', style: const TextStyle(fontSize: 13))),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(steps[i].$1, size: 18),
                      const SizedBox(width: 6),
                      Text(steps[i].$2, style: const TextStyle(fontWeight: FontWeight.w600)),
                    ]),
                    Text(steps[i].$3, style: t.textTheme.bodySmall),
                  ]),
                ),
              ]),
            ),
          const SizedBox(height: 4),
          Text('Antes da primeira OS: cadastre as peças em Produtos (com foto), carregue a tabela na aba '
              '"Mão de obra" e crie os mecânicos em Usuários.', style: t.textTheme.bodySmall),
          if (onNew != null) ...[
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: onNew, icon: const Icon(Icons.add), label: const Text('Receber a primeira moto')),
          ],
        ]),
      ),
    );
  }
}

// =================================================================== MOTOS
final _vehicleQueryProvider = StateProvider.autoDispose<String>((_) => '');
final _vehiclesProvider = FutureProvider.autoDispose<List<Vehicle>>((ref) {
  return ref.read(workshopRepositoryProvider).vehicles(q: ref.watch(_vehicleQueryProvider));
});

class _VehiclesTab extends ConsumerStatefulWidget {
  const _VehiclesTab();

  @override
  ConsumerState<_VehiclesTab> createState() => _VehiclesTabState();
}

class _VehiclesTabState extends ConsumerState<_VehiclesTab> {
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _new() async {
    final c = await showDialog<Partner>(context: context, builder: (_) => const PartnerPickerDialog(title: 'Dono da moto'));
    if (c == null || !mounted) return;
    final v = await showDialog<Vehicle>(context: context, builder: (_) => VehicleFormDialog(customerId: c.id, customerName: c.displayName));
    if (v != null) ref.invalidate(_vehiclesProvider);
  }

  Future<void> _edit(Vehicle v) async {
    final r = await showDialog<Vehicle>(
      context: context,
      builder: (_) => VehicleFormDialog(customerId: v.customerId, customerName: v.customerName ?? '', initial: v),
    );
    if (r != null) ref.invalidate(_vehiclesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(_vehiclesProvider);
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'veh-new',
        onPressed: _new,
        icon: const Icon(Icons.add),
        label: const Text('Nova moto'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Placa, modelo ou dono'),
            onChanged: (v) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 300), () => ref.read(_vehicleQueryProvider.notifier).state = v.trim());
            },
          ),
          const SizedBox(height: 12),
          list.when(
            loading: () => const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator())),
            error: (e, _) => Text(e.toString()),
            data: (items) => items.isEmpty
                ? const Padding(padding: EdgeInsets.all(48), child: Center(child: Text('Nenhuma moto cadastrada')))
                : Card(
                    child: Column(children: [
                      for (var i = 0; i < items.length; i++) ...[
                        if (i > 0) const Divider(height: 1),
                        ListTile(
                          leading: const CircleAvatar(child: Icon(Icons.two_wheeler, size: 20)),
                          title: Text('${items[i].plateFmt} · ${items[i].label}'),
                          subtitle: Text([
                            items[i].customerName ?? '',
                            if (items[i].km != null) '${number(items[i].km!)} km',
                            if (items[i].lastServiceAt != null) 'último serviço ${dateBr(items[i].lastServiceAt)}',
                            if (items[i].openOrders > 0) '${items[i].openOrders} OS em aberto',
                          ].join(' · ')),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            IconButton(
                              tooltip: 'Histórico',
                              icon: const Icon(Icons.history),
                              onPressed: () => showDialog<void>(context: context, builder: (_) => _HistoryDialog(vehicle: items[i])),
                            ),
                            IconButton(tooltip: 'Editar', icon: const Icon(Icons.edit_outlined), onPressed: () => _edit(items[i])),
                          ]),
                        ),
                      ],
                    ]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _HistoryDialog extends ConsumerWidget {
  const _HistoryDialog({required this.vehicle});
  final Vehicle vehicle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AlertDialog(
      title: Text('Histórico · ${vehicle.plateFmt}'),
      content: SizedBox(
        width: 520,
        height: 440,
        child: FutureBuilder<List<WorkOrderRow>>(
          future: ref.read(workshopRepositoryProvider).vehicleHistory(vehicle.id),
          builder: (context, snap) {
            if (snap.hasError) return Center(child: Text(snap.error.toString()));
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final list = snap.data!;
            if (list.isEmpty) return const Center(child: Text('Nenhuma OS para esta moto ainda'));
            return ListView(children: [
              for (final o in list)
                ListTile(
                  leading: Icon(o.status.icon, color: o.status.color(Theme.of(context).colorScheme)),
                  title: Text('OS ${o.number} · ${dateBr(o.openedAt)} · ${o.status.label}'),
                  subtitle: Text(o.complaint ?? ''),
                  trailing: o.total != null ? Text(money(o.total!)) : null,
                  onTap: () {
                    final nav = Navigator.of(context);
                    nav.pop();
                    nav.push(MaterialPageRoute(builder: (_) => WorkOrderPage(orderId: o.id)));
                  },
                ),
            ]);
          },
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar'))],
    );
  }
}

// =================================================================== MÃO DE OBRA
final _servicesProvider = FutureProvider.autoDispose((ref) => ref.read(workshopRepositoryProvider).services(all: true));

class _ServicesTab extends ConsumerWidget {
  const _ServicesTab({required this.canEdit});
  final bool canEdit;

  Future<void> _edit(BuildContext context, WidgetRef ref, [LaborService? s]) async {
    final name = TextEditingController(text: s?.name ?? '');
    final price = TextEditingController(text: s == null ? '' : s.price.toStringAsFixed(2).replaceAll('.', ','));
    final minutes = TextEditingController(text: s?.estMinutes?.toString() ?? '');
    var active = s?.isActive ?? true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(s == null ? 'Novo serviço' : 'Editar serviço'),
          content: SizedBox(
            width: 400,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'Serviço')),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: price,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Valor da mão de obra', prefixText: r'R$ '),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: minutes,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: 'Tempo', suffixText: 'min'),
                  ),
                ),
              ]),
              if (s != null)
                SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Ativo'), value: active, onChanged: (v) => set(() => active = v)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Salvar')),
          ],
        ),
      ),
    );
    if (ok != true || name.text.trim().length < 2) return;
    try {
      await ref.read(workshopRepositoryProvider).saveService(
            id: s?.id,
            name: name.text.trim(),
            price: parseMoney(price.text),
            estMinutes: int.tryParse(minutes.text),
            isActive: active,
          );
      ref.invalidate(_servicesProvider);
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _defaults(BuildContext context, WidgetRef ref) async {
    try {
      final n = await ref.read(workshopRepositoryProvider).loadDefaultServices();
      ref.invalidate(_servicesProvider);
      if (context.mounted) showOk(context, n == 0 ? 'A tabela já tinha esses serviços' : '$n serviços adicionados — ajuste os preços');
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(_servicesProvider);
    final t = Theme.of(context);
    return Scaffold(
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              heroTag: 'svc-new',
              onPressed: () => _edit(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('Novo serviço'),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          Text('Tabela de mão de obra', style: t.textTheme.titleLarge),
          const Text('O valor sugerido entra na OS e pode ser ajustado em cada uma. Peças ficam em Produtos.'),
          const SizedBox(height: 12),
          if (canEdit)
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => _defaults(context, ref),
                icon: const Icon(Icons.playlist_add),
                label: const Text('Carregar tabela padrão (20 serviços de moto)'),
              ),
            ),
          const SizedBox(height: 12),
          list.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text(e.toString()),
            data: (items) => items.isEmpty
                ? const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('Nenhum serviço cadastrado')))
                : Card(
                    child: Column(children: [
                      for (var i = 0; i < items.length; i++) ...[
                        if (i > 0) const Divider(height: 1),
                        ListTile(
                          onTap: canEdit ? () => _edit(context, ref, items[i]) : null,
                          leading: const Icon(Icons.handyman_outlined),
                          title: Text(items[i].name, style: TextStyle(color: items[i].isActive ? null : t.colorScheme.outline)),
                          subtitle: items[i].estMinutes != null ? Text('~${items[i].estMinutes} min') : null,
                          trailing: Text(money(items[i].price), style: const TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ]),
                  ),
          ),
        ],
      ),
    );
  }
}

// =================================================================== REVISÕES
final _reminderDaysProvider = StateProvider.autoDispose<int>((_) => 15);
final _remindersProvider = FutureProvider.autoDispose((ref) => ref.read(workshopRepositoryProvider).reminders(days: ref.watch(_reminderDaysProvider)));

class _RemindersTab extends ConsumerWidget {
  const _RemindersTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final days = ref.watch(_reminderDaysProvider);
    final list = ref.watch(_remindersProvider);
    final company = ref.watch(sessionControllerProvider)?.tenant.nomeFantasia ?? '';
    final t = Theme.of(context);
    final today = DateTime.now();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Revisões a vencer', style: t.textTheme.titleLarge),
        const Text('Motos com revisão marcada na entrega. Chame o cliente pelo WhatsApp com um toque.'),
        const SizedBox(height: 12),
        Wrap(spacing: 8, children: [
          for (final d in const [7, 15, 30, 60])
            ChoiceChip(label: Text('próximos $d dias'), selected: days == d, onSelected: (_) => ref.read(_reminderDaysProvider.notifier).state = d),
        ]),
        const SizedBox(height: 12),
        list.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text(e.toString()),
          data: (items) => items.isEmpty
              ? const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('Nenhuma revisão no período')))
              : Card(
                  child: Column(children: [
                    for (var i = 0; i < items.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      Builder(builder: (context) {
                        final r = items[i];
                        final late = r.nextServiceDate.isBefore(DateTime(today.year, today.month, today.day));
                        final plate = r.plate.length == 7 ? '${r.plate.substring(0, 3)}-${r.plate.substring(3)}' : r.plate;
                        return ListTile(
                          leading: Icon(Icons.event_repeat, color: late ? t.colorScheme.error : t.colorScheme.primary),
                          title: Text('$plate · ${r.vehicleLabel}'),
                          subtitle: Text('${r.customerName} · revisão ${late ? 'vencida em' : 'em'} ${dateBr(r.nextServiceDate)}'
                              '${r.nextServiceKm != null ? ' ou ${number(r.nextServiceKm!)} km' : ''}'),
                          trailing: FilledButton.tonalIcon(
                            onPressed: () => openWhatsApp(
                              r.customerPhone,
                              'Olá, ${r.customerName.split(' ').first}! Aqui é da *$company*. Está chegando a hora da revisão da sua '
                              '${r.vehicleLabel} ($plate). Quer agendar? Responda com o melhor dia para você.',
                            ),
                            icon: const Icon(Icons.chat, size: 18),
                            label: const Text('Chamar'),
                          ),
                        );
                      }),
                    ],
                  ]),
                ),
        ),
      ],
    );
  }
}

// =================================================================== COMISSÕES
final _commMonthProvider = StateProvider.autoDispose<DateTime>((_) => DateTime(DateTime.now().year, DateTime.now().month));
final _commissionsProvider = FutureProvider.autoDispose((ref) {
  final m = ref.watch(_commMonthProvider);
  return ref.read(workshopRepositoryProvider).commissions(from: m, to: DateTime(m.year, m.month + 1, 0));
});

class _CommissionsTab extends ConsumerWidget {
  const _CommissionsTab();

  static const _months = ['janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', 'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = ref.watch(_commMonthProvider);
    final list = ref.watch(_commissionsProvider);
    final t = Theme.of(context);
    void shift(int d) => ref.read(_commMonthProvider.notifier).state = DateTime(m.year, m.month + d);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Comissões dos mecânicos', style: t.textTheme.titleLarge),
        const Text('Calculada sobre a mão de obra das OS entregues no mês. A % de cada mecânico fica em Usuários.'),
        const SizedBox(height: 12),
        Row(children: [
          IconButton(onPressed: () => shift(-1), icon: const Icon(Icons.chevron_left)),
          Text('${_months[m.month - 1]} de ${m.year}', style: t.textTheme.titleMedium),
          IconButton(onPressed: () => shift(1), icon: const Icon(Icons.chevron_right)),
        ]),
        list.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text(e.toString()),
          data: (items) => items.isEmpty
              ? const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('Nenhuma OS entregue com mecânico neste mês')))
              : Card(
                  child: Column(children: [
                    for (final c in items)
                      ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.build, size: 18)),
                        title: Text(c.name),
                        subtitle: Text('${c.orders} OS · mão de obra ${money(c.labor)} · ${number(c.pct)}%'),
                        trailing: Text(money(c.commission), style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      ),
                  ]),
                ),
        ),
      ],
    );
  }
}
