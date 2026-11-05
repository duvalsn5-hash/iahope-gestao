import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../auth/presentation/session_controller.dart';
import '../../cash/domain/cash.dart';
import '../../cash/presentation/cash_controller.dart';
import '../../cash/presentation/cash_dialogs.dart';
import '../../partners/domain/partner.dart';
import '../../partners/presentation/partner_picker_dialog.dart';
import '../../products/domain/product.dart';
import '../domain/pos_models.dart';
import 'pos_controller.dart';
import 'widgets/camera_scanner_sheet.dart';
import 'widgets/payment_dialog.dart';
import 'widgets/receipt_dialog.dart';

/// Ponto de Venda.
///
/// Leitor de código de barras: leitores USB/Bluetooth funcionam como teclado,
/// "digitam" o código e enviam Enter. O campo de busca fica SEMPRE focado,
/// então basta bipar. No Android há também o botão de câmera.
///
/// Atalhos (Windows/Web):
///   F2 consultar produto · F3 cliente · F7 quantidade · F8 cancela item · F9 desconto · F10 finalizar
///   Botões grandes à direita: Dinheiro, PIX, Cartão e A Prazo já abrem o pagamento na forma escolhida.
///   ↑/↓ navegar · +/- quantidade do item selecionado · Esc limpar · Ctrl+Del cancelar venda
///   Digite "3*" antes do código para lançar 3 unidades.
class PosScreen extends ConsumerStatefulWidget {
  const PosScreen({super.key});

