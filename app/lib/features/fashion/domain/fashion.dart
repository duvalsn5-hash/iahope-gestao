import '../../products/domain/product.dart';

double _d(Object? v) => (v as num? ?? 0).toDouble();
DateTime? _date(Object? v) => v == null ? null : DateTime.tryParse(v.toString());

/// Grades prontas de tamanhos (um toque no cadastro do modelo).
const kSizePresets = [
  ('Adulto PP–GG', ['PP', 'P', 'M', 'G', 'GG']),
  ('Plus G1–G4', ['G1', 'G2', 'G3', 'G4']),
  ('Jeans 36–48', ['36', '38', '40', '42', '44', '46', '48']),
  ('Infantil 2–16', ['2', '4', '6', '8', '10', '12', '14', '16']),
  ('Calçados 34–44', ['34', '35', '36', '37', '38', '39', '40', '41', '42', '43', '44']),
  ('Tamanho único', ['U']),
];

const kColorSuggestions = [
  'Preta', 'Branca', 'Cinza', 'Azul', 'Azul Marinho', 'Vermelha', 'Rosa', 'Verde', 'Amarela', 'Bege',
  'Marrom', 'Vinho', 'Lilás', 'Laranja', 'Jeans claro', 'Jeans escuro', 'Estampada',
];

/// Modelo com a grade (cada combinação tamanho × cor é um produto).
class GradeModel {
  const GradeModel({
    required this.gradeId,
    required this.model,
    this.category,
    required this.price,
    required this.cost,
    this.imageUrl,
    required this.sizes,
    required this.colors,
    required this.totalStock,
    required this.variants,
  });

  final String gradeId, model;
  final String? category, imageUrl;
  final double price, cost, totalStock;
  final List<String> sizes, colors;
  final List<Product> variants;

  Product? variant(String color, String size) {
    for (final v in variants) {
      if (v.color == color && v.size == size) return v;
    }
    return null;
  }

  factory GradeModel.fromJson(Map<String, dynamic> j) => GradeModel(
        gradeId: j['gradeId'] as String,
        model: (j['model'] ?? '') as String,
        category: j['category'] as String?,
        price: _d(j['price']),
        cost: _d(j['cost']),
        imageUrl: j['imageUrl'] as String?,
        sizes: [for (final s in j['sizes'] as List? ?? const []) s.toString()],
        colors: [for (final c in j['colors'] as List? ?? const []) c.toString()],
        totalStock: _d(j['totalStock']),
        variants: [for (final v in j['variants'] as List? ?? const []) Product.fromJson(v as Map<String, dynamic>)],
      );
}

class NewGrade {
  const NewGrade({
    this.gradeId,
    required this.model,
    this.category,
    required this.price,
    this.cost = 0,
    required this.sizes,
    required this.colors,
    this.stock = const {},
  });
  final String? gradeId;
  final String model;
  final String? category;
  final double price, cost;
  final List<String> sizes, colors;

  /// "Cor|Tamanho" → quantidade inicial
  final Map<String, double> stock;

  Map<String, dynamic> toJson() => {
        if (gradeId != null) 'gradeId': gradeId,
        'model': model,
        'category': (category?.trim().isEmpty ?? true) ? null : category!.trim(),
        'price': price,
        'cost': cost,
        'sizes': sizes,
        'colors': colors,
        'stock': stock,
      };
}

// ------------------------------------------------------------------ trocas
class ReturnableItem {
  const ReturnableItem({
    required this.id,
    this.productId,
    required this.description,
    this.barcode,
    required this.qty,
    required this.returnedQty,
    required this.unitPrice,
    required this.paidUnit,
  });
  final int id;
  final String? productId, barcode;
  final String description;
  final double qty, returnedQty, unitPrice, paidUnit;
  double get available => qty - returnedQty;

  factory ReturnableItem.fromJson(Map<String, dynamic> j) => ReturnableItem(
        id: (j['id'] as num).toInt(),
        productId: j['productId'] as String?,
        description: j['description'] as String,
        barcode: j['barcode'] as String?,
        qty: _d(j['qty']),
        returnedQty: _d(j['returnedQty']),
        unitPrice: _d(j['unitPrice']),
        paidUnit: _d(j['paidUnit']),
      );
}

class SaleForReturn {
  const SaleForReturn({
    required this.id,
    required this.number,
    required this.status,
    required this.createdAt,
    this.customerId,
    this.customerName,
    required this.total,
    required this.discount,
    required this.items,
    required this.returnsCount,
  });
  final String id, status;
  final int number;
  final DateTime createdAt;
  final String? customerId, customerName;
  final double total, discount;
  final List<ReturnableItem> items;
  final int returnsCount;

