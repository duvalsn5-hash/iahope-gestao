import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/whatsapp.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../auth/presentation/session_controller.dart';
import '../../partners/domain/partner.dart';
import '../../partners/presentation/partner_picker_dialog.dart';
import '../../pos/presentation/pos_controller.dart';
import '../../products/data/products_repository.dart';
import '../../products/domain/product.dart';
import '../../products/presentation/product_picker_dialog.dart';
import '../data/fashion_repository.dart';
import '../data/label_printer.dart';
import '../domain/fashion.dart';
import 'grade_dialog.dart';
import 'labels_dialog.dart';

final _gradeQuery = StateProvider.autoDispose<String>((_) => '');
final gradesProvider = FutureProvider.autoDispose<List<GradeModel>>(
    (ref) => ref.read(fashionRepositoryProvider).grades(q: ref.watch(_gradeQuery)));
final _voucherQuery = StateProvider.autoDispose<(String, bool)>((_) => ('', true));
final vouchersProvider = FutureProvider.autoDispose<List<Voucher>>((ref) {
  final f = ref.watch(_voucherQuery);
  return ref.read(fashionRepositoryProvider).vouchers(q: f.$1, openOnly: f.$2);
});
final _consStatus = StateProvider.autoDispose<String>((_) => 'ABERTA');
final consignmentsProvider = FutureProvider.autoDispose<List<Consignment>>(
    (ref) => ref.read(fashionRepositoryProvider).consignments(status: ref.watch(_consStatus)));

/// Loja de roupas e calçados: grade, etiquetas, trocas com vale e condicional.
class FashionScreen extends ConsumerWidget {
  const FashionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manager = ref.watch(sessionControllerProvider)?.isManager ?? false;
    final tabs = [
      const Tab(icon: Icon(Icons.grid_on), text: 'Grade e etiquetas'),
      const Tab(icon: Icon(Icons.swap_horiz), text: 'Trocas'),
      const Tab(icon: Icon(Icons.confirmation_number_outlined), text: 'Vales-troca'),
      const Tab(icon: Icon(Icons.shopping_bag_outlined), text: 'Condicional'),
    ];
    return DefaultTabController(
      length: tabs.length,
      child: Column(children: [
        TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: tabs),
        Expanded(
          child: TabBarView(children: [
            _GradeTab(canEdit: manager),
            const _ReturnsTab(),
            const _VouchersTab(),
            const _ConsignmentsTab(),
          ]),
        ),
      ]),
    );
  }
}

// ===================================================================== GRADE
class _GradeTab extends ConsumerStatefulWidget {
  const _GradeTab({required this.canEdit});
  final bool canEdit;

  @override
  ConsumerState<_GradeTab> createState() => _GradeTabState();
}

class _GradeTabState extends ConsumerState<_GradeTab> {
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<List<String>> _categories() async {
    final s = ref.read(sessionControllerProvider);
    final used = await ref.read(productsRepositoryProvider).categories().catchError((_) => <(String, int)>[]);
    return <String>{...?s?.business.productCategories, for (final c in used) c.$1}.toList()..sort();
  }

