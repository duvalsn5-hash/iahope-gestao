import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../domain/product.dart';

final productsRepositoryProvider = Provider((ref) => ProductsRepository(ref.watch(dioProvider)));

class ProductsRepository {
  ProductsRepository(this._dio);
  final Dio _dio;

  Future<List<Product>> search(String q, {bool all = false, bool lowOnly = false}) => apiCall(() async {
        final r = await _dio.get('/products', queryParameters: {
          'q': q,
          if (all) 'all': '1',
          if (lowOnly) 'low': '1',
        });
        return (r.data as List).map((e) => Product.fromJson(e as Map<String, dynamic>)).toList();
      });

  /// Busca exata por EAN, SKU ou etiqueta de balança. Retorna null se não existir.
  Future<ScanHit?> byCode(String code) async {
    try {
      return await apiCall(() async {
        final r = await _dio.get('/products/barcode/${Uri.encodeComponent(code)}');
        final j = r.data as Map<String, dynamic>;
        return ScanHit(Product.fromJson(j), scaleQty: (j['scaleQty'] as num?)?.toDouble());
      });
    } on ApiException catch (e) {
      if (e.status == 404) return null;
      rethrow;
    }
  }

  Future<Product> create(ProductInput p) => apiCall(() async {
        final r = await _dio.post('/products', data: p.toJson());
        return Product.fromJson(r.data as Map<String, dynamic>);
      });

  Future<Product> update(String id, ProductInput p) => apiCall(() async {
        final r = await _dio.put('/products/$id', data: p.toJson(includeStock: false));
        return Product.fromJson(r.data as Map<String, dynamic>);
      });

  /// qty positivo = entrada; negativo = baixa. reason: ENTRADA | AJUSTE
  Future<Product> adjustStock(String id, double qty, String reason) => apiCall(() async {
        final r = await _dio.post('/products/$id/stock', data: {'qty': qty, 'reason': reason});
        return Product.fromJson(r.data as Map<String, dynamic>);
      });

  Future<List<StockMovement>> movements(String id) => apiCall(() async {
        final r = await _dio.get('/products/$id/movements');
        return (r.data as List).map((e) => StockMovement.fromJson(e as Map<String, dynamic>)).toList();
      });
}
