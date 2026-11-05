import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/utils/image_tools.dart';
import '../../../core/widgets/common_widgets.dart';
import '../domain/product.dart';

/// O que o formulário devolve: os dados + o que fazer com a foto.
class ProductFormResult {
  const ProductFormResult(this.input, {this.newPhoto, this.removePhoto = false});
  final ProductInput input;

  /// JPEG já reduzido para enviar.
  final Uint8List? newPhoto;
  final bool removePhoto;
}

const kUnits = ['UN', 'KG', 'G', 'L', 'ML', 'M', 'CX', 'PC', 'PCT', 'RL', 'FD', 'DZ', 'KIT', 'PAR', 'CJ'];

String _num(double v) => v == 0 ? '' : v.toStringAsFixed(2).replaceAll('.', ',');

/// Cadastro / edição de produto.
class ProductFormDialog extends StatefulWidget {
  const ProductFormDialog({
    super.key,
    this.initial,
    this.showScale = false,
    this.categories = const [],
    this.preferredUnits = const [],
  });
  final Product? initial;
  final bool showScale;

  /// Categorias sugeridas (as do ramo + as já usadas pela empresa).
  final List<String> categories;

  /// Unidades mais usadas no ramo (aparecem primeiro na lista).
  final List<String> preferredUnits;

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
  late String _category = widget.initial?.category ?? '';
  late String _unit = widget.initial?.unit ?? 'UN';
  late bool _active = widget.initial?.isActive ?? true;
  Uint8List? _photo; // nova foto escolhida (já reduzida)
  bool _removePhoto = false;
  bool _processing = false;

  Future<void> _pickPhoto() async {
    final file = await FilePicker.pickFile(type: FileType.image);
    if (file == null) return;
    setState(() => _processing = true);
    try {
      final small = await shrinkImage(await file.readAsBytes());
      if (!mounted) return;
      if (small == null) {
        showError(context, 'Não consegui abrir esta imagem. Use JPG ou PNG.');
        return;
      }
      setState(() {
        _photo = small;
        _removePhoto = false;
      });
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

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
      ProductFormResult(
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
        category: _category,
      ),
        newPhoto: _photo,
        removePhoto: _removePhoto,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 12, width: 12);
    final digits = [FilteringTextInputFormatter.digitsOnly];
    final units = {...widget.preferredUnits, ...kUnits, _unit}.toList();

    return AlertDialog(
      title: Text(_isNew ? 'Novo produto' : 'Editar produto'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _PhotoField(
                photo: _photo,
                url: _removePhoto ? null : widget.initial?.imageUrl,
                processing: _processing,
                onPick: _pickPhoto,
                onRemove: () => setState(() {
                  _photo = null;
                  _removePhoto = widget.initial?.imageUrl != null;
                }),
              ),
              gap,
              TextFormField(
                controller: _name,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Descrição'),
                validator: (v) => (v ?? '').trim().length < 2 ? 'Informe a descrição' : null,
              ),
              gap,
              _CategoryField(
                initial: _category,
                options: widget.categories,
                onChanged: (v) => _category = v,
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

/// Área da foto: mostra a atual (ou a nova) e os botões trocar/remover.
class _PhotoField extends StatelessWidget {
  const _PhotoField({required this.photo, required this.url, required this.processing, required this.onPick, required this.onRemove});
  final Uint8List? photo;
  final String? url;
  final bool processing;
  final VoidCallback onPick, onRemove;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final has = photo != null || url != null;
    Widget preview;
    if (processing) {
      preview = const SizedBox(width: 96, height: 96, child: Center(child: CircularProgressIndicator()));
    } else if (photo != null) {
      preview = ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(photo!, width: 96, height: 96, fit: BoxFit.cover));
    } else {
      preview = ProductThumb(url: url, size: 96, icon: Icons.add_a_photo_outlined);
    }
    return Row(children: [
      InkWell(onTap: processing ? null : onPick, borderRadius: BorderRadius.circular(12), child: preview),
      const SizedBox(width: 16),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Foto do produto', style: t.textTheme.titleSmall),
          Text('Aparece no PDV, no cadastro e na OS. JPG ou PNG; o app reduz o tamanho sozinho.',
              style: t.textTheme.bodySmall),
          const SizedBox(height: 6),
          Wrap(spacing: 8, children: [
            OutlinedButton.icon(
              onPressed: processing ? null : onPick,
              icon: const Icon(Icons.photo_library_outlined, size: 18),
              label: Text(has ? 'Trocar foto' : 'Escolher foto'),
            ),
            if (has) TextButton(onPressed: onRemove, child: const Text('Remover')),
          ]),
        ]),
      ),
    ]);
  }
}

/// Categoria com sugestões do ramo; aceita digitar uma nova.
class _CategoryField extends StatelessWidget {
  const _CategoryField({required this.initial, required this.options, required this.onChanged});
  final String initial;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Autocomplete<String>(
      initialValue: TextEditingValue(text: initial),
      optionsBuilder: (v) {
        final q = v.text.trim().toLowerCase();
        return q.isEmpty ? options : options.where((o) => o.toLowerCase().contains(q));
      },
      onSelected: onChanged,
      fieldViewBuilder: (context, controller, focus, onSubmit) => TextFormField(
        controller: controller,
        focusNode: focus,
        textCapitalization: TextCapitalization.sentences,
        maxLength: 40,
        decoration: const InputDecoration(
          labelText: 'Categoria',
          hintText: 'Escolha ou digite uma nova',
          prefixIcon: Icon(Icons.sell_outlined),
          counterText: '',
        ),
        onChanged: onChanged,
      ),
    );
  }
}
