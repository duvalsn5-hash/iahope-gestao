import 'package:flutter/material.dart';

import '../../../core/utils/formatters.dart';
import '../domain/cash.dart';

const kMethodLabels = {
  'DINHEIRO': 'Dinheiro',
  'PIX': 'PIX',
  'DEBITO': 'Cartão de débito',
  'CREDITO': 'Cartão de crédito',
  'PRAZO': 'A prazo (fiado)',
  'OUTROS': 'Outros',
};

/// Pede um valor em reais. Usado na abertura, sangria e suprimento.
Future<(double, String?)?> askCashAmount(
  BuildContext context, {
  required String title,
  required String label,
  String? help,
  bool askReason = false,
  double? initial,
}) {
  final amount = TextEditingController(text: initial == null ? '' : initial.toStringAsFixed(2).replaceAll('.', ','));
  final reason = TextEditingController();
  return showDialog<(double, String?)>(
    context: context,
    builder: (c) {
      void ok() {
        final v = parseMoney(amount.text);
        if (v < 0) return;
        Navigator.pop(c, (v, reason.text.trim().isEmpty ? null : reason.text.trim()));
      }

      return AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 360,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (help != null) ...[Text(help), const SizedBox(height: 12)],
            TextField(
              controller: amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: Theme.of(c).textTheme.headlineSmall,
              decoration: InputDecoration(labelText: label, prefixText: r'R$ '),
              onSubmitted: (_) {
                if (!askReason) ok();
              },
            ),
            if (askReason) ...[
              const SizedBox(height: 12),
              TextField(
                controller: reason,
                decoration: const InputDecoration(labelText: 'Motivo (opcional)'),
                onSubmitted: (_) => ok(),
              ),
            ],
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
          FilledButton(onPressed: ok, child: const Text('Confirmar')),
        ],
      );
    },
  );
}

/// Linhas do resumo do caixa (vendas por forma de pagamento + gaveta).
class CashSummaryView extends StatelessWidget {
  const CashSummaryView({super.key, required this.s});
  final CashSummary s;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    Widget row(String l, String v, {bool bold = false, Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Expanded(child: Text(l, style: bold ? const TextStyle(fontWeight: FontWeight.w600) : null)),
            Text(v, style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w500, color: color)),
          ]),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      row('Vendas (${s.salesCount})', money(s.salesTotal), bold: true),
      for (final e in s.byMethod.entries) row('   ${kMethodLabels[e.key] ?? e.key}', money(e.value)),
      if (s.change > 0) row('   Troco devolvido', '- ${money(s.change)}'),
      const Divider(),
      Text('Gaveta (dinheiro)', style: t.textTheme.labelLarge),
      row('Abertura', money(s.opening)),
      if (s.supply > 0) row('Suprimentos', '+ ${money(s.supply)}'),
      if (s.received > 0) row('Recebimentos de contas', '+ ${money(s.received)}'),
      if (s.withdrawal > 0) row('Sangrias', '- ${money(s.withdrawal)}'),
      if (s.paidOut > 0) row('Pagamentos de contas', '- ${money(s.paidOut)}'),
      row('Esperado na gaveta', money(s.expectedCash), bold: true, color: t.colorScheme.primary),
      if (s.counted != null) row('Contado', money(s.counted!)),
      if (s.difference != null)
        row(
          s.difference! == 0 ? 'Diferença' : (s.difference! > 0 ? 'Sobra' : 'Falta'),
          money(s.difference!.abs()),
          bold: true,
          color: s.difference! == 0
              ? Colors.green.shade700
              : (s.difference! > 0 ? Colors.orange.shade800 : t.colorScheme.error),
        ),
    ]);
  }
}

/// Fechamento: mostra o resumo, pede o valor contado e calcula sobra/falta na hora.
class CloseCashDialog extends StatefulWidget {
  const CloseCashDialog({super.key, required this.summary});
  final CashSummary summary;

  @override
  State<CloseCashDialog> createState() => _CloseCashDialogState();
}

class _CloseCashDialogState extends State<CloseCashDialog> {
  final _counted = TextEditingController();
  final _notes = TextEditingController();

  @override
  void dispose() {
    _counted.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final counted = _counted.text.trim().isEmpty ? null : parseMoney(_counted.text);
    final diff = counted == null ? null : counted - widget.summary.expectedCash;

    return AlertDialog(
      title: const Text('Fechar caixa'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            CashSummaryView(s: widget.summary),
            const SizedBox(height: 16),
            TextField(
              controller: _counted,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: t.textTheme.headlineSmall,
              decoration: InputDecoration(
                labelText: 'Dinheiro contado na gaveta',
                prefixText: r'R$ ',
                helperText: diff == null
                    ? 'Conte as notas e moedas e digite o total'
                    : diff.abs() < 0.005
                        ? 'Caixa bateu'
                        : diff > 0
                            ? 'Sobra de ${money(diff)}'
                            : 'Falta de ${money(-diff)}',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(controller: _notes, decoration: const InputDecoration(labelText: 'Observação (opcional)')),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton.icon(
          onPressed: counted == null
              ? null
              : () => Navigator.pop(context, (counted, _notes.text.trim().isEmpty ? null : _notes.text.trim())),
          icon: const Icon(Icons.lock_outline),
          label: const Text('Fechar caixa'),
        ),
      ],
    );
  }
}
