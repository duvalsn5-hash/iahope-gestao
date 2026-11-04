import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../products/data/products_repository.dart';
import '../../products/domain/product.dart';
import '../../products/presentation/product_form_dialog.dart' show kUnits;
import '../data/purchases_repository.dart';
import '../domain/purchase.dart';

/// Conferência da NF-e antes de lançar: cada item é vinculado a um produto
/// existente ou vira um produto novo; o fator converte a unidade da nota
/// (ex.: CX com 12) para a unidade de estoque.
class PurchaseImportPage extends ConsumerStatefulWidget {
  const PurchaseImportPage({super.key, required this.preview});
  final NfePreview preview;

  @override
  ConsumerState<PurchaseImportPage> createState() => _PurchaseImportPageState();
}

class _PurchaseImportPageState extends ConsumerState<PurchaseImportPage> {
  bool _saving = false;

  NfePreview get p => widget.preview;
  int get _pending => p.items.where((i) => !i.resolved).length;

  Future<void> _linkExisting(NfeItem it) async {
    final prod = await showDialog<Product>(context: context, builder: (_) => _ProductPicker(initialQuery: it.description));
    if (prod == null) return;
    setState(() {
      it.createNew = false;
      it.match = NfeMatch(productId: prod.id, name: prod.name, sku: prod.sku, unit: prod.unit, price: prod.price, by: 'MANUAL');
    });
  }

  Future<void> _editNew(NfeItem it) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => _NewProductDialog(item: it));
    if (ok == true) setState(() => it.createNew = true);
  }

  Future<void> _editFactor(NfeItem it) async {
    final c = TextEditingController(text: number(it.factor));
    final v = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Fator de conversão'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Quantas unidades de estoque vêm em 1 ${it.unit} da nota?\nEx.: caixa com 12 unidades → 12'),
          const SizedBox(height: 12),
          TextField(
            controller: c,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onSubmitted: (s) => Navigator.pop(ctx, parseMoney(s)),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, parseMoney(c.text)), child: const Text('OK')),
        ],
      ),
    );
    if (v != null && v > 0) setState(() => it.factor = v);
  }

  Future<void> _save() async {
    if (_pending > 0) {
      showError(context, 'Ainda há $_pending item(ns) sem produto definido');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(purchasesRepositoryProvider).register(p);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final compact = Breakpoints.isCompact(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('NF-e ${p.number} · ${p.supplier.name}', overflow: TextOverflow.ellipsis),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              onPressed: _saving || p.alreadyImported ? null : _save,
              icon: _saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check),
              label: Text(compact ? 'Lançar' : 'Lançar nota'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final w in p.warnings)
            Card(
              color: t.colorScheme.errorContainer,
              child: ListTile(leading: const Icon(Icons.warning_amber), title: Text(w)),
            ),
          ResponsiveGrid(maxColumns: 4, children: [
            KpiCard(label: 'Fornecedor', value: p.supplier.name, subtitle: formatDoc(p.supplier.doc)),
            KpiCard(label: 'Emissão', value: dateBr(parseIsoDate(p.issueDate)), subtitle: 'série ${p.series}'),
            KpiCard(label: 'Total da nota', value: money(p.total), subtitle: '${p.items.length} item(ns)'),
            KpiCard(
              label: 'Itens a conferir',
              value: '$_pending',
              color: _pending == 0 ? Colors.green.shade700 : t.colorScheme.error,
              subtitle: _pending == 0 ? 'tudo pronto' : 'defina o produto de cada item',
            ),
          ]),
          const SizedBox(height: 16),
          Text('Itens', style: t.textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final it in p.items)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: it.resolved ? t.colorScheme.outlineVariant : t.colorScheme.error),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(it.description, style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text('Cód. fornecedor ${it.supplierCode}${it.barcode != null ? ' · EAN ${it.barcode}' : ''}',
                            style: t.textTheme.bodySmall),
                      ]),
                    ),
                    Text(money(it.total), style: const TextStyle(fontWeight: FontWeight.w700)),
                  ]),
                  const SizedBox(height: 6),
                  Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text('${number(it.qty)} ${it.unit} × ${money(it.unitPrice)}'),
                    ActionChip(
                      avatar: const Icon(Icons.swap_vert, size: 16),
                      label: Text('fator ${number(it.factor)} → ${number(it.stockQty)} no estoque'),
                      onPressed: () => _editFactor(it),
                    ),
                    if (it.resolved) Text('custo ${money(it.unitCost)}/un', style: t.textTheme.bodySmall),
                  ]),
                  const Divider(height: 20),
                  if (it.createNew)
                    _ResolvedLine(
                      icon: Icons.add_box_outlined,
                      text: 'Novo produto: ${it.newName} (${it.newSku}) · venda ${money(it.newPrice)}',
                      color: t.colorScheme.primary,
                    )
                  else if (it.match != null)
                    _ResolvedLine(
                      icon: Icons.link,
                      text: '${it.match!.name} (${it.match!.sku})'
                          '${it.match!.by == 'FORNECEDOR' ? ' · reconhecido pelo código do fornecedor' : it.match!.by == 'CODIGO_BARRAS' ? ' · reconhecido pelo código de barras' : ''}',
                      color: Colors.green.shade700,
                    )
                  else
                    _ResolvedLine(icon: Icons.help_outline, text: 'Produto não identificado', color: t.colorScheme.error),
                  const SizedBox(height: 6),
                  Wrap(spacing: 8, children: [
                    OutlinedButton.icon(
                      onPressed: () => _linkExisting(it),
                      icon: const Icon(Icons.search, size: 18),
                      label: const Text('Vincular a produto'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _editNew(it),
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(it.createNew ? 'Editar produto novo' : 'Criar produto novo'),
                    ),
                  ]),
                ]),
              ),
            ),
          const SizedBox(height: 8),
          Text('Contas a pagar geradas', style: t.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: p.installments.isEmpty
                ? const ListTile(
                    leading: Icon(Icons.info_outline),
                    title: Text('A nota não traz duplicatas'),
                    subtitle: Text('Nenhuma conta a pagar será criada (compra à vista). Lance manualmente no Financeiro se precisar.'),
                  )
                : Column(children: [
                    for (final d in p.installments)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.event),
                        title: Text('Duplicata ${d.document}'),
                        subtitle: Text('vence ${dateBr(parseIsoDate(d.dueDate))}'),
                        trailing: Text(money(d.amount), style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                  ]),
          ),
        ],
      ),
    );
  }
}

