import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../domain/product.dart';

final productsRepositoryProvider = Provider((ref) => ProductsRepository(ref.watch(dioProvider)));

class ProductsRepository {
  ProductsRepository(this._dio);
  final Dio _dio;

  Future<List<Product>> search(String q, {bool all = false, bool lowOnly = false, String? category}) => apiCall(() async {
        final r = await _dio.get('/products', queryParameters: {
          'q': q,
          if (category != null && category.isNotEmpty) 'category': category,
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

  /// Envia a foto já reduzida (JPEG). Retorna a URL pública.
  Future<String> uploadImage(String id, Uint8List jpeg) => apiCall(() async {
        final form = FormData.fromMap({
          'image': MultipartFile.fromBytes(jpeg, filename: 'produto.jpg', contentType: DioMediaType('image', 'jpeg')),
        });
        final r = await _dio.post('/products/$id/image', data: form);
        return r.data['imageUrl'] as String;
      });

  Future<void> removeImage(String id) => apiCall(() => _dio.delete('/products/$id/image'));

  /// qty positivo = entrada; negativo = baixa. reason: ENTRADA | AJUSTE
  Future<Product> adjustStock(String id, double qty, String reason) => apiCall(() async {
        final r = await _dio.post('/products/$id/stock', data: {'qty': qty, 'reason': reason});
        return Product.fromJson(r.data as Map<String, dynamic>);
      });

  Future<List<StockMovement>> movements(String id) => apiCall(() async {
        final r = await _dio.get('/products/$id/movements');
        return (r.data as List).map((e) => StockMovement.fromJson(e as Map<String, dynamic>)).toList();
      });

  /// Categorias já usadas pela empresa: (nome, quantidade de produtos).
  Future<List<(String, int)>> categories() => apiCall(() async {
        final r = await _dio.get('/products/categories');
        return [for (final e in r.data as List) ((e['name'] as String), (e['count'] as num).toInt())];
      });
}