  @override
  ConsumerState<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends ConsumerState<PosScreen> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  List<Product> _choices = const [];
  int _choiceIndex = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusSearch());
  }

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _focusSearch() {
    if (!mounted) return;
    _searchFocus.requestFocus();
    _search.selection = TextSelection(baseOffset: 0, extentOffset: _search.text.length);
  }

  PosController get _pos => ref.read(posControllerProvider.notifier);

  /// Leituras que chegam enquanto a anterior ainda consulta a API
  /// (leitor bipando em sequência) entram numa fila — nenhuma é perdida.
  final _queue = <String>[];

  Future<void> _submit() async {
    final text = _search.text.trim();
    // Enter com lista de opções aberta → adiciona a opção destacada
    if (_choices.isNotEmpty && (text.isEmpty || text == _lastQuery)) {
      _addProduct(_choices[_choiceIndex]);
      return;
    }
    if (text.isEmpty) return;
    _search.clear();
    _queue.add(text);
    if (_busy) return;
    setState(() => _busy = true);
    try {
      while (_queue.isNotEmpty && mounted) {
        await _process(_queue.removeAt(0));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
      _focusSearch();
    }
  }

  Future<void> _process(String text) async {
    try {
      final r = await _pos.handleInput(text);
      if (!mounted) return;
      switch (r) {
        case ScanAdded():
          setState(() => _choices = const []);
          SystemSound.play(SystemSoundType.click);
        case ScanMultiplierSet(:final qty):
          showOk(context, 'Próximo item: ${number(qty)} unidade(s)');
        case ScanChoices(:final products):
          _lastQuery = text;
          _search.text = text;
          setState(() {
            _choices = products;
            _choiceIndex = 0;
          });
        case ScanNotFound(:final query):
          setState(() => _choices = const []);
          showError(context, 'Produto "$query" não encontrado');
          SystemSound.play(SystemSoundType.alert);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  String? _lastQuery;

  void _addProduct(Product p) {
    _pos.add(p);
    _search.clear();
    setState(() => _choices = const []);
    _focusSearch();
  }

  Future<void> _scanCamera() async {
    final code = await scanWithCamera(context);
    if (code == null) return;
    _search.text = code;
    await _submit();
  }

  Future<void> _editQty() async {
    final s = ref.read(posControllerProvider);
    final idx = s.selected ?? (s.items.isEmpty ? null : s.items.length - 1);
    if (idx == null) {
      _focusSearch();
      return;
    }
    final v = await _askNumber('Quantidade — ${s.items[idx].product.name}', s.items[idx].qty);
    if (v != null) _pos.setQty(idx, v);
    _focusSearch();
  }

  Future<void> _editDiscount() async {
    final s = ref.read(posControllerProvider);
    if (s.isEmpty) {
      _focusSearch();
      return;
    }
    final v = await _askNumber('Desconto (R\$) — subtotal ${money(s.subtotal)}', s.discount, money: true);
    if (v != null) _pos.setDiscount(v);
    _focusSearch();
  }

  void _removeSelected() {
    final s = ref.read(posControllerProvider);
    final idx = s.selected ?? (s.items.isEmpty ? null : s.items.length - 1);
    if (idx != null) _pos.remove(idx);
    _focusSearch();
  }

  Future<void> _cancelSale() async {
    if (ref.read(posControllerProvider).isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Cancelar venda atual?'),
        content: const Text('Todos os itens serão removidos.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Não')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Sim, cancelar')),
        ],
      ),
    );
    if (ok == true) _pos.clear();
    _focusSearch();
  }

  Future<void> _finish([PaymentMethod? method]) async {
    var s = ref.read(posControllerProvider);
    if (s.isEmpty || _busy) return;
    // A prazo exige cliente: pede o cliente antes de abrir o pagamento
    if (method == PaymentMethod.prazo && s.customer == null) {
      await _pickCustomer();
      s = ref.read(posControllerProvider);
      if (s.customer == null || !mounted) return;
    }
    final result = await showDialog<PaymentResult>(
      context: context,
      builder: (_) => PaymentDialog(total: s.total, customerName: s.customer?.displayName, initialMethod: method),
    );
    if (result == null || !mounted) {
      _focusSearch();
      return;
    }
    setState(() => _busy = true);
    try {
      final receipt = await _pos.finish(result.payments, dueDays: result.dueDays);
      if (!mounted) return;
      await showDialog<void>(context: context, builder: (_) => ReceiptDialog(receipt: receipt));
    } catch (e) {
      if (mounted) showError(context, e); // ex.: estoque insuficiente — carrinho é mantido
    } finally {
      if (mounted) setState(() => _busy = false);
      _focusSearch();
    }
  }

  Future<double?> _askNumber(String title, double initial, {bool money = false}) {
    final ctrl = TextEditingController(
      text: money ? initial.toStringAsFixed(2).replaceAll('.', ',') : number(initial),
    );
    return showDialog<double>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onTap: () => ctrl.selection = TextSelection(baseOffset: 0, extentOffset: ctrl.text.length),
          onSubmitted: (v) => Navigator.pop(c, parseMoney(v)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, parseMoney(ctrl.text)), child: const Text('OK')),
        ],
      ),
    );
  }

  void _moveSelection(int delta) {
    if (_choices.isNotEmpty) {
      setState(() => _choiceIndex = (_choiceIndex + delta).clamp(0, _choices.length - 1).toInt());
      return;
    }
    final s = ref.read(posControllerProvider);
    if (s.isEmpty) return;
    final cur = s.selected ?? s.items.length - 1;
    _pos.select((cur + delta).clamp(0, s.items.length - 1).toInt());
  }

  void _bumpQty(double by) {
    final s = ref.read(posControllerProvider);
    final idx = s.selected;
    if (idx != null) _pos.increment(idx, by);
  }

  Future<void> _pickCustomer() async {
    final p = await showDialog<Partner>(context: context, builder: (_) => const PartnerPickerDialog());
    if (p != null) _pos.setCustomer(p);
    _focusSearch();
  }

  Future<void> _openCash() async {
    final r = await askCashAmount(
      context,
      title: 'Abrir caixa',
      label: 'Troco inicial na gaveta',
      help: 'Conte o dinheiro que está na gaveta para começar o dia.',
      initial: 0,
    );
    if (r == null || !mounted) return;
    try {
      await ref.read(cashControllerProvider.notifier).open(r.$1);
      if (mounted) showOk(context, 'Caixa aberto com ${money(r.$1)}');
    } catch (e) {
      if (mounted) showError(context, e);
    }
    _focusSearch();
  }

  Future<void> _cashMove(String kind) async {
    final r = await askCashAmount(
      context,
      title: kind == 'SANGRIA' ? 'Sangria (retirada)' : 'Suprimento (reforço de troco)',
      label: 'Valor',
      askReason: true,
    );
    if (r == null || r.$1 <= 0 || !mounted) {
      _focusSearch();
      return;
    }
    try {
      await ref.read(cashControllerProvider.notifier).movement(kind, r.$1, r.$2);
      if (mounted) showOk(context, '${kind == 'SANGRIA' ? 'Sangria' : 'Suprimento'} de ${money(r.$1)} registrado');
    } catch (e) {
      if (mounted) showError(context, e);
    }
    _focusSearch();
  }

  Future<void> _closeCash(CashSummary summary) async {
    if (!ref.read(posControllerProvider).isEmpty) {
      showError(context, 'Finalize ou cancele a venda em andamento antes de fechar o caixa');
      return;
    }
    final r = await showDialog<(double, String?)>(context: context, builder: (_) => CloseCashDialog(summary: summary));
    if (r == null || !mounted) return;
    try {
      final closed = await ref.read(cashControllerProvider.notifier).close(r.$1, r.$2);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Caixa fechado'),
          content: SizedBox(width: 400, child: CashSummaryView(s: closed)),
          actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
        ),
      );
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }


  @override
  Widget build(BuildContext context) {
    final cash = ref.watch(cashControllerProvider);
    final cashState = cash.valueOrNull;
    if (cashState == null) {
      return cash.hasError
          ? Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(cash.error.toString()),
                const SizedBox(height: 8),
                FilledButton(onPressed: () => ref.invalidate(cashControllerProvider), child: const Text('Tentar de novo')),
              ]),
            )
          : const Center(child: CircularProgressIndicator());
    }
    if (!cashState.open) return _CashClosedPanel(onOpen: _openCash);

    final state = ref.watch(posControllerProvider);
    final session = ref.watch(sessionControllerProvider);
    final summary = ref.watch(posSummaryProvider).valueOrNull;
    final wide = MediaQuery.sizeOf(context).width >= 900;

    final bindings = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.f2): _focusSearch,
      const SingleActivator(LogicalKeyboardKey.f3): _pickCustomer,
      const SingleActivator(LogicalKeyboardKey.f7): _editQty,
      const SingleActivator(LogicalKeyboardKey.f8): _removeSelected,
      const SingleActivator(LogicalKeyboardKey.f9): _editDiscount,
      const SingleActivator(LogicalKeyboardKey.f10): _finish,
      const SingleActivator(LogicalKeyboardKey.delete, control: true): _cancelSale,
      const SingleActivator(LogicalKeyboardKey.arrowDown): () => _moveSelection(1),
      const SingleActivator(LogicalKeyboardKey.arrowUp): () => _moveSelection(-1),
      const SingleActivator(LogicalKeyboardKey.numpadAdd): () => _bumpQty(1),
      const SingleActivator(LogicalKeyboardKey.numpadSubtract): () => _bumpQty(-1),
      const SingleActivator(LogicalKeyboardKey.escape): () {
        _search.clear();
        setState(() => _choices = const []);
        _focusSearch();
      },
    };

    final header = _PosHeader(
      companyName: session?.tenant.nomeFantasia ?? '',
      logoUrl: session?.tenant.logoUrl,
      compact: !wide,
      hasItems: !state.isEmpty,
      busy: _busy,
      cashSummary: cashState.summary!,
      onSearch: _focusSearch,
      onCustomer: _pickCustomer,
      onQty: _editQty,
      onRemove: _removeSelected,
      onDiscount: _editDiscount,
      onFinish: _finish,
      onWithdraw: () => _cashMove('SANGRIA'),
      onSupply: () => _cashMove('SUPRIMENTO'),
      onCloseCash: () => _closeCash(cashState.summary!),
    );

    final searchField = _SearchBar(
      controller: _search,
      focusNode: _searchFocus,
      busy: _busy,
      pendingQty: state.pendingQty,
      onSubmit: _submit,
      onCamera: cameraScannerAvailable ? _scanCamera : null,
    );

    final listArea = _choices.isNotEmpty
        ? _ChoicesList(products: _choices, highlighted: _choiceIndex, onPick: _addProduct)
        : _ItemsTable(
            state: state,
            compact: !wide,
            onSelect: (i) {
              _pos.select(i);
              if (wide) _focusSearch();
            },
            onInc: (i) => _pos.increment(i),
            onDec: (i) => _pos.increment(i, -1),
            onRemove: (i) => _pos.remove(i),
          );

    final saleCard = _SaleCard(
      saleNumber: summary?.nextNumber,
      customer: state.customer,
      onCustomer: _pickCustomer,
      onClearCustomer: () => _pos.setCustomer(null),
      search: searchField,
      list: listArea,
      state: state,
      compact: !wide,
    );

    final payPanel = _PaymentPanel(
      state: state,
      busy: _busy,
      compact: !wide,
      todaySales: summary?.sales,
      todayTotal: summary?.total,
      onPay: _finish,
      onDiscount: _editDiscount,
      onCancel: _cancelSale,
    );

    return CallbackShortcuts(
      bindings: bindings,
      child: Focus(
        child: Padding(
          padding: EdgeInsets.all(wide ? 12 : 8),
          child: Column(children: [
            header,
            SizedBox(height: wide ? 12 : 8),
            Expanded(
              child: wide
                  ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Expanded(child: saleCard),
                      const SizedBox(width: 12),
                      SizedBox(width: 320, child: payPanel),
                    ])
                  : Column(children: [Expanded(child: saleCard), const SizedBox(height: 8), payPanel]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Caixa fechado: o PDV só libera depois da abertura.
class _CashClosedPanel extends StatelessWidget {
  const _CashClosedPanel({required this.onOpen});
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.enter): onOpen},
      child: Focus(
        autofocus: true,
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.lock_outline, size: 72, color: t.colorScheme.outline),
            const SizedBox(height: 12),
            Text('Caixa fechado', style: t.textTheme.headlineSmall),
            const SizedBox(height: 4),
            const Text('Abra o caixa informando o troco inicial para começar a vender.'),
            const SizedBox(height: 20),
            FilledButton.icon(onPressed: onOpen, icon: const Icon(Icons.lock_open), label: const Text('Abrir caixa (Enter)')),
          ]),
        ),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.focusNode,
    required this.busy,
    required this.onSubmit,
    this.pendingQty,
    this.onCamera,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool busy;
  final double? pendingQty;
  final VoidCallback onSubmit;
  final VoidCallback? onCamera;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          autofocus: true,
          textInputAction: TextInputAction.search,
          style: Theme.of(context).textTheme.titleMedium,
          decoration: InputDecoration(
            prefixIcon: busy
                ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                : const Icon(Icons.qr_code_scanner),
            prefix: pendingQty != null ? Text('${number(pendingQty!)} × ') : null,
            hintText: 'Bipe o código de barras ou digite nome/SKU (F2)',
            isDense: false,
          ),
          onSubmitted: (_) => onSubmit(),
        ),
      ),
      if (onCamera != null) ...[
        const SizedBox(width: 8),
        IconButton.filledTonal(
          iconSize: 28,
          onPressed: onCamera,
          icon: const Icon(Icons.photo_camera),
          tooltip: 'Ler com a câmera',
        ),
      ],
    ]);
  }
}

