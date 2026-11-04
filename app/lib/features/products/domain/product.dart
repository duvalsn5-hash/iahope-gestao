class Product {
  const Product({
    required this.id,
    required this.sku,
    this.barcode,
    required this.name,
    required this.unit,
    required this.price,
    required this.stockQty,
    this.minStock = 0,
  });

  final String id;
  final String sku;
  final String? barcode;
  final String name;
  final String unit;
  final double price;
  final double stockQty;
  final double minStock;

  bool get lowStock => stockQty <= minStock;

  factory Product.fromJson(Map<String, dynamic> j) => Product(
        id: j['id'] as String,
        sku: j['sku'] as String,
        barcode: j['barcode'] as String?,
        name: j['name'] as String,
        unit: (j['unit'] ?? 'UN') as String,
        price: (j['price'] as num).toDouble(),
        stockQty: (j['stockQty'] as num).toDouble(),
        minStock: (j['minStock'] as num? ?? 0).toDouble(),
      );
}
