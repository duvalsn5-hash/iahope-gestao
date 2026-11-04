import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/utils/formatters.dart';
import '../domain/partner.dart';

/// Cadastro de cliente / fornecedor. [quick] = versão curta usada dentro do PDV.
class PartnerFormDialog extends StatefulWidget {
  const PartnerFormDialog({super.key, this.initial, this.defaultKind = PartnerKind.cliente, this.quick = false});
  final Partner? initial;
  final PartnerKind defaultKind;
  final bool quick;

  @override
  State<PartnerFormDialog> createState() => _PartnerFormDialogState();
}

class _PartnerFormDialogState extends State<PartnerFormDialog> {
  final _form = GlobalKey<FormState>();
  late PartnerKind _kind = widget.initial?.kind ?? widget.defaultKind;
  late bool _active = widget.initial?.isActive ?? true;
  late final _doc = TextEditingController(text: formatDoc(widget.initial?.doc));
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late final _trade = TextEditingController(text: widget.initial?.tradeName ?? '');
  late final _ie = TextEditingController(text: widget.initial?.ie ?? '');
  late final _phone = TextEditingController(text: widget.initial?.phone ?? '');
  late final _email = TextEditingController(text: widget.initial?.email ?? '');
  late final _zip = TextEditingController(text: widget.initial?.zip ?? '');
  late final _street = TextEditingController(text: widget.initial?.street ?? '');
  late final _number = TextEditingController(text: widget.initial?.number ?? '');
  late final _district = TextEditingController(text: widget.initial?.district ?? '');
  late final _city = TextEditingController(text: widget.initial?.city ?? '');
  late final _state = TextEditingController(text: widget.initial?.state ?? '');
  late final _limit = TextEditingController(
      text: (widget.initial?.creditLimit ?? 0) == 0 ? '' : widget.initial!.creditLimit.toStringAsFixed(2).replaceAll('.', ','));
  late final _notes = TextEditingController(text: widget.initial?.notes ?? '');

  bool get _isNew => widget.initial == null || widget.initial!.id.isEmpty;

  List<TextEditingController> get _all =>
      [_doc, _name, _trade, _ie, _phone, _email, _zip, _street, _number, _district, _city, _state, _limit, _notes];

  @override
  void dispose() {
    for (final c in _all) {
      c.dispose();
    }
    super.dispose();
  }

  String? _nn(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  void _save() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(
      context,
      Partner(
        id: widget.initial?.id ?? '',
        kind: _kind,
        doc: onlyDigits(_doc.text).isEmpty ? null : onlyDigits(_doc.text),
        name: _name.text.trim(),
        tradeName: _nn(_trade),
        ie: _nn(_ie),
        phone: _nn(_phone),
        email: _nn(_email),
        zip: onlyDigits(_zip.text).isEmpty ? null : onlyDigits(_zip.text),
        street: _nn(_street),
        number: _nn(_number),
        district: _nn(_district),
        city: _nn(_city),
        state: _nn(_state)?.toUpperCase(),
        creditLimit: parseMoney(_limit.text),
        notes: _nn(_notes),
        isActive: _active,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 12, width: 12);
    final quick = widget.quick;

    return AlertDialog(
      title: Text(_isNew ? (quick ? 'Cliente rápido' : 'Novo cadastro') : 'Editar cadastro'),
      content: SizedBox(
        width: 560,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (!quick)
                SegmentedButton<PartnerKind>(
                  segments: [
                    for (final k in PartnerKind.values) ButtonSegment(value: k, label: Text(partnerKindLabel(k))),
                  ],
                  selected: {_kind},
                  onSelectionChanged: (s) => setState(() => _kind = s.first),
                ),
              if (!quick) gap,
              TextFormField(
                controller: _doc,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [CpfCnpjInputFormatter()],
                decoration: const InputDecoration(labelText: 'CPF ou CNPJ', hintText: 'opcional para consumidor'),
                validator: (v) {
                  final d = onlyDigits(v ?? '');
                  if (d.isEmpty) return null;
                  if (d.length == 11) return isValidCpf(d) ? null : 'CPF inválido';
                  if (d.length == 14) return isValidCnpj(d) ? null : 'CNPJ inválido';
                  return 'Informe 11 (CPF) ou 14 (CNPJ) dígitos';
                },
              ),
              gap,
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Nome / Razão social'),
                validator: (v) => (v ?? '').trim().length < 2 ? 'Informe o nome' : null,
              ),
              gap,
              Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Telefone / WhatsApp'),
                  ),
                ),
                if (!quick) ...[
                  gap,
                  Expanded(
                    child: TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'E-mail'),
                      validator: (v) =>
                          (v ?? '').trim().isEmpty || RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v!.trim()) ? null : 'E-mail inválido',
                    ),
                  ),
                ],
              ]),
              if (!quick) ...[
                gap,
                Row(children: [
                  Expanded(child: TextFormField(controller: _trade, decoration: const InputDecoration(labelText: 'Nome fantasia'))),
                  gap,
                  SizedBox(
                    width: 180,
                    child: TextFormField(controller: _ie, decoration: const InputDecoration(labelText: 'Inscrição estadual')),
                  ),
                ]),
                gap,
                Row(children: [
                  SizedBox(
                    width: 130,
                    child: TextFormField(
                      controller: _zip,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)],
                      decoration: const InputDecoration(labelText: 'CEP'),
                    ),
                  ),
                  gap,
                  Expanded(child: TextFormField(controller: _street, decoration: const InputDecoration(labelText: 'Endereço'))),
                  gap,
                  SizedBox(width: 90, child: TextFormField(controller: _number, decoration: const InputDecoration(labelText: 'Nº'))),
                ]),
                gap,
                Row(children: [
                  Expanded(child: TextFormField(controller: _district, decoration: const InputDecoration(labelText: 'Bairro'))),
                  gap,
                  Expanded(child: TextFormField(controller: _city, decoration: const InputDecoration(labelText: 'Cidade'))),
                  gap,
                  SizedBox(
                    width: 70,
                    child: TextFormField(
                      controller: _state,
                      textCapitalization: TextCapitalization.characters,
                      inputFormatters: [LengthLimitingTextInputFormatter(2)],
                      decoration: const InputDecoration(labelText: 'UF'),
                    ),
                  ),
                ]),
                if (_kind != PartnerKind.fornecedor) ...[
                  gap,
                  TextFormField(
                    controller: _limit,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Limite para venda a prazo',
                      prefixText: r'R$ ',
                      helperText: 'deixe vazio para não limitar',
                    ),
                  ),
                ],
                gap,
                TextFormField(
                  controller: _notes,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Observações'),
                ),
                if (!_isNew)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Ativo'),
                    value: _active,
                    onChanged: (v) => setState(() => _active = v),
                  ),
              ],
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
