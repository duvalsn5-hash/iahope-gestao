import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/utils/image_tools.dart';
import '../../../core/utils/whatsapp.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../auth/presentation/session_controller.dart';
import '../../cash/data/cash_repository.dart';
import '../../pos/data/pos_repository.dart';
import '../../pos/domain/pos_models.dart';
import '../../pos/presentation/widgets/payment_dialog.dart';
import '../../pos/presentation/widgets/receipt_dialog.dart';
import '../../products/domain/product.dart';
import '../../products/presentation/product_picker_dialog.dart';
import '../data/order_printer.dart';
import '../data/printshop_repository.dart';
import '../domain/printshop.dart';

/// Pedido sob encomenda: itens com grade de tamanhos, arte, sinal, andamento e entrega.
/// Atalhos: Ctrl+S salvar · Ctrl+I novo item · Ctrl+P imprimir
class OrderPage extends ConsumerStatefulWidget {
  const OrderPage({super.key, required this.orderId});
  final String orderId;

  @override
  ConsumerState<OrderPage> createState() => _OrderPageState();
}

class _OrderPageState extends ConsumerState<OrderPage> {
  CustomOrder? _o;
  bool _busy = false;
  bool _dirty = false;
  final _title = TextEditingController();
  final _artNotes = TextEditingController();
  final _notes = TextEditingController();
  final _discount = TextEditingController();