  Future<void> _new([GradeModel? existing]) async {
    final cats = await _categories();
    if (!mounted) return;
    final g = await showDialog<NewGrade>(context: context, builder: (_) => GradeDialog(existing: existing, categories: cats));
    if (g == null || !mounted) return;
    try {
      final created = await ref.read(fashionRepositoryProvider).saveGrade(g);
      ref.invalidate(gradesProvider);
      if (!mounted) return;
      showOk(context, '${created.length} produto(s) criado(s) com código de barras');
      final withStock = [for (final p in created) if (p.stockQty > 0) (p, p.stockQty.ceil())];
      if (withStock.isNotEmpty) {
        final print = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Imprimir as etiquetas?'),
            content: Text('Uma etiqueta para cada peça em estoque (${withStock.fold<int>(0, (a, e) => a + e.$2)} no total).'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Agora não')),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Montar etiquetas')),
            ],
          ),
        );
        if (print == true && mounted) await showDialog<void>(context: context, builder: (_) => LabelsDialog(initial: withStock));
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _open(GradeModel g) async {
    final action = await showDialog<String>(context: context, builder: (_) => _GradeDetail(g: g, canEdit: widget.canEdit));
    if (!mounted || action == null) return;
    switch (action) {
      case 'add':
        await _new(g);
      case 'labels':
        await showDialog<void>(
          context: context,
          builder: (_) => LabelsDialog(initial: [for (final v in g.variants) if (v.stockQty > 0) (v, v.stockQty.ceil())]),
        );
      case 'edit':
        await _editPrice(g);
    }
  }

  Future<void> _editPrice(GradeModel g) async {
    final name = TextEditingController(text: g.model);
    final price = TextEditingController(text: g.price.toStringAsFixed(2).replaceAll('.', ','));
    final cost = TextEditingController(text: g.cost == 0 ? '' : g.cost.toStringAsFixed(2).replaceAll('.', ','));
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Nome e preço do modelo'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Modelo')),
          const SizedBox(height: 12),
          TextField(controller: price, decoration: const InputDecoration(labelText: 'Preço (todas as combinações)', prefixText: r'R$ ')),
          const SizedBox(height: 12),
          TextField(controller: cost, decoration: const InputDecoration(labelText: 'Custo', prefixText: r'R$ ')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Salvar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(fashionRepositoryProvider).updateGrade(g.gradeId,
          model: name.text.trim(), category: g.category, price: parseMoney(price.text), cost: parseMoney(cost.text));
      ref.invalidate(gradesProvider);
      if (mounted) showOk(context, 'Modelo atualizado');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(gradesProvider);
    final compact = Breakpoints.isCompact(context);
    return CallbackShortcuts(
      bindings: {if (widget.canEdit) const SingleActivator(LogicalKeyboardKey.keyN, control: true): () => _new()},
      child: Scaffold(
        floatingActionButton: widget.canEdit
            ? FloatingActionButton.extended(
                onPressed: () => _new(),
                icon: const Icon(Icons.add),
                label: Text(compact ? 'Modelo' : 'Novo modelo (Ctrl+N)'),
              )
            : null,
        body: RefreshIndicator(
          onRefresh: () => ref.refresh(gradesProvider.future),
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), children: [
            const _StepsCard(steps: [
              ('Cadastre o modelo', 'Nome, preço, tamanhos e cores. Cada combinação vira um produto com código de barras.'),
              ('Imprima as etiquetas', 'Folha A4 ou rolo térmico, com preço e código de barras.'),
              ('Venda no PDV', 'Bipe a etiqueta: entra o tamanho e a cor certos e o estoque baixa sozinho.'),
            ]),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              SizedBox(
                width: compact ? double.infinity : 360,
                child: TextField(
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Modelo, categoria ou código'),
                  onChanged: (v) {
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 300), () => ref.read(_gradeQuery.notifier).state = v.trim());
                  },
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => showDialog<void>(context: context, builder: (_) => const LabelsDialog()),
                icon: const Icon(Icons.label_outline),
                label: const Text('Etiquetas avulsas'),
              ),
            ]),
            const SizedBox(height: 12),
            list.when(
              loading: () => const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator())),
              error: (e, _) => Card(child: ListTile(leading: const Icon(Icons.error), title: Text(e.toString()))),
              data: (items) => items.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(48),
                      child: Center(child: Text('Nenhum modelo com grade ainda. Toque em "Novo modelo".')),
                    )
                  : ResponsiveGrid(maxColumns: 3, children: [for (final g in items) _GradeCard(g: g, onTap: () => _open(g))]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _GradeCard extends StatelessWidget {
  const _GradeCard({required this.g, required this.onTap});
  final GradeModel g;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final zero = g.variants.where((v) => v.stockQty <= 0).length;
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            ProductThumb(url: g.imageUrl, size: 64, icon: Icons.checkroom_outlined),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(g.model, style: t.textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text('${g.category ?? 'Sem categoria'} · ${money(g.price)}', style: t.textTheme.bodySmall),
                const SizedBox(height: 4),
                Text('Tam: ${g.sizes.join(' ')}', maxLines: 1, overflow: TextOverflow.ellipsis),
                Text('Cores: ${g.colors.join(', ')}', maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Row(children: [
                  Text('${number(g.totalStock)} peças', style: const TextStyle(fontWeight: FontWeight.w700)),
                  if (zero > 0) ...[
                    const SizedBox(width: 8),
                    Text('$zero sem estoque', style: TextStyle(color: t.colorScheme.error, fontSize: 12)),
                  ],
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Grade do modelo: linhas = cores, colunas = tamanhos, valor = estoque.
class _GradeDetail extends StatelessWidget {
  const _GradeDetail({required this.g, required this.canEdit});
  final GradeModel g;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return AlertDialog(
      title: Text(g.model),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('${g.category ?? 'Sem categoria'} · ${money(g.price)} · ${number(g.totalStock)} peças', style: t.textTheme.bodyMedium),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 18,
                headingRowHeight: 36,
                dataRowMinHeight: 36,
                dataRowMaxHeight: 40,
                columns: [
                  const DataColumn(label: Text('Cor')),
                  for (final s in g.sizes) DataColumn(label: Text(s), numeric: true),
                  const DataColumn(label: Text('Total'), numeric: true),
                ],
                rows: [
                  for (final c in g.colors)
                    DataRow(cells: [
                      DataCell(Text(c)),
                      for (final s in g.sizes)
                        DataCell(Builder(builder: (_) {
                          final v = g.variant(c, s);
                          if (v == null) return const Text('—');
                          return Tooltip(
                            message: '${v.barcode ?? v.sku}\n${v.sku}',
                            child: Text(number(v.stockQty),
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: v.stockQty <= 0 ? t.colorScheme.error : null,
                                )),
                          );
                        })),
                      DataCell(Text(number(g.variants.where((v) => v.color == c).fold<double>(0, (a, v) => a + v.stockQty)))),
                    ]),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text('Para dar entrada de estoque numa combinação, use Produtos (Alt+P) ou importe o XML da nota.',
                style: t.textTheme.bodySmall),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar')),
        if (canEdit) TextButton(onPressed: () => Navigator.pop(context, 'edit'), child: const Text('Nome e preço')),
        if (canEdit) OutlinedButton(onPressed: () => Navigator.pop(context, 'add'), child: const Text('+ Tamanhos/cores')),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, 'labels'),
          icon: const Icon(Icons.label_outline),
          label: const Text('Etiquetas'),
        ),
      ],
    );
  }
}

// ==================================================================== TROCAS
class _ReturnsTab extends ConsumerStatefulWidget {
  const _ReturnsTab();

  @override
  ConsumerState<_ReturnsTab> createState() => _ReturnsTabState();
}

class _ReturnsTabState extends ConsumerState<_ReturnsTab> {
  final _number = TextEditingController();
  final _reason = TextEditingController();
  SaleForReturn? _sale;
  final Map<int, double> _qty = {};
  String _mode = 'VALE';
  int _validDays = 90;
  bool _busy = false;

  @override
  void dispose() {
    _number.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _find() async {
    final n = int.tryParse(_number.text.trim());
    if (n == null) return;
    setState(() => _busy = true);
    try {
      final s = await ref.read(fashionRepositoryProvider).saleByNumber(n);
      setState(() {
        _sale = s;
        _qty.clear();
      });
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  double get _amount {
    final s = _sale;
    if (s == null) return 0;
    return s.items.fold<double>(0, (a, i) => a + (_qty[i.id] ?? 0) * i.paidUnit);
  }

  Future<void> _confirm() async {
    final s = _sale!;
    setState(() => _busy = true);
    try {
      final r = await ref.read(fashionRepositoryProvider).returnItems(
            saleId: s.id,
            items: _qty,
            mode: _mode,
            customerId: s.customerId,
            reason: _reason.text.trim(),
            validDays: _validDays,
          );
      if (!mounted) return;
      ref.invalidate(vouchersProvider);
      await showDialog<void>(context: context, builder: (_) => _ReturnDoneDialog(r: r, customer: s.customerName, validDays: _validDays));
      setState(() {
        _sale = null;
        _qty.clear();
        _number.clear();
        _reason.clear();
      });
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final s = _sale;
    return ListView(padding: const EdgeInsets.all(16), children: [
      const _StepsCard(steps: [
        ('Ache a venda', 'Digite o número do cupom (aparece no topo do cupom: "Venda nº").'),
        ('Marque o que voltou', 'Escolha as peças e quantas. As peças voltam para o estoque.'),
        ('Vale ou dinheiro', 'Vale-troca: a cliente usa como pagamento no PDV. Dinheiro: sai da gaveta do caixa.'),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        SizedBox(
          width: 220,
          child: TextField(
            controller: _number,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Nº do cupom', prefixIcon: Icon(Icons.receipt_long_outlined)),
            onSubmitted: (_) => _find(),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(onPressed: _busy ? null : _find, icon: const Icon(Icons.search), label: const Text('Buscar')),
      ]),
      if (s != null) ...[
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Venda nº ${s.number} · ${dateTimeBr(s.createdAt)}', style: t.textTheme.titleMedium),
              Text('${s.customerName ?? 'Consumidor final'} · total ${money(s.total)}'
                  '${s.discount > 0 ? ' (desconto ${money(s.discount)})' : ''}'),
              if (s.status != 'FINALIZADA')
                Text('Venda ${s.status.toLowerCase()} — não aceita troca', style: TextStyle(color: t.colorScheme.error)),
              const Divider(),
              for (final i in s.items)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(i.description),
                  subtitle: Text('Comprou ${number(i.qty)} · já voltou ${number(i.returnedQty)} · pago ${money(i.paidUnit)} cada'),
                  trailing: i.available <= 0 || i.productId == null || s.status != 'FINALIZADA'
                      ? const Text('—')
                      : Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(
                            icon: const Icon(Icons.remove),
                            onPressed: (_qty[i.id] ?? 0) <= 0 ? null : () => setState(() => _qty[i.id] = (_qty[i.id] ?? 0) - 1),
                          ),
                          SizedBox(width: 28, child: Text(number(_qty[i.id] ?? 0), textAlign: TextAlign.center)),
                          IconButton(
                            icon: const Icon(Icons.add),
                            onPressed: (_qty[i.id] ?? 0) >= i.available ? null : () => setState(() => _qty[i.id] = (_qty[i.id] ?? 0) + 1),
                          ),
                        ]),
                ),
              const Divider(),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'VALE', icon: Icon(Icons.confirmation_number_outlined), label: Text('Vale-troca')),
                  ButtonSegment(value: 'DINHEIRO', icon: Icon(Icons.payments_outlined), label: Text('Devolver dinheiro')),
                ],
                selected: {_mode},
                onSelectionChanged: (v) => setState(() => _mode = v.first),
              ),
              const SizedBox(height: 8),
              if (_mode == 'VALE')
                DropdownButtonFormField<int>(
                  initialValue: _validDays,
                  decoration: const InputDecoration(labelText: 'Validade do vale'),
                  items: const [
                    DropdownMenuItem(value: 30, child: Text('30 dias')),
                    DropdownMenuItem(value: 60, child: Text('60 dias')),
                    DropdownMenuItem(value: 90, child: Text('90 dias')),
                    DropdownMenuItem(value: 180, child: Text('180 dias')),
                    DropdownMenuItem(value: 0, child: Text('Sem validade')),
                  ],
                  onChanged: (v) => setState(() => _validDays = v ?? 90),
                )
              else
                Text('Precisa de caixa aberto; o valor sai da gaveta.', style: t.textTheme.bodySmall),
              const SizedBox(height: 8),
              TextField(controller: _reason, decoration: const InputDecoration(labelText: 'Motivo (opcional)', hintText: 'Ex.: tamanho')),
              const SizedBox(height: 12),
              Row(children: [
                Text('A devolver: ', style: t.textTheme.titleMedium),
                Text(money(_amount), style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _amount <= 0 || _busy ? null : _confirm,
                  icon: const Icon(Icons.check),
                  label: Text(_mode == 'VALE' ? 'Gerar vale-troca' : 'Devolver em dinheiro'),
                ),
              ]),
            ]),
          ),
        ),
      ],
    ]);
  }
}