  factory SaleForReturn.fromJson(Map<String, dynamic> j) => SaleForReturn(
        id: j['id'] as String,
        number: (j['number'] as num).toInt(),
        status: j['status'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
        customerId: j['customerId'] as String?,
        customerName: j['customerName'] as String?,
        total: _d(j['total']),
        discount: _d(j['discount']),
        items: [for (final i in j['items'] as List) ReturnableItem.fromJson(i as Map<String, dynamic>)],
        returnsCount: (j['returns'] as List? ?? const []).length,
      );
}

class ReturnResult {
  const ReturnResult({required this.amount, required this.mode, this.code, required this.saleNumber});
  final double amount;
  final String mode;
  final String? code;
  final int saleNumber;
  bool get isVoucher => mode == 'VALE';

  factory ReturnResult.fromJson(Map<String, dynamic> j) => ReturnResult(
        amount: _d(j['amount']),
        mode: j['mode'] as String,
        code: j['code'] as String?,
        saleNumber: (j['saleNumber'] as num? ?? 0).toInt(),
      );
}

class Voucher {
  const Voucher({
    required this.code,
    required this.amount,
    required this.balance,
    this.expiresAt,
    this.customerName,
    this.originSale,
    required this.createdAt,
  });
  final String code;
  final double amount, balance;
  final DateTime? expiresAt;
  final String? customerName;
  final int? originSale;
  final DateTime createdAt;

  bool get expired {
    if (expiresAt == null) return false;
    final n = DateTime.now();
    return expiresAt!.isBefore(DateTime(n.year, n.month, n.day));
  }

  factory Voucher.fromJson(Map<String, dynamic> j) => Voucher(
        code: j['code'] as String,
        amount: _d(j['amount']),
        balance: _d(j['balance']),
        expiresAt: _date(j['expiresAt']),
        customerName: j['customerName'] as String?,
        originSale: (j['originSale'] as num?)?.toInt(),
        createdAt: DateTime.parse(j['createdAt'] as String),
      );
}

// ------------------------------------------------------------- condicional
class ConsignmentItem {
  const ConsignmentItem({
    required this.id,
    required this.productId,
    required this.description,
    this.imageUrl,
    required this.qty,
    required this.unitPrice,
    this.returnedQty,
    this.keptQty,
  });
  final int id;
  final String productId, description;
  final String? imageUrl;
  final double qty, unitPrice;
  final double? returnedQty, keptQty;

  factory ConsignmentItem.fromJson(Map<String, dynamic> j) => ConsignmentItem(
        id: (j['id'] as num).toInt(),
        productId: j['productId'] as String,
        description: j['description'] as String,
        imageUrl: j['imageUrl'] as String?,
        qty: _d(j['qty']),
        unitPrice: _d(j['unitPrice']),
        returnedQty: (j['returnedQty'] as num?)?.toDouble(),
        keptQty: (j['keptQty'] as num?)?.toDouble(),
      );
}

class Consignment {
  const Consignment({
    required this.id,
    required this.number,
    required this.customerId,
    required this.customerName,
    this.customerPhone,
    required this.status,
    this.dueDate,
    this.notes,
    required this.createdAt,
    this.pieces = 0,
    this.total = 0,
    this.items = const [],
  });
  final String id, customerId, customerName, status;
  final int number;
  final String? customerPhone, notes;
  final DateTime? dueDate;
  final DateTime createdAt;
  final double pieces, total;
  final List<ConsignmentItem> items;

  bool get isOpen => status == 'ABERTA';
  bool get overdue {
    if (!isOpen || dueDate == null) return false;
    final n = DateTime.now();
    return dueDate!.isBefore(DateTime(n.year, n.month, n.day));
  }

  factory Consignment.fromJson(Map<String, dynamic> j) {
    final items = [for (final i in j['items'] as List? ?? const []) ConsignmentItem.fromJson(i as Map<String, dynamic>)];
    return Consignment(
      id: j['id'] as String,
      number: (j['number'] as num).toInt(),
      customerId: j['customerId'] as String,
      customerName: (j['customerName'] ?? '') as String,
      customerPhone: j['customerPhone'] as String?,
      status: j['status'] as String,
      dueDate: _date(j['dueDate']),
      notes: j['notes'] as String?,
      createdAt: DateTime.parse(j['createdAt'] as String),
      pieces: j['pieces'] != null ? _d(j['pieces']) : items.fold<double>(0, (a, i) => a + i.qty),
      total: j['total'] != null ? _d(j['total']) : items.fold<double>(0, (a, i) => a + i.qty * i.unitPrice),
      items: items,
    );
  }
}
