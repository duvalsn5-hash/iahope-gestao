import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/utils/formatters.dart';
import '../../domain/pos_models.dart';

/// Recebimento com múltiplas formas de pagamento.
/// Teclado: F1 Dinheiro · F2 PIX · F3 Débito · F4 Crédito · Enter lança/confirma · Esc volta
class PaymentDialog extends StatefulWidget {
  const PaymentDialog({super.key, required this.total});
  final double total;

  @override
  State<PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<PaymentDialog> {
  final _amount = TextEditingController();
  final _amountFocus = FocusNode();
  final List<Payment> _payments = [];
  PaymentMethod _method = PaymentMethod.dinheiro;

  double get _paid => _payments.fold<double>(0, (a, p) => a + p.amount);
  double get _remaining => ((widget.total - _paid) * 100).roundToDouble() / 100;
  double get _change => _remaining < 0 ? -_remaining : 0;
  bool get _done => _remaining <= 0;

  @override
  void initState() {
    super.initState();
    _resetAmount();
  }

  @override
  void dispose() {
    _amount.dispose();
    _amountFocus.dispose();
    super.dispose();
  }

  void _resetAmount() {
    _amount.text = _remaining > 0 ? _remaining.toStringAsFixed(2).replaceAll('.', ',') : '';
    _amount.selection = TextSelection(baseOffset: 0, extentOffset: _amount.text.length);
    _amountFocus.requestFocus();
  }

  void _pick(PaymentMethod m) {
    setState(() => _method = m);
    _resetAmount();
  }

  void _enter() {
    final v = parseMoney(_amount.text);
    if (v <= 0) {
      if (_done) _confirm();
      return;
    }
    // troco só faz sentido em dinheiro; cartão/PIX limitado ao restante
    final value = _method == PaymentMethod.dinheiro ? v : (v > _remaining ? _remaining : v);
    if (value <= 0) return;
    setState(() => _payments.add(Payment(_method, value)));
    _resetAmount();
  }

  void _confirm() {
    if (!_done) return;
    Navigator.pop(context, List<Payment>.unmodifiable(_payments));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final keys = {
      PaymentMethod.dinheiro: LogicalKeyboardKey.f1,
      PaymentMethod.pix: LogicalKeyboardKey.f2,
      PaymentMethod.debito: LogicalKeyboardKey.f3,
      PaymentMethod.credito: LogicalKeyboardKey.f4,
    };

    return CallbackShortcuts(
      bindings: {
        for (final e in keys.entries) SingleActivator(e.value): () => _pick(e.key),
        const SingleActivator(LogicalKeyboardKey.f10): _confirm,
      },
      child: AlertDialog(
        title: Row(children: [
          const Expanded(child: Text('Pagamento')),
          Text(money(widget.total), style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
        ]),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final m in PaymentMethod.values)
                ChoiceChip(
                  label: Text('${m.label} (${keys[m]!.keyLabel})'),
                  selected: _method == m,
                  onSelected: (_) => _pick(m),
                ),
            ]),
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
            const SizedBox(height: 12),
            for (var i = 0; i < _payments.length; i++)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(_payments[i].method.label),
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
