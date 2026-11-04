import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../auth/presentation/session_controller.dart';
import '../domain/productivity.dart';
import 'hourly_bar_chart.dart';
import 'productivity_controller.dart';

/// Acompanhamento do ritmo de descarga hora a hora, por doca e por carga.
/// Atalhos: F7 lançar produção · F8 nova carga · Ctrl+R atualizar
class ProductivityDashboard extends ConsumerWidget {
  const ProductivityDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dash = ref.watch(productivityControllerProvider);
    final day = ref.watch(productivityDayProvider);
    final canRecord = ref.watch(sessionControllerProvider)?.canRecordProductivity ?? false;
    final now = DateTime.now();
    final isToday = day.year == now.year && day.month == now.month && day.day == now.day;

    Future<void> openRecord([OpenOrder? order]) async {
      final data = dash.valueOrNull;
      final entry = await showDialog<ProductivityEntry>(
        context: context,
        builder: (_) => _RecordDialog(orders: data?.orders ?? const [], preselected: order, docks: data?.docks.map((d) => d.dock).toList() ?? const []),
      );
      if (entry == null || !context.mounted) return;
      try {
        await ref.read(productivityControllerProvider.notifier).record(entry);
        if (context.mounted) showOk(context, '${entry.volumes} volumes lançados na ${entry.dock}');
      } catch (e) {
        if (context.mounted) showError(context, e);
      }
    }

    Future<void> openNewOrder() async {
      final r = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => const _NewOrderDialog());
      if (r == null || !context.mounted) return;
      try {
        await ref.read(productivityControllerProvider.notifier).createOrder(
              number: r['number'] as String,
              carrier: r['carrier'] as String?,
              plate: r['plate'] as String?,
              dock: r['dock'] as String?,
              expected: r['expected'] as int,
            );
      } catch (e) {
        if (context.mounted) showError(context, e);
      }
    }

    return CallbackShortcuts(
      bindings: {
        if (canRecord && isToday) const SingleActivator(LogicalKeyboardKey.f7): () => openRecord(),
        if (canRecord) const SingleActivator(LogicalKeyboardKey.f8): openNewOrder,
        const SingleActivator(LogicalKeyboardKey.keyR, control: true): () =>
            ref.read(productivityControllerProvider.notifier).silentRefresh(),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          floatingActionButton: canRecord && isToday
              ? FloatingActionButton.extended(
                  onPressed: openRecord,
                  icon: const Icon(Icons.add_chart),
                  label: Text(Breakpoints.isCompact(context) ? 'Lançar' : 'Lançar produção (F7)'),
                )
              : null,
          body: RefreshIndicator(
            onRefresh: () => ref.read(productivityControllerProvider.notifier).silentRefresh(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  alignment: WrapAlignment.spaceBetween,
                  children: [
                    Text('Produtividade de descarga', style: Theme.of(context).textTheme.headlineSmall),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      if (isToday)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.circle, size: 10, color: Colors.green.shade600),
                            const SizedBox(width: 4),
                            Text('Ao vivo · ${AppConfig.productivityRefresh.inSeconds}s',
                                style: Theme.of(context).textTheme.labelSmall),
                          ]),
                        ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.calendar_today, size: 16),
                        label: Text(isToday ? 'Hoje' : dateBr(day)),
                        onPressed: () async {
                          final d = await showDatePicker(
                            context: context,
                            initialDate: day,
                            firstDate: DateTime(2024),
                            lastDate: DateTime.now(),
                          );
                          if (d != null) ref.read(productivityDayProvider.notifier).state = d;
                        },
                      ),
                      if (canRecord) ...[
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.local_shipping_outlined, size: 16),
                          label: const Text('Nova carga (F8)'),
                          onPressed: openNewOrder,
                        ),
                      ],
                    ]),
                  ],
                ),
                const SizedBox(height: 12),
                dash.when(
                  loading: () => const Padding(padding: EdgeInsets.all(64), child: Center(child: CircularProgressIndicator())),
                  error: (e, _) => Card(child: ListTile(leading: const Icon(Icons.error), title: Text(e.toString()))),
                  data: (d) => _DashboardBody(data: d, isToday: isToday, onRecordForOrder: canRecord && isToday ? openRecord : null),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DashboardBody extends ConsumerWidget {
  const _DashboardBody({required this.data, required this.isToday, this.onRecordForOrder});
  final ProductivityDashboardData data;
  final bool isToday;
  final void Function(OpenOrder)? onRecordForOrder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final nowHour = DateTime.now().hour;
    final current = isToday ? data.hours.firstWhere((h) => h.hour == nowHour) : null;
    final pct = data.pctTarget;
    final pctColor = pct == null ? null : pct >= 100 ? Colors.green.shade700 : pct >= 80 ? Colors.amber.shade800 : t.colorScheme.error;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ResponsiveGrid(maxColumns: 5, children: [
        KpiCard(label: 'Volumes no dia', value: number(data.totalVolumes), icon: Icons.inventory_2),
        KpiCard(label: 'Peso descarregado', value: '${number(data.totalWeightKg.round())} kg', icon: Icons.scale),
        KpiCard(
          label: '% da meta',
          value: pct == null ? '—' : '${pct.toStringAsFixed(1)}%',
          icon: Icons.flag,
          color: pctColor,
          subtitle: data.targetVolumes > 0 ? 'meta ${number(data.targetVolumes)}' : 'sem meta lançada',
        ),
        KpiCard(label: 'Média por hora', value: number(data.avgPerHour), icon: Icons.speed,
            subtitle: data.peakHour != null ? 'pico às ${data.peakHour}h' : null),
        if (current != null)
          KpiCard(
            label: 'Hora atual (${nowHour}h)',
            value: number(current.volumes),
            icon: Icons.timer,
            subtitle: current.target > 0 ? 'meta ${number(current.target)}' : null,
          ),
      ]),
      const SizedBox(height: 16),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('Volumes por hora', style: t.textTheme.titleMedium)),
              Text('atualizado ${TimeOfDay.fromDateTime(data.loadedAt).format(context)}', style: t.textTheme.labelSmall),
            ]),
            const SizedBox(height: 4),
            Text('— linha = meta da hora', style: t.textTheme.labelSmall),
            const SizedBox(height: 12),
            HourlyBarChart(hours: data.hours, highlightHour: isToday ? nowHour : null),
          ]),
        ),
      ),
      const SizedBox(height: 16),
      LayoutBuilder(builder: (context, c) {
        final docks = _DocksCard(docks: data.docks);
        final orders = _OrdersCard(orders: data.orders, onRecord: onRecordForOrder);
        return c.maxWidth >= 900
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: docks),
                const SizedBox(width: 16),
                Expanded(child: orders),
              ])
            : Column(children: [docks, const SizedBox(height: 16), orders]);
      }),
    ]);
  }
}

