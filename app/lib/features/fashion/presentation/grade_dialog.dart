import 'package:flutter/material.dart';

import '../../../core/utils/formatters.dart';
import '../domain/fashion.dart';

/// Cadastro do modelo com grade: nome, preço, tamanhos, cores e estoque inicial
/// de cada combinação. Com [existing], acrescenta tamanhos/cores a um modelo.
class GradeDialog extends StatefulWidget {
  const GradeDialog({super.key, this.existing, this.categories = const []});
  final GradeModel? existing;
  final List<String> categories;

  @override
  State<GradeDialog> createState() => _GradeDialogState();
}

class _GradeDialogState extends State<GradeDialog> {
  final _form = GlobalKey<FormState>();
  late final _model = TextEditingController(text: widget.existing?.model ?? '');
  late final _price = TextEditingController(
      text: widget.existing == null ? '' : widget.existing!.price.toStringAsFixed(2).replaceAll('.', ','));
  late final _cost = TextEditingController(
      text: (widget.existing?.cost ?? 0) == 0 ? '' : widget.existing!.cost.toStringAsFixed(2).replaceAll('.', ','));
  late String _category = widget.existing?.category ?? '';
  final _newSize = TextEditingController();
  final _newColor = TextEditingController();
  late final List<String> _sizes = [...?widget.existing?.sizes];
  late final List<String> _colors = [...?widget.existing?.colors];
  final Map<String, TextEditingController> _qty = {};
  int _step = 0;

  bool get _adding => widget.existing != null;

  @override
  void dispose() {
    for (final c in [_model, _price, _cost, _newSize, _newColor, ..._qty.values]) {
      c.dispose();
    }
    super.dispose();
  }

  bool _exists(String color, String size) => widget.existing?.variant(color, size) != null;

  TextEditingController _cell(String color, String size) => _qty.putIfAbsent('$color|$size', TextEditingController.new);

  void _addSize(String v) {
    final s = v.trim().toUpperCase();
    if (s.isEmpty || _sizes.contains(s)) return;
    setState(() => _sizes.add(s));
    _newSize.clear();
  }

  void _addColor(String v) {
    final c = v.trim();
    if (c.isEmpty) return;
    final cap = c[0].toUpperCase() + c.substring(1);
    if (_colors.any((x) => x.toLowerCase() == cap.toLowerCase())) return;
    setState(() => _colors.add(cap));
    _newColor.clear();
  }

  int get _newCombos => [for (final c in _colors) for (final s in _sizes) if (!_exists(c, s)) 1].length;

