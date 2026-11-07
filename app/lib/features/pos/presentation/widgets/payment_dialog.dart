import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/utils/formatters.dart';
import '../../domain/pos_models.dart';

/// Resultado do pagamento: formas usadas + prazo da parte "a prazo" (dias).
typedef PaymentResult = ({List<Payment> payments, int dueDays});

/// Recebimento com múltiplas formas de pagamento.
/// Teclado: F1 Dinheiro · F2 PIX · F3 Débito · F4 Crédito · F6 A prazo · F7 Vale-troca ·
/// Enter lança/confirma · F10 conclui · Esc volta
class PaymentDialog extends StatefulWidget {
  const PaymentDialog({super.key, required this.total, this.customerName, this.initialMethod, this.lookupVoucher});
  final double total;

  /// Confere um vale-troca pelo código (null = forma "Vale-troca" não aparece).
  final Future<VoucherInfo?> Function(String code)? lookupVoucher;

  /// Forma já escolhida no painel do PDV (botões Dinheiro / PIX / Cartão / A prazo).
  final PaymentMethod? initialMethod;

  /// Venda a prazo só aparece com cliente identificado.
  final String? customerName;

  @override
  State<PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<PaymentDialog> {
  final _amount = TextEditingController();
  final _amountFocus = FocusNode();
  final _days = TextEditingController(text: '30');
  final List<Payment> _payments = [];
  PaymentMethod _method = PaymentMethod.dinheiro;

  bool get _allowPrazo => widget.customerName != null;
  double get _paid => _payments.fold<double>(0, (a, p) => a + p.amount);
  double get _remaining => ((widget.total - _paid) * 100).roundToDouble() / 100;
  double get _change => _remaining < 0 ? -_remaining : 0;
  bool get _done => _remaining <= 0;
  bool get _hasPrazo => _payments.any((p) => p.method == PaymentMethod.prazo);

  List<PaymentMethod> get _methods =>
      [
        for (final m in PaymentMethod.values)
          if ((m != PaymentMethod.prazo || _allowPrazo) && (m != PaymentMethod.vale || widget.lookupVoucher != null)) m,
      ];

  static const _keys = {
    PaymentMethod.dinheiro: LogicalKeyboardKey.f1,
    PaymentMethod.pix: LogicalKeyboardKey.f2,
    PaymentMethod.debito: LogicalKeyboardKey.f3,
    PaymentMethod.credito: LogicalKeyboardKey.f4,
    PaymentMethod.prazo: LogicalKeyboardKey.f6,
    PaymentMethod.vale: LogicalKeyboardKey.f7,
  };

  @override
  void initState() {
    super.initState();
    final m = widget.initialMethod;
    if (m != null && _methods.contains(m)) _method = m;
    _resetAmount();
  }

  @override
  void dispose() {
    _amount.dispose();
    _amountFocus.dispose();
    _days.dispose();
    super.dispose();
  }

  void _resetAmount() {
    _amount.text = _remaining > 0 ? _remaining.toStringAsFixed(2).replaceAll('.', ',') : '';
    _amount.selection = TextSelection(baseOffset: 0, extentOffset: _amount.text.length);
    _amountFocus.requestFocus();
  }

  void _pick(PaymentMethod m) {
    if (!_methods.contains(m)) return;
    setState(() => _method = m);
    _resetAmount();
  }

  Future<void> _enter() async {
    final v = parseMoney(_amount.text);
    if (v <= 0) {
      if (_done) _confirm();
      return;
    }
    if (_method == PaymentMethod.vale) return _enterVoucher(v);
    // troco só faz sentido em dinheiro; demais formas limitadas ao restante
    final value = _method == PaymentMethod.dinheiro ? v : (v > _remaining ? _remaining : v);
    if (value <= 0) return;
    setState(() => _payments.add(Payment(_method, value)));
    _resetAmount();
  }

  /// Vale-troca: pede o código, confere o saldo e lança até o saldo / o que falta.
  Future<void> _enterVoucher(double wanted) async {
    final ctrl = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Código do vale-troca'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(hintText: 'Ex.: VT000012', prefixIcon: Icon(Icons.confirmation_number_outlined)),
          onSubmitted: (v) => Navigator.pop(c, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: const Text('Conferir')),
        ],
      ),
    );
    if (code == null || code.isEmpty || !mounted) return;
    if (_payments.any((p) => p.voucher?.toUpperCase() == code.toUpperCase())) {
      _snack('Este vale já foi lançado');
      return;
    }
    try {
      final info = await widget.lookupVoucher!(code);
      if (!mounted) return;
      if (info == null || info.balance <= 0) {
        _snack('Vale $code sem saldo');
        return;
      }
      var value = wanted;
      if (value > info.balance) value = info.balance;
      if (value > _remaining) value = _remaining;
      if (value <= 0) return;
      setState(() => _payments.add(Payment(PaymentMethod.vale, value, voucher: info.code)));
      _resetAmount();
    } catch (e) {
      if (mounted) _snack(e.toString());
    }
  }

  void _snack(String m) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(m)));

  void _confirm() {
    if (!_done) return;
    final days = int.tryParse(_days.text) ?? 30;
    Navigator.pop<PaymentResult>(context, (payments: List<Payment>.unmodifiable(_payments), dueDays: days));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);

    return CallbackShortcuts(
      bindings: {
        for (final m in _methods) SingleActivator(_keys[m]!): () => _pick(m),
        const SingleActivator(LogicalKeyboardKey.f10): _confirm,
      },
      child: AlertDialog(
        title: Row(children: [
          const Expanded(child: Text('Pagamento')),
          Text(money(widget.total), style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
        ]),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (widget.customerName != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(children: [
                    const Icon(Icons.person, size: 18),
                    const SizedBox(width: 6),
                    Expanded(child: Text(widget.customerName!, overflow: TextOverflow.ellipsis)),
                  ]),
                ),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final m in _methods)
                  ChoiceChip(
                    label: Text('${m.label} (${_keys[m]!.keyLabel})'),
                    selected: _method == m,
                    onSelected: (_) => _pick(m),
                  ),
              ]),
              if (!_allowPrazo)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Para vender a prazo, identifique o cliente (F3) antes de finalizar.',
                      style: t.textTheme.bodySmall),
                ),
              const SizedBox(height: 16),
              TextField(
                controller: _amount,
                focusNode: _amountFocus,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: t.textTheme.headlineSmall,
                decoration: InputDecoration(
                  labelText: 'Valor em ${_method.label}',
                  prefixText: r'R$ ',
                  helperText: _done ? 'Enter para concluir' : 'Enter para lançar',
                ),
                onSubmitted: (_) => _enter(),
              ),
              if (_method == PaymentMethod.prazo || _hasPrazo) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _days,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Vencimento da parte a prazo', suffixText: 'dias'),
                ),
              ],
              const SizedBox(height: 12),
              for (var i = 0; i < _payments.length; i++)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(_payments[i].voucher != null
                      ? '${_payments[i].method.label} ${_payments[i].voucher}'
                      : _payments[i].method.label),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(money(_payments[i].amount)),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        setState(() => _payments.removeAt(i));
                        _resetAmount();
                      },
                    ),
                  ]),
                ),
              const Divider(),
              _row(context, 'Pago', money(_paid)),
              if (!_done) _row(context, 'Falta', money(_remaining), color: t.colorScheme.error),
              if (_change > 0) _row(context, 'Troco', money(_change), color: Colors.green.shade700, big: true),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Voltar (Esc)')),
          FilledButton.icon(
            onPressed: _done ? _confirm : null,
            icon: const Icon(Icons.check),
            label: const Text('Concluir venda (F10)'),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext c, String l, String v, {Color? color, bool big = false}) {
    final style = (big ? Theme.of(c).textTheme.titleLarge : Theme.of(c).textTheme.titleMedium)
        ?.copyWith(color: color, fontWeight: FontWeight.bold);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [Expanded(child: Text(l, style: style)), Text(v, style: style)]),
    );
  }
}
