import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/config/app_config.dart';
import '../../../core/utils/formatters.dart';
import '../../products/domain/product.dart';
import '../domain/fashion.dart';

/// Formatos de etiqueta.
enum LabelLayout {
  a4('Folha A4 — 3 × 8 (63 × 34 mm)'),
  roll('Rolo térmico 40 × 25 mm'),
  roll50('Rolo térmico 50 × 30 mm');

  const LabelLayout(this.label);
  final String label;
}

bool _validEan13(String s) {
  if (!RegExp(r'^\d{13}$').hasMatch(s)) return false;
  var sum = 0;
  for (var i = 0; i < 12; i++) {
    final d = int.parse(s[i]);
    sum += i.isOdd ? d * 3 : d;
  }
  return (10 - sum % 10) % 10 == int.parse(s[12]);
}

/// Etiquetas com nome, tamanho/cor, preço e código de barras.
class LabelPrinter {
  static Future<void> print(List<(Product, int)> labels, {required String company, LabelLayout layout = LabelLayout.a4}) async {
    final all = <Product>[for (final (p, n) in labels) for (var i = 0; i < n; i++) p];
    if (all.isEmpty) return;
    final doc = pw.Document(title: 'Etiquetas', author: AppConfig.credits);

    pw.Widget label(Product p, {required double scale}) {
      final code = (p.barcode?.isNotEmpty ?? false) ? p.barcode! : p.sku;
      final ean = _validEan13(code);
      final variant = [if (p.size != null) 'Tam ${p.size}', if (p.color != null) p.color!].join(' · ');
      return pw.Container(
        padding: pw.EdgeInsets.all(3 * scale),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
          pw.Text(company.toUpperCase(), maxLines: 1, style: pw.TextStyle(fontSize: 5 * scale, color: PdfColors.grey700)),
          pw.Text(p.name, maxLines: 2, style: pw.TextStyle(fontSize: 7 * scale, fontWeight: pw.FontWeight.bold)),
          pw.Row(children: [
            pw.Expanded(child: pw.Text(variant, maxLines: 1, style: pw.TextStyle(fontSize: 6.5 * scale))),
            pw.Text(money(p.price), style: pw.TextStyle(fontSize: 10 * scale, fontWeight: pw.FontWeight.bold)),
          ]),
          pw.SizedBox(height: 1.5 * scale),
          pw.Expanded(
            child: pw.BarcodeWidget(
              barcode: ean ? pw.Barcode.ean13() : pw.Barcode.code128(),
              data: code,
              drawText: true,
              textStyle: pw.TextStyle(fontSize: 5.5 * scale),
            ),
          ),
        ]),
      );
    }

    switch (layout) {
      case LabelLayout.a4:
        const cols = 3, rows = 8;
        final w = 63.5 * PdfPageFormat.mm, h = 33.9 * PdfPageFormat.mm;
        for (var start = 0; start < all.length; start += cols * rows) {
          final page = all.sublist(start, (start + cols * rows).clamp(0, all.length));
          doc.addPage(pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.symmetric(horizontal: 7 * PdfPageFormat.mm, vertical: 13 * PdfPageFormat.mm),
            build: (_) => pw.Wrap(children: [
              for (final p in page)
                pw.Container(
                  width: w,
                  height: h,
                  decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey300, width: .3)),
                  child: label(p, scale: 1),
                ),
            ]),
          ));
        }
      case LabelLayout.roll:
      case LabelLayout.roll50:
        final (w, h, scale) = layout == LabelLayout.roll ? (40.0, 25.0, .78) : (50.0, 30.0, 1.0);
        final fmt = PdfPageFormat(w * PdfPageFormat.mm, h * PdfPageFormat.mm);
        for (final p in all) {
          doc.addPage(pw.Page(pageFormat: fmt, margin: pw.EdgeInsets.zero, build: (_) => label(p, scale: scale)));
        }
    }
    await Printing.layoutPdf(onLayout: (_) => doc.save(), name: 'etiquetas.pdf');
  }

  /// Comprovante do vale-troca (bobina 80 mm).
  static Future<void> printVoucher(ReturnResult r, {required String company, String? customer, DateTime? expiresAt}) async {
    final doc = pw.Document(title: 'Vale-troca ${r.code}');
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.roll80,
      margin: const pw.EdgeInsets.all(8),
      build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
        pw.Text(company, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        pw.Text('VALE-TROCA', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Text(money(r.amount), style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        pw.BarcodeWidget(barcode: pw.Barcode.code128(), data: r.code ?? '', width: 160, height: 40),
        pw.SizedBox(height: 6),
        if (customer != null) pw.Text('Cliente: $customer', style: const pw.TextStyle(fontSize: 9)),
        pw.Text('Origem: venda nº ${r.saleNumber}', style: const pw.TextStyle(fontSize: 9)),
        pw.Text('Emitido em ${dateBr(DateTime.now())}', style: const pw.TextStyle(fontSize: 9)),
        if (expiresAt != null) pw.Text('Válido até ${dateBr(expiresAt)}', style: const pw.TextStyle(fontSize: 9)),
        pw.SizedBox(height: 6),
        pw.Text('Apresente este vale no caixa. Use como pagamento em qualquer compra.',
            textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 8)),
        pw.SizedBox(height: 8),
        pw.Text(AppConfig.credits, textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 6)),
      ]),
    ));
    await Printing.layoutPdf(onLayout: (_) => doc.save(), name: 'vale-${r.code}.pdf');
  }
}