class _ChoicesList extends StatelessWidget {
  const _ChoicesList({required this.products, required this.highlighted, required this.onPick});
  final List<Product> products;
  final int highlighted;
  final ValueChanged<Product> onPick;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text('${products.length} produto(s) — ↑/↓ e Enter, ou toque', style: t.textTheme.labelMedium),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: products.length,
            itemBuilder: (_, i) {
              final p = products[i];
              return ListTile(
                selected: i == highlighted,
                selectedTileColor: t.colorScheme.primaryContainer,
                leading: ProductThumb(url: p.imageUrl, size: 44),
                title: Text(p.name),
                subtitle: Text('SKU ${p.sku}${p.barcode != null ? ' · ${p.barcode}' : ''} · estoque ${number(p.stockQty)} ${p.unit}'),
                trailing: Text(money(p.price), style: const TextStyle(fontWeight: FontWeight.bold)),
                onTap: () => onPick(p),
              );
            },
          ),
        ),
      ]),
    );
  }
}

// =============================================================================
//  Visual do PDV: faixa azul com atalhos coloridos e relógio, venda no centro,
//  formas de pagamento à direita.
// =============================================================================
const _navy = Color(0xFF0B2A6F);
const _navy2 = Color(0xFF1546A8);
const _green = Color(0xFF1FA34A);
const _red = Color(0xFFD93636);
const _blue = Color(0xFF1E7BE0);
const _purple = Color(0xFF7B3FC4);
const _orange = Color(0xFFF08A12);
const _amber = Color(0xFFF2B705);
const _indigo = Color(0xFF3F51B5);

