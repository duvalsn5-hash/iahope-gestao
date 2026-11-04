import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/common_widgets.dart';
import '../../data/receipt_printer.dart';
import '../../domain/pos_models.dart';

/// Comprovante na tela (com a logo da empresa) + impressão do cupom 80mm.
class ReceiptDialog extends StatelessWidget {
  const ReceiptDialog({super.key, required this.receipt});
  final Receipt receipt;

  Future<void> _print(BuildContext context) async {
    try {
      await ReceiptPrinter.printReceipt(receipt);
    } catch (e) {
      if (context.mounted) showError(context, 'Falha ao imprimir: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = receipt;
    final t = Theme.of(context);
    final mono = t.textTheme.bodySmall?.copyWith(fontFamily: 'monospace');

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f9): () => _print(context),
        const SingleActivator(LogicalKeyboardKey.enter): () => Navigator.pop(context),
      },
      child: Focus(
        autofocus: true,
        child: AlertDialog(
          title: Row(children: [
            Icon(Icons.check_circle, color: Colors.green.shade600),
            const SizedBox(width: 8),
            Text('Venda nº ${r.number} concluída'),
          ]),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(border: Border.all(color: t.colorScheme.outlineVariant)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Center(child: CompanyLogo(url: r.logoUrl, name: r.companyName, size: 64)),
                  const SizedBox(height: 6),
                  Text(r.companyName, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text('CNPJ ${formatCnpj(r.cnpj)}', textAlign: TextAlign.center, style: mono),
                  Text(dateTimeBr(r.createdAt), textAlign: TextAlign.center, style: mono),
                  const Divider(),
                  for (final i in r.items) ...[
                    Text(i.description, style: mono),
                    Row(children: [
                      Expanded(child: Text('  ${number(i.qty)} x ${money(i.unitPrice)}', style: mono)),
                      Text(money(i.total), style: mono),
                    ]),
                  ],
                  const Divider(),
                  if (r.discount > 0) _l('Desconto', '- ${money(r.discount)}', mono),
                  _l('TOTAL', money(r.total), t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  for (final p in r.payments) _l(paymentLabel(p.$1), money(p.$2), mono),
                  if (r.change > 0) _l('Troco', money(r.change), t.textTheme.titleMedium?.copyWith(color: Colors.green.shade700)),
                  const Divider(),
                  Text(r.footer, textAlign: TextAlign.center, style: t.textTheme.labelSmall),
                ]),
              ),
            ),
          ),
          actions: [
            OutlinedButton.icon(onPressed: () => _print(context), icon: const Icon(Icons.print), label: const Text('Imprimir (F9)')),
            FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Nova venda (Enter)')),
          ],
        ),
      ),
    );
  }

  Widget _l(String a, String b, TextStyle? s) =>
      Row(children: [Expanded(child: Text(a, style: s)), Text(b, style: s)]);
}
