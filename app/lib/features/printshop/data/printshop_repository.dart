import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../pos/domain/pos_models.dart';
import '../domain/printshop.dart';

final printshopRepositoryProvider = Provider((ref) => PrintshopRepository(ref.watch(dioProvider)));

class PrintshopRepository {
  PrintshopRepository(this._dio);
  final Dio _dio;

  /// status: ABERTOS | ENTREGUES | CANCELADOS | TODOS | <status da API>
  Future<List<OrderRow>> orders({String status = 'ABERTOS', String q = ''}) => apiCall(() async {
        final r = await _dio.get('/printshop/orders', queryParameters: {'status': status, 'q': q});
        return (r.data as List).map((e) => OrderRow.fromJson(e as Map<String, dynamic>)).toList();
      });

  Future<PrintshopSummary> summary() => apiCall(() async {
        final r = await _dio.get('/printshop/summary');
        return PrintshopSummary({for (final e in (r.data as Map).entries) e.key.toString(): e.value as num});
      });

  Future<CustomOrder> order(String id) => apiCall(() async {
        final r = await _dio.get('/printshop/orders/$id');
        return CustomOrder.fromJson(r.data as Map<String, dynamic>);
      });

  Future<CustomOrder> create(Map<String, dynamic> data) => apiCall(() async {
        final r = await _dio.post('/printshop/orders', data: data);
        return CustomOrder.fromJson(r.data as Map<String, dynamic>);
      });

  Future<CustomOrder> save(CustomOrder o) => apiCall(() async {
        final r = await _dio.put('/printshop/orders/${o.id}', data: o.toJson());
        return CustomOrder.fromJson(r.data as Map<String, dynamic>);
      });

  Future<CustomOrder> setStatus(String id, OrderStatus s, {String? note}) => apiCall(() async {
        final r = await _dio.post('/printshop/orders/$id/status', data: {'status': s.api, if (note != null) 'note': note});
        return CustomOrder.fromJson(r.data as Map<String, dynamic>);
      });

  Future<CustomOrder> deposit(String id, double amount, PaymentMethod method) => apiCall(() async {
        final r = await _dio.post('/printshop/orders/$id/deposit', data: {'amount': amount, 'method': method.api});
        return CustomOrder.fromJson(r.data as Map<String, dynamic>);
      });

  Future<Receipt> close(String id, {required List<Payment> payments, int dueDays = 30}) => apiCall(() async {
        final r = await _dio.post('/printshop/orders/$id/close', data: {
          'payments': [for (final p in payments) p.toJson()],
          'dueDays': dueDays,
        });
        return Receipt.fromJson(r.data['receipt'] as Map<String, dynamic>);
      });

  Future<CustomOrder> uploadArt(String id, Uint8List bytes, String name) => apiCall(() async {
        final form = FormData.fromMap({'image': MultipartFile.fromBytes(bytes, filename: name)});
        final r = await _dio.post('/printshop/orders/$id/arts', data: form);
        return CustomOrder.fromJson(r.data as Map<String, dynamic>);
      });

  Future<CustomOrder> removeArt(String id, String artId) => apiCall(() async {
        final r = await _dio.delete('/printshop/orders/$id/arts/$artId');
        return CustomOrder.fromJson(r.data as Map<String, dynamic>);
      });
}