/// Faixa do topo: empresa, botões de atalho coloridos, caixa e relógio.
class _PosHeader extends StatelessWidget {
  const _PosHeader({
    required this.companyName,
    required this.logoUrl,
    required this.compact,
    required this.hasItems,
    required this.busy,
    required this.cashSummary,
    required this.onSearch,
    required this.onCustomer,
    required this.onQty,
    required this.onRemove,
    required this.onDiscount,
    required this.onFinish,
    required this.onWithdraw,
    required this.onSupply,
    required this.onCloseCash,
  });

  final String companyName;
  final String? logoUrl;
  final bool compact, hasItems, busy;
  final CashSummary cashSummary;
  final VoidCallback onSearch, onCustomer, onQty, onRemove, onDiscount, onFinish, onWithdraw, onSupply, onCloseCash;

  @override
  Widget build(BuildContext context) {
    final keys = [
      _KeyButton('F2', 'Consultar produto', _green, onSearch),
      _KeyButton('F3', 'Cliente', _blue, onCustomer),
      _KeyButton('F7', 'Quantidade', _indigo, hasItems ? onQty : null),
      _KeyButton('F8', 'Cancela item', _red, hasItems ? onRemove : null),
      _KeyButton('F9', 'Desconto', _amber, hasItems ? onDiscount : null, darkText: true),
      _KeyButton('F10', 'Finalizar venda', _green, hasItems && !busy ? onFinish : null),
    ];

    final cashMenu = PopupMenuButton<String>(
      tooltip: 'Caixa: sangria, suprimento e fechamento',
      onSelected: (v) {
        if (v == 'S') {
          onWithdraw();
        } else if (v == 'U') {
          onSupply();
        } else {
          onCloseCash();
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'S', child: ListTile(leading: Icon(Icons.outbox), title: Text('Sangria'))),
        PopupMenuItem(value: 'U', child: ListTile(leading: Icon(Icons.move_to_inbox), title: Text('Suprimento'))),
        PopupMenuItem(value: 'F', child: ListTile(leading: Icon(Icons.lock_outline), title: Text('Fechar caixa'))),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: .12), borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.circle, size: 10, color: Colors.greenAccent.shade400),
          const SizedBox(width: 6),
          Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            const Text('CAIXA ABERTO ▾', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
            Text('Gaveta ${money(cashSummary.expectedCash)}', style: const TextStyle(color: Colors.white70, fontSize: 11)),
          ]),
        ]),
      ),
    );

    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 14, vertical: compact ? 8 : 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [_navy, _navy2]),
        borderRadius: BorderRadius.circular(12),
      ),
      child: compact
          ? Column(children: [
              Row(children: [
                CompanyLogo(url: logoUrl, name: companyName, size: 28),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(companyName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                ),
                cashMenu,
              ]),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final k in keys) Padding(padding: const EdgeInsets.only(right: 6), child: k.build(small: true)),
                ]),
              ),
            ])
          : Row(children: [
              CompanyLogo(url: logoUrl, name: companyName, size: 44),
              const SizedBox(width: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(companyName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                  const Text('Frente de caixa', style: TextStyle(color: Colors.white70, fontSize: 12)),
                ]),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    for (final k in keys) Padding(padding: const EdgeInsets.only(right: 8), child: k.build()),
                  ]),
                ),
              ),
              const SizedBox(width: 12),
              cashMenu,
              const SizedBox(width: 16),
              const _Clock(),
            ]),
    );
  }
}

