import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/utils/whatsapp.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../auth/presentation/session_controller.dart';
import '../../cash/data/cash_repository.dart';
import '../../pos/presentation/widgets/payment_dialog.dart';
import '../../pos/presentation/widgets/receipt_dialog.dart';
import '../../products/data/products_repository.dart';
import '../../products/domain/product.dart';
import '../data/os_printer.dart';
import '../data/workshop_repository.dart';
import '../domain/workshop.dart';
import 'new_order_dialog.dart' show mechanicsProvider;

/// Uma OS do começo ao fim. O botão grande no topo sempre mostra o próximo passo.
/// Atalhos: Ctrl+S salvar · Ctrl+P imprimir
class WorkOrderPage extends ConsumerStatefulWidget {
  const WorkOrderPage({super.key, required this.orderId});
  final String orderId;

  @override
  ConsumerState<WorkOrderPage> createState() => _WorkOrderPageState();
}

class _WorkOrderPageState extends ConsumerState<WorkOrderPage> {
  WorkOrder? _o;
  bool _dirty = false;
  bool _busy = false;
  final _diagnosis = TextEditingController();
  final _complaint = TextEditingController();
  final _discount = TextEditingController();

  WorkshopRepository get _repo => ref.read(workshopRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _diagnosis.dispose();
    _complaint.dispose();
    _discount.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final o = await _repo.order(widget.orderId);
      if (mounted) _apply(o);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  void _apply(WorkOrder o) {
    setState(() {
      _o = o;
      _dirty = false;
      _diagnosis.text = o.diagnosis ?? '';
      _complaint.text = o.complaint ?? '';
      _discount.text = o.discount == 0 ? '' : o.discount.toStringAsFixed(2).replaceAll('.', ',');
    });
  }

  void _touch() => setState(() => _dirty = true);

  /// Salva antes de qualquer passo (andamento, WhatsApp, impressão, caixa).
  Future<bool> _save({bool quiet = false}) async {
    final o = _o;
    if (o == null || o.status.isFinal) return true;
    if (!_dirty) return true;
    o.diagnosis = _diagnosis.text.trim().isEmpty ? null : _diagnosis.text.trim();
    o.complaint = _complaint.text.trim().isEmpty ? null : _complaint.text.trim();
    o.discount = parseMoney(_discount.text);
    setState(() => _busy = true);
    try {
      _apply(await _repo.save(o));
      if (!quiet && mounted) showOk(context, 'OS salva');
      return true;
    } catch (e) {
      if (mounted) showError(context, e);
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _advance(OsStatus to, {String? note}) async {
    if (!await _save(quiet: true)) return;
    final o = _o!;
    if (to == OsStatus.orcamento && o.items.isEmpty) {
      showError(context, 'Lance as peças e a mão de obra antes de enviar o orçamento');
      return;
    }
    setState(() => _busy = true);
    try {
      _apply(await _repo.setStatus(o.id, to, note: note));
      if (to == OsStatus.orcamento && mounted) await _sendBudget();
      if (to == OsStatus.pronta && mounted) await _offerReadyMessage();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _company() => ref.read(sessionControllerProvider)?.tenant.nomeFantasia ?? '';

  String _budgetText(WorkOrder o) {
    final b = StringBuffer()
      ..writeln('*${_company()}* — Orçamento OS nº ${o.number}')
      ..writeln('Moto: ${o.vehicle.label} · ${o.vehicle.plateFmt}')
      ..writeln();
    if ((o.diagnosis ?? '').isNotEmpty) b..writeln('Diagnóstico: ${o.diagnosis}')..writeln();
    final parts = o.items.where((i) => i.isPart).toList();
    final labor = o.items.where((i) => !i.isPart).toList();
    if (parts.isNotEmpty) {
      b.writeln('*Peças*');
      for (final i in parts) {
        b.writeln('• ${i.description}${i.qty != 1 ? ' (${number(i.qty)}x)' : ''} — ${money(i.total)}');
      }
    }
    if (labor.isNotEmpty) {
      b.writeln('*Mão de obra*');
      for (final i in labor) {
        b.writeln('• ${i.description} — ${money(i.total)}');
      }
    }
    if (o.discount > 0) b.writeln('Desconto: - ${money(o.discount)}');
    b
      ..writeln()
      ..writeln('*Total: ${money(o.total)}*')
      ..writeln('Garantia: ${o.warrantyDays} dias.')
      ..writeln()
      ..writeln('Posso fazer o serviço? Responda *SIM* para aprovar.');
    return b.toString();
  }

  Future<void> _sendBudget() async {
    final o = _o!;
    final ok = await openWhatsApp(o.customerPhone, _budgetText(o));
    if (!ok && mounted) {
      await Clipboard.setData(ClipboardData(text: _budgetText(o)));
      if (mounted) showOk(context, 'Não abriu o WhatsApp — o orçamento foi copiado, é só colar na conversa');
    }
  }

  Future<void> _offerReadyMessage() async {
    final o = _o!;
    final send = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Moto pronta!'),
        content: Text('Avisar ${o.customerName} pelo WhatsApp que a moto pode ser retirada?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Agora não')),
          FilledButton.icon(onPressed: () => Navigator.pop(c, true), icon: const Icon(Icons.chat), label: const Text('Avisar')),
        ],
      ),
    );
    if (send == true) {
      await openWhatsApp(o.customerPhone,
          'Olá, ${o.customerName.split(' ').first}! Sua ${o.vehicle.label} (${o.vehicle.plateFmt}) está pronta na *${_company()}*. '
          'Total: *${money(o.total)}*. Pode vir retirar quando quiser.');
    }
  }

  Future<void> _print() async {
    if (!await _save(quiet: true)) return;
    final s = ref.read(sessionControllerProvider);
    try {
      await OsPrinter.print(_o!, company: s?.tenant.razaoSocial ?? _company(), companyDoc: s?.tenant.cnpj, logoUrl: s?.tenant.logoUrl);
    } catch (e) {
      if (mounted) showError(context, 'Falha ao imprimir: $e');
    }
  }

  Future<void> _closeAtCashier() async {
    if (!await _save(quiet: true)) return;
    final o = _o!;
    final cash = await ref.read(cashRepositoryProvider).current();
    if (!mounted) return;
    if (!cash.open) {
      showError(context, 'Abra o caixa no PDV (menu PDV) para receber a OS');
      return;
    }
    final pay = await showDialog<PaymentResult>(
      context: context,
      builder: (_) => PaymentDialog(total: o.total, customerName: o.customerName),
    );
    if (pay == null || !mounted) return;
    final next = await showDialog<(DateTime?, int?)>(context: context, builder: (_) => _NextServiceDialog(km: o.kmIn ?? o.vehicle.km));
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      final saleId = await _repo.close(o.id,
          payments: pay.payments, dueDays: pay.dueDays, nextServiceDate: next?.$1, nextServiceKm: next?.$2);
      final receipt = await _repo.receipt(saleId);
      await _load();
      if (mounted) await showDialog<void>(context: context, builder: (_) => ReceiptDialog(receipt: receipt));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Cancelar OS?'),
        content: TextField(controller: reason, decoration: const InputDecoration(labelText: 'Motivo (ex.: cliente não aprovou)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Voltar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Cancelar OS')),
        ],
      ),
    );
    if (ok == true) await _advance(OsStatus.cancelada, note: reason.text.trim().isEmpty ? null : reason.text.trim());
  }

  Future<void> _addPart() async {
    final p = await showDialog<Product>(context: context, builder: (_) => const _PartPicker());
    if (p == null) return;
    setState(() {
      _o!.items.add(OsItem(
        kind: 'PECA',
        productId: p.id,
        description: p.name,
        qty: 1,
        unitPrice: p.price,
        imageUrl: p.imageUrl,
        stockQty: p.stockQty,
        unit: p.unit,
      ));
      _dirty = true;
    });
  }

  Future<void> _addLabor() async {
    final s = await showDialog<LaborService>(context: context, builder: (_) => const _LaborPicker());
    if (s == null) return;
    setState(() {
      _o!.items.add(OsItem(kind: 'SERVICO', serviceId: s.id.isEmpty ? null : s.id, description: s.name, qty: 1, unitPrice: s.price,
          mechanicId: _o!.mechanicId));
      _dirty = true;
    });
  }

  Future<void> _editItem(OsItem it) async {
    final qty = TextEditingController(text: number(it.qty));
    final price = TextEditingController(text: it.unitPrice.toStringAsFixed(2).replaceAll('.', ','));
    final desc = TextEditingController(text: it.description);
    final r = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(it.isPart ? 'Peça' : 'Mão de obra'),
        content: SizedBox(
          width: 380,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (!it.isPart) TextField(controller: desc, decoration: const InputDecoration(labelText: 'Descrição')),
            if (!it.isPart) const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: qty,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: 'Quantidade', suffixText: it.unit),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: price,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Valor unitário', prefixText: r'R$ '),
                ),
              ),
            ]),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, 'del'), child: const Text('Remover item')),
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, 'ok'), child: const Text('OK')),
        ],
      ),
    );
    if (r == null) return;
    setState(() {
      if (r == 'del') {
        _o!.items.remove(it);
      } else {
        final q = parseMoney(qty.text);
        if (q > 0) it.qty = q;
        it.unitPrice = parseMoney(price.text);
        if (!it.isPart && desc.text.trim().isNotEmpty) it.description = desc.text.trim();
      }
      _dirty = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final o = _o;
    final t = Theme.of(context);
    final session = ref.watch(sessionControllerProvider);
    if (o == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final editable = !o.status.isFinal;
    final canClose = session?.canCloseWorkOrder ?? false;
    final isManager = session?.isManager ?? false;
    final wide = MediaQuery.sizeOf(context).width >= 1000;

    final left = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _StatusFlow(status: o.status),
      const SizedBox(height: 12),
      _Section(
        title: 'Cliente e moto',
        icon: Icons.two_wheeler,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${o.vehicle.plateFmt} · ${o.vehicle.label}${o.vehicle.color != null ? ' · ${o.vehicle.color}' : ''}',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          Text('${o.customerName}${o.customerPhone != null ? ' · ${o.customerPhone}' : ''}'),
          const SizedBox(height: 4),
          Text([
            if (o.kmIn != null) '${number(o.kmIn!)} km',
            if (o.fuelLevel != null) 'combustível ${o.fuelLevel}',
            'entrada ${dateTimeBr(o.openedAt)}',
            if (o.promisedAt != null) 'previsão ${dateTimeBr(o.promisedAt)}',
          ].join(' · '), style: t.textTheme.bodySmall),
          if (o.checklist.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 4, children: [
              for (final e in o.checklist.entries)
                Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: Icon(e.value == true ? Icons.check : (e.value == false ? Icons.close : Icons.info_outline), size: 16),
                  label: Text(e.value is String ? '${e.key}: ${e.value}' : e.key),
                ),
            ]),
          ],
        ]),
      ),
      const SizedBox(height: 12),
      _Section(
        title: 'Relato e diagnóstico',
        icon: Icons.notes,
        child: Column(children: [
          TextField(
            controller: _complaint,
            enabled: editable,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'O que o cliente relatou'),
            onChanged: (_) => _touch(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _diagnosis,
            enabled: editable,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Diagnóstico do mecânico', hintText: 'O que foi encontrado e o que precisa trocar'),
            onChanged: (_) => _touch(),
          ),
          const SizedBox(height: 12),
          Consumer(builder: (context, ref, _) {
            final mechanics = ref.watch(mechanicsProvider).valueOrNull ?? const [];
            final ids = mechanics.map((m) => m.id).toSet();
            return DropdownButtonFormField<String?>(
              initialValue: ids.contains(o.mechanicId) ? o.mechanicId : null,
              decoration: const InputDecoration(labelText: 'Mecânico responsável'),
              items: [
                DropdownMenuItem(value: null, child: Text(o.mechanicName ?? '— nenhum —')),
                for (final m in mechanics) DropdownMenuItem(value: m.id, child: Text(m.fullName)),
              ],
              onChanged: editable
                  ? (v) {
                      o.mechanicId = v;
                      _touch();
                    }
                  : null,
            );
          }),
        ]),
      ),
    ]);

    final right = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _Section(
        title: 'Peças',
        icon: Icons.settings_outlined,
        action: editable ? TextButton.icon(onPressed: _addPart, icon: const Icon(Icons.add), label: const Text('Adicionar peça')) : null,
        child: _ItemsList(items: o.items.where((i) => i.isPart).toList(), editable: editable, onTap: _editItem,
            empty: 'Nenhuma peça. Use "Adicionar peça" para buscar no estoque (com foto).'),
      ),
      const SizedBox(height: 12),
      _Section(
        title: 'Mão de obra',
        icon: Icons.handyman_outlined,
        action: editable ? TextButton.icon(onPressed: _addLabor, icon: const Icon(Icons.add), label: const Text('Adicionar serviço')) : null,
        child: _ItemsList(items: o.items.where((i) => !i.isPart).toList(), editable: editable, onTap: _editItem,
            empty: 'Nenhum serviço. Escolha da tabela de mão de obra ou digite um avulso.'),
      ),
      const SizedBox(height: 12),
      _Section(
        title: 'Total',
        icon: Icons.payments_outlined,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _kv('Peças', money(o.partsTotal)),
          _kv('Mão de obra', money(o.laborTotal)),
          if (editable)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: TextField(
                controller: _discount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Desconto', prefixText: r'R$ ', isDense: true),
                onChanged: (_) => setState(() {
                  o.discount = parseMoney(_discount.text);
                  _dirty = true;
                }),
              ),
            )
          else if (o.discount > 0)
            _kv('Desconto', '- ${money(o.discount)}'),
          const Divider(),
          Row(children: [
            Text('TOTAL', style: t.textTheme.titleMedium),
            const Spacer(),
            Text(money(o.total), style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: t.colorScheme.primary)),
          ]),
          Text('Garantia: ${o.warrantyDays} dias', style: t.textTheme.bodySmall),
          if (o.nextServiceDate != null || o.nextServiceKm != null)
            Text('Próxima revisão: ${[if (o.nextServiceDate != null) dateBr(o.nextServiceDate), if (o.nextServiceKm != null) '${number(o.nextServiceKm!)} km'].join(' ou ')}',
                style: t.textTheme.bodySmall),
        ]),
      ),
      const SizedBox(height: 12),
      _Timeline(events: o.events),
    ]);

    final next = o.status.next;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () => _save(),
        const SingleActivator(LogicalKeyboardKey.keyP, control: true): _print,
      },
      child: Focus(
        autofocus: true,
        child: PopScope(
          canPop: !_dirty,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;
            final nav = Navigator.of(context);
            if (await _save(quiet: true)) nav.pop();
          },
          child: Scaffold(
            appBar: AppBar(
              title: Text('OS nº ${o.number} · ${o.vehicle.plateFmt}'),
              actions: [
                if (_dirty)
                  TextButton.icon(onPressed: _busy ? null : () => _save(), icon: const Icon(Icons.save), label: const Text('Salvar')),
                IconButton(tooltip: 'Orçamento no WhatsApp', onPressed: () async {
                  if (await _save(quiet: true)) await _sendBudget();
                }, icon: const Icon(Icons.chat_outlined)),
                IconButton(tooltip: 'Imprimir OS (Ctrl+P)', onPressed: _print, icon: const Icon(Icons.print_outlined)),
                if (editable && isManager)
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'cancel') _cancel();
                    },
                    itemBuilder: (_) => const [PopupMenuItem(value: 'cancel', child: Text('Cancelar OS'))],
                  ),
              ],
            ),
            bottomNavigationBar: editable
                ? SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: Row(children: [
                        Expanded(
                          child: Text(
                            'Próximo passo: ${next != null ? o.status.nextAction : (canClose ? 'receber no caixa e entregar' : 'o caixa recebe e entrega')}',
                            style: t.textTheme.bodySmall,
                          ),
                        ),
                        if (next != null)
                          FilledButton.icon(
                            onPressed: _busy ? null : () => _advance(next),
                            icon: Icon(next.icon),
                            label: Text(o.status.nextAction),
                          )
                        else if (o.status == OsStatus.pronta && canClose)
                          FilledButton.icon(
                            onPressed: _busy ? null : _closeAtCashier,
                            icon: const Icon(Icons.point_of_sale),
                            label: const Text('Receber e entregar'),
                          ),
                      ]),
                    ),
                  )
                : null,
            body: _busy && _o == null
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (wide)
                        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Expanded(child: left),
                          const SizedBox(width: 16),
                          Expanded(child: right),
                        ])
                      else ...[left, const SizedBox(height: 12), right],
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [Text(k), const Spacer(), Text(v, style: const TextStyle(fontWeight: FontWeight.w600))]),
      );
}