class _ReturnDoneDialog extends ConsumerWidget {
  const _ReturnDoneDialog({required this.r, this.customer, required this.validDays});
  final ReturnResult r;
  final String? customer;
  final int validDays;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final company = ref.read(sessionControllerProvider)?.tenant.nomeFantasia ?? '';
    final expires = validDays > 0 ? DateTime.now().add(Duration(days: validDays)) : null;
    return AlertDialog(
      icon: Icon(r.isVoucher ? Icons.confirmation_number : Icons.payments, size: 40, color: t.colorScheme.primary),
      title: Text(r.isVoucher ? 'Vale-troca gerado' : 'Devolução registrada'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        if (r.isVoucher) SelectableText(r.code ?? '', style: t.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
        Text(money(r.amount), style: t.textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(r.isVoucher
            ? 'Entregue o código à cliente. No PDV, escolha "Vale-troca" (F7) no pagamento.'
            : 'Entregue o dinheiro à cliente. As peças já voltaram ao estoque.'),
        if (expires != null && r.isVoucher) Text('Válido até ${dateBr(expires)}', style: t.textTheme.bodySmall),
      ]),
      actions: [
        if (r.isVoucher)
          OutlinedButton.icon(
            onPressed: () => LabelPrinter.printVoucher(r, company: company, customer: customer, expiresAt: expires),
            icon: const Icon(Icons.print),
            label: const Text('Imprimir vale'),
          ),
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
      ],
    );
  }
}