  void _next() {
    if (_step == 0) {
      if (!_form.currentState!.validate()) return;
      if (_sizes.isEmpty || _colors.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Escolha pelo menos um tamanho e uma cor')));
        return;
      }
      if (_newCombos == 0) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nenhuma combinação nova para criar')));
        return;
      }
      setState(() => _step = 1);
      return;
    }
    Navigator.pop(
      context,
      NewGrade(
        gradeId: widget.existing?.gradeId,
        model: _model.text.trim(),
        category: _category,
        price: parseMoney(_price.text),
        cost: parseMoney(_cost.text),
        sizes: _sizes,
        colors: _colors,
        stock: {
          for (final e in _qty.entries)
            if (parseMoney(e.value.text) > 0) e.key: parseMoney(e.value.text),
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return AlertDialog(
      title: Text(_adding ? 'Acrescentar tamanhos/cores · ${widget.existing!.model}' : 'Novo modelo com grade'),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(child: _step == 0 ? _stepGrade(t) : _stepStock(t)),
      ),
      actions: [
        if (_step == 1) TextButton(onPressed: () => setState(() => _step = 0), child: const Text('Voltar')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: _next,
          child: Text(_step == 0 ? 'Próximo: estoque ($_newCombos combinações)' : 'Criar $_newCombos produtos'),
        ),
      ],
    );
  }

  Widget _stepGrade(ThemeData t) {
    const gap = SizedBox(height: 12, width: 12);
    return Form(
      key: _form,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        _Hint(
          '1. Dê o nome do modelo e o preço. 2. Escolha os tamanhos e as cores. '
          '3. No próximo passo, informe quantas peças tem de cada combinação. '
          'Cada combinação vira um produto com código de barras próprio.',
        ),
        gap,
        TextFormField(
          controller: _model,
          enabled: !_adding,
          autofocus: !_adding,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Modelo', hintText: 'Ex.: Camiseta básica algodão'),
          validator: (v) => (v ?? '').trim().length < 2 ? 'Informe o modelo' : null,
        ),
        gap,
        if (!_adding) ...[
          Autocomplete<String>(
            initialValue: TextEditingValue(text: _category),
            optionsBuilder: (v) {
              final q = v.text.toLowerCase();
              return q.isEmpty ? widget.categories : widget.categories.where((c) => c.toLowerCase().contains(q));
            },
            onSelected: (v) => _category = v,
            fieldViewBuilder: (_, c, f, __) => TextFormField(
              controller: c,
              focusNode: f,
              decoration: const InputDecoration(labelText: 'Categoria', prefixIcon: Icon(Icons.sell_outlined)),
              onChanged: (v) => _category = v,
            ),
          ),
          gap,
          Row(children: [
            Expanded(
              child: TextFormField(
                controller: _price,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Preço de venda', prefixText: r'R$ '),
                validator: (v) => parseMoney(v ?? '') <= 0 ? 'Informe o preço' : null,
              ),
            ),
            gap,
            Expanded(
              child: TextFormField(
                controller: _cost,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Custo (opcional)', prefixText: r'R$ '),
              ),
            ),
          ]),
          gap,
        ],
        Text('Tamanhos', style: t.textTheme.titleSmall),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final (label, list) in kSizePresets)
            ActionChip(
              avatar: const Icon(Icons.playlist_add, size: 16),
              label: Text(label),
              onPressed: () => setState(() {
                for (final s in list) {
                  if (!_sizes.contains(s)) _sizes.add(s);
                }
              }),
            ),
        ]),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          for (final s in _sizes)
            InputChip(
              label: Text(s),
              onDeleted: widget.existing?.sizes.contains(s) ?? false ? null : () => setState(() => _sizes.remove(s)),
            ),
          SizedBox(
            width: 120,
            child: TextField(
              controller: _newSize,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(isDense: true, hintText: 'outro + Enter'),
              onSubmitted: _addSize,
            ),
          ),
        ]),
        gap,
        Text('Cores', style: t.textTheme.titleSmall),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          for (final c in _colors)
            InputChip(
              label: Text(c),
              onDeleted: widget.existing?.colors.contains(c) ?? false ? null : () => setState(() => _colors.remove(c)),
            ),
          SizedBox(
            width: 180,
            child: Autocomplete<String>(
              optionsBuilder: (v) => kColorSuggestions.where(
                  (c) => c.toLowerCase().contains(v.text.toLowerCase()) && !_colors.contains(c)),
              onSelected: (v) {
                _addColor(v);
              },
              fieldViewBuilder: (_, c, f, __) => TextField(
                controller: c,
                focusNode: f,
                decoration: const InputDecoration(isDense: true, hintText: 'cor + Enter'),
                onSubmitted: (v) {
                  _addColor(v);
                  c.clear();
                },
              ),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final c in kColorSuggestions.take(8))
            if (!_colors.contains(c)) ActionChip(label: Text(c), onPressed: () => _addColor(c)),
        ]),
      ]),
    );
  }

  Widget _stepStock(ThemeData t) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      const _Hint('Quantas peças você tem de cada combinação? Deixe em branco o que não tem (fica com estoque zero).'),
      const SizedBox(height: 12),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          defaultColumnWidth: const FixedColumnWidth(64),
          columnWidths: const {0: FixedColumnWidth(130)},
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            TableRow(children: [
              const Padding(padding: EdgeInsets.all(6), child: Text('Cor \\ Tam', style: TextStyle(fontWeight: FontWeight.bold))),
              for (final s in _sizes)
                Padding(
                  padding: const EdgeInsets.all(6),
                  child: Text(s, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
            ]),
            for (final c in _colors)
              TableRow(children: [
                Padding(padding: const EdgeInsets.all(6), child: Text(c)),
                for (final s in _sizes)
                  Padding(
                    padding: const EdgeInsets.all(3),
                    child: _exists(c, s)
                        ? Tooltip(
                            message: 'Já existe',
                            child: Text('✓ ${number(widget.existing!.variant(c, s)!.stockQty)}',
                                textAlign: TextAlign.center, style: TextStyle(color: t.colorScheme.outline)),
                          )
                        : TextField(
                            controller: _cell(c, s),
                            textAlign: TextAlign.center,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(isDense: true, hintText: '0'),
                          ),
                  ),
              ]),
          ],
        ),
      ),
    ]);
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: cs.primaryContainer.withValues(alpha: .5), borderRadius: BorderRadius.circular(10)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.lightbulb_outline, size: 18, color: cs.primary),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
      ]),
    );
  }
}
