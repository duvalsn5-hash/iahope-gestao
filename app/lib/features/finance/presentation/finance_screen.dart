import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../cash/data/cash_repository.dart';
import '../../cash/domain/cash.dart';
import '../data/finance_repository.dart';
import '../domain/finance.dart';
import 'finance_dialogs.dart';

class FinFilter {
  const FinFilter({this.status = 'ABERTOS', this.q = ''});
  final String status;
  final String q;
}

final finFilterProvider = StateProvider.autoDispose.family<FinFilter, String>((_, __) => const FinFilter());

final finEntriesProvider = FutureProvider.autoDispose.family<List<FinEntry>, String>((ref, kind) {
  final f = ref.watch(finFilterProvider(kind));
  return ref.read(financeRepositoryProvider).entries(kind: kind, status: f.status, q: f.q);
});

final finSummaryProvider = FutureProvider.autoDispose<FinSummary>((ref) => ref.read(financeRepositoryProvider).summary());

final cashSessionsProvider = FutureProvider.autoDispose<List<CashSessionRow>>((ref) => ref.read(cashRepositoryProvider).sessions());

/// Financeiro: contas a receber, contas a pagar e histórico de caixas.
class FinanceScreen extends ConsumerWidget {
  const FinanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(finSummaryProvider).valueOrNull ?? const FinSummary();
    final t = Theme.of(context);

    return DefaultTabController(
      length: 3,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Financeiro', style: t.textTheme.headlineSmall),
            const SizedBox(height: 12),
            ResponsiveGrid(maxColumns: 4, children: [
              KpiCard(
                label: 'A receber em aberto',
                value: money(summary.receivable.open),
                icon: Icons.call_received,
                color: Colors.green.shade700,
                subtitle: summary.receivable.overdue > 0 ? '${money(summary.receivable.overdue)} vencidos' : 'nada vencido',
              ),
              KpiCard(
                label: 'A pagar em aberto',
                value: money(summary.payable.open),
                icon: Icons.call_made,
                color: t.colorScheme.error,
                subtitle: summary.payable.overdue > 0 ? '${money(summary.payable.overdue)} vencidos' : 'nada vencido',
              ),
              KpiCard(
                label: 'Vence hoje',
                value: money(summary.payable.dueToday),
                icon: Icons.today,
                subtitle: 'receber hoje: ${money(summary.receivable.dueToday)}',
              ),
              KpiCard(
                label: 'Pagar nos próximos 7 dias',
                value: money(summary.payable.next7),
                icon: Icons.date_range,
                subtitle: 'receber: ${money(summary.receivable.next7)}',
              ),
            ]),
          ]),
        ),
        const TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(icon: Icon(Icons.call_received), text: 'A receber'),
            Tab(icon: Icon(Icons.call_made), text: 'A pagar'),
            Tab(icon: Icon(Icons.point_of_sale), text: 'Caixas'),
          ],
        ),
        const Expanded(
          child: TabBarView(children: [
            _EntriesTab(kind: 'RECEBER'),
            _EntriesTab(kind: 'PAGAR'),
            _CashSessionsTab(),
          ]),
        ),
      ]),
    );
  }
}

class _EntriesTab extends ConsumerStatefulWidget {
  const _EntriesTab({required this.kind});
  final String kind;

  @override
  ConsumerState<_EntriesTab> createState() => _EntriesTabState();
}

class _EntriesTabState extends ConsumerState<_EntriesTab> {
  final _q = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  void _refresh() {
    ref.invalidate(finEntriesProvider(widget.kind));
    ref.invalidate(finSummaryProvider);
  }

  Future<void> _new() async {
    final e = await showDialog<NewFinEntry>(context: context, builder: (_) => FinEntryDialog(kind: widget.kind));
    if (e == null || !mounted) return;
    try {
      await ref.read(financeRepositoryProvider).create(e);
      _refresh();
      if (mounted) showOk(context, 'Lançamento criado');
    } catch (err) {
      if (mounted) showError(context, err);
    }
  }

  Future<void> _settle(FinEntry e) async {
    final r = await showDialog<(double, String, bool)>(context: context, builder: (_) => SettleDialog(entry: e));
    if (r == null || !mounted) return;
    try {
      await ref.read(financeRepositoryProvider).settle(e.id, amount: r.$1, method: r.$2, fromCash: r.$3);
      _refresh();
      if (mounted) showOk(context, e.kind == 'RECEBER' ? 'Recebimento registrado' : 'Pagamento registrado');
    } catch (err) {
      if (mounted) showError(context, err);
    }
  }