  PrintshopRepository get _repo => ref.read(printshopRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_title, _artNotes, _notes, _discount]) {
      c.dispose();
    }
    super.dispose();
  }

  void _apply(CustomOrder o) {
    _o = o;
    _title.text = o.title;
    _artNotes.text = o.artNotes ?? '';
    _notes.text = o.notes ?? '';
    _discount.text = o.discount == 0 ? '' : o.discount.toStringAsFixed(2).replaceAll('.', ',');
    _dirty = false;
  }

  Future<void> _load() async {
    try {
      final o = await _repo.order(widget.orderId);
      if (mounted) setState(() => _apply(o));
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  void _touch() => setState(() => _dirty = true);

  Future<bool> _save({bool quiet = false}) async {
    final o = _o!;
    if (!o.editable) return true;
    o
      ..title = _title.text.trim()
      ..artNotes = _artNotes.text.trim()
      ..notes = _notes.text.trim()
      ..discount = parseMoney(_discount.text);
    setState(() => _busy = true);
    try {
      final saved = await _repo.save(o);
      if (mounted) {
        setState(() => _apply(saved));
        if (!quiet) showOk(context, 'Pedido salvo');
      }
      return true;
    } catch (e) {
      if (mounted) showError(context, e);
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _run(Future<CustomOrder> Function() op, [String? ok]) async {
    setState(() => _busy = true);
    try {
      final o = await op();
      if (mounted) {
        setState(() => _apply(o));
        if (ok != null) showOk(context, ok);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _advance(OrderStatus to, {String? note}) async {
    if (_dirty && !await _save(quiet: true)) return;
    await _run(() => _repo.setStatus(_o!.id, to, note: note), 'Pedido: ${to.label}');
    if (to == OrderStatus.pronto && mounted && _o?.customerPhone != null) {
      final send = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Avisar o cliente?'),
          content: const Text('Mandar mensagem pelo WhatsApp dizendo que o pedido está pronto.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Agora não')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Avisar')),
          ],
        ),
      );
      if (send == true) _whatsReady();
    }
  }

  // ---------------------------------------------------------------- itens
  Future<void> _editItem([int? index]) async {
    final o = _o!;
    final it = await showDialog<OrderItem>(
      context: context,
      builder: (_) => _ItemDialog(initial: index == null ? null : o.items[index]),
    );
    if (it == null) return;
    setState(() {
      if (index == null) {
        o.items = [...o.items, it];
      } else {
        o.items = [...o.items]..[index] = it;
      }
      _dirty = true;
    });
  }

  void _removeItem(int i) => setState(() {
        _o!.items = [..._o!.items]..removeAt(i);
        _dirty = true;
      });

  // ---------------------------------------------------------------- artes
  Future<void> _addArt() async {
    final file = await FilePicker.pickFile(type: FileType.image);
    if (file == null) return;
    setState(() => _busy = true);
    try {
      final small = await shrinkImage(await file.readAsBytes(), maxSide: 1600, quality: 85);
      if (small == null) throw 'Não consegui abrir esta imagem. Use JPG ou PNG.';
      final o = await _repo.uploadArt(_o!.id, small, 'arte.jpg');
      if (mounted) setState(() => _o!.arts = o.arts);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeArt(OrderArt a) async {
    try {
      final o = await _repo.removeArt(_o!.id, a.id);
      if (mounted) setState(() => _o!.arts = o.arts);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  // ---------------------------------------------------------------- dinheiro
  Future<bool> _cashOpen() async {
    final cash = await ref.read(cashRepositoryProvider).current();
    if (!cash.open && mounted) showError(context, 'Abra o caixa no PDV (menu PDV) antes de receber');
    return cash.open;
  }

  Future<void> _deposit() async {
    if (_dirty && !await _save(quiet: true)) return;
    if (!mounted) return;
    final r = await showDialog<(double, PaymentMethod)>(context: context, builder: (_) => _DepositDialog(max: _o!.balance));
    if (r == null) return;
    if (r.$2 == PaymentMethod.dinheiro && !await _cashOpen()) return;
    await _run(() => _repo.deposit(_o!.id, r.$1, r.$2), 'Sinal de ${money(r.$1)} recebido');
  }

  Future<void> _deliver() async {
    if (_dirty && !await _save(quiet: true)) return;
    if (!await _cashOpen() || !mounted) return;
    final o = _o!;
    var payments = <Payment>[];
    var dueDays = 30;
    if (o.balance > 0) {
      final hasModa = ref.read(sessionControllerProvider)?.hasModule('MODA') ?? false;
      final pay = await showDialog<PaymentResult>(
        context: context,
        builder: (_) => PaymentDialog(
          total: o.balance,
          customerName: o.customerName,
          lookupVoucher: hasModa ? (code) => ref.read(posRepositoryProvider).voucher(code) : null,
        ),
      );
      if (pay == null) return;
      payments = pay.payments;
      dueDays = pay.dueDays;
    } else {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Entregar o pedido?'),
          content: const Text('O pedido já está todo pago pelo sinal.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Voltar')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Entregar')),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _busy = true);
    try {
      final receipt = await _repo.close(o.id, payments: payments, dueDays: dueDays);
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
        title: const Text('Cancelar pedido?'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_o!.deposit > 0)
            Text('Atenção: há ${money(_o!.deposit)} de sinal. Se for devolver, faça uma sangria no caixa.',
                style: TextStyle(color: Theme.of(c).colorScheme.error)),
          TextField(controller: reason, decoration: const InputDecoration(labelText: 'Motivo')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Voltar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Cancelar pedido')),
        ],
      ),
    );
    if (ok == true) await _advance(OrderStatus.cancelado, note: reason.text.trim().isEmpty ? null : reason.text.trim());
  }

  // ---------------------------------------------------------------- WhatsApp / impressão
  String get _company => ref.read(sessionControllerProvider)?.tenant.nomeFantasia ?? '';

  void _whatsBudget() {
    final o = _o!;
    final msg = [
      'Olá, ${o.customerName.split(' ').first}! Aqui é da *$_company*.',
      'Segue o orçamento do pedido nº ${o.number} — *${o.title}* (${techniqueLabel(o.technique)}):',
      '',
      for (final i in o.items)
        '• ${number(i.effectiveQty)}× ${i.description}${i.color != null ? ' ${i.color}' : ''}'
            '${i.sizesText.isNotEmpty ? ' (${i.sizesText})' : ''} — ${money(i.total)}',
      if (o.discount > 0) 'Desconto: ${money(o.discount)}',
      '*Total: ${money(o.total)}*',
      if (o.dueDate != null) 'Entrega prevista: ${dateBr(o.dueDate)}',
      '',
      'Para começar, confirme a arte e o sinal. Qualquer dúvida, é só chamar!',
    ].join('\n');
    openWhatsApp(o.customerPhone, msg);
  }

  void _whatsReady() {
    final o = _o!;
    openWhatsApp(
      o.customerPhone,
      'Olá, ${o.customerName.split(' ').first}! Seu pedido nº ${o.number} (*${o.title}*) está *pronto* aqui na *$_company*. '
      '${o.balance > 0 ? 'Falta acertar ${money(o.balance)} na retirada. ' : ''}Pode vir buscar!',
    );
  }

  Future<void> _print({bool production = false}) async {
    if (_dirty && !await _save(quiet: true)) return;
    final s = ref.read(sessionControllerProvider);
    await OrderPrinter.print(_o!, company: _company, logoUrl: s?.tenant.logoUrl, production: production);
  }

  @override
  Widget build(BuildContext context) {
    final o = _o;
    final t = Theme.of(context);
    if (o == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final s = ref.watch(sessionControllerProvider);
    final canCash = s?.canSell ?? false;
    final manager = s?.isManager ?? false;
    final wide = MediaQuery.sizeOf(context).width >= 1000;

    final header = _Section(
      title: 'Pedido',
      icon: Icons.assignment_outlined,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('${o.customerName}${o.customerPhone != null ? ' · ${o.customerPhone}' : ''}', style: t.textTheme.titleMedium),
        const SizedBox(height: 8),
        TextField(
          controller: _title,
          enabled: o.editable,
          decoration: const InputDecoration(labelText: 'Descrição do pedido'),
          onChanged: (_) => _touch(),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: o.technique,
              decoration: const InputDecoration(labelText: 'Técnica'),
              items: [for (final (k, v) in kTechniques) DropdownMenuItem(value: k, child: Text(v))],
              onChanged: !o.editable ? null : (v) => setState(() {
                    o.technique = v ?? o.technique;
                    _dirty = true;
                  }),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              onTap: !o.editable
                  ? null
                  : () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: o.dueDate ?? DateTime.now(),
                        firstDate: DateTime.now().subtract(const Duration(days: 365)),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (d != null) {
                        setState(() {
                          o.dueDate = d;
                          _dirty = true;
                        });
                      }
                    },
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Entrega', prefixIcon: Icon(Icons.event)),
                child: Text(o.dueDate == null ? 'Sem prazo' : dateBr(o.dueDate)),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: _artNotes,
          enabled: o.editable,
          maxLines: 3,
          minLines: 2,
          decoration: const InputDecoration(
            labelText: 'Arte: posição, tamanho e cores',
            hintText: 'Ex.: frente centralizada 28 cm, costas nome + número, 2 cores (branco e dourado)',
          ),
          onChanged: (_) => _touch(),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _notes,
          enabled: o.editable,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'Observações'),
          onChanged: (_) => _touch(),
        ),
      ]),
    );

    final items = _Section(
      title: 'Itens e grade de tamanhos',
      icon: Icons.checkroom_outlined,
      action: o.editable ? TextButton.icon(onPressed: () => _editItem(), icon: const Icon(Icons.add), label: const Text('Item (Ctrl+I)')) : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (o.items.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Nenhum item. Ex.: "Camiseta DTF frente" — grade P:5 M:10 G:5 — R\$ 35 cada.'),
          ),
        for (final (i, it) in o.items.indexed)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: it.imageUrl != null ? ProductThumb(url: it.imageUrl, size: 40) : const CircleAvatar(child: Icon(Icons.checkroom)),
            title: Text('${it.description}${it.color != null ? ' · ${it.color}' : ''}'),
            subtitle: Text([
              if (it.sizesText.isNotEmpty) it.sizesText,
              '${number(it.effectiveQty)} × ${money(it.unitPrice)}',
              if (it.productId != null) it.missingStock ? '⚠ estoque ${number(it.stockQty ?? 0)}' : 'peça do estoque',
            ].join('  ·  '),
                style: it.missingStock ? TextStyle(color: t.colorScheme.error) : null),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(money(it.total), style: const TextStyle(fontWeight: FontWeight.bold)),
              if (o.editable) ...[
                IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => _editItem(i)),
                IconButton(icon: Icon(Icons.delete_outline, color: t.colorScheme.error), onPressed: () => _removeItem(i)),
              ],
            ]),
          ),
        const Divider(),
        Row(children: [
          Expanded(child: Text('${number(o.pieces)} peça(s)', style: t.textTheme.titleSmall)),
          SizedBox(
            width: 140,
            child: TextField(
              controller: _discount,
              enabled: o.editable,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Desconto', prefixText: r'R$ ', isDense: true),
              onChanged: (_) => setState(() {
                o.discount = parseMoney(_discount.text);
                _dirty = true;
              }),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        _kv('Total', money(o.total), big: true),
        _kv('Sinal recebido', money(o.deposit)),
        _kv('Falta receber', money(o.balance), color: o.balance > 0 ? t.colorScheme.error : Colors.green.shade700),
      ]),
    );

    final arts = _Section(
      title: 'Arte',
      icon: Icons.image_outlined,
      action: o.editable && o.arts.length < 6
          ? TextButton.icon(onPressed: _busy ? null : _addArt, icon: const Icon(Icons.add_photo_alternate_outlined), label: const Text('Enviar arte'))
          : null,
      child: o.arts.isEmpty
          ? const Padding(padding: EdgeInsets.all(12), child: Text('Envie a arte ou o mockup (JPG/PNG). Sai impressa na ordem de produção.'))
          : Wrap(spacing: 8, runSpacing: 8, children: [
              for (final a in o.arts)
                Stack(children: [
                  InkWell(
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (_) => Dialog(child: InteractiveViewer(child: Image.network(a.url))),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(a.url, width: 120, height: 120, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const SizedBox(width: 120, height: 120, child: Icon(Icons.broken_image))),
                    ),
                  ),
                  if (o.editable)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: IconButton.filledTonal(
                        visualDensity: VisualDensity.compact,
                        iconSize: 16,
                        onPressed: () => _removeArt(a),
                        icon: const Icon(Icons.close),
                      ),
                    ),
                ]),
            ]),
    );

    final flow = _Section(
      title: 'Andamento',
      icon: Icons.timeline,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 4, runSpacing: 4, children: [
          for (final st in [...kBoard, OrderStatus.entregue])
            Chip(
              avatar: Icon(st.icon, size: 16, color: st == o.status ? Colors.white : st.color),
              label: Text(st.label, style: TextStyle(color: st == o.status ? Colors.white : null)),
              backgroundColor: st == o.status ? st.color : null,
            ),
          if (o.status == OrderStatus.cancelado) Chip(label: const Text('Cancelado'), backgroundColor: t.colorScheme.errorContainer),
        ]),
        const SizedBox(height: 12),
        if (o.status.next != null)
          FilledButton.icon(
            onPressed: _busy || o.items.isEmpty ? null : () => _advance(o.status.next!),
            icon: Icon(o.status.next!.icon),
            label: Text(o.status.nextAction!),
          ),
        if (o.status.isOpen && canCash) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy || o.balance <= 0 || o.items.isEmpty ? null : _deposit,
            icon: const Icon(Icons.savings_outlined),
            label: const Text('Receber sinal'),
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: _busy || o.items.isEmpty ? null : _deliver,
            icon: const Icon(Icons.handshake_outlined),
            label: Text(o.balance > 0 ? 'Entregar e receber ${money(o.balance)}' : 'Entregar'),
          ),
        ],
        const Divider(height: 24),
        for (final e in o.events.reversed)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(orderStatusFromApi(e.status).icon, size: 18, color: orderStatusFromApi(e.status).color),
            title: Text(e.note ?? orderStatusFromApi(e.status).label),
            subtitle: Text('${dateTimeBr(e.at)}${e.user != null ? ' · ${e.user}' : ''}'),
          ),
      ]),
    );

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () => _save(),
        if (o.editable) const SingleActivator(LogicalKeyboardKey.keyI, control: true): () => _editItem(),
        const SingleActivator(LogicalKeyboardKey.keyP, control: true): () => _print(),
      },
      child: PopScope(
        canPop: !_dirty,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          final leave = await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
              title: const Text('Sair sem salvar?'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Sair')),
                FilledButton(onPressed: () => Navigator.pop(c, false), child: const Text('Ficar')),
              ],
            ),
          );
          if (leave == true && context.mounted) {
            setState(() => _dirty = false);
            Navigator.of(context).pop();
          }
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            appBar: AppBar(
              title: Text('Pedido nº ${o.number} · ${o.status.label}'),
              actions: [
                IconButton(tooltip: 'Orçamento no WhatsApp', onPressed: _whatsBudget, icon: const Icon(Icons.chat_outlined)),
                PopupMenuButton<String>(
                  tooltip: 'Imprimir',
                  icon: const Icon(Icons.print_outlined),
                  onSelected: (v) => _print(production: v == 'prod'),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'orc', child: Text('Pedido / orçamento (cliente)')),
                    PopupMenuItem(value: 'prod', child: Text('Ordem de produção (equipe)')),
                  ],
                ),
                if (o.status == OrderStatus.pronto)
                  IconButton(tooltip: 'Avisar que está pronto', onPressed: _whatsReady, icon: const Icon(Icons.campaign_outlined)),
                if (manager && o.status.isOpen)
                  IconButton(tooltip: 'Cancelar pedido', onPressed: _cancel, icon: const Icon(Icons.cancel_outlined)),
                if (o.editable)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: FilledButton.icon(
                      onPressed: _busy || !_dirty ? null : () => _save(),
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Salvar'),
                    ),
                  ),
              ],
            ),
            body: Stack(children: [
              ListView(padding: const EdgeInsets.all(16), children: [
                if (wide)
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(flex: 3, child: Column(children: [header, items, arts])),
                    const SizedBox(width: 16),
                    Expanded(flex: 2, child: flow),
                  ])
                else ...[
                  flow,
                  header,
                  items,
                  arts,
                ],
              ]),
              if (_busy) const LinearProgressIndicator(),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _kv(String k, String v, {bool big = false, Color? color}) {
    final st = (big ? Theme.of(context).textTheme.titleLarge : Theme.of(context).textTheme.titleSmall)
        ?.copyWith(fontWeight: FontWeight.bold, color: color);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [Expanded(child: Text(k, style: st)), Text(v, style: st)]),
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
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(14),
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

