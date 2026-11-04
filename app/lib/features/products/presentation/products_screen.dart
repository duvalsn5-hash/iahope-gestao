import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../auth/presentation/session_controller.dart';
import '../data/products_repository.dart';
import '../domain/product.dart';
import 'product_form_dialog.dart';

class ProductFilter {
  const ProductFilter({this.q = '', this.lowOnly = false});
  final String q;
  final bool lowOnly;
}

final productFilterProvider = StateProvider.autoDispose<ProductFilter>((_) => const ProductFilter());

final productListProvider = FutureProvider.autoDispose<List<Product>>((ref) {
  final f = ref.watch(productFilterProvider);
  return ref.read(productsRepositoryProvider).search(f.q, all: true, lowOnly: f.lowOnly);
});

/// Cadastro de produtos: busca, novo, edição, ajuste de estoque e histórico.
/// Atalhos: Ctrl+N novo · Ctrl+F buscar
class ProductsScreen extends ConsumerStatefulWidget {
  const ProductsScreen({super.key});

  @override
  ConsumerState<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends ConsumerState<ProductsScreen> {
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
    _debounce = Timer(const Duration(milliseconds: 300), () {
      final f = ref.read(productFilterProvider);
      ref.read(productFilterProvider.notifier).state = ProductFilter(q: v.trim(), lowOnly: f.lowOnly);
    });
  }

  bool get _canEdit => ref.read(sessionControllerProvider)?.canEditProducts ?? false;
  bool get _scaleOn => ref.read(sessionControllerProvider)?.hasModule('BALANCA') ?? false;

  Future<void> _edit([Product? p]) async {
    if (!_canEdit) return;
    final input = await showDialog<ProductInput>(
      context: context,
      builder: (_) => ProductFormDialog(initial: p, showScale: _scaleOn),
    );
    if (input == null || !mounted) return;
    try {
      final repo = ref.read(productsRepositoryProvider);
      if (p == null) {
        await repo.create(input);
      } else {
        await repo.update(p.id, input);
      }
      ref.invalidate(productListProvider);
      if (mounted) showOk(context, p == null ? 'Produto cadastrado' : 'Produto atualizado');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _adjust(Product p) async {
    final r = await showDialog<(double, String)>(context: context, builder: (_) => _StockDialog(product: p));
    if (r == null || !mounted) return;
    try {
      await ref.read(productsRepositoryProvider).adjustStock(p.id, r.$1, r.$2);
      ref.invalidate(productListProvider);
      if (mounted) showOk(context, 'Estoque atualizado');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _history(Product p) => showDialog<void>(context: context, builder: (_) => _HistoryDialog(product: p));

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(productListProvider);
    final filter = ref.watch(productFilterProvider);
    final compact = Breakpoints.isCompact(context);
    final canEdit = ref.watch(sessionControllerProvider)?.canEditProducts ?? false;

    return CallbackShortcuts(
      bindings: {
        if (canEdit) const SingleActivator(LogicalKeyboardKey.keyN, control: true): () => _edit(),
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () => _searchFocus.requestFocus(),
      },
      child: Scaffold(
        floatingActionButton: canEdit
            ? FloatingActionButton.extended(
                onPressed: () => _edit(),
                icon: const Icon(Icons.add),
                label: Text(compact ? 'Novo' : 'Novo produto (Ctrl+N)'),
              )
            : null,
        body: RefreshIndicator(
          onRefresh: () => ref.refresh(productListProvider.future),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              Text('Produtos', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                SizedBox(
                  width: compact ? double.infinity : 380,
                  child: TextField(
                    controller: _search,
                    focusNode: _searchFocus,
                    autofocus: !compact,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Nome, SKU, código de barras ou código da balança',
                    ),
                    onChanged: _onSearch,
                  ),
                ),
                FilterChip(
                  label: const Text('Estoque baixo'),
                  avatar: const Icon(Icons.warning_amber, size: 18),
                  selected: filter.lowOnly,
                  onSelected: (v) => ref.read(productFilterProvider.notifier).state = ProductFilter(q: filter.q, lowOnly: v),
                ),
              ]),
              const SizedBox(height: 12),
              list.when(
                loading: () => const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator())),
                error: (e, _) => Card(child: ListTile(leading: const Icon(Icons.error), title: Text(e.toString()))),
                data: (items) => items.isEmpty
                    ? const Padding(padding: EdgeInsets.all(48), child: Center(child: Text('Nenhum produto encontrado')))
                    : compact
                        ? Column(children: [
                            for (final p in items)
                              _ProductCard(p: p, onTap: () => _edit(p), onStock: () => _adjust(p), onHistory: () => _history(p)),
                          ])
                        : _ProductTable(items: items, onEdit: _edit, onStock: _adjust, onHistory: _history, canEdit: canEdit),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _stockText(BuildContext context, Product p) => Text(
      '${number(p.stockQty)} ${p.unit}',
      style: TextStyle(
        color: p.lowStock ? Theme.of(context).colorScheme.error : null,
        fontWeight: p.lowStock ? FontWeight.w600 : null,
      ),
    );

class _ProductTable extends StatelessWidget {
  const _ProductTable({
    required this.items,
    required this.onEdit,
    required this.onStock,
    required this.onHistory,
    required this.canEdit,
  });

  final List<Product> items;
  final void Function(Product) onEdit, onStock, onHistory;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          showCheckboxColumn: false,
          columns: const [
            DataColumn(label: Text('Produto')),
            DataColumn(label: Text('SKU')),
            DataColumn(label: Text('Código de barras')),
            DataColumn(label: Text('Preço'), numeric: true),
            DataColumn(label: Text('Custo'), numeric: true),
            DataColumn(label: Text('Estoque'), numeric: true),
            DataColumn(label: Text('')),
          ],
          rows: [
            for (final p in items)
              DataRow(
                onSelectChanged: canEdit ? (_) => onEdit(p) : null,
                cells: [
                  DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                    if (!p.isActive)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Icon(Icons.block, size: 16, color: t.colorScheme.outline),
                      ),
                    if (p.scaleCode != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Tooltip(message: 'Balança: código ${p.scaleCode}', child: const Icon(Icons.scale, size: 16)),
                      ),
                    Text(p.name, style: TextStyle(color: p.isActive ? null : t.colorScheme.outline)),
                  ])),
                  DataCell(Text(p.sku)),
                  DataCell(Text(p.barcode ?? '—')),
                  DataCell(Text(money(p.price))),
                  DataCell(Text(p.cost > 0 ? money(p.cost) : '—')),
                  DataCell(_stockText(context, p)),
                  DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(tooltip: 'Entrada / ajuste de estoque', icon: const Icon(Icons.add_box_outlined), onPressed: () => onStock(p)),
                    IconButton(tooltip: 'Histórico', icon: const Icon(Icons.history), onPressed: () => onHistory(p)),
                  ])),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.p, required this.onTap, required this.onStock, required this.onHistory});
  final Product p;
  final VoidCallback onTap, onStock, onHistory;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onTap,
        title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Row(children: [
          Text('${p.sku} · ${money(p.price)} · '),
          _stockText(context, p),
          if (!p.isActive) const Text(' · inativo'),
        ]),
        trailing: PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'stock') {
              onStock();
            } else {
              onHistory();
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'stock', child: Text('Entrada / ajuste de estoque')),
            PopupMenuItem(value: 'history', child: Text('Histórico')),
          ],
        ),
      ),
    );
  }
}