/// Linha do fluxo: mostra em que passo a OS está.
class _StatusFlow extends StatelessWidget {
  const _StatusFlow({required this.status});
  final OsStatus status;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    if (status == OsStatus.cancelada) {
      return Card(
        color: t.colorScheme.errorContainer,
        child: const ListTile(leading: Icon(Icons.cancel_outlined), title: Text('OS cancelada')),
      );
    }
    final idx = kOsFlow.indexOf(status);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (var i = 0; i < kOsFlow.length; i++) ...[
              Column(children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: i <= idx ? kOsFlow[i].color(t.colorScheme) : t.colorScheme.surfaceContainerHighest,
                  child: Icon(kOsFlow[i].icon, size: 16, color: i <= idx ? Colors.white : t.colorScheme.outline),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  width: 84,
                  child: Text(kOsFlow[i].label,
                      textAlign: TextAlign.center,
                      style: t.textTheme.labelSmall?.copyWith(fontWeight: i == idx ? FontWeight.bold : null)),
                ),
              ]),
              if (i < kOsFlow.length - 1)
                Container(width: 16, height: 2, margin: const EdgeInsets.only(bottom: 20), color: i < idx ? t.colorScheme.primary : t.colorScheme.outlineVariant),
            ],
          ]),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.icon, required this.child, this.action});
  final String title;
  final IconData icon;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Icon(icon, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
              if (action != null) action!,
            ]),
            const SizedBox(height: 8),
            child,
          ]),
        ),
      );
}