/// Botão colorido de atalho (tecla em cima, ação embaixo).
class _KeyButton {
  const _KeyButton(this.keyLabel, this.label, this.color, this.onTap, {this.darkText = false});
  final String keyLabel, label;
  final Color color;
  final VoidCallback? onTap;
  final bool darkText;

  Widget build({bool small = false}) {
    final enabled = onTap != null;
    final fg = darkText ? const Color(0xFF3A2A00) : Colors.white;
    return Opacity(
      opacity: enabled ? 1 : .45,
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(8),
        elevation: enabled ? 2 : 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: SizedBox(
            width: small ? 92 : 104,
            height: small ? 46 : 58,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(keyLabel, style: TextStyle(color: fg, fontWeight: FontWeight.w900, fontSize: small ? 14 : 18)),
              Text(label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: TextStyle(color: fg, fontSize: small ? 10 : 11, height: 1.1)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Relógio e data no canto da faixa.
class _Clock extends StatefulWidget {
  const _Clock();

  @override
  State<_Clock> createState() => _ClockState();
}

class _ClockState extends State<_Clock> {
  late Timer _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() => _now = DateTime.now()));
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String two(int v) => v.toString().padLeft(2, '0');
    return Row(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.schedule, color: Colors.white, size: 22),
      const SizedBox(width: 8),
      Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
        Text('${two(_now.hour)}:${two(_now.minute)}:${two(_now.second)}',
            style: const TextStyle(
                color: Colors.white, fontSize: 22, fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()])),
        Text(dateBr(_now), style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ]),
    ]);
  }
}

