import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../domain/product.dart';

final productsRepositoryProvider = Provider((ref) => ProductsRepository(ref.watch(dioProvider)));

class ProductsRepository {
  ProductsRepository(this._dio);
  final Dio _dio;

  Future<List<Product>> search(String q) => apiCall(() async {
        final r = await _dio.get('/products', queryParameters: {'q': q});
        return (r.data as List).map((e) => Product.fromJson(e as Map<String, dynamic>)).toList();
      });

  /// Busca exata por EAN/código de barras ou SKU. Retorna null se não existir.
  Future<Product?> byCode(String code) async {
    try {
      return await apiCall(() async {
        final r = await _dio.get('/products/barcode/${Uri.encodeComponent(code)}');
        return Product.fromJson(r.data as Map<String, dynamic>);
      });
    } on ApiException catch (e) {
      if (e.status == 404) return null;
      rethrow;
    }
  }
}