class _DocksCard extends StatelessWidget {
  const _DocksCard({required this.docks});
  final List<DockTotal> docks;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(padding: const EdgeInsets.all(16), child: Text('Por doca', style: Theme.of(context).textTheme.titleMedium)),
        if (docks.isEmpty) const Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 16), child: Text('Nenhum lançamento no dia')),
        for (final d in docks)
          ListTile(
            leading: const Icon(Icons.garage_outlined),
            title: Text(d.dock),
            subtitle: d.target > 0
                ? Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: LinearProgressIndicator(value: (d.volumes / d.target).clamp(0, 1).toDouble(), minHeight: 6),
                  )
                : Text('${number(d.weightKg.round())} kg'),
            trailing: Text(number(d.volumes), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
      ]),
    );
  }
}

class _OrdersCard extends ConsumerWidget {
  const _OrdersCard({required this.orders, this.onRecord});
  final List<OpenOrder> orders;
  final void Function(OpenOrder)? onRecord;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(padding: const EdgeInsets.all(16), child: Text('Cargas em aberto', style: Theme.of(context).textTheme.titleMedium)),
        if (orders.isEmpty) const Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 16), child: Text('Nenhuma carga aguardando')),
        for (final o in orders)
          ListTile(
            leading: Icon(o.status == 'EM_DESCARGA' ? Icons.downloading : Icons.schedule),
            title: Text('${o.orderNumber}${o.carrier != null ? ' · ${o.carrier}' : ''}'),
            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${o.vehiclePlate ?? 'sem placa'} · ${o.dock ?? 'doca não definida'} · ${number(o.unloaded)}/${number(o.expected)} vol'),
              if (o.expected > 0)
                Padding(padding: const EdgeInsets.only(top: 4), child: LinearProgressIndicator(value: o.progress)),
            ]),
            trailing: PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'LANCAR') {
                  onRecord?.call(o);
                  return;
                }
                try {
                  await ref.read(productivityControllerProvider.notifier).setOrderStatus(o.id, v);
                } catch (e) {
                  if (context.mounted) showError(context, e);
                }
              },
              itemBuilder: (_) => [
                if (onRecord != null) const PopupMenuItem(value: 'LANCAR', child: Text('Lançar volumes')),
                if (o.status == 'AGUARDANDO') const PopupMenuItem(value: 'EM_DESCARGA', child: Text('Iniciar descarga')),
                const PopupMenuItem(value: 'FINALIZADO', child: Text('Finalizar')),
                const PopupMenuItem(value: 'CANCELADO', child: Text('Cancelar')),
              ],
            ),
          ),
      ]),
    );
  }
}

class _RecordDialog extends StatefulWidget {
  const _RecordDialog({required this.orders, required this.docks, this.preselected});
  final List<OpenOrder> orders;
  final List<String> docks;
  final OpenOrder? preselected;

