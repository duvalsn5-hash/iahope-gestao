class Product {
  const Product({
    required this.id,
    required this.sku,
    this.barcode,
    required this.name,
    required this.unit,
    required this.price,
    this.cost = 0,
    required this.stockQty,
    this.minStock = 0,
    this.scaleCode,
    this.isActive = true,
    this.imageUrl,
    this.category,
    this.gradeId,
    this.size,
    this.color,
  });

  final String id;
  final String sku;
  final String? barcode;
  final String name;
  final String unit;
  final double price;
  final double cost;
  final double stockQty;
  final double minStock;

  /// Código do produto na etiqueta da balança (módulo BALANCA).
  final int? scaleCode;
  final bool isActive;

  /// Foto do produto (URL pública, muda a cada troca).
  final String? imageUrl;

  /// Categoria do produto (Bebidas, Camisetas, Freios…).
  final String? category;

  /// Grade (loja de roupas): modelo, tamanho e cor desta combinação.
  final String? gradeId, size, color;

  bool get lowStock => stockQty <= minStock;

  /// Margem sobre o preço de venda (%), quando há custo.
  double? get marginPct => price > 0 && cost > 0 ? (price - cost) / price * 100 : null;

  factory Product.fromJson(Map<String, dynamic> j) => Product(
        id: j['id'] as String,
        sku: j['sku'] as String,
        barcode: j['barcode'] as String?,
        name: j['name'] as String,
        unit: (j['unit'] ?? 'UN') as String,
        price: (j['price'] as num).toDouble(),
        cost: (j['cost'] as num? ?? 0).toDouble(),
        stockQty: (j['stockQty'] as num).toDouble(),
        minStock: (j['minStock'] as num? ?? 0).toDouble(),
        scaleCode: (j['scaleCode'] as num?)?.toInt(),
        isActive: j['isActive'] as bool? ?? true,
        imageUrl: j['imageUrl'] as String?,
        category: j['category'] as String?,
        gradeId: j['gradeId'] as String?,
        size: j['size'] as String?,
        color: j['color'] as String?,
      );
}

/// Dados do formulário de cadastro/edição.
class ProductInput {
  const ProductInput({
    required this.sku,
    this.barcode,
    required this.name,
    required this.unit,
    required this.price,
    this.cost = 0,
    this.stockQty = 0,
    this.minStock = 0,
    this.scaleCode,
    this.isActive = true,
    this.category,
  });

  final String sku;
  final String? barcode;
  final String name;
  final String unit;
  final double price;
  final double cost;
  final double stockQty;
  final double minStock;
  final int? scaleCode;
  final bool isActive;
  final String? category;

  Map<String, dynamic> toJson({bool includeStock = true}) => {
        'sku': sku,
        'barcode': (barcode?.isEmpty ?? true) ? null : barcode,
        'name': name,
        'unit': unit,
        'price': price,
        'cost': cost,
        if (includeStock) 'stockQty': stockQty,
        'minStock': minStock,
        'scaleCode': scaleCode,
        'isActive': isActive,
        'category': (category?.trim().isEmpty ?? true) ? null : category!.trim(),
      };
}

/// Resultado da leitura de um código no PDV: o produto e, se veio de
/// etiqueta de balança, a quantidade já pesada.
class ScanHit {
  const ScanHit(this.product, {this.scaleQty});
  final Product product;
  final double? scaleQty;
}

class StockMovement {
  const StockMovement({required this.qty, required this.reason, required this.createdAt, this.user});
  final double qty;
  final String reason;
  final DateTime createdAt;
  final String? user;

  factory StockMovement.fromJson(Map<String, dynamic> j) => StockMovement(
        qty: (j['qty'] as num).toDouble(),
        reason: j['reason'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
        user: j['user'] as String?,
      );
}