/// Venda no centro: número, cliente, busca, itens e total.
class _SaleCard extends StatelessWidget {
  const _SaleCard({
    required this.saleNumber,
    required this.customer,
    required this.onCustomer,
    required this.onClearCustomer,
    required this.search,
    required this.list,
    required this.state,
    required this.compact,
  });

  final int? saleNumber;
  final Partner? customer;
  final VoidCallback onCustomer, onClearCustomer;
  final Widget search, list;
  final PosState state;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final label = TextStyle(color: _navy2, fontWeight: FontWeight.w800, fontSize: compact ? 12 : 14);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // número da venda + cliente
        Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: compact ? 6 : 10),
          color: _navy.withValues(alpha: .06),
          child: Row(children: [
            Text(saleNumber == null ? 'VENDA' : 'VENDA Nº ${saleNumber.toString().padLeft(6, '0')}', style: label),
            const SizedBox(width: 12),
            Container(width: 1, height: 22, color: t.dividerColor),
            const SizedBox(width: 12),
            Expanded(
              child: InkWell(
                onTap: onCustomer,
                child: Row(children: [
                  Text('CLIENTE: ', style: TextStyle(fontWeight: FontWeight.w700, fontSize: compact ? 12 : 13)),
                  Expanded(
                    child: Text(
                      customer?.displayName.toUpperCase() ?? 'CONSUMIDOR FINAL',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: compact ? 12 : 13, color: customer == null ? t.colorScheme.outline : null),
                    ),
                  ),
                ]),
              ),
            ),
            if (customer != null)
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Tirar cliente',
                onPressed: onClearCustomer,
                icon: const Icon(Icons.close, size: 18),
              )
            else
              TextButton.icon(
                onPressed: onCustomer,
                icon: const Icon(Icons.person_search, size: 18),
                label: Text(compact ? 'F3' : 'Identificar (F3)'),
              ),
          ]),
        ),
        Padding(padding: const EdgeInsets.fromLTRB(12, 10, 12, 8), child: search),
        Expanded(child: list),
        // rodapé: quantidade de itens e total
        Container(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: compact ? 6 : 10),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: t.dividerColor))),
          child: Row(children: [
            Text('Qtde. itens: ', style: t.textTheme.bodyMedium),
            Text('${state.itemCount}', style: const TextStyle(fontWeight: FontWeight.w800)),
            if (state.unitCount != state.itemCount)
              Text('  (${number(state.unitCount)} un)', style: t.textTheme.bodySmall),
            const Spacer(),
            if (!compact) ...[
              Text('TOTAL', style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(width: 24),
              Text(money(state.total),
                  style: t.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800, color: _navy2)),
            ],
          ]),
        ),
      ]),
    );
  }
}

/// Tabela de itens: Descrição · Cód. barras · Qtd · Vlr. unit. · Total.
class _ItemsTable extends StatelessWidget {
  const _ItemsTable({
    required this.state,
    required this.compact,
    required this.onSelect,
    required this.onInc,
    required this.onDec,
    required this.onRemove,
  });

