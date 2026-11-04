import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/cash.dart';

final cashRepositoryProvider = Provider((ref) => CashRepository(ref.watch(dioProvider)));

class CashRepository {
  CashRepository(this._dio);
  final Dio _dio;

  Future<CashState> current() => apiCall(() async {
        final r = await _dio.get('/cash/current');
        return CashState.fromJson(r.data as Map<String, dynamic>);
      });

  Future<void> open(double openingAmount) =>
      apiCall(() => _dio.post('/cash/open', data: {'openingAmount': openingAmount}));

  /// kind: SANGRIA | SUPRIMENTO
  Future<void> movement(String kind, double amount, String? reason) =>
      apiCall(() => _dio.post('/cash/movements', data: {'kind': kind, 'amount': amount, if (reason != null) 'reason': reason}));

  Future<CashSummary> close(double counted, String? notes) => apiCall(() async {
        final r = await _dio.post('/cash/close', data: {'countedAmount': counted, if (notes != null) 'notes': notes});
        return CashSummary.fromJson(r.data as Map<String, dynamic>);
      });

  Future<List<CashSessionRow>> sessions({String? from, String? to}) => apiCall(() async {
        final r = await _dio.get('/cash/sessions', queryParameters: {if (from != null) 'from': from, if (to != null) 'to': to});
        return (r.data as List).map((e) => CashSessionRow.fromJson(e as Map<String, dynamic>)).toList();
      });
}