/// Item do pedido: descrição, peça do estoque (opcional), cor, grade de tamanhos e preço.
class _ItemDialog extends StatefulWidget {
  const _ItemDialog({this.initial});
  final OrderItem? initial;

  @override
  State<_ItemDialog> createState() => _ItemDialogState();
}

class _ItemDialogState extends State<_ItemDialog> {
  late final _desc = TextEditingController(text: widget.initial?.description ?? '');
  late final _color = TextEditingController(text: widget.initial?.color ?? '');
  late final _price = TextEditingController(
      text: (widget.initial?.unitPrice ?? 0) == 0 ? '' : widget.initial!.unitPrice.toStringAsFixed(2).replaceAll('.', ','));
  late final _qty = TextEditingController(
      text: widget.initial == null || widget.initial!.sizes.isNotEmpty ? '' : number(widget.initial!.qty));
  final _newSize = TextEditingController();
  late final Map<String, TextEditingController> _sizes = {
    for (final e in (widget.initial?.sizes ?? const <String, double>{}).entries) e.key: TextEditingController(text: number(e.value)),
  };
  Product? _product;
  late String? _productId = widget.initial?.productId;
  late String? _productName = widget.initial?.productName;

  @override
  void dispose() {
    for (final c in [_desc, _color, _price, _qty, _newSize, ..._sizes.values]) {
      c.dispose();
    }
    super.dispose();
  }