  final PosState state;
  final bool compact;
  final ValueChanged<int> onSelect, onInc, onDec, onRemove;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    if (state.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.qr_code_scanner, size: 64, color: t.colorScheme.outline),
          const SizedBox(height: 8),
          Text('CAIXA LIVRE', style: t.textTheme.headlineSmall?.copyWith(color: _navy2, fontWeight: FontWeight.w800)),
          const Text('Bipe um produto ou digite o nome (F2)'),
        ]),
      );
    }
    const head = TextStyle(color: _navy2, fontWeight: FontWeight.w700, fontSize: 13);

    if (compact) {
      return ListView.separated(
        itemCount: state.items.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final it = state.items[i];
          return ListTile(
            dense: true,
            selected: state.selected == i,
            selectedTileColor: _blue.withValues(alpha: .10),
            leading: ProductThumb(url: it.product.imageUrl, size: 36),
            title: Text(it.product.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${number(it.qty)} × ${money(it.product.price)}'),
            onTap: () => onSelect(i),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.remove), onPressed: () => onDec(i)),
              IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.add), onPressed: () => onInc(i)),
              Text(money(it.total), style: const TextStyle(fontWeight: FontWeight.bold)),
            ]),
          );
        },
      );
    }

    Widget cell(Widget child, {int flex = 1, TextAlign align = TextAlign.left}) => Expanded(
          flex: flex,
          child: Align(
            alignment: align == TextAlign.right ? Alignment.centerRight : Alignment.centerLeft,
            child: child,
          ),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.dividerColor, width: 1.5))),
        child: Row(children: [
          SizedBox(width: 36, child: Text('#', style: head)),
          cell(Text('Descrição', style: head), flex: 5),
          cell(Text('Cód. Barras', style: head), flex: 3),
          cell(Text('Qtd.', style: head), flex: 2, align: TextAlign.right),
          cell(Text('Vlr. Unit.', style: head), flex: 2, align: TextAlign.right),
          cell(Text('Total', style: head), flex: 2, align: TextAlign.right),
          const SizedBox(width: 96),
        ]),
      ),
      Expanded(
        child: ListView.builder(
          itemCount: state.items.length,
          itemBuilder: (_, i) {
            final it = state.items[i];
            final sel = state.selected == i;
            final low = it.qty > it.product.stockQty;
            return Material(
              color: sel ? _blue.withValues(alpha: .12) : (i.isOdd ? t.colorScheme.surfaceContainerHighest.withValues(alpha: .35) : null),
              child: InkWell(
                onTap: () => onSelect(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(children: [
                    SizedBox(width: 36, child: Text('${i + 1}', style: t.textTheme.bodySmall)),
                    cell(
                      Row(children: [
                        if (it.product.imageUrl != null)
                          Padding(padding: const EdgeInsets.only(right: 8), child: ProductThumb(url: it.product.imageUrl, size: 28)),
                        Flexible(
                          child: Text(it.product.name.toUpperCase(),
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                        ),
                        if (low)
                          Tooltip(
                            message: 'Estoque: ${number(it.product.stockQty)}',
                            child: Icon(Icons.warning_amber, size: 16, color: t.colorScheme.error),
                          ),
                      ]),
                      flex: 5,
                    ),
                    cell(Text(it.product.barcode ?? it.product.sku, style: t.textTheme.bodySmall), flex: 3),
                    cell(Text('${number(it.qty)} ${it.product.unit}'), flex: 2, align: TextAlign.right),
                    cell(Text(money(it.product.price)), flex: 2, align: TextAlign.right),
                    cell(Text(money(it.total), style: const TextStyle(fontWeight: FontWeight.w800)), flex: 2, align: TextAlign.right),
                    SizedBox(
                      width: 96,
                      child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                        IconButton(visualDensity: VisualDensity.compact, iconSize: 18, icon: const Icon(Icons.remove), onPressed: () => onDec(i)),
                        IconButton(visualDensity: VisualDensity.compact, iconSize: 18, icon: const Icon(Icons.add), onPressed: () => onInc(i)),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          iconSize: 18,
                          icon: Icon(Icons.delete_outline, color: t.colorScheme.error),
                          onPressed: () => onRemove(i),
                        ),
                      ]),
                    ),
                  ]),
                ),
              ),
            );
          },
        ),
      ),
    ]);
  }
}

