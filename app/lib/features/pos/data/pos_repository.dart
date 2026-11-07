import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/pos_models.dart';

final posRepositoryProvider = Provider((ref) => PosRepository(ref.watch(dioProvider)));

class PosRepository {
  PosRepository(this._dio);
  final Dio _dio;

  /// Fecha a venda: o servidor valida estoque, grava e dá baixa numa transação.
  Future<Receipt> closeSale({
    required List<CartItem> items,
    required List<Payment> payments,
    double discount = 0,
    String? customerDoc,
    String? customerId,
    int dueDays = 30,
  }) =>
      apiCall(() async {
        final r = await _dio.post('/pos/sales', data: {
          'items': [for (final i in items) {'productId': i.product.id, 'qty': i.qty}],
          'payments': [for (final p in payments) p.toJson()],
          'discount': discount,
          if (customerDoc != null && customerDoc.isNotEmpty) 'customerDoc': customerDoc,
          if (customerId != null) 'customerId': customerId,
          'dueDays': dueDays,
        });
        return Receipt.fromJson(r.data as Map<String, dynamic>);
      });

  Future<({int sales, double total, int nextNumber})> todaySummary() => apiCall(() async {
        final r = await _dio.get('/pos/summary');
        return (
          sales: (r.data['sales'] as num).toInt(),
          total: (r.data['total'] as num).toDouble(),
          nextNumber: (r.data['nextNumber'] as num? ?? 0).toInt(),
        );
      });

  /// Confere o vale-troca (código e saldo). Vencido = sem saldo.
  Future<VoucherInfo?> voucher(String code) => apiCall(() async {
        final r = await _dio.get('/pos/vouchers/${Uri.encodeComponent(code.trim())}');
        final expired = r.data['expired'] == true;
        return (code: r.data['code'] as String, balance: expired ? 0.0 : (r.data['balance'] as num).toDouble());
      });
}