  double get _sizesQty => _sizes.values.fold<double>(0, (a, c) => a + parseMoney(c.text));
  double get _totalQty => _sizesQty > 0 ? _sizesQty : parseMoney(_qty.text);

  void _addSizes(List<String> list) => setState(() {
        for (final s in list) {
          _sizes.putIfAbsent(s, TextEditingController.new);
        }
      });

  Future<void> _pickProduct() async {
    final p = await showDialog<Product>(
      context: context,
      builder: (_) => const ProductPickerDialog(title: 'Peça lisa do estoque', emptyText: 'Nenhuma peça. Cadastre em Produtos.'),
    );
    if (p == null) return;
    setState(() {
      _product = p;
      _productId = p.id;
      _productName = p.name;
      if (_desc.text.trim().isEmpty) _desc.text = p.name;
      if (_color.text.trim().isEmpty && p.color != null) _color.text = p.color!;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final ok = _desc.text.trim().isNotEmpty && _totalQty > 0;
    return AlertDialog(
      title: Text(widget.initial == null ? 'Novo item' : 'Editar item'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: _desc,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Descrição', hintText: 'Ex.: Camiseta DTF frente e costas'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: Text(
                  _productId == null
                      ? 'Peça do estoque: nenhuma (só serviço/estampa)'
                      : 'Peça do estoque: ${_productName ?? ''}${_product != null ? ' (tem ${number(_product!.stockQty)})' : ''}',
                  style: t.textTheme.bodySmall,
                ),
              ),
              TextButton(onPressed: _pickProduct, child: Text(_productId == null ? 'Usar peça lisa' : 'Trocar')),
              if (_productId != null)
                IconButton(
                  tooltip: 'Sem peça do estoque',
                  onPressed: () => setState(() {
                    _productId = null;
                    _productName = null;
                    _product = null;
                  }),
                  icon: const Icon(Icons.link_off),
                ),
            ]),
            TextField(controller: _color, decoration: const InputDecoration(labelText: 'Cor da peça (opcional)')),
            const SizedBox(height: 12),
            Text('Grade de tamanhos', style: t.textTheme.titleSmall),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final (label, list) in kOrderSizePresets)
                ActionChip(avatar: const Icon(Icons.playlist_add, size: 16), label: Text(label), onPressed: () => _addSizes(list)),
              SizedBox(
                width: 110,
                child: TextField(
                  controller: _newSize,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(isDense: true, hintText: 'outro + Enter'),
                  onSubmitted: (v) {
                    if (v.trim().isNotEmpty) _addSizes([v.trim().toUpperCase()]);
                    _newSize.clear();
                  },
                ),
              ),
            ]),
            const SizedBox(height: 8),
            if (_sizes.isNotEmpty)
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final e in _sizes.entries)
                  SizedBox(
                    width: 84,
                    child: TextField(
                      controller: e.value,
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: e.key,
                        isDense: true,
                        suffixIcon: InkWell(
                          onTap: () => setState(() => _sizes.remove(e.key)?.dispose()),
                          child: const Icon(Icons.close, size: 14),
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
              ])
            else
              TextField(
                controller: _qty,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Quantidade (sem grade)', helperText: 'Ex.: canecas, bonés tamanho único'),
                onChanged: (_) => setState(() {}),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _price,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Preço por peça (já com a estampa)', prefixText: r'R$ '),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Text('${number(_totalQty)} peça(s) · ${money(_totalQty * parseMoney(_price.text))}', style: t.textTheme.titleMedium),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: !ok
              ? null
              : () => Navigator.pop(
                    context,
                    OrderItem(
                      productId: _productId,
                      productName: _productName,
                      imageUrl: _product?.imageUrl ?? widget.initial?.imageUrl,
                      stockQty: _product?.stockQty ?? widget.initial?.stockQty,
                      description: _desc.text.trim(),
                      color: _color.text.trim().isEmpty ? null : _color.text.trim(),
                      sizes: {for (final e in _sizes.entries) if (parseMoney(e.value.text) > 0) e.key: parseMoney(e.value.text)},
                      qty: _totalQty,
                      unitPrice: parseMoney(_price.text),
                    ),
                  ),
          child: const Text('OK'),
        ),
      ],
    );
  }
}

