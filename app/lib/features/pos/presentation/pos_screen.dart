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
///   F2 buscar · F3 cliente · F7 quantidade · F8 remover item · F9 desconto · F10 finalizar
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

  Future<void> _finish() async {
    final s = ref.read(posControllerProvider);
    if (s.isEmpty || _busy) return;
    final result = await showDialog<PaymentResult>(
      context: context,
      builder: (_) => PaymentDialog(total: s.total, customerName: s.customer?.displayName),
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
        : _CartList(
            state: state,
            onSelect: (i) {
              _pos.select(i);
              if (wide) _focusSearch();
            },
            onInc: (i) => _pos.increment(i),
            onDec: (i) => _pos.increment(i, -1),
            onRemove: (i) => _pos.remove(i),
          );

    final totals = _TotalsPanel(
      state: state,
      logoUrl: session?.tenant.logoUrl,
      companyName: session?.tenant.nomeFantasia ?? '',
      busy: _busy,
      showShortcuts: wide,
      onDiscount: _editDiscount,
      onCancel: _cancelSale,
      onFinish: _finish,
    );

    final cashBar = _CashBar(
      summary: cashState.summary!,
      customer: state.customer,
      onCustomer: _pickCustomer,
      onClearCustomer: () => _pos.setCustomer(null),
      onWithdraw: () => _cashMove('SANGRIA'),
      onSupply: () => _cashMove('SUPRIMENTO'),
      onClose: () => _closeCash(cashState.summary!),
    );

    return CallbackShortcuts(
      bindings: bindings,
      child: Focus(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            cashBar,
            const SizedBox(height: 8),
            Expanded(
              child: wide
              ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Expanded(
                    flex: 3,
                    child: Column(children: [searchField, const SizedBox(height: 12), Expanded(child: listArea)]),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(width: 360, child: totals),
                ])
              : Column(children: [
                  searchField,
                  const SizedBox(height: 8),
                  Expanded(child: listArea),
                  const SizedBox(height: 8),
                  totals,
                ]),
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

/// Barra do topo do PDV: situação do caixa, cliente identificado e ações de caixa.
class _CashBar extends StatelessWidget {
  const _CashBar({
    required this.summary,
    required this.customer,
    required this.onCustomer,
    required this.onClearCustomer,
    required this.onWithdraw,
    required this.onSupply,
    required this.onClose,
  });

  final CashSummary summary;
  final Partner? customer;
  final VoidCallback onCustomer, onClearCustomer, onWithdraw, onSupply, onClose;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
      Chip(
        avatar: Icon(Icons.circle, size: 12, color: Colors.green.shade600),
        label: Text('Caixa aberto · gaveta ${money(summary.expectedCash)} · ${summary.salesCount} venda(s)'),
      ),
      customer == null
          ? ActionChip(avatar: const Icon(Icons.person_search, size: 18), label: const Text('Cliente (F3)'), onPressed: onCustomer)
          : InputChip(
              avatar: const Icon(Icons.person, size: 18),
              label: Text(customer!.displayName, overflow: TextOverflow.ellipsis),
              backgroundColor: t.colorScheme.primaryContainer,
              onPressed: onCustomer,
              onDeleted: onClearCustomer,
            ),
      PopupMenuButton<String>(
        tooltip: 'Caixa',
        onSelected: (v) {
          switch (v) {
            case 'S':
              onWithdraw();
            case 'U':
              onSupply();
            case 'F':
              onClose();
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'S', child: ListTile(leading: Icon(Icons.outbox), title: Text('Sangria'))),
          PopupMenuItem(value: 'U', child: ListTile(leading: Icon(Icons.move_to_inbox), title: Text('Suprimento'))),
          PopupMenuItem(value: 'F', child: ListTile(leading: Icon(Icons.lock_outline), title: Text('Fechar caixa'))),
        ],
        child: const Chip(avatar: Icon(Icons.point_of_sale, size: 18), label: Text('Caixa ▾')),
      ),
    ]);
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

class _CartList extends StatelessWidget {
  const _CartList({
    required this.state,
    required this.onSelect,
    required this.onInc,
    required this.onDec,
    required this.onRemove,
  });

  final PosState state;
  final ValueChanged<int> onSelect, onInc, onDec, onRemove;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    if (state.isEmpty) {
      return Card(
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.shopping_cart_outlined, size: 64, color: t.colorScheme.outline),
            const SizedBox(height: 8),
            Text('Caixa livre', style: t.textTheme.titleLarge),
            const Text('Bipe um produto para começar'),
          ]),
        ),
      );
    }
    return Card(
      child: ListView.separated(
        itemCount: state.items.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final it = state.items[i];
          final lowStock = it.qty > it.product.stockQty;
          return ListTile(
            selected: state.selected == i,
            selectedTileColor: t.colorScheme.secondaryContainer.withValues(alpha: .5),
            leading: CircleAvatar(radius: 14, child: Text('${i + 1}', style: const TextStyle(fontSize: 12))),
            title: Text(it.product.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              '${number(it.qty)} ${it.product.unit} × ${money(it.product.price)}'
              '${lowStock ? '  ⚠ estoque ${number(it.product.stockQty)}' : ''}',
              style: lowStock ? TextStyle(color: t.colorScheme.error) : null,
            ),
            onTap: () => onSelect(i),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.remove), onPressed: () => onDec(i)),
              IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.add), onPressed: () => onInc(i)),
              SizedBox(
                width: 90,
                child: Text(money(it.total), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.delete_outline, color: t.colorScheme.error),
                onPressed: () => onRemove(i),
              ),
            ]),
          );
        },
      ),
    );
  }
}

