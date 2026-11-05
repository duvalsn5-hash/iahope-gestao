import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/config/app_config.dart';
import '../../../core/utils/formatters.dart';
import '../domain/workshop.dart';

/// Ordem de serviço em A4: dados da moto, checklist de entrada, peças, mão de obra,
/// garantia e linhas de assinatura (entrada e retirada).
class OsPrinter {
  static Future<void> print(WorkOrder o, {required String company, String? companyDoc, String? logoUrl}) async {
    pw.ImageProvider? logo;
    if (logoUrl != null) {
      try {
        logo = await networkImage(logoUrl);
      } catch (_) {}
    }
    const s = pw.TextStyle(fontSize: 9);
    const b = pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold);
    const h = pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold);

    pw.Widget kv(String k, String v) => pw.RichText(text: pw.TextSpan(children: [
          pw.TextSpan(text: '$k: ', style: b),
          pw.TextSpan(text: v, style: s),
        ]));

    pw.Widget table(String title, List<OsItem> items) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
          pw.SizedBox(height: 8),
          pw.Text(title, style: h),
          pw.SizedBox(height: 4),
          pw.TableHelper.fromTextArray(
            headers: ['Descrição', 'Qtd', 'Unitário', 'Total'],
            data: [for (final i in items) [i.description, number(i.qty), money(i.unitPrice), money(i.total)]],
            headerStyle: b,
            cellStyle: s,
            columnWidths: {0: const pw.FlexColumnWidth(5), 1: const pw.FlexColumnWidth(1), 2: const pw.FlexColumnWidth(1.6), 3: const pw.FlexColumnWidth(1.6)},
            cellAlignments: {1: pw.Alignment.centerRight, 2: pw.Alignment.centerRight, 3: pw.Alignment.centerRight},
          ),
        ]);

    final parts = o.items.where((i) => i.isPart).toList();
    final labor = o.items.where((i) => !i.isPart).toList();
    final doc = pw.Document(title: 'OS ${o.number}', author: AppConfig.credits);

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      footer: (_) => pw.Center(child: pw.Text(AppConfig.credits, style: const pw.TextStyle(fontSize: 7))),
      build: (_) => [
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          if (logo != null) pw.Padding(padding: const pw.EdgeInsets.only(right: 12), child: pw.Image(logo, height: 48)),
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(company, style: const pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
              if (companyDoc != null) pw.Text('CNPJ ${formatCnpj(companyDoc)}', style: s),
            ]),
          ),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Text('ORDEM DE SERVIÇO', style: h),
            pw.Text('Nº ${o.number.toString().padLeft(5, '0')}', style: const pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.Text('Entrada ${dateTimeBr(o.openedAt)}', style: s),
            pw.Text(o.status.label, style: s),
          ]),
        ]),
        pw.Divider(),
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('Cliente', style: h),
              kv('Nome', o.customerName),
              if (o.customerDoc != null) kv('CPF/CNPJ', formatDoc(o.customerDoc)),
              if (o.customerPhone != null) kv('Telefone', o.customerPhone!),
            ]),
          ),
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('Moto', style: h),
              kv('Placa', o.vehicle.plateFmt),
              kv('Modelo', o.vehicle.label),
              if (o.vehicle.color != null) kv('Cor', o.vehicle.color!),
              kv('Km na entrada', o.kmIn == null ? '-' : number(o.kmIn!)),
              kv('Combustível', o.fuelLevel ?? '-'),
            ]),
          ),
        ]),
        pw.SizedBox(height: 8),
        pw.Text('Checklist de entrada', style: h),
        pw.Wrap(spacing: 10, runSpacing: 2, children: [
          for (final e in o.checklist.entries)
            pw.Text('${e.value == true ? '[x]' : e.value == false ? '[ ]' : '•'} ${e.key}${e.value is String ? ': ${e.value}' : ''}', style: s),
        ]),
        if ((o.complaint ?? '').isNotEmpty) ...[pw.SizedBox(height: 8), pw.Text('Relato do cliente', style: h), pw.Text(o.complaint!, style: s)],
        if ((o.diagnosis ?? '').isNotEmpty) ...[pw.SizedBox(height: 8), pw.Text('Diagnóstico', style: h), pw.Text(o.diagnosis!, style: s)],
        if (parts.isNotEmpty) table('Peças', parts),
        if (labor.isNotEmpty) table('Mão de obra', labor),
        pw.SizedBox(height: 8),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            kv('Peças', money(o.partsTotal)),
            kv('Mão de obra', money(o.laborTotal)),
            if (o.discount > 0) kv('Desconto', '- ${money(o.discount)}'),
            pw.Text('TOTAL ${money(o.total)}', style: const pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          ]),
        ),
        pw.SizedBox(height: 8),
        if (o.mechanicName != null) kv('Mecânico responsável', o.mechanicName!),
        kv('Garantia dos serviços', '${o.warrantyDays} dias a partir da entrega'),
        if (o.nextServiceDate != null || o.nextServiceKm != null)
          kv('Próxima revisão', [if (o.nextServiceDate != null) dateBr(o.nextServiceDate), if (o.nextServiceKm != null) '${number(o.nextServiceKm!)} km'].join(' ou ')),
        pw.SizedBox(height: 36),
        pw.Row(children: [
          pw.Expanded(child: pw.Column(children: [pw.Divider(), pw.Text('Cliente — autorizo o serviço (entrada)', style: s)])),
          pw.SizedBox(width: 24),
          pw.Expanded(child: pw.Column(children: [pw.Divider(), pw.Text('Cliente — recebi a moto (retirada)', style: s)])),
        ]),
      ],
    ));
    await Printing.layoutPdf(name: 'OS-${o.number}', onLayout: (_) async => doc.save());
  }
}
