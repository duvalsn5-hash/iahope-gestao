import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/common_widgets.dart';
import '../data/workshop_repository.dart';
import '../domain/workshop.dart';

const kBrands = ['Honda', 'Yamaha', 'Suzuki', 'Kawasaki', 'BMW', 'Triumph', 'Harley-Davidson', 'Dafra', 'Shineray', 'Haojue', 'Royal Enfield', 'Outra'];

/// Cadastro / edição da moto de um cliente. Retorna a moto salva.
class VehicleFormDialog extends ConsumerStatefulWidget {
  const VehicleFormDialog({super.key, required this.customerId, required this.customerName, this.initial});
  final String customerId;
  final String customerName;
  final Vehicle? initial;

  @override
  ConsumerState<VehicleFormDialog> createState() => _VehicleFormDialogState();
}

class _VehicleFormDialogState extends ConsumerState<VehicleFormDialog> {
  final _form = GlobalKey<FormState>();
  late final _plate = TextEditingController(text: widget.initial?.plateFmt ?? '');
  late final _model = TextEditingController(text: widget.initial?.model ?? '');
  late final _year = TextEditingController(text: widget.initial?.year?.toString() ?? '');
  late final _color = TextEditingController(text: widget.initial?.color ?? '');
  late final _km = TextEditingController(text: widget.initial?.km?.toString() ?? '');
  late final _chassis = TextEditingController(text: widget.initial?.chassis ?? '');
  late String? _brand = widget.initial?.brand;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_plate, _model, _year, _color, _km, _chassis]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final v = await ref.read(workshopRepositoryProvider).saveVehicle(
            Vehicle(
              id: '',
              customerId: widget.customerId,
              plate: _plate.text.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), ''),
              brand: _brand,
              model: _model.text.trim(),
              year: int.tryParse(_year.text),
              color: _color.text.trim().isEmpty ? null : _color.text.trim(),
              km: int.tryParse(_km.text),
              chassis: _chassis.text.trim().isEmpty ? null : _chassis.text.trim(),
            ),
            id: widget.initial?.id,
          );
      if (mounted) Navigator.pop(context, v);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 12, width: 12);
    final digits = [FilteringTextInputFormatter.digitsOnly];
    return AlertDialog(
      title: Text(widget.initial == null ? 'Nova moto' : 'Editar moto'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Dono: ${widget.customerName}', style: Theme.of(context).textTheme.bodyMedium),
              gap,
              TextFormField(
                controller: _plate,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [LengthLimitingTextInputFormatter(8)],
                decoration: const InputDecoration(labelText: 'Placa', hintText: 'ABC1D23 ou ABC-1234'),
                validator: (v) {
                  final p = (v ?? '').toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
                  return RegExp(r'^[A-Z0-9]{5,8}$').hasMatch(p) ? null : 'Placa inválida';
                },
              ),
              gap,
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: kBrands.contains(_brand) ? _brand : null,
                    decoration: const InputDecoration(labelText: 'Marca'),
                    items: [for (final b in kBrands) DropdownMenuItem(value: b, child: Text(b))],
                    onChanged: (v) => setState(() => _brand = v),
                  ),
                ),
                gap,
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _model,
                    decoration: const InputDecoration(labelText: 'Modelo', hintText: 'CG 160 Titan'),
                    validator: (v) => (v ?? '').trim().isEmpty ? 'Informe o modelo' : null,
                  ),
                ),
              ]),
              gap,
              Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: _year,
                    keyboardType: TextInputType.number,
                    inputFormatters: [...digits, LengthLimitingTextInputFormatter(4)],
                    decoration: const InputDecoration(labelText: 'Ano'),
                  ),
                ),
                gap,
                Expanded(child: TextFormField(controller: _color, decoration: const InputDecoration(labelText: 'Cor'))),
                gap,
                Expanded(
                  child: TextFormField(
                    controller: _km,
                    keyboardType: TextInputType.number,
                    inputFormatters: digits,
                    decoration: const InputDecoration(labelText: 'Km'),
                  ),
                ),
              ]),
              gap,
              TextFormField(controller: _chassis, decoration: const InputDecoration(labelText: 'Chassi (opcional)')),
            ]),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _saving ? null : _save, child: const Text('Salvar moto')),
      ],
    );
  }
}