// ===================================================================== VALES
class _VouchersTab extends ConsumerWidget {
  const _VouchersTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final f = ref.watch(_voucherQuery);
    final list = ref.watch(vouchersProvider);
    return RefreshIndicator(
      onRefresh: () => ref.refresh(vouchersProvider.future),
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SizedBox(
            width: 320,
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Código ou cliente'),
              onSubmitted: (v) => ref.read(_voucherQuery.notifier).state = (v.trim(), f.$2),
            ),
          ),
          FilterChip(
            label: const Text('Só com saldo'),
            selected: f.$2,
            onSelected: (v) => ref.read(_voucherQuery.notifier).state = (f.$1, v),
          ),
        ]),
        const SizedBox(height: 12),
        list.when(
          loading: () => const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator())),
          error: (e, _) => Card(child: ListTile(leading: const Icon(Icons.error), title: Text(e.toString()))),
          data: (items) => items.isEmpty
              ? const Padding(padding: EdgeInsets.all(48), child: Center(child: Text('Nenhum vale-troca')))
              : Card(
                  child: Column(children: [
                    for (final v in items)
                      ListTile(
                        leading: Icon(Icons.confirmation_number_outlined,
                            color: v.balance <= 0 || v.expired ? t.colorScheme.outline : t.colorScheme.primary),
                        title: Text('${v.code} · saldo ${money(v.balance)}'),
                        subtitle: Text([
                          'emitido ${dateBr(v.createdAt)} (${money(v.amount)})',
                          if (v.originSale != null) 'venda nº ${v.originSale}',
                          if (v.customerName != null) v.customerName!,
                          if (v.expiresAt != null) (v.expired ? 'VENCIDO em ' : 'vale até ') + dateBr(v.expiresAt!),
                        ].join(' · ')),
                      ),
                  ]),
                ),
        ),
      ]),
    );
  }
}