  Future<void> _cancel(FinEntry e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Cancelar lançamento?'),
        content: Text(e.description),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Não')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Sim, cancelar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(financeRepositoryProvider).cancel(e.id);
      _refresh();
    } catch (err) {
      if (mounted) showError(context, err);
    }
  }

  @override
  Widget build(BuildContext context) {
    final kind = widget.kind;
    final filter = ref.watch(finFilterProvider(kind));
    final list = ref.watch(finEntriesProvider(kind));
    final compact = Breakpoints.isCompact(context);
    final receive = kind == 'RECEBER';

    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.keyN, control: true): _new},
      child: Scaffold(
        floatingActionButton: FloatingActionButton.extended(
          heroTag: 'fin-$kind',
          onPressed: _new,
          icon: const Icon(Icons.add),
          label: Text(compact ? 'Lançar' : (receive ? 'Nova conta a receber (Ctrl+N)' : 'Nova conta a pagar (Ctrl+N)')),
        ),
        body: RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            children: [
              Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                SizedBox(
                  width: compact ? double.infinity : 320,
                  child: TextField(
                    controller: _q,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: receive ? 'Descrição, cliente ou documento' : 'Descrição, fornecedor ou documento',
                    ),
                    onChanged: (v) {
                      _debounce?.cancel();
                      _debounce = Timer(const Duration(milliseconds: 300), () {
                        ref.read(finFilterProvider(kind).notifier).state = FinFilter(status: filter.status, q: v.trim());
                      });
                    },
                  ),
                ),
                for (final s in const [('ABERTOS', 'Em aberto'), ('VENCIDOS', 'Vencidos'), ('PAGOS', 'Quitados'), ('TODOS', 'Todos')])
                  ChoiceChip(
                    label: Text(s.$2),
                    selected: filter.status == s.$1,
                    onSelected: (_) => ref.read(finFilterProvider(kind).notifier).state = FinFilter(status: s.$1, q: filter.q),
                  ),
              ]),
              const SizedBox(height: 12),
              list.when(
                loading: () => const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator())),
                error: (e, _) => Card(child: ListTile(leading: const Icon(Icons.error), title: Text(e.toString()))),
                data: (items) {
                  if (items.isEmpty) {
                    return const Padding(padding: EdgeInsets.all(48), child: Center(child: Text('Nenhum lançamento')));
                  }
                  final total = items.fold<double>(0, (a, e) => a + (e.isOpen ? e.balance : 0));
                  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    if (total > 0)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text('${items.length} lançamento(s) · saldo em aberto ${money(total)}',
                            style: Theme.of(context).textTheme.labelLarge),
                      ),
                    Card(
                      child: Column(children: [
                        for (var i = 0; i < items.length; i++) ...[
                          if (i > 0) const Divider(height: 1),
                          _EntryTile(e: items[i], onSettle: () => _settle(items[i]), onCancel: () => _cancel(items[i])),
                        ],
                      ]),
                    ),
                  ]);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.e, required this.onSettle, required this.onCancel});
  final FinEntry e;
  final VoidCallback onSettle, onCancel;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final (label, color) = switch (e.status) {
      'VENCIDO' => ('Vencido', t.colorScheme.error),
      'PARCIAL' => ('Parcial', Colors.orange.shade800),
      'PAGO' => (e.kind == 'RECEBER' ? 'Recebido' : 'Pago', Colors.green.shade700),
      'CANCELADO' => ('Cancelado', t.colorScheme.outline),
      _ => ('Em aberto', t.colorScheme.primary),
    };
    final origin = switch (e.origin) { 'VENDA' => 'Venda', 'COMPRA' => 'Compra', _ => e.category };
    final info = [
      'vence ${dateBr(e.dueDate)}',
      if (e.partnerName != null) e.partnerName!,
      if (origin != null) origin,
      if (e.document != null) 'doc ${e.document}',
    ].join(' · ');

    return ListTile(
      onTap: e.isOpen ? onSettle : null,
      title: Text(e.description, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(info, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(money(e.isOpen ? e.balance : e.amount), style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
        if (e.isOpen)
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'settle') {
                onSettle();
              } else {
                onCancel();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'settle', child: Text(e.kind == 'RECEBER' ? 'Receber' : 'Pagar')),
              if (e.paidAmount == 0) const PopupMenuItem(value: 'cancel', child: Text('Cancelar')),
            ],
          ),
      ]),
    );
  }
}

class _CashSessionsTab extends ConsumerWidget {
  const _CashSessionsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(cashSessionsProvider);
    final t = Theme.of(context);
    return RefreshIndicator(
      onRefresh: () => ref.refresh(cashSessionsProvider.future),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          list.when(
            loading: () => const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator())),
            error: (e, _) => Card(child: ListTile(leading: const Icon(Icons.error), title: Text(e.toString()))),
            data: (items) => items.isEmpty
                ? const Padding(padding: EdgeInsets.all(48), child: Center(child: Text('Nenhum caixa aberto ainda')))
                : Card(
                    child: Column(children: [
                      for (var i = 0; i < items.length; i++) ...[
                        if (i > 0) const Divider(height: 1),
                        Builder(builder: (context) {
                          final s = items[i];
                          final diff = s.difference;
                          return ListTile(
                            leading: Icon(s.status == 'ABERTO' ? Icons.lock_open : Icons.lock_outline,
                                color: s.status == 'ABERTO' ? Colors.green.shade700 : null),
                            title: Text('${s.operator} · ${dateTimeBr(s.openedAt)}'),
                            subtitle: Text(
                              '${s.salesCount} venda(s) · ${money(s.salesTotal)} · abertura ${money(s.opening)}'
                              '${s.closedAt != null ? ' · fechado ${dateTimeBr(s.closedAt)}' : ' · aberto'}',
                            ),
                            trailing: diff == null
                                ? null
                                : Text(
                                    diff.abs() < 0.005 ? 'bateu' : (diff > 0 ? 'sobra ${money(diff)}' : 'falta ${money(-diff)}'),
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: diff.abs() < 0.005
                                          ? Colors.green.shade700
                                          : (diff > 0 ? Colors.orange.shade800 : t.colorScheme.error),
                                    ),
                                  ),
                          );
                        }),
                      ],
                    ]),
                  ),
          ),
        ],
      ),
    );
  }
}
