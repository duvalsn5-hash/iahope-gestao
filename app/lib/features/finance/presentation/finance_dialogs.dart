import 'package:flutter/material.dart';

import '../../../core/utils/formatters.dart';
import '../../partners/domain/partner.dart';
import '../../partners/presentation/partner_picker_dialog.dart';
import '../domain/finance.dart';

const kSettleMethods = {
  'DINHEIRO': 'Dinheiro',
  'PIX': 'PIX',
  'TRANSFERENCIA': 'Transferência',
  'BOLETO': 'Boleto',
  'DEBITO': 'Cartão de débito',
  'CREDITO': 'Cartão de crédito',
  'OUTROS': 'Outros',
};

/// Lançamento manual de conta a pagar ou a receber (com parcelamento).
class FinEntryDialog extends StatefulWidget {
  const FinEntryDialog({super.key, required this.kind});
  final String kind; // PAGAR | RECEBER

  @override
  State<FinEntryDialog> createState() => _FinEntryDialogState();
}

class _FinEntryDialogState extends State<FinEntryDialog> {
  final _form = GlobalKey<FormState>();
  final _desc = TextEditingController();
  final _category = TextEditingController();
  final _doc = TextEditingController();
  final _amount = TextEditingController();
  final _parts = TextEditingController(text: '1');
  DateTime _due = DateTime.now();
  Partner? _partner;

  bool get _pay => widget.kind == 'PAGAR';

  @override
  void dispose() {
    for (final c in [_desc, _category, _doc, _amount, _parts]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickPartner() async {
    final p = await showDialog<Partner>(
      context: context,
      builder: (_) => PartnerPickerDialog(
        kind: _pay ? 'FORNECEDOR' : 'CLIENTE',
        title: _pay ? 'Fornecedor' : 'Cliente',
      ),
    );
    if (p != null) setState(() => _partner = p);
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(
      context,
      NewFinEntry(
        kind: widget.kind,
        partnerId: _partner?.id,
        description: _desc.text.trim(),
        category: _category.text.trim().isEmpty ? null : _category.text.trim(),
        document: _doc.text.trim().isEmpty ? null : _doc.text.trim(),
        dueDate: _due,
        amount: parseMoney(_amount.text),
        installments: (int.tryParse(_parts.text) ?? 1).clamp(1, 60).toInt(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 12, width: 12);
    final cats = _pay
        ? const ['Fornecedores', 'Aluguel', 'Energia', 'Água', 'Internet', 'Salários', 'Impostos', 'Frete', 'Outros']
        : const ['Vendas', 'Serviços', 'Outros'];
    final parts = int.tryParse(_parts.text) ?? 1;
    final amount = parseMoney(_amount.text);

    return AlertDialog(
      title: Text(_pay ? 'Nova conta a pagar' : 'Nova conta a receber'),
      content: SizedBox(
        width: 500,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(
                controller: _desc,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Descrição'),
                validator: (v) => (v ?? '').trim().length < 2 ? 'Informe a descrição' : null,
              ),
              gap,
              InkWell(
                onTap: _pickPartner,
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: _pay ? 'Fornecedor (opcional)' : 'Cliente (opcional)',
                    suffixIcon: _partner == null
                        ? const Icon(Icons.search)
                        : IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _partner = null)),
                  ),
                  child: Text(_partner?.displayName ?? 'Selecionar…'),
                ),
              ),
              gap,
              Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: _amount,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Valor total', prefixText: r'R$ '),
                    onChanged: (_) => setState(() {}),
                    validator: (v) => parseMoney(v ?? '') <= 0 ? 'Informe o valor' : null,
                  ),
                ),
                gap,
                SizedBox(
                  width: 110,
                  child: TextFormField(
                    controller: _parts,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Parcelas'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ]),
              if (parts > 1 && amount > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('$parts parcelas mensais de ~${money(amount / parts)}',
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
                ),
              gap,
              Row(children: [
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _due,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (d != null) setState(() => _due = d);
                    },
                    child: InputDecorator(
                      decoration: InputDecoration(labelText: parts > 1 ? '1º vencimento' : 'Vencimento'),
                      child: Text(dateBr(_due)),
                    ),
                  ),
                ),
                gap,
                Expanded(child: TextFormField(controller: _doc, decoration: const InputDecoration(labelText: 'Nº documento'))),
              ]),
              gap,
              Autocomplete<String>(
                optionsBuilder: (v) => cats.where((c) => c.toLowerCase().contains(v.text.toLowerCase())),
                onSelected: (v) => _category.text = v,
                fieldViewBuilder: (context, ctrl, focus, onSubmit) => TextFormField(
                  controller: ctrl,
                  focusNode: focus,
                  decoration: const InputDecoration(labelText: 'Categoria'),
                  onChanged: (v) => _category.text = v,
                ),
              ),
            ]),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _save, child: const Text('Lançar')),
      ],
    );
  }
}

/// Baixa (pagamento/recebimento) total ou parcial.
/// Retorna (valor, forma, passa pela gaveta do caixa?)
class SettleDialog extends StatefulWidget {
  const SettleDialog({super.key, required this.entry});
  final FinEntry entry;

  @override
  State<SettleDialog> createState() => _SettleDialogState();
}

class _SettleDialogState extends State<SettleDialog> {
  late final _amount = TextEditingController(text: widget.entry.balance.toStringAsFixed(2).replaceAll('.', ','));
  String _method = 'PIX';
  bool _fromCash = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final receive = e.kind == 'RECEBER';
    return AlertDialog(
      title: Text(receive ? 'Receber' : 'Pagar'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(e.description, style: const TextStyle(fontWeight: FontWeight.w600)),
          if (e.partnerName != null) Text(e.partnerName!),
          Text('Vencimento ${dateBr(e.dueDate)} · saldo ${money(e.balance)}'),
          const SizedBox(height: 16),
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Valor', prefixText: r'R$ ', helperText: 'menor que o saldo = baixa parcial'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _method,
            decoration: const InputDecoration(labelText: 'Forma'),
            items: [for (final m in kSettleMethods.entries) DropdownMenuItem(value: m.key, child: Text(m.value))],
            onChanged: (v) => setState(() {
              _method = v ?? 'PIX';
              if (_method != 'DINHEIRO') _fromCash = false;
            }),
          ),
          if (_method == 'DINHEIRO')
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _fromCash,
              onChanged: (v) => setState(() => _fromCash = v ?? false),
              title: Text(receive ? 'Entrou na gaveta do meu caixa' : 'Saiu da gaveta do meu caixa'),
              subtitle: const Text('Precisa estar com o caixa aberto no PDV'),
            ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            final v = parseMoney(_amount.text);
            if (v <= 0) return;
            Navigator.pop(context, (v, _method, _fromCash));
          },
          child: Text(receive ? 'Confirmar recebimento' : 'Confirmar pagamento'),
        ),
      ],
    );
  }
}