class _TotalsPanel extends ConsumerWidget {
  const _TotalsPanel({
    required this.state,
    required this.logoUrl,
    required this.companyName,
    required this.busy,
    required this.showShortcuts,
    required this.onDiscount,
    required this.onCancel,
    required this.onFinish,
  });

  final PosState state;
  final String? logoUrl;
  final String companyName;
  final bool busy, showShortcuts;
  final VoidCallback onDiscount, onCancel, onFinish;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final summary = ref.watch(posSummaryProvider).valueOrNull;
    final compact = !showShortcuts;

    final totalBlock = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!compact) ...[
        Row(children: [
          CompanyLogo(url: logoUrl, name: companyName, size: 56),
          const SizedBox(width: 12),
          Expanded(child: Text(companyName, style: t.textTheme.titleMedium)),
        ]),
        const Divider(height: 24),
        _kv(context, 'Itens', '${state.itemCount} (${number(state.unitCount)} un)'),
        _kv(context, 'Subtotal', money(state.subtotal)),
      ],
      if (state.discount > 0) _kv(context, 'Desconto', '- ${money(state.discount)}'),
      Row(children: [
        Text('TOTAL', style: t.textTheme.titleLarge),
        const Spacer(),
        Text(money(state.total),
            style: (compact ? t.textTheme.headlineMedium : t.textTheme.displaySmall)
                ?.copyWith(fontWeight: FontWeight.bold, color: t.colorScheme.primary)),
      ]),
    ]);

    final actions = Row(children: [
      OutlinedButton(onPressed: state.isEmpty ? null : onDiscount, child: Text(compact ? '%' : 'Desconto (F9)')),
      const SizedBox(width: 8),
      Expanded(
        child: FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
          onPressed: state.isEmpty || busy ? null : onFinish,
          icon: const Icon(Icons.payments),
          label: Text(compact ? 'Finalizar' : 'Finalizar (F10)', style: const TextStyle(fontSize: 18)),
        ),
      ),
    ]);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            totalBlock,
            const SizedBox(height: 12),
            actions,
            if (!compact) ...[
              TextButton.icon(
                onPressed: state.isEmpty ? null : onCancel,
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('Cancelar venda (Ctrl+Del)'),
              ),
              const Spacer(),
              if (summary != null)
                Text('Hoje: ${summary.sales} venda(s) · ${money(summary.total)}', style: t.textTheme.bodySmall),
              const SizedBox(height: 8),
              const _ShortcutsLegend(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _kv(BuildContext c, String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [Text(k), const Spacer(), Text(v, style: const TextStyle(fontWeight: FontWeight.w600))]),
      );
}

class _ShortcutsLegend extends StatelessWidget {
  const _ShortcutsLegend();

  @override
  Widget build(BuildContext context) {
    const items = [
      ('F2', 'Buscar'),
      ('F3', 'Cliente'),
      ('F7', 'Quantidade'),
      ('F8', 'Remover item'),
      ('F9', 'Desconto'),
      ('F10', 'Finalizar'),
      ('↑ ↓', 'Navegar'),
      ('+ −', 'Qtd. (teclado num.)'),
      ('3*', 'Multiplicar'),
      ('Esc', 'Limpar busca'),
    ];
    final s = Theme.of(context).textTheme.labelSmall;
    return Wrap(spacing: 10, runSpacing: 4, children: [
      for (final (k, v) in items)
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).colorScheme.outline),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(k, style: s?.copyWith(fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 4),
          Text(v, style: s),
        ]),
    ]);
  }
}
