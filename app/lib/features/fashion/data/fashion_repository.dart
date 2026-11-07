import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/utils/formatters.dart';
import '../../partners/domain/partner.dart';
import '../../products/domain/product.dart';
import '../domain/fashion.dart';

final fashionRepositoryProvider = Provider((ref) => FashionRepository(ref.watch(dioProvider)));

class FashionRepository {
  FashionRepository(this._dio);
  final Dio _dio;

  // ---- grade
  Future<List<GradeModel>> grades({String q = ''}) => apiCall(() async {
        final r = await _dio.get('/fashion/grades', queryParameters: {'q': q});
        return (r.data as List).map((e) => GradeModel.fromJson(e as Map<String, dynamic>)).toList();
      });

  /// Cria o modelo (ou acrescenta combinações) → produtos criados.
  Future<List<Product>> saveGrade(NewGrade g) => apiCall(() async {
        final r = await _dio.post('/fashion/grade', data: g.toJson());
        return [for (final v in r.data['variants'] as List) Product.fromJson(v as Map<String, dynamic>)];
      });

  Future<void> updateGrade(String gradeId, {required String model, String? category, required double price, double cost = 0}) =>
      apiCall(() => _dio.put('/fashion/grade/$gradeId', data: {'model': model, 'category': category, 'price': price, 'cost': cost}));

  Future<List<Product>> fillBarcodes(List<String> productIds) => apiCall(() async {
        final r = await _dio.post('/fashion/barcodes', data: {'productIds': productIds});
        return [for (final v in r.data as List) Product.fromJson(v as Map<String, dynamic>)];
      });

  // ---- trocas
  Future<SaleForReturn> saleByNumber(int number) => apiCall(() async {
        final r = await _dio.get('/fashion/sales/$number');
        return SaleForReturn.fromJson(r.data as Map<String, dynamic>);
      });

  Future<ReturnResult> returnItems({
    required String saleId,
    required Map<int, double> items,
    required String mode,
    String? customerId,
    String? reason,
    int validDays = 90,
  }) =>
      apiCall(() async {
        final r = await _dio.post('/fashion/returns', data: {
          'saleId': saleId,
          'items': [for (final e in items.entries) if (e.value > 0) {'saleItemId': e.key, 'qty': e.value}],
          'mode': mode,
          if (customerId != null) 'customerId': customerId,
          if (reason != null && reason.isNotEmpty) 'reason': reason,
          'validDays': validDays,
        });
        return ReturnResult.fromJson(r.data as Map<String, dynamic>);
      });

  Future<List<Voucher>> vouchers({String q = '', bool openOnly = false}) => apiCall(() async {
        final r = await _dio.get('/fashion/vouchers', queryParameters: {'q': q, if (openOnly) 'open': '1'});
        return (r.data as List).map((e) => Voucher.fromJson(e as Map<String, dynamic>)).toList();
      });

  // ---- condicional
  Future<List<Consignment>> consignments({String status = 'ABERTA'}) => apiCall(() async {
        final r = await _dio.get('/fashion/consignments', queryParameters: {'status': status});
        return (r.data as List).map((e) => Consignment.fromJson(e as Map<String, dynamic>)).toList();
      });

  Future<Consignment> consignment(String id) => apiCall(() async {
        final r = await _dio.get('/fashion/consignments/$id');
        return Consignment.fromJson(r.data as Map<String, dynamic>);
      });

  Future<Consignment> openConsignment({
    required String customerId,
    required List<(Product, double)> items,
    DateTime? dueDate,
    String? notes,
  }) =>
      apiCall(() async {
        final r = await _dio.post('/fashion/consignments', data: {
          'customerId': customerId,
          'items': [for (final (p, q) in items) {'productId': p.id, 'qty': q}],
          if (dueDate != null) 'dueDate': isoDate(dueDate),
          if (notes != null && notes.isNotEmpty) 'notes': notes,
        });
        return Consignment.fromJson(r.data as Map<String, dynamic>);
      });

  /// Acerto: devolve o que voltou; resposta traz o cliente e o que ele ficou (para o PDV).
  Future<({Partner? customer, List<(Product, double)> kept})> closeConsignment(String id, Map<int, double> returned) =>
      apiCall(() async {
        final r = await _dio.post('/fashion/consignments/$id/close', data: {
          'returns': [for (final e in returned.entries) {'itemId': e.key, 'returned': e.value}],
        });
        final c = r.data['customer'];
        return (
          customer: c == null ? null : Partner.fromJson(c as Map<String, dynamic>),
          kept: [
            for (final k in r.data['kept'] as List)
              (Product.fromJson(k['product'] as Map<String, dynamic>), (k['qty'] as num).toDouble()),
          ],
        );
      });

  Future<void> cancelConsignment(String id) => apiCall(() => _dio.post('/fashion/consignments/$id/cancel'));
}
