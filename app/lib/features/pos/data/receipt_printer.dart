import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/utils/formatters.dart';
import '../domain/pos_models.dart';

/// Cupom não fiscal 80mm com a logo da empresa.
/// Printing abre o diálogo nativo: impressora térmica no Windows,
/// compartilhar/imprimir no Android e a impressão do navegador na Web.
class ReceiptPrinter {
  static Future<void> printReceipt(Receipt r) async {
    pw.ImageProvider? logo;
    if (r.logoUrl != null) {
      try {
        logo = await networkImage(r.logoUrl!);
      } catch (_) {
        logo = null; // imprime sem logo se a imagem falhar
      }
    }

    final doc = pw.Document(title: 'Cupom ${r.number}', author: r.footer);
    const small = pw.TextStyle(fontSize: 8);
    const bold = pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold);

    pw.Widget line(String l, String rgt, {pw.TextStyle? style}) => pw.Row(children: [
          pw.Expanded(child: pw.Text(l, style: style ?? small)),
          pw.Text(rgt, style: style ?? small),
        ]);

    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.roll80.copyWith(marginLeft: 4 * PdfPageFormat.mm, marginRight: 4 * PdfPageFormat.mm),
      build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        if (logo != null) pw.Center(child: pw.Image(logo, height: 48)),
        pw.SizedBox(height: 4),
        pw.Text(r.companyName, textAlign: pw.TextAlign.center, style: bold),
        pw.Text(r.razaoSocial, textAlign: pw.TextAlign.center, style: small),
        pw.Text('CNPJ ${formatCnpj(r.cnpj)}', textAlign: pw.TextAlign.center, style: small),
        pw.Divider(thickness: .5),
        pw.Text('CUPOM NÃO FISCAL Nº ${r.number.toString().padLeft(6, '0')}', textAlign: pw.TextAlign.center, style: bold),
        pw.Text(dateTimeBr(r.createdAt), textAlign: pw.TextAlign.center, style: small),
        pw.Divider(thickness: .5),
        for (final i in r.items) ...[
          pw.Text(i.description, style: small),
          line('  ${_qty(i.qty)} x ${money(i.unitPrice)}', money(i.total)),
        ],
        pw.Divider(thickness: .5),
        line('Subtotal', money(r.subtotal)),
        if (r.discount > 0) line('Desconto', '- ${money(r.discount)}'),
        line('TOTAL', money(r.total), style: const pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        for (final p in r.payments) line(paymentLabel(p.$1), money(p.$2)),
        if (r.change > 0) line('Troco', money(r.change), style: bold),
        pw.Divider(thickness: .5),
        if (r.cashier != null) pw.Text('Operador: ${r.cashier}', style: small),
        pw.SizedBox(height: 6),
        pw.Text(r.footer, textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 6)),
      ]),
    ));

    await Printing.layoutPdf(name: 'cupom-${r.number}', onLayout: (_) async => doc.save());
  }

  static String _qty(double q) => q == q.roundToDouble() ? q.toInt().toString() : q.toStringAsFixed(3);
}
