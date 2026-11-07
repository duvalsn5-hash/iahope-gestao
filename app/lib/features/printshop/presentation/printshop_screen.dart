import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../partners/domain/partner.dart';
import '../../partners/presentation/partner_picker_dialog.dart';
import '../data/printshop_repository.dart';
import '../domain/printshop.dart';
import 'order_page.dart';

final _filter = StateProvider.autoDispose<(String, String)>((_) => ('ABERTOS', ''));
final printOrdersProvider = FutureProvider.autoDispose<List<OrderRow>>((ref) {
  final f = ref.watch(_filter);
  return ref.read(printshopRepositoryProvider).orders(status: f.$1, q: f.$2);
});
final printSummaryProvider = FutureProvider.autoDispose((ref) {
  ref.watch(printOrdersProvider);
  return ref.read(printshopRepositoryProvider).summary();
});

/// Estamparia e personalizados: quadro de produção dos pedidos sob encomenda.
/// Atalhos: Ctrl+N novo pedido · Ctrl+F buscar
class PrintshopScreen extends ConsumerStatefulWidget {
  const PrintshopScreen({super.key});

  @override
  ConsumerState<PrintshopScreen> createState() => _PrintshopScreenState();
}

class _PrintshopScreenState extends ConsumerState<PrintshopScreen> {
  final _searchFocus = FocusNode();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _new() async {
    final data = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => const _NewOrderDialog());
    if (data == null || !mounted) return;
    try {
      final o = await ref.read(printshopRepositoryProvider).create(data);
      ref.invalidate(printOrdersProvider);
      if (mounted) await _open(o.id);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _open(String id) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => OrderPage(orderId: id)));
    ref.invalidate(printOrdersProvider);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final f = ref.watch(_filter);
    final list = ref.watch(printOrdersProvider);
    final sum = ref.watch(printSummaryProvider).valueOrNull;
    final wide = MediaQuery.sizeOf(context).width >= 1100;
    final board = wide && f.$1 == 'ABERTOS';

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): _new,
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () => _searchFocus.requestFocus(),
      },
      child: Scaffold(
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _new,
          icon: const Icon(Icons.add),
          label: Text(Breakpoints.isCompact(context) ? 'Pedido' : 'Novo pedido (Ctrl+N)'),
        ),
        body: RefreshIndicator(
          onRefresh: () => ref.refresh(printOrdersProvider.future),
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), children: [
            Text('Estamparia e personalizados', style: t.textTheme.headlineSmall),
            const SizedBox(height: 12),
            ResponsiveGrid(maxColumns: 6, children: [
              KpiCard(label: 'Orçamentos', value: '${sum?.of('orcamento') ?? 0}', icon: OrderStatus.orcamento.icon),
              KpiCard(label: 'Aprovados', value: '${sum?.of('aprovado') ?? 0}', icon: OrderStatus.aprovado.icon, color: Colors.indigo),
              KpiCard(label: 'Em produção', value: '${sum?.of('producao') ?? 0}', icon: OrderStatus.producao.icon, color: Colors.orange.shade800),
              KpiCard(label: 'Prontos p/ entregar', value: '${sum?.of('pronto') ?? 0}', icon: OrderStatus.pronto.icon, color: Colors.green.shade700),
              KpiCard(label: 'Atrasados', value: '${sum?.of('atrasados') ?? 0}', icon: Icons.alarm, color: t.colorScheme.error),
              KpiCard(label: 'Sinais em aberto', value: money(sum?.deposits ?? 0), icon: Icons.savings_outlined),
            ]),
            const SizedBox(height: 12),
            const _Guide(),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              SizedBox(
                width: Breakpoints.isCompact(context) ? double.infinity : 340,
                child: TextField(
                  focusNode: _searchFocus,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Nº, cliente ou descrição (Ctrl+F)'),
                  onChanged: (v) {
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 300), () => ref.read(_filter.notifier).state = (f.$1, v.trim()));
                  },
                ),
              ),
              for (final s in const [('ABERTOS', 'Em andamento'), ('ENTREGUES', 'Entregues'), ('CANCELADOS', 'Cancelados'), ('TODOS', 'Todos')])
                ChoiceChip(
                  label: Text(s.$2),
                  selected: f.$1 == s.$1,
                  onSelected: (_) => ref.read(_filter.notifier).state = (s.$1, f.$2),
                ),
            ]),
            const SizedBox(height: 12),
            list.when(
              loading: () => const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator())),
              error: (e, _) => Card(child: ListTile(leading: const Icon(Icons.error), title: Text(e.toString()))),
              data: (items) {
                if (items.isEmpty) {
                  return const Padding(padding: EdgeInsets.all(48), child: Center(child: Text('Nenhum pedido aqui')));
                }
                if (!board) {
                  return Column(children: [for (final o in items) _OrderCard(o: o, onTap: () => _open(o.id))]);
                }
                return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (final st in kBoard)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: st.color.withValues(alpha: .07),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            Row(children: [
                              Icon(st.icon, size: 18, color: st.color),
                              const SizedBox(width: 6),
                              Text(st.label, style: t.textTheme.titleSmall?.copyWith(color: st.color)),
                              const Spacer(),
                              Text('${items.where((o) => o.status == st).length}'),
                            ]),
                            const SizedBox(height: 8),
                            for (final o in items.where((o) => o.status == st)) _OrderCard(o: o, onTap: () => _open(o.id), compact: true),
                          ]),
                        ),
                      ),
                    ),
                ]);
              },
            ),
          ]),
        ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.o, required this.onTap, this.compact = false});
  final OrderRow o;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (o.artUrl != null)
              Padding(padding: const EdgeInsets.only(right: 10), child: ProductThumb(url: o.artUrl, size: compact ? 44 : 56, icon: Icons.image)),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text('#${o.number} ', style: const TextStyle(fontWeight: FontWeight.w800)),
                  Expanded(child: Text(o.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
                ]),
                Text(o.customerName, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textTheme.bodySmall),
                const SizedBox(height: 4),
                Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  _Tag(techniqueLabel(o.technique), t.colorScheme.secondaryContainer),
                  Text('${number(o.pieces)} pç · ${money(o.total)}', style: t.textTheme.bodySmall),
                  if (o.dueDate != null)
                    Text(
                      '${o.late ? 'ATRASADO · ' : ''}entrega ${dateBr(o.dueDate)}',
                      style: TextStyle(fontSize: 12, color: o.late ? t.colorScheme.error : null, fontWeight: o.late ? FontWeight.w700 : null),
                    ),
                  if (!compact) _Tag(o.status.label, o.status.color.withValues(alpha: .15)),
                  if (o.deposit > 0) Text('sinal ${money(o.deposit)}', style: t.textTheme.bodySmall),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, this.bg);
  final String text;
  final Color bg;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
        child: Text(text, style: const TextStyle(fontSize: 11)),
      );
}

