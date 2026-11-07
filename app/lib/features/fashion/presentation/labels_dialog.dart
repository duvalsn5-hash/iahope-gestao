import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../auth/presentation/session_controller.dart';
import '../../products/domain/product.dart';
import '../../products/presentation/product_picker_dialog.dart';
import '../data/fashion_repository.dart';
import '../data/label_printer.dart';

/// Monta e imprime etiquetas: escolha os produtos, a quantidade de cada e o formato.
class LabelsDialog extends ConsumerStatefulWidget {
  const LabelsDialog({super.key, this.initial = const []});
  final List<(Product, int)> initial;

  @override
  ConsumerState<LabelsDialog> createState() => _LabelsDialogState();
}

class _LabelsDialogState extends ConsumerState<LabelsDialog> {
  late final List<(Product, int)> _items = [...widget.initial];
  LabelLayout _layout = LabelLayout.a4;
  bool _busy = false;

  int get _total => _items.fold(0, (a, e) => a + e.$2);
  List<Product> get _withoutCode => [for (final (p, _) in _items) if (p.barcode == null || p.barcode!.isEmpty) p];

  Future<void> _add() async {
    final p = await showDialog<Product>(context: context, builder: (_) => const ProductPickerDialog(title: 'Produto da etiqueta'));
    if (p == null) return;
    setState(() {
      final i = _items.indexWhere((e) => e.$1.id == p.id);
      if (i >= 0) {
        _items[i] = (p, _items[i].$2 + 1);
      } else {
        _items.add((p, p.stockQty > 0 ? p.stockQty.ceil() : 1));
      }
    });
  }

  Future<void> _fillCodes() async {
    setState(() => _busy = true);
    try {
      final updated = await ref.read(fashionRepositoryProvider).fillBarcodes([for (final p in _withoutCode) p.id]);
      setState(() {
        for (var i = 0; i < _items.length; i++) {
          final u = updated.where((x) => x.id == _items[i].$1.id);
          if (u.isNotEmpty) _items[i] = (u.first, _items[i].$2);
        }
      });
      if (mounted) showOk(context, '${updated.length} código(s) de barras gerado(s)');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _print() async {
    final company = ref.read(sessionControllerProvider)?.tenant.nomeFantasia ?? '';
    setState(() => _busy = true);
    try {
      await LabelPrinter.print([for (final e in _items) if (e.$2 > 0) e], company: company, layout: _layout);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final manager = ref.watch(sessionControllerProvider)?.isManager ?? false;
    return AlertDialog(
      title: const Text('Etiquetas com código de barras'),
      content: SizedBox(
        width: 620,
        height: 480,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DropdownButtonFormField<LabelLayout>(
            initialValue: _layout,
            decoration: const InputDecoration(labelText: 'Formato', prefixIcon: Icon(Icons.label_outline)),
            items: [for (final l in LabelLayout.values) DropdownMenuItem(value: l, child: Text(l.label))],
            onChanged: (v) => setState(() => _layout = v ?? LabelLayout.a4),
          ),
          if (_withoutCode.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.amber.withValues(alpha: .15), borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                const Icon(Icons.qr_code_2, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text('${_withoutCode.length} produto(s) sem código de barras (sai o SKU).')),
                if (manager) TextButton(onPressed: _busy ? null : _fillCodes, child: const Text('Gerar códigos')),
              ]),
            ),
          ],
          const SizedBox(height: 8),
          Expanded(
            child: _items.isEmpty
                ? const Center(child: Text('Adicione os produtos que vão ganhar etiqueta.'))
                : ListView.separated(
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final (p, n) = _items[i];
                      return ListTile(
                        dense: true,
                        leading: ProductThumb(url: p.imageUrl, size: 36),
                        title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text('${p.barcode ?? p.sku} · ${money(p.price)} · estoque ${number(p.stockQty)}'),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(
                            icon: const Icon(Icons.remove),
                            onPressed: () => setState(() => n <= 1 ? _items.removeAt(i) : _items[i] = (p, n - 1)),
                          ),
                          SizedBox(width: 32, child: Text('$n', textAlign: TextAlign.center, style: t.textTheme.titleMedium)),
                          IconButton(icon: const Icon(Icons.add), onPressed: () => setState(() => _items[i] = (p, n + 1))),
                        ]),
                      );
                    },
                  ),
          ),
          Row(children: [
            OutlinedButton.icon(onPressed: _add, icon: const Icon(Icons.add), label: const Text('Adicionar produto')),
            const Spacer(),
            Text('$_total etiqueta(s)', style: t.textTheme.titleSmall),
          ]),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar')),
        FilledButton.icon(
          onPressed: _total == 0 || _busy ? null : _print,
          icon: const Icon(Icons.print),
          label: const Text('Imprimir'),
        ),
      ],
    );
  }
}
