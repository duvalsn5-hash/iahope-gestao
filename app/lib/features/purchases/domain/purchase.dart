import '../../../core/utils/formatters.dart';

double _d(Object? v) => (v as num? ?? 0).toDouble();

class NfeSupplier {
  const NfeSupplier(this.json);
  final Map<String, dynamic> json;
  String get doc => (json['doc'] ?? '') as String;
  String get name => (json['name'] ?? '') as String;
  String? get city => json['city'] as String?;
  String? get state => json['state'] as String?;
}

class NfeMatch {
  const NfeMatch({required this.productId, required this.name, required this.sku, required this.unit, required this.price, this.by});
  final String productId;
  final String name;
  final String sku;
  final String unit;
  final double price;

  /// FORNECEDOR (código já aprendido) | CODIGO_BARRAS | MANUAL
  final String? by;

  factory NfeMatch.fromJson(Map<String, dynamic> j) => NfeMatch(
        productId: j['productId'] as String,
        name: j['name'] as String,
        sku: j['sku'] as String,
        unit: (j['unit'] ?? 'UN') as String,
        price: _d(j['price']),
        by: j['by'] as String?,
      );
}

class NfeItem {
  NfeItem({
    required this.line,
    required this.supplierCode,
    this.barcode,
    required this.description,
    required this.unit,
    required this.qty,
    required this.unitPrice,
    required this.total,
    required this.factor,
    this.match,
  });

  final int line;
  final String supplierCode;
  final String? barcode;
  final String description;
  final String unit;
  final double qty;
  final double unitPrice;
  final double total;

  // ---- editáveis na conferência
  double factor;
  NfeMatch? match;
  bool createNew = false;
  String newSku = '';
  String newName = '';
  String newUnit = 'UN';
  double newPrice = 0;

  /// Custo por unidade de estoque (após o fator de conversão).
  double get unitCost => qty * factor > 0 ? total / (qty * factor) : 0;
  double get stockQty => qty * factor;
  bool get resolved => match != null || (createNew && newSku.isNotEmpty && newName.isNotEmpty && newPrice > 0);

  factory NfeItem.fromJson(Map<String, dynamic> j) {
    final it = NfeItem(
      line: (j['line'] as num).toInt(),
      supplierCode: (j['supplierCode'] ?? '') as String,
      barcode: j['barcode'] as String?,
      description: j['description'] as String,
      unit: (j['unit'] ?? 'UN') as String,
      qty: _d(j['qty']),
      unitPrice: _d(j['unitPrice']),
      total: _d(j['total']),
      factor: _d(j['factor'] ?? 1),
      match: j['match'] == null ? null : NfeMatch.fromJson(j['match'] as Map<String, dynamic>),
    );
    it.newSku = it.supplierCode;
    it.newName = it.description;
    it.newUnit = it.unit;
    return it;
  }

  Map<String, dynamic> toRegisterJson() => {
        'supplierCode': supplierCode,
        'description': description,
        'qty': qty,
        'unitPrice': unitPrice,
        'total': total,
        'factor': factor,
        if (!createNew && match != null) 'productId': match!.productId,
        if (createNew)
          'newProduct': {'sku': newSku, 'barcode': barcode, 'name': newName, 'unit': newUnit, 'price': newPrice},
      };
}

class NfeInstallment {
  const NfeInstallment({required this.document, required this.dueDate, required this.amount});
  final String document;
  final String dueDate; // YYYY-MM-DD
  final double amount;

  factory NfeInstallment.fromJson(Map<String, dynamic> j) =>
      NfeInstallment(document: j['document'] as String, dueDate: j['dueDate'] as String, amount: _d(j['amount']));

  Map<String, dynamic> toJson() => {'document': document, 'dueDate': dueDate, 'amount': amount};
}

class NfePreview {
  NfePreview({
    required this.raw,
    required this.accessKey,
    required this.number,
    required this.series,
    required this.issueDate,
    required this.supplier,
    required this.total,
    required this.items,
    required this.installments,
    required this.alreadyImported,
    required this.warnings,
  });

  final Map<String, dynamic> raw;
  final String? accessKey;
  final String number;
  final String series;
  final String issueDate;
  final NfeSupplier supplier;
  final double total;
  final List<NfeItem> items;
  List<NfeInstallment> installments;
  final bool alreadyImported;
  final List<String> warnings;

  factory NfePreview.fromJson(Map<String, dynamic> j) => NfePreview(
        raw: j,
        accessKey: j['accessKey'] as String?,
        number: (j['number'] ?? '') as String,
        series: (j['series'] ?? '') as String,
        issueDate: (j['issueDate'] ?? '') as String,
        supplier: NfeSupplier(j['supplier'] as Map<String, dynamic>),
        total: _d(j['total']),
        items: [for (final i in j['items'] as List) NfeItem.fromJson(i as Map<String, dynamic>)],
        installments: [for (final i in (j['installments'] as List? ?? const [])) NfeInstallment.fromJson(i as Map<String, dynamic>)],
        alreadyImported: j['alreadyImported'] as bool? ?? false,
        warnings: [for (final w in (j['warnings'] as List? ?? const [])) w.toString()],
      );

  Map<String, dynamic> toRegisterJson() => {
        'accessKey': accessKey,
        'number': number,
        'series': series,
        'issueDate': issueDate.isEmpty ? isoDate(DateTime.now()) : issueDate,
        'total': total,
        'supplier': supplier.json,
        'items': [for (final i in items) i.toRegisterJson()],
        'installments': [for (final i in installments) i.toJson()],
      };
}

class PurchaseRow {
  const PurchaseRow({
    required this.id,
    required this.number,
    this.series,
    this.accessKey,
    this.issueDate,
    required this.total,
    required this.itemsCount,
    this.supplierName,
    required this.createdAt,
    this.user,
  });

  final String id;
  final String number;
  final String? series;
  final String? accessKey;
  final DateTime? issueDate;
  final double total;
  final int itemsCount;
  final String? supplierName;
  final DateTime createdAt;
  final String? user;

  factory PurchaseRow.fromJson(Map<String, dynamic> j) => PurchaseRow(
        id: j['id'] as String,
        number: (j['number'] ?? '') as String,
        series: j['series'] as String?,
        accessKey: j['accessKey'] as String?,
        issueDate: parseIsoDate(j['issueDate'] as String?),
        total: _d(j['total']),
        itemsCount: (j['itemsCount'] as num? ?? 0).toInt(),
        supplierName: j['supplierName'] as String?,
        createdAt: DateTime.parse(j['createdAt'] as String),
        user: j['user'] as String?,
      );
}