/// Sinal: valor e forma (dinheiro entra na gaveta do caixa aberto).
class _DepositDialog extends StatefulWidget {
  const _DepositDialog({required this.max});
  final double max;

  @override
  State<_DepositDialog> createState() => _DepositDialogState();
}

class _DepositDialogState extends State<_DepositDialog> {
  late final _amount = TextEditingController(text: (widget.max / 2).toStringAsFixed(2).replaceAll('.', ','));
  PaymentMethod _method = PaymentMethod.pix;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = parseMoney(_amount.text);
    return AlertDialog(
      title: const Text('Receber sinal'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Falta receber ${money(widget.max)}. Costume: 50% para começar.'),
          const SizedBox(height: 12),
          Wrap(spacing: 6, children: [
            for (final m in const [PaymentMethod.pix, PaymentMethod.dinheiro, PaymentMethod.debito, PaymentMethod.credito])
              ChoiceChip(label: Text(m.label), selected: _method == m, onSelected: (_) => setState(() => _method = m)),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Valor do sinal', prefixText: r'R$ '),
            onChanged: (_) => setState(() {}),
          ),
          if (_method == PaymentMethod.dinheiro)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Dinheiro entra na gaveta do caixa aberto.', style: Theme.of(context).textTheme.bodySmall),
            ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: v <= 0 || v > widget.max + .001 ? null : () => Navigator.pop(context, (v, _method)),
          child: const Text('Receber'),
        ),
      ],
    );
  }
}