// =============================================================== CONDICIONAL
class _ConsignmentsTab extends ConsumerWidget {
  const _ConsignmentsTab();

  Future<void> _new(BuildContext context, WidgetRef ref) async {
    final c = await showDialog<Consignment>(context: context, builder: (_) => const _NewConsignmentDialog());
    if (c == null || !context.mounted) return;
    ref.invalidate(consignmentsProvider);
    showOk(context, 'Condicional nº ${c.number} aberta — ${number(c.pieces)} peça(s) separadas do estoque');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final status = ref.watch(_consStatus);
    final list = ref.watch(consignmentsProvider);
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _new(context, ref),
        icon: const Icon(Icons.shopping_bag_outlined),
        label: const Text('Nova condicional'),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(consignmentsProvider.future),
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), children: [
          const _StepsCard(steps: [
            ('Separe as peças', 'Escolha a cliente e as peças que ela vai levar para provar. Elas saem do estoque.'),
            ('Combine a volta', 'Defina a data. Use o WhatsApp para lembrar a cliente.'),
            ('Faça o acerto', 'Marque o que voltou. O que ela ficou vai direto para o PDV para receber.'),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 8, children: [
            for (final s in const [('ABERTA', 'Com a cliente'), ('FECHADA', 'Acertadas'), ('TODAS', 'Todas')])
              ChoiceChip(
                label: Text(s.$2),
                selected: status == s.$1,
                onSelected: (_) => ref.read(_consStatus.notifier).state = s.$1,
              ),
          ]),
          const SizedBox(height: 12),
          list.when(
            loading: () => const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator())),
            error: (e, _) => Card(child: ListTile(leading: const Icon(Icons.error), title: Text(e.toString()))),
            data: (items) => items.isEmpty
                ? const Padding(padding: EdgeInsets.all(48), child: Center(child: Text('Nenhuma condicional')))
                : Column(children: [
                    for (final c in items)
                      Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: c.overdue ? t.colorScheme.errorContainer : t.colorScheme.secondaryContainer,
                            child: Text('${c.number}'),
                          ),
                          title: Text(c.customerName),
                          subtitle: Text([
                            '${number(c.pieces)} peça(s) · ${money(c.total)}',
                            if (c.dueDate != null) (c.overdue ? 'ATRASADA desde ' : 'volta em ') + dateBr(c.dueDate!),
                            if (!c.isOpen) c.status.toLowerCase(),
                          ].join(' · ')),
                          trailing: c.isOpen ? const Icon(Icons.chevron_right) : null,
                          onTap: () async {
                            final changed = await showDialog<bool>(context: context, builder: (_) => _ConsignmentDialog(id: c.id));
                            if (changed == true) ref.invalidate(consignmentsProvider);
                          },
                        ),
                      ),
                  ]),
          ),
        ]),
      ),
    );
  }
}

