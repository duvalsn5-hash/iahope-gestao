import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/utils/formatters.dart';
import '../domain/product.dart';

const kUnits = ['UN', 'KG', 'G', 'L', 'ML', 'M', 'CX', 'PC', 'PCT', 'RL', 'FD', 'DZ'];

String _num(double v) => v == 0 ? '' : v.toStringAsFixed(2).replaceAll('.', ',');

/// Cadastro / edição de produto.
class ProductFormDialog extends StatefulWidget {
  const ProductFormDialog({super.key, this.initial, this.showScale = false});
  final Product? initial;
  final bool showScale;

  @override
  State<ProductFormDialog> createState() => _ProductFormDialogState();
}

class _ProductFormDialogState extends State<ProductFormDialog> {
  final _form = GlobalKey<FormState>();
  late final _sku = TextEditingController(text: widget.initial?.sku ?? '');
  late final _barcode = TextEditingController(text: widget.initial?.barcode ?? '');
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late final _price = TextEditingController(text: _num(widget.initial?.price ?? 0));
  late final _cost = TextEditingController(text: _num(widget.initial?.cost ?? 0));
  final _stock = TextEditingController();
  late final _min = TextEditingController(
      text: widget.initial == null || widget.initial!.minStock == 0 ? '' : number(widget.initial!.minStock));
  late final _scale = TextEditingController(text: widget.initial?.scaleCode?.toString() ?? '');
  late String _unit = widget.initial?.unit ?? 'UN';
  late bool _active = widget.initial?.isActive ?? true;

  bool get _isNew => widget.initial == null;

  @override
  void dispose() {
    for (final c in [_sku, _barcode, _name, _price, _cost, _stock, _min, _scale]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _margin() {
    final price = parseMoney(_price.text), cost = parseMoney(_cost.text);
    if (price <= 0 || cost <= 0) return null;
    return 'Margem ${((price - cost) / price * 100).toStringAsFixed(1)}%';
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(
      context,
      ProductInput(
        sku: _sku.text.trim(),
        barcode: _barcode.text.trim(),
        name: _name.text.trim(),
        unit: _unit,
        price: parseMoney(_price.text),
        cost: parseMoney(_cost.text),
        stockQty: parseMoney(_stock.text),
        minStock: parseMoney(_min.text),
        scaleCode: int.tryParse(_scale.text.trim()),
        isActive: _active,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 12, width: 12);
    final digits = [FilteringTextInputFormatter.digitsOnly];
    final units = {...kUnits, _unit}.toList();

    return AlertDialog(
      title: Text(_isNew ? 'Novo produto' : 'Editar produto'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(
                controller: _name,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Descrição'),
                validator: (v) => (v ?? '').trim().length < 2 ? 'Informe a descrição' : null,
              ),
              gap,
              Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: _sku,
                    decoration: const InputDecoration(labelText: 'Código interno (SKU)'),
                    validator: (v) => (v ?? '').trim().isEmpty ? 'Obrigatório' : null,
                  ),
                ),
                gap,
                Expanded(
                  child: TextFormField(
                    controller: _barcode,
                    keyboardType: TextInputType.number,
                    inputFormatters: digits,
                    decoration: const InputDecoration(labelText: 'Código de barras (EAN)', hintText: 'bipe aqui'),
                  ),
                ),
              ]),
              gap,
              Row(children: [
                SizedBox(
                  width: 120,
                  child: DropdownButtonFormField<String>(
                    initialValue: _unit,
                    decoration: const InputDecoration(labelText: 'Unidade'),
                    items: [for (final u in units) DropdownMenuItem(value: u, child: Text(u))],
                    onChanged: (v) => setState(() => _unit = v ?? 'UN'),
                  ),
                ),
                gap,
                Expanded(
                  child: TextFormField(
                    controller: _price,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: 'Preço de venda', prefixText: r'R$ ', helperText: _margin()),
                    onChanged: (_) => setState(() {}),
                    validator: (v) => parseMoney(v ?? '') <= 0 ? 'Informe o preço' : null,
                  ),
                ),
                gap,
                Expanded(
                  child: TextFormField(
                    controller: _cost,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Custo', prefixText: r'R$ '),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ]),
              gap,
              Row(children: [
                if (_isNew) ...[
                  Expanded(
                    child: TextFormField(
                      controller: _stock,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(labelText: 'Estoque inicial', suffixText: _unit),
                    ),
                  ),
                  gap,
                ],
                Expanded(
                  child: TextFormField(
                    controller: _min,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: 'Estoque mínimo', suffixText: _unit),
                  ),
                ),
                if (widget.showScale) ...[
                  gap,
                  Expanded(
                    child: TextFormField(
                      controller: _scale,
                      keyboardType: TextInputType.number,
                      inputFormatters: digits,
                      decoration: const InputDecoration(labelText: 'Código na balança', helperText: 'só p/ pesáveis'),
                    ),
                  ),
                ],
              ]),
              if (!_isNew)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Ativo'),
                  subtitle: const Text('Produto inativo não aparece no PDV'),
                  value: _active,
                  onChanged: (v) => setState(() => _active = v),
                ),
            ]),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _save, child: const Text('Salvar')),
      ],
    );
  }
}
