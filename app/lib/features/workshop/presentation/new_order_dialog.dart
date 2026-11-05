import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../auth/domain/session.dart';
import '../../partners/domain/partner.dart';
import '../../partners/presentation/partner_picker_dialog.dart';
import '../../users/data/users_repository.dart';
import '../../users/domain/app_user.dart';
import '../data/workshop_repository.dart';
import '../domain/workshop.dart';
import 'vehicle_form_dialog.dart';

final mechanicsProvider = FutureProvider.autoDispose<List<AppUser>>((ref) async {
  final page = await ref.read(usersRepositoryProvider).list(role: 'MECANICO');
  return page.users.where((u) => u.isActive).toList();
});

/// Recepção da moto em 3 passos: 1) cliente e moto  2) o que o cliente relatou  3) checklist de entrada.
/// Retorna a OS criada.
class NewOrderDialog extends ConsumerStatefulWidget {
  const NewOrderDialog({super.key});

  @override
  ConsumerState<NewOrderDialog> createState() => _NewOrderDialogState();
}

class _NewOrderDialogState extends ConsumerState<NewOrderDialog> {
  int _step = 0;
  Partner? _customer;
  List<Vehicle> _vehicles = const [];
  Vehicle? _vehicle;
  final _complaint = TextEditingController();
  final _km = TextEditingController();
  String? _fuel;
  String? _mechanicId;
  DateTime? _promised;
  final Map<String, dynamic> _checklist = {for (final c in kChecklist) c: false};
  final _damage = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _complaint.dispose();
    _km.dispose();
    _damage.dispose();
    super.dispose();
  }

  Future<void> _pickCustomer() async {
    final p = await showDialog<Partner>(context: context, builder: (_) => const PartnerPickerDialog(title: 'Dono da moto'));
    if (p == null) return;
    setState(() {
      _customer = p;
      _vehicle = null;
      _vehicles = const [];
    });
    final list = await ref.read(workshopRepositoryProvider).vehicles(customerId: p.id);
    if (!mounted) return;
    setState(() {
      _vehicles = list;
      if (list.length == 1) _select(list.first);
    });
  }

  void _select(Vehicle v) {
    _vehicle = v;
    if (v.km != null && _km.text.isEmpty) _km.text = v.km.toString();
  }

  Future<void> _newVehicle() async {
    final v = await showDialog<Vehicle>(
      context: context,
      builder: (_) => VehicleFormDialog(customerId: _customer!.id, customerName: _customer!.displayName),
    );
    if (v == null) return;
    setState(() {
      _vehicles = [v, ..._vehicles];
      _select(v);
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final cl = Map<String, dynamic>.from(_checklist);
      if (_damage.text.trim().isNotEmpty) cl['Avarias'] = _damage.text.trim();
      final o = await ref.read(workshopRepositoryProvider).open(
            customerId: _customer!.id,
            vehicleId: _vehicle!.id,
            complaint: _complaint.text.trim().isEmpty ? null : _complaint.text.trim(),
            kmIn: int.tryParse(_km.text),
            fuelLevel: _fuel,
            checklist: cl,
            mechanicId: _mechanicId,
            promisedAt: _promised,
          );
      if (mounted) Navigator.pop(context, o);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  bool get _canNext => switch (_step) {
        0 => _customer != null && _vehicle != null,
        _ => true,
      };

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final mechanics = ref.watch(mechanicsProvider).valueOrNull ?? const [];

    final steps = [
      // ---------------------------------------------------------- 1. cliente e moto
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        const _Hint('Quem trouxe a moto? Busque pelo nome ou CPF — ou cadastre na hora.'),
        OutlinedButton.icon(
          onPressed: _pickCustomer,
          icon: const Icon(Icons.person_search),
          label: Text(_customer?.displayName ?? 'Escolher cliente'),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), alignment: Alignment.centerLeft),
        ),
        if (_customer != null) ...[
          const SizedBox(height: 16),
          Text('Qual moto?', style: t.textTheme.titleSmall),
          const SizedBox(height: 8),
          for (final v in _vehicles)
            Card(
              margin: const EdgeInsets.only(bottom: 6),
              color: _vehicle?.id == v.id ? t.colorScheme.primaryContainer : null,
              child: ListTile(
                leading: const Icon(Icons.two_wheeler),
                title: Text('${v.plateFmt} · ${v.label}'),
                subtitle: Text([if (v.color != null) v.color!, if (v.km != null) '${number(v.km!)} km'].join(' · ')),
                trailing: _vehicle?.id == v.id ? const Icon(Icons.check_circle) : null,
                onTap: () => setState(() => _select(v)),
              ),
            ),
          TextButton.icon(onPressed: _newVehicle, icon: const Icon(Icons.add), label: const Text('Cadastrar outra moto deste cliente')),
        ],
      ]),
      // ---------------------------------------------------------- 2. relato
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        const _Hint('Anote com as palavras do cliente o que ele percebeu. O diagnóstico do mecânico vem depois.'),
        TextField(
          controller: _complaint,
          autofocus: true,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'O que o cliente relatou', hintText: 'Ex.: barulho na corrente, revisão dos 20 mil'),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _km,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Km no painel'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              onTap: () async {
                final now = DateTime.now();
                final d = await showDatePicker(context: context, initialDate: now, firstDate: now, lastDate: now.add(const Duration(days: 90)));
                if (d == null || !context.mounted) return;
                final tm = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 17, minute: 0));
                setState(() => _promised = DateTime(d.year, d.month, d.day, tm?.hour ?? 17, tm?.minute ?? 0));
              },
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Previsão de entrega'),
                child: Text(_promised == null ? 'opcional' : dateTimeBr(_promised)),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        Text('Combustível', style: t.textTheme.labelLarge),
        const SizedBox(height: 6),
        Wrap(spacing: 6, children: [
          for (final f in kFuelLevels)
            ChoiceChip(label: Text(f), selected: _fuel == f, onSelected: (_) => setState(() => _fuel = f)),
        ]),
        const SizedBox(height: 12),
        DropdownButtonFormField<String?>(
          initialValue: _mechanicId,
          decoration: InputDecoration(
            labelText: 'Mecânico responsável',
            helperText: mechanics.isEmpty ? 'Cadastre mecânicos em Usuários (perfil Mecânico)' : null,
          ),
          items: [
            const DropdownMenuItem(value: null, child: Text('— definir depois —')),
            for (final m in mechanics) DropdownMenuItem(value: m.id, child: Text(m.fullName)),
          ],
          onChanged: (v) => setState(() => _mechanicId = v),
        ),
      ]),
      // ---------------------------------------------------------- 3. checklist
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        const _Hint('Confira a moto com o cliente olhando. Marque o que está presente e funcionando — isso evita discussão na retirada.'),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final c in kChecklist)
            FilterChip(
              label: Text(c),
              selected: _checklist[c] == true,
              onSelected: (v) => setState(() => _checklist[c] = v),
            ),
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: _damage,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'Riscos, amassados ou avarias', hintText: 'Ex.: risco no tanque lado esquerdo'),
        ),
      ]),
    ];

    const titles = ['Cliente e moto', 'Relato e entrada', 'Checklist'];

    return AlertDialog(
      title: Row(children: [
        const Expanded(child: Text('Receber moto (nova OS)')),
        Text('${_step + 1}/3', style: t.textTheme.labelLarge),
      ]),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              for (var i = 0; i < 3; i++) ...[
                Expanded(
                  child: Column(children: [
                    LinearProgressIndicator(value: i <= _step ? 1 : 0, minHeight: 4),
                    const SizedBox(height: 4),
                    Text(titles[i], style: t.textTheme.labelSmall?.copyWith(fontWeight: i == _step ? FontWeight.bold : null)),
                  ]),
                ),
                if (i < 2) const SizedBox(width: 6),
              ],
            ]),
            const SizedBox(height: 16),
            steps[_step],
          ]),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            if (_step == 0) {
              Navigator.pop(context);
            } else {
              setState(() => _step--);
            }
          },
          child: Text(_step == 0 ? 'Cancelar' : 'Voltar'),
        ),
        if (_step < 2)
          FilledButton(onPressed: _canNext ? () => setState(() => _step++) : null, child: const Text('Próximo'))
        else
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.check),
            label: const Text('Abrir OS'),
          ),
      ],
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.lightbulb_outline, size: 18, color: t.colorScheme.primary),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: t.textTheme.bodySmall)),
      ]),
    );
  }
}

/// Mostra quem pode ver o quê (usado na ajuda da oficina).
String workshopRoleHelp(UserRole r) => switch (r) {
      UserRole.mecanico => 'Você vê só as OS em que é o mecânico. Lance peças, serviços e o diagnóstico; o caixa recebe.',
      UserRole.caixa => 'Você abre OS na recepção e recebe a OS pronta no caixa.',
      _ => 'Você vê todas as OS, a tabela de mão de obra, comissões e revisões.',
    };
