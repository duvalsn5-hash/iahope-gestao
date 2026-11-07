import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/config/app_config.dart';
import '../../../core/utils/formatters.dart';
import '../domain/printshop.dart';

/// Pedido em A4: serve de orçamento para o cliente e de ordem de produção
/// (grade de tamanhos, técnica, observações da arte e a própria arte).
class OrderPrinter {
  static Future<void> print(CustomOrder o, {required String company, String? logoUrl, bool production = false}) async {
    Future<pw.ImageProvider?> img(String? url) async {
      if (url == null) return null;
      try {
        return await networkImage(url);
      } catch (_) {
        return null;
      }
    }

    final logo = await img(logoUrl);
    final arts = <pw.ImageProvider>[];
    for (final a in o.arts.take(2)) {
      final i = await img(a.url);
      if (i != null) arts.add(i);
    }
    const s = pw.TextStyle(fontSize: 9);
    const b = pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold);
    const h = pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold);
    final sizes = <String>{for (final i in o.items) ...i.sizes.keys.where((k) => (i.sizes[k] ?? 0) > 0)}.toList();

    final doc = pw.Document(title: 'Pedido ${o.number}', author: AppConfig.credits);
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      footer: (c) => pw.Row(children: [
        pw.Text(AppConfig.credits, style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
        pw.Spacer(),
        pw.Text('${c.pageNumber}/${c.pagesCount}', style: const pw.TextStyle(fontSize: 7)),
      ]),
      build: (_) => [
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          if (logo != null) pw.SizedBox(width: 60, height: 60, child: pw.Image(logo)),
          if (logo != null) pw.SizedBox(width: 10),
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(company, style: const pw.TextStyle(fontSize: 14)),
              pw.Text(production ? 'ORDEM DE PRODUÇÃO' : 'PEDIDO / ORÇAMENTO', style: h),
            ]),
          ),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Text('Nº ${o.number}', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.Text('Emitido ${dateBr(DateTime.now())}', style: s),
            if (o.dueDate != null) pw.Text('Entrega: ${dateBr(o.dueDate)}', style: b),
          ]),
        ]),
        pw.Divider(),
        pw.Text(o.title, style: h),
        pw.SizedBox(height: 4),
        pw.Text('Cliente: ${o.customerName}${o.customerPhone != null ? ' · ${o.customerPhone}' : ''}', style: s),
        pw.Text('Técnica: ${techniqueLabel(o.technique)} · Situação: ${o.status.label}', style: s),
        if (o.artNotes?.isNotEmpty ?? false) ...[
          pw.SizedBox(height: 6),
          pw.Text('Arte (posição, tamanho, cores):', style: b),
          pw.Text(o.artNotes!, style: s),
        ],
        pw.SizedBox(height: 10),
        pw.TableHelper.fromTextArray(
          headerStyle: b,
          cellStyle: s,
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
          cellAlignments: {for (var i = 2; i < 4 + sizes.length + (production ? 0 : 2); i++) i: pw.Alignment.centerRight},
          headers: [
            'Item',
            'Cor',
            ...sizes,
            'Qtd',
            if (!production) 'Unit.',
            if (!production) 'Total',
          ],
          data: [
            for (final i in o.items)
              [
                i.description,
                i.color ?? '',
                for (final z in sizes) (i.sizes[z] ?? 0) > 0 ? number(i.sizes[z]!) : '',
                number(i.effectiveQty),
                if (!production) money(i.unitPrice),
                if (!production) money(i.total),
              ],
          ],
        ),
        pw.SizedBox(height: 8),
        if (!production)
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
              if (o.discount > 0) pw.Text('Desconto: ${money(o.discount)}', style: s),
              pw.Text('Total: ${money(o.total)}', style: h),
              if (o.deposit > 0) pw.Text('Sinal recebido: ${money(o.deposit)}', style: s),
              if (o.deposit > 0) pw.Text('Saldo na entrega: ${money(o.balance)}', style: b),
            ]),
          )
        else
          pw.Text('Total de peças: ${number(o.pieces)}', style: h),
        if (o.notes?.isNotEmpty ?? false) ...[
          pw.SizedBox(height: 8),
          pw.Text('Observações: ${o.notes}', style: s),
        ],
        if (arts.isNotEmpty) ...[
          pw.SizedBox(height: 12),
          pw.Text('Arte', style: b),
          pw.SizedBox(height: 4),
          pw.Row(children: [
            for (final a in arts)
              pw.Padding(
                padding: const pw.EdgeInsets.only(right: 10),
                child: pw.Container(
                  width: 220,
                  height: 220,
                  decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400)),
                  child: pw.Image(a, fit: pw.BoxFit.contain),
                ),
              ),
          ]),
        ],
        pw.SizedBox(height: 30),
        pw.Row(children: [
          pw.Expanded(
            child: pw.Column(children: [
              pw.Container(height: .5, color: PdfColors.black),
              pw.Text(production ? 'Conferido por' : 'Aprovação do cliente', style: s),
            ]),
          ),
          pw.SizedBox(width: 40),
          pw.Expanded(
            child: pw.Column(children: [
              pw.Container(height: .5, color: PdfColors.black),
              pw.Text(production ? 'Data de conclusão' : 'Data', style: s),
            ]),
          ),
        ]),
      ],
    ));
    await Printing.layoutPdf(onLayout: (_) => doc.save(), name: 'pedido-${o.number}.pdf');
  }
}