class _NewConsignmentDialog extends ConsumerStatefulWidget {
  const _NewConsignmentDialog();

  @override
  ConsumerState<_NewConsignmentDialog> createState() => _NewConsignmentDialogState();
}

class _NewConsignmentDialogState extends ConsumerState<_NewConsignmentDialog> {
  Partner? _customer;
  final List<(Product, double)> _items = [];
  DateTime _due = DateTime.now().add(const Duration(days: 3));
  final _notes = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickCustomer() async {
    final p = await showDialog<Partner>(context: context, builder: (_) => const PartnerPickerDialog());
    if (p != null) setState(() => _customer = p);
  }

  Future<void> _addPiece() async {
    final p = await showDialog<Product>(context: context, builder: (_) => const ProductPickerDialog(title: 'Peça para a condicional'));
    if (p == null) return;
    setState(() {
      final i = _items.indexWhere((e) => e.$1.id == p.id);
      if (i >= 0) {
        _items[i] = (p, _items[i].$2 + 1);
      } else {
        _items.add((p, 1));
      }
    });
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final c = await ref.read(fashionRepositoryProvider).openConsignment(
            customerId: _customer!.id,
            items: _items,
            dueDate: _due,
            notes: _notes.text.trim(),
          );
      if (mounted) Navigator.pop(context, c);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _items.fold<double>(0, (a, e) => a + e.$1.price * e.$2);
    return AlertDialog(
      title: const Text('Nova condicional'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.person_outline),
              title: Text(_customer?.displayName ?? 'Escolha a cliente'),
              subtitle: _customer?.phone != null ? Text(_customer!.phone!) : null,
              trailing: OutlinedButton(onPressed: _pickCustomer, child: Text(_customer == null ? 'Escolher' : 'Trocar')),
            ),
            const Divider(),
            for (final (i, e) in _items.indexed)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: ProductThumb(url: e.$1.imageUrl, size: 36),
                title: Text(e.$1.name),
                subtitle: Text('${money(e.$1.price)} · estoque ${number(e.$1.stockQty)}'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    icon: const Icon(Icons.remove),
                    onPressed: () => setState(() => e.$2 <= 1 ? _items.removeAt(i) : _items[i] = (e.$1, e.$2 - 1)),
                  ),
                  Text(number(e.$2)),
                  IconButton(icon: const Icon(Icons.add), onPressed: () => setState(() => _items[i] = (e.$1, e.$2 + 1))),
                ]),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(onPressed: _addPiece, icon: const Icon(Icons.add), label: const Text('Adicionar peça (bipe ou busque)')),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _due,
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 60)),
                );
                if (d != null) setState(() => _due = d);
              },
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Data para devolver / acertar', prefixIcon: Icon(Icons.event)),
                child: Text(dateBr(_due)),
              ),
            ),
            const SizedBox(height: 8),
            TextField(controller: _notes, decoration: const InputDecoration(labelText: 'Observação (opcional)')),
            const SizedBox(height: 8),
            Text('${_items.length} peça(s) · ${money(total)}', style: Theme.of(context).textTheme.titleMedium),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: _customer == null || _items.isEmpty || _busy ? null : _save,
          child: const Text('Separar peças'),
        ),
      ],
    );
  }
}