  @override
  State<_RecordDialog> createState() => _RecordDialogState();
}

class _RecordDialogState extends State<_RecordDialog> {
  final _form = GlobalKey<FormState>();
  late final _dock = TextEditingController(text: widget.preselected?.dock ?? (widget.docks.isNotEmpty ? widget.docks.first : 'DOCA 1'));
  final _volumes = TextEditingController();
  final _weight = TextEditingController();
  final _pallets = TextEditingController();
  final _team = TextEditingController(text: '1');
  final _target = TextEditingController();
  String? _orderId;

  @override
  void initState() {
    super.initState();
    _orderId = widget.preselected?.id;
  }

  @override
  void dispose() {
    for (final c in [_dock, _volumes, _weight, _pallets, _team, _target]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(
      context,
      ProductivityEntry(
        dock: _dock.text.trim().toUpperCase(),
        volumes: int.parse(_volumes.text),
        weightKg: parseMoney(_weight.text),
        pallets: int.tryParse(_pallets.text) ?? 0,
        teamSize: int.tryParse(_team.text) ?? 1,
        targetVolumes: int.tryParse(_target.text) ?? 0,
        orderId: _orderId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final digits = [FilteringTextInputFormatter.digitsOnly];
    InputDecoration dec(String l) => InputDecoration(labelText: l);
    const gap = SizedBox(height: 12, width: 12);

    return AlertDialog(
      title: Text('Lançar produção — ${TimeOfDay.now().hour}h'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String?>(
                value: _orderId,
                isExpanded: true,
                decoration: dec('Carga (opcional)'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('— sem vínculo —')),
                  for (final o in widget.orders)
                    DropdownMenuItem(value: o.id, child: Text('${o.orderNumber} ${o.carrier ?? ''}', overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() => _orderId = v),
              ),
              gap,
              TextFormField(controller: _dock, decoration: dec('Doca'), validator: (v) => (v ?? '').trim().isEmpty ? 'Informe a doca' : null),
              gap,
              Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: _volumes,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: digits,
                    decoration: dec('Volumes'),
                    validator: (v) => (int.tryParse(v ?? '') ?? -1) < 0 ? 'Obrigatório' : null,
                  ),
                ),
                gap,
                Expanded(child: TextFormField(controller: _weight, keyboardType: TextInputType.number, decoration: dec('Peso (kg)'))),
              ]),
              gap,
              Row(children: [
                Expanded(child: TextFormField(controller: _pallets, keyboardType: TextInputType.number, inputFormatters: digits, decoration: dec('Pallets'))),
                gap,
                Expanded(child: TextFormField(controller: _team, keyboardType: TextInputType.number, inputFormatters: digits, decoration: dec('Equipe'))),
                gap,
                Expanded(
                  child: TextFormField(
                    controller: _target,
                    keyboardType: TextInputType.number,
                    inputFormatters: digits,
                    decoration: dec('Meta/hora'),
                    onFieldSubmitted: (_) => _save(),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              Text('Os volumes são somados ao que já foi lançado nesta hora para a doca.',
                  style: Theme.of(context).textTheme.bodySmall),
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

class _NewOrderDialog extends StatefulWidget {
  const _NewOrderDialog();

  @override
  State<_NewOrderDialog> createState() => _NewOrderDialogState();
}

class _NewOrderDialogState extends State<_NewOrderDialog> {
  final _number = TextEditingController();
  final _carrier = TextEditingController();
  final _plate = TextEditingController();
  final _dock = TextEditingController();
  final _expected = TextEditingController();

  @override
  void dispose() {
    for (final c in [_number, _carrier, _plate, _dock, _expected]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    if (_number.text.trim().isEmpty) return;
    Navigator.pop(context, {
      'number': _number.text.trim(),
      'carrier': _carrier.text.trim(),
      'plate': _plate.text.trim().toUpperCase(),
      'dock': _dock.text.trim().toUpperCase(),
      'expected': int.tryParse(_expected.text) ?? 0,
    });
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 12);
    return AlertDialog(
      title: const Text('Nova carga'),
      content: SizedBox(
        width: 400,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: _number, autofocus: true, decoration: const InputDecoration(labelText: 'Nº da carga / ordem')),
          gap,
          TextField(controller: _carrier, decoration: const InputDecoration(labelText: 'Transportadora')),
          gap,
          Row(children: [
            Expanded(child: TextField(controller: _plate, decoration: const InputDecoration(labelText: 'Placa'))),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: _dock, decoration: const InputDecoration(labelText: 'Doca'))),
          ]),
          gap,
          TextField(
            controller: _expected,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Volumes previstos'),
            onSubmitted: (_) => _save(),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _save, child: const Text('Criar')),
      ],
    );
  }
}