class _ItemsList extends StatelessWidget {
  const _ItemsList({required this.items, required this.editable, required this.onTap, required this.empty});
  final List<OsItem> items;
  final bool editable;
  final void Function(OsItem) onTap;
  final String empty;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    if (items.isEmpty) return Text(empty, style: t.textTheme.bodySmall);
    return Column(children: [
      for (final it in items)
        ListTile(
          contentPadding: EdgeInsets.zero,
          onTap: editable ? () => onTap(it) : null,
          leading: it.isPart ? ProductThumb(url: it.imageUrl, size: 44) : const CircleAvatar(child: Icon(Icons.handyman, size: 18)),
          title: Text(it.description, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            '${number(it.qty)}${it.unit != null ? ' ${it.unit}' : ''} × ${money(it.unitPrice)}'
            '${it.missingStock ? '  ⚠ estoque ${number(it.stockQty!)}' : ''}',
            style: it.missingStock ? TextStyle(color: t.colorScheme.error) : null,
          ),
          trailing: Text(money(it.total), style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
    ]);
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.events});
  final List<OsEvent> events;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return _Section(
      title: 'Histórico',
      icon: Icons.history,
      child: Column(children: [
        for (final e in events.reversed)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(e.status.icon, color: e.status.color(t.colorScheme)),
            title: Text(e.status.label),
            subtitle: Text([dateTimeBr(e.createdAt), if (e.user != null) e.user!, if (e.note != null) e.note!].join(' · ')),
          ),
      ]),
    );
  }
}