/// Detalhe da condicional: acerto (o que voltou) e lembrete por WhatsApp.
class _ConsignmentDialog extends ConsumerStatefulWidget {
  const _ConsignmentDialog({required this.id});
  final String id;

  @override
  ConsumerState<_ConsignmentDialog> createState() => _ConsignmentDialogState();
}

class _ConsignmentDialogState extends ConsumerState<_ConsignmentDialog> {
  Consignment? _c;
  final Map<int, double> _returned = {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final c = await ref.read(fashionRepositoryProvider).consignment(widget.id);
      setState(() {
        _c = c;
        for (final i in c.items) {
          _returned[i.id] = i.returnedQty ?? i.qty; // padrão: tudo voltou
        }
      });
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  double get _keptTotal {
    final c = _c;
    if (c == null) return 0;
    return c.items.fold<double>(0, (a, i) => a + (i.qty - (_returned[i.id] ?? i.qty)) * i.unitPrice);
  }

  Future<void> _settle() async {
    setState(() => _busy = true);
    try {
      final r = await ref.read(fashionRepositoryProvider).closeConsignment(widget.id, _returned);
      if (!mounted) return;
      if (r.kept.isEmpty) {
        showOk(context, 'Acerto feito: tudo voltou para o estoque');
        Navigator.pop(context, true);
        return;
      }
      ref.read(posControllerProvider.notifier).loadCart(r.kept, customer: r.customer);
      Navigator.pop(context, true);
      showOk(context, 'Peças que a cliente ficou já estão no PDV — é só receber');
      context.go(Routes.pos);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    setState(() => _busy = true);
    try {
      await ref.read(fashionRepositoryProvider).cancelConsignment(widget.id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _remind() {
    final c = _c!;
    final company = ref.read(sessionControllerProvider)?.tenant.nomeFantasia ?? '';
    final msg = [
      'Olá, ${c.customerName.split(' ').first}! Aqui é da *$company*.',
      'Passando para lembrar da condicional nº ${c.number}${c.dueDate != null ? ' (combinamos ${dateBr(c.dueDate!)})' : ''}:',
      for (final i in c.items) '• ${number(i.qty)}× ${i.description} — ${money(i.unitPrice)}',
      '',
      'Quando puder, traga o que não for ficar. Obrigado!',
    ].join('\n');
    openWhatsApp(c.customerPhone, msg);
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    final t = Theme.of(context);
    if (c == null) return const AlertDialog(content: SizedBox(height: 120, child: Center(child: CircularProgressIndicator())));
    return AlertDialog(
      title: Text('Condicional nº ${c.number} · ${c.customerName}'),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Text([
              'Saiu em ${dateBr(c.createdAt)}',
              if (c.dueDate != null) 'volta em ${dateBr(c.dueDate!)}',
              c.status.toLowerCase(),
            ].join(' · ')),
            if (c.notes != null) Text(c.notes!, style: t.textTheme.bodySmall),
            const Divider(),
            if (c.isOpen) Text('Quantas voltaram de cada peça?', style: t.textTheme.titleSmall),
            for (final i in c.items)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: ProductThumb(url: i.imageUrl, size: 36),
                title: Text(i.description),
                subtitle: Text(c.isOpen
                    ? 'Levou ${number(i.qty)} · ${money(i.unitPrice)} cada'
                    : 'Levou ${number(i.qty)} · voltou ${number(i.returnedQty ?? 0)} · ficou ${number(i.keptQty ?? 0)}'),
                trailing: !c.isOpen
                    ? null
                    : Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(
                          icon: const Icon(Icons.remove),
                          onPressed: (_returned[i.id] ?? 0) <= 0 ? null : () => setState(() => _returned[i.id] = (_returned[i.id] ?? 0) - 1),
                        ),
                        SizedBox(width: 28, child: Text(number(_returned[i.id] ?? 0), textAlign: TextAlign.center)),
                        IconButton(
                          icon: const Icon(Icons.add),
                          onPressed: (_returned[i.id] ?? 0) >= i.qty ? null : () => setState(() => _returned[i.id] = (_returned[i.id] ?? 0) + 1),
                        ),
                      ]),
              ),
            if (c.isOpen) ...[
              const Divider(),
              Text('A cliente ficou com: ${money(_keptTotal)}', style: t.textTheme.titleMedium),
              Text('O que ela ficou vai para o PDV com a cliente identificada. O resto volta ao estoque.',
                  style: t.textTheme.bodySmall),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar')),
        if (c.isOpen) ...[
          IconButton(tooltip: 'Lembrar pelo WhatsApp', onPressed: _remind, icon: const Icon(Icons.chat_outlined)),
          TextButton(onPressed: _busy ? null : _cancel, child: const Text('Devolveu tudo')),
          FilledButton.icon(
            onPressed: _busy ? null : _settle,
            icon: const Icon(Icons.point_of_sale),
            label: Text(_keptTotal > 0 ? 'Acertar e receber ${money(_keptTotal)}' : 'Acertar'),
          ),
        ],
      ],
    );
  }
}

// ============================================================ PASSO A PASSO
/// Cartão com os passos do recurso (ajuda direto na tela).
class _StepsCard extends StatelessWidget {
  const _StepsCard({required this.steps});
  final List<(String, String)> steps;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      color: t.colorScheme.primaryContainer.withValues(alpha: .35),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(spacing: 16, runSpacing: 8, children: [
          for (final (i, s) in steps.indexed)
            SizedBox(
              width: 300,
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