class _StockDialog extends StatefulWidget {
  const _StockDialog({required this.product});
  final Product product;

  @override
  State<_StockDialog> createState() => _StockDialogState();
}

class _StockDialogState extends State<_StockDialog> {
  final _qty = TextEditingController();
  String _mode = 'ENTRADA'; // ENTRADA soma · SAIDA baixa · CONTAGEM define o total

  @override
  void dispose() {
    _qty.dispose();
    super.dispose();
  }

  void _save() {
    final v = parseMoney(_qty.text);
    final p = widget.product;
    final delta = switch (_mode) {
      'ENTRADA' => v,
      'SAIDA' => -v,
      _ => v - p.stockQty,
    };
    if (delta == 0) return;
    Navigator.pop(context, (delta, _mode == 'ENTRADA' ? 'ENTRADA' : 'AJUSTE'));
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    return AlertDialog(
      title: Text(p.name),
      content: SizedBox(
        width: 380,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Estoque atual: ${number(p.stockQty)} ${p.unit}'),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'ENTRADA', label: Text('Entrada')),
              ButtonSegment(value: 'SAIDA', label: Text('Saída')),
              ButtonSegment(value: 'CONTAGEM', label: Text('Contagem')),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _qty,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: _mode == 'CONTAGEM' ? 'Quantidade contada' : 'Quantidade',
              suffixText: p.unit,
            ),
            onSubmitted: (_) => _save(),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _save, child: const Text('Confirmar')),
      ],
    );
  }
}

class _HistoryDialog extends ConsumerWidget {
  const _HistoryDialog({required this.product});
  final Product product;

  static const _labels = {
    'VENDA': 'Venda',
    'ENTRADA': 'Entrada',
    'AJUSTE': 'Ajuste',
    'CANCELAMENTO': 'Venda cancelada',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AlertDialog(
      title: Text('Histórico — ${product.name}'),
      content: SizedBox(
        width: 460,
        height: 420,
        child: FutureBuilder<List<StockMovement>>(
          future: ref.read(productsRepositoryProvider).movements(product.id),
          builder: (context, snap) {
            if (snap.hasError) return Center(child: Text(snap.error.toString()));
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final list = snap.data!;
            if (list.isEmpty) return const Center(child: Text('Sem movimentações'));
            return ListView.separated(
              itemCount: list.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final m = list[i];
                final positive = m.qty > 0;
                return ListTile(
                  dense: true,
                  leading: Icon(positive ? Icons.arrow_downward : Icons.arrow_upward,
                      color: positive ? Colors.green.shade700 : Theme.of(context).colorScheme.error),
                  title: Text(_labels[m.reason] ?? m.reason),
                  subtitle: Text('${dateTimeBr(m.createdAt)}${m.user != null ? ' · ${m.user}' : ''}'),
                  trailing: Text('${positive ? '+' : ''}${number(m.qty)} ${product.unit}',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                );
              },
            );
          },
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar'))],
    );
  }
}