/// Busca de peça no estoque, com foto e quantidade disponível.
class _PartPicker extends ConsumerStatefulWidget {
  const _PartPicker();

  @override
  ConsumerState<_PartPicker> createState() => _PartPickerState();
}

class _PartPickerState extends ConsumerState<_PartPicker> {
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
      title: const Text('Adicionar peça'),
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
                ? const Center(child: Text('Nenhuma peça encontrada. Cadastre em Produtos.'))
                : ListView.builder(
                    itemCount: _items.length,
                    itemBuilder: (_, i) {
                      final p = _items[i];
                      return ListTile(
                        leading: ProductThumb(url: p.imageUrl, size: 48),
                        title: Text(p.name),
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

/// Escolha de mão de obra da tabela, ou serviço avulso digitado.
class _LaborPicker extends ConsumerStatefulWidget {
  const _LaborPicker();

  @override
  ConsumerState<_LaborPicker> createState() => _LaborPickerState();
}

class _LaborPickerState extends ConsumerState<_LaborPicker> {
  final _q = TextEditingController();
  final _price = TextEditingController();
  List<LaborService> _all = const [];

  @override
  void initState() {
    super.initState();
    ref.read(workshopRepositoryProvider).services().then((r) {
      if (mounted) setState(() => _all = r);
    });
  }

  @override
  void dispose() {
    _q.dispose();
    _price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.text.trim().toLowerCase();
    final list = q.isEmpty ? _all : _all.where((s) => s.name.toLowerCase().contains(q)).toList();
    return AlertDialog(
      title: const Text('Adicionar mão de obra'),
      content: SizedBox(
        width: 480,
        height: 440,
        child: Column(children: [
          TextField(
            controller: _q,
            autofocus: true,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar ou digitar um serviço avulso'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(children: [
              for (final s in list)
                ListTile(
                  leading: const Icon(Icons.handyman_outlined),
                  title: Text(s.name),
                  subtitle: s.estMinutes != null ? Text('~${s.estMinutes} min') : null,
                  trailing: Text(money(s.price), style: const TextStyle(fontWeight: FontWeight.w600)),
                  onTap: () => Navigator.pop(context, s),
                ),
              if (q.isNotEmpty && !list.any((s) => s.name.toLowerCase() == q)) ...[
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.edit_note),
                  title: Text('Serviço avulso: "${_q.text.trim()}"'),
                  subtitle: TextField(
                    controller: _price,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Valor', prefixText: r'R$ ', isDense: true),
                  ),
                  trailing: FilledButton(
                    onPressed: () => Navigator.pop(context, LaborService(id: '', name: _q.text.trim(), price: parseMoney(_price.text))),
                    child: const Text('Usar'),
                  ),
                ),
              ],
              if (_all.isEmpty && q.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('A tabela de mão de obra está vazia. Na aba "Mão de obra" da Oficina, toque em '
                      '"Carregar tabela padrão" para começar com 20 serviços comuns de moto.'),
                ),
            ]),
          ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar'))],
    );
  }
}

/// Na entrega: quando o cliente deve voltar para a próxima revisão.
class _NextServiceDialog extends StatefulWidget {
  const _NextServiceDialog({this.km});
  final int? km;

  @override
  State<_NextServiceDialog> createState() => _NextServiceDialogState();
}

class _NextServiceDialogState extends State<_NextServiceDialog> {
  DateTime? _date;
  late final _km = TextEditingController(text: widget.km == null ? '' : '${widget.km! + 3000}');

  @override
  void dispose() {
    _km.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return AlertDialog(
      title: const Text('Próxima revisão'),
      content: SizedBox(
        width: 400,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Quando o cliente deve voltar? A oficina recebe o lembrete na aba Revisões, '
              'com botão para chamar o cliente no WhatsApp.'),
          const SizedBox(height: 12),
          Wrap(spacing: 6, children: [
            for (final m in const [3, 6, 12])
              ChoiceChip(
                label: Text('$m meses'),
                selected: _date != null && _date!.month == DateTime(now.year, now.month + m).month && _date!.year == DateTime(now.year, now.month + m).year,
                onSelected: (_) => setState(() => _date = DateTime(now.year, now.month + m, now.day)),
              ),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: _km,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Ou com quantos km', suffixText: 'km'),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, (null, null)), child: const Text('Sem revisão')),
        FilledButton(
          onPressed: () => Navigator.pop(context, (_date, int.tryParse(_km.text))),
          child: const Text('Confirmar'),
        ),
      ],
    );
  }
}