class _ResolvedLine extends StatelessWidget {
  const _ResolvedLine({required this.icon, required this.text, required this.color});
  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w500))),
      ]);
}

/// Dados do produto que será criado a partir do item da nota.
class _NewProductDialog extends StatefulWidget {
  const _NewProductDialog({required this.item});
  final NfeItem item;

  @override
  State<_NewProductDialog> createState() => _NewProductDialogState();
}

class _NewProductDialogState extends State<_NewProductDialog> {
  final _form = GlobalKey<FormState>();
  late final _sku = TextEditingController(text: widget.item.newSku);
  late final _name = TextEditingController(text: widget.item.newName);
  late final _price = TextEditingController(
      text: widget.item.newPrice > 0 ? widget.item.newPrice.toStringAsFixed(2).replaceAll('.', ',') : '');
  late String _unit = kUnits.contains(widget.item.newUnit) ? widget.item.newUnit : 'UN';

  @override
  void dispose() {
    _sku.dispose();
    _name.dispose();
    _price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cost = widget.item.unitCost;
    final price = parseMoney(_price.text);
    return AlertDialog(
      title: const Text('Produto novo'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _form,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Descrição'),
              validator: (v) => (v ?? '').trim().length < 2 ? 'Obrigatório' : null,
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _sku,
                  decoration: const InputDecoration(labelText: 'Código interno (SKU)'),
                  validator: (v) => (v ?? '').trim().isEmpty ? 'Obrigatório' : null,
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 110,
                child: DropdownButtonFormField<String>(
                  initialValue: _unit,
                  decoration: const InputDecoration(labelText: 'Unidade'),
                  items: [for (final u in kUnits) DropdownMenuItem(value: u, child: Text(u))],
                  onChanged: (v) => setState(() => _unit = v ?? 'UN'),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            TextFormField(
              controller: _price,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Preço de venda',
                prefixText: r'R$ ',
                helperText: 'custo ${money(cost)}/un'
                    '${price > 0 && cost > 0 ? ' · margem ${((price - cost) / price * 100).toStringAsFixed(1)}%' : ''}',
              ),
              onChanged: (_) => setState(() {}),
              validator: (v) => parseMoney(v ?? '') <= 0 ? 'Informe o preço' : null,
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 6, children: [
              for (final pct in const [30, 50, 80, 100])
                ActionChip(
                  label: Text('+$pct%'),
                  onPressed: cost <= 0
                      ? null
                      : () => setState(() => _price.text = (cost * (1 + pct / 100)).toStringAsFixed(2).replaceAll('.', ',')),
                ),
            ]),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            final it = widget.item;
            it.newSku = _sku.text.trim();
            it.newName = _name.text.trim();
            it.newUnit = _unit;
            it.newPrice = parseMoney(_price.text);
            Navigator.pop(context, true);
          },
          child: const Text('OK'),
        ),
      ],
    );
  }
}

/// Busca de produto existente para vincular ao item da nota.
class _ProductPicker extends ConsumerStatefulWidget {
  const _ProductPicker({required this.initialQuery});
  final String initialQuery;

  @override
  ConsumerState<_ProductPicker> createState() => _ProductPickerState();
}

class _ProductPickerState extends ConsumerState<_ProductPicker> {
  final _q = TextEditingController();
  Timer? _debounce;
  List<Product> _items = const [];

  @override
  void initState() {
    super.initState();
    // começa pela primeira palavra da descrição da nota
    final first = widget.initialQuery.split(RegExp(r'\s+')).first;
    _q.text = first;
    _load(first);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  Future<void> _load(String q) async {
    try {
      final r = await ref.read(productsRepositoryProvider).search(q);
      if (mounted) setState(() => _items = r);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Vincular a produto'),
      content: SizedBox(
        width: 480,
        height: 420,
        child: Column(children: [
          TextField(
            controller: _q,
            autofocus: true,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Nome, SKU ou código de barras'),
            onChanged: (v) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 250), () => _load(v.trim()));
            },
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _items.isEmpty
                ? const Center(child: Text('Nenhum produto encontrado'))
                : ListView.builder(
                    itemCount: _items.length,
                    itemBuilder: (_, i) => ListTile(
                      title: Text(_items[i].name),
                      subtitle: Text('${_items[i].sku} · estoque ${number(_items[i].stockQty)} ${_items[i].unit}'),
                      trailing: Text(money(_items[i].price)),
                      onTap: () => Navigator.pop(context, _items[i]),
                    ),
                  ),
          ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar'))],
    );
  }
}
