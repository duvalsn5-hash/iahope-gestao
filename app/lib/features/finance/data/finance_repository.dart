import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/finance.dart';

final financeRepositoryProvider = Provider((ref) => FinanceRepository(ref.watch(dioProvider)));

class FinanceRepository {
  FinanceRepository(this._dio);
  final Dio _dio;

  /// status: ABERTOS | VENCIDOS | PAGOS | TODOS
  Future<List<FinEntry>> entries({required String kind, String status = 'ABERTOS', String q = ''}) => apiCall(() async {
        final r = await _dio.get('/finance/entries', queryParameters: {'kind': kind, 'status': status, 'q': q});
        return (r.data as List).map((e) => FinEntry.fromJson(e as Map<String, dynamic>)).toList();
      });

  Future<FinSummary> summary() => apiCall(() async {
        final r = await _dio.get('/finance/summary');
        return FinSummary.fromJson(r.data as Map<String, dynamic>);
      });

  Future<void> create(NewFinEntry e) => apiCall(() => _dio.post('/finance/entries', data: e.toJson()));

  Future<void> settle(String id, {required double amount, required String method, bool fromCash = false}) =>
      apiCall(() => _dio.post('/finance/entries/$id/settle', data: {'amount': amount, 'method': method, 'fromCash': fromCash}));

  Future<void> cancel(String id) => apiCall(() => _dio.post('/finance/entries/$id/cancel'));
}
