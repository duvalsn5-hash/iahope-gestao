import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../data/products_repository.dart';
import '../domain/product.dart';

/// Busca de produto por nome/SKU ou leitor de código de barras (bipou → escolhe).
class ProductPickerDialog extends ConsumerStatefulWidget {
  const ProductPickerDialog({super.key, this.title = 'Adicionar produto', this.emptyText = 'Nenhum produto encontrado. Cadastre em Produtos.'});
  final String title;
  final String emptyText;

  @override
  ConsumerState<ProductPickerDialog> createState() => _ProductPickerDialogState();
}

class _ProductPickerDialogState extends ConsumerState<ProductPickerDialog> {
  final _q = TextEditingController();
  Timer? _debounce;
  List<Product> _items = const [];

  @override
  void initState() {
    super.initState();
    _load('');
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

  Future<void> _submit(String v) async {
    // leitor de código de barras: bipou → adiciona direto
    final hit = await ref.read(productsRepositoryProvider).byCode(v.trim());
    if (!mounted) return;
    if (hit != null) {
      Navigator.pop(context, hit.product);
    } else if (_items.length == 1) {
      Navigator.pop(context, _items.first);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 520,
        height: 460,
        child: Column(children: [
          TextField(
            controller: _q,
            autofocus: true,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.qr_code_scanner), hintText: 'Bipe o código ou digite nome / SKU'),
            onChanged: (v) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 250), () => _load(v.trim()));
            },
            onSubmitted: _submit,
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _items.isEmpty
                ? Center(child: Text(widget.emptyText))
                : ListView.builder(
                    itemCount: _items.length,
                    itemBuilder: (_, i) {
                      final p = _items[i];
                      return ListTile(
                        leading: ProductThumb(url: p.imageUrl, size: 48),
                        title: Text(p.name),
                        isThreeLine: false,
                        subtitle: Text('${p.sku} · estoque ${number(p.stockQty)} ${p.unit}',
                            style: p.stockQty <= 0 ? TextStyle(color: t.colorScheme.error) : null),
                        trailing: Text(money(p.price), style: const TextStyle(fontWeight: FontWeight.w600)),
                        onTap: () => Navigator.pop(context, p),
                      );
                    },
                  ),
          ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar'))],
    );
  }
}