/// Painel da direita: formas de pagamento em botões grandes e o resumo.
class _PaymentPanel extends StatelessWidget {
  const _PaymentPanel({
    required this.state,
    required this.busy,
    required this.compact,
    required this.onPay,
    required this.onDiscount,
    required this.onCancel,
    this.todaySales,
    this.todayTotal,
  });

  final PosState state;
  final bool busy, compact;
  final int? todaySales;
  final double? todayTotal;
  final void Function(PaymentMethod) onPay;
  final VoidCallback onDiscount, onCancel;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final enabled = !state.isEmpty && !busy;
    final buttons = [
      _PayButton('Dinheiro', Icons.payments_outlined, _green, enabled ? () => onPay(PaymentMethod.dinheiro) : null),
      _PayButton('PIX', Icons.pix, _blue, enabled ? () => onPay(PaymentMethod.pix) : null),
      _PayButton('Cartão', Icons.credit_card, _purple, enabled ? () => onPay(PaymentMethod.debito) : null),
      _PayButton('A Prazo', Icons.event_note, _orange, enabled ? () => onPay(PaymentMethod.prazo) : null),
    ];

    if (compact) {
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              if (state.discount > 0) Text('Desc. ${money(state.discount)}  ', style: const TextStyle(color: _red)),
              TextButton(onPressed: state.isEmpty ? null : onDiscount, child: const Text('Desconto')),
              const Spacer(),
              Text('TOTAL  ', style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              Text(money(state.total), style: t.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, color: _navy2)),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              for (final (i, b) in buttons.indexed) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(child: b.build(small: true)),
              ],
            ]),
          ]),
        ),
      );
    }

    Widget kv(String k, String v, {Color? color, bool big = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Text(k, style: TextStyle(fontWeight: big ? FontWeight.w800 : FontWeight.w600, fontSize: big ? 15 : 12)),
            const Spacer(),
            Text(v, style: TextStyle(fontWeight: FontWeight.w800, fontSize: big ? 20 : 15, color: color ?? (big ? _navy2 : null))),
          ]),
        );

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('FORMA DE PAGAMENTO',
              textAlign: TextAlign.center,
              style: TextStyle(color: _navy2, fontWeight: FontWeight.w800, letterSpacing: .5)),
          const SizedBox(height: 12),
          for (final b in buttons) Padding(padding: const EdgeInsets.only(bottom: 10), child: b.build()),
          if (state.customer == null)
            Text('A Prazo pede o cliente (F3).', textAlign: TextAlign.center, style: t.textTheme.bodySmall),
          const Spacer(),
          const Divider(),
          kv('SUBTOTAL', money(state.subtotal)),
          InkWell(
            onTap: state.isEmpty ? null : onDiscount,
            child: kv('DESCONTO (F9)', state.discount > 0 ? '- ${money(state.discount)}' : money(0), color: _red),
          ),
          const Divider(),
          kv('TOTAL', money(state.total), big: true),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: state.isEmpty ? null : onCancel,
            icon: const Icon(Icons.cancel_outlined, size: 18),
            label: const Text('Cancelar venda (Ctrl+Del)'),
          ),
          if (todaySales != null)
            Text('Hoje: $todaySales venda(s) · ${money(todayTotal ?? 0)}',
                textAlign: TextAlign.center, style: t.textTheme.bodySmall),
        ]),
      ),
    );
  }
}

class _PayButton {
  const _PayButton(this.label, this.icon, this.color, this.onTap);
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  Widget build({bool small = false}) => Opacity(
        opacity: onTap == null ? .5 : 1,
        child: Material(
          color: color,
          borderRadius: BorderRadius.circular(10),
          elevation: onTap == null ? 0 : 2,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: SizedBox(
              height: small ? 52 : 64,
              child: small
                  ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(icon, color: Colors.white, size: 20),
                      Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                    ])
                  : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white70, width: 1.5),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(icon, color: Colors.white, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Text(label, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                    ]),
            ),
          ),
        ),
      );
}