class _Guide extends StatelessWidget {
  const _Guide();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    const steps = [
      ('Orçamento', 'Novo pedido: cliente, o que vai estampar, grade de tamanhos e preço. Mande pelo WhatsApp.'),
      ('Aprovado', 'Cliente aprovou a arte e o valor. Receba o sinal (entra no caixa).'),
      ('Produção', 'Imprima a ordem de produção com a grade e a arte para a equipe.'),
      ('Pronto → Entregue', 'Avise o cliente e receba o restante no caixa. As peças lisas baixam do estoque.'),
    ];
    return Card(
      color: t.colorScheme.primaryContainer.withValues(alpha: .35),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(spacing: 16, runSpacing: 8, children: [
          for (final (i, s) in steps.indexed)
            SizedBox(
              width: 260,
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                CircleAvatar(radius: 12, child: Text('${i + 1}', style: const TextStyle(fontSize: 12))),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s.$1, style: t.textTheme.titleSmall),
                    Text(s.$2, style: t.textTheme.bodySmall),
                  ]),
                ),
              ]),
            ),
        ]),
      ),
    );
  }
}

/// Começo do pedido: cliente, descrição, técnica e prazo. Os itens vêm na tela do pedido.
class _NewOrderDialog extends StatefulWidget {
  const _NewOrderDialog();

  @override
  State<_NewOrderDialog> createState() => _NewOrderDialogState();
}

class _NewOrderDialogState extends State<_NewOrderDialog> {
  Partner? _customer;
  final _title = TextEditingController();
  String _technique = 'DTF';
  DateTime? _due = DateTime.now().add(const Duration(days: 7));

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final p = await showDialog<Partner>(context: context, builder: (_) => const PartnerPickerDialog());
    if (p != null) setState(() => _customer = p);
  }

  @override
  Widget build(BuildContext context) {
    final ok = _customer != null && _title.text.trim().length >= 2;
    return AlertDialog(
      title: const Text('Novo pedido'),
      content: SizedBox(
        width: 480,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.person_outline),
            title: Text(_customer?.displayName ?? 'Cliente'),
            subtitle: Text(_customer == null ? 'Escolha ou cadastre o cliente' : (_customer!.phone ?? 'sem telefone')),
            trailing: OutlinedButton(onPressed: _pick, child: Text(_customer == null ? 'Escolher' : 'Trocar')),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _title,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'O que é o pedido?', hintText: 'Ex.: Camisetas da formatura 3º ano'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _technique,
            decoration: const InputDecoration(labelText: 'Técnica'),
            items: [for (final (k, v) in kTechniques) DropdownMenuItem(value: k, child: Text(v))],
            onChanged: (v) => setState(() => _technique = v ?? 'DTF'),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _due ?? DateTime.now(),
                firstDate: DateTime.now().subtract(const Duration(days: 1)),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (d != null) setState(() => _due = d);
            },
            child: InputDecorator(
              decoration: const InputDecoration(labelText: 'Prazo de entrega', prefixIcon: Icon(Icons.event)),
              child: Text(_due == null ? 'Sem prazo' : dateBr(_due)),
            ),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: !ok
              ? null
              : () => Navigator.pop(context, {
                    'customerId': _customer!.id,
                    'title': _title.text.trim(),
                    'technique': _technique,
                    if (_due != null) 'dueDate': isoDate(_due!),
                    'items': <Map<String, dynamic>>[],
                  }),
          child: const Text('Criar e montar itens'),
        ),
      ],
    );
  }
}
