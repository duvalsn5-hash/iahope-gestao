import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/utils/formatters.dart';
import '../../pos/domain/pos_models.dart';
import '../domain/workshop.dart';

final workshopRepositoryProvider = Provider((ref) => WorkshopRepository(ref.watch(dioProvider)));

class WorkshopRepository {
  WorkshopRepository(this._dio);
  final Dio _dio;

  // ---- motos
  Future<List<Vehicle>> vehicles({String q = '', String? customerId}) => apiCall(() async {
        final r = await _dio.get('/workshop/vehicles', queryParameters: {'q': q, if (customerId != null) 'customerId': customerId});
        return (r.data as List).map((e) => Vehicle.fromJson(e as Map<String, dynamic>)).toList();
      });

  Future<Vehicle> saveVehicle(Vehicle v, {String? id}) => apiCall(() async {
        final r = id == null ? await _dio.post('/workshop/vehicles', data: v.toJson()) : await _dio.put('/workshop/vehicles/$id', data: v.toJson());
        return Vehicle.fromJson(r.data as Map<String, dynamic>);
      });

  Future<List<WorkOrderRow>> vehicleHistory(String id) => apiCall(() async {
        final r = await _dio.get('/workshop/vehicles/$id/history');
        return (r.data as List).map((e) => WorkOrderRow.fromJson(e as Map<String, dynamic>)).toList();
      });

  // ---- mão de obra
  Future<List<LaborService>> services({String q = '', bool all = false}) => apiCall(() async {
        final r = await _dio.get('/workshop/services', queryParameters: {'q': q, if (all) 'all': '1'});
        return (r.data as List).map((e) => LaborService.fromJson(e as Map<String, dynamic>)).toList();
      });

  Future<void> saveService({String? id, required String name, required double price, int? estMinutes, bool isActive = true}) =>
      apiCall(() {
        final data = {'name': name, 'price': price, 'estMinutes': estMinutes, 'isActive': isActive};
        return id == null ? _dio.post('/workshop/services', data: data) : _dio.put('/workshop/services/$id', data: data);
      });

  Future<int> loadDefaultServices() => apiCall(() async {
        final r = await _dio.post('/workshop/services/defaults');
        return (r.data['added'] as num).toInt();
      });

  // ---- OS
  /// status: ABERTAS | ENTREGUES | CANCELADAS | TODAS | <status da API>
  Future<List<WorkOrderRow>> orders({String status = 'ABERTAS', String q = ''}) => apiCall(() async {
        final r = await _dio.get('/workshop/orders', queryParameters: {'status': status, 'q': q});
        return (r.data as List).map((e) => WorkOrderRow.fromJson(e as Map<String, dynamic>)).toList();
      });

  Future<Map<String, int>> summary() => apiCall(() async {
        final r = await _dio.get('/workshop/summary');
        return {for (final e in (r.data as Map).entries) e.key.toString(): (e.value as num).toInt()};
      });

  Future<WorkOrder> order(String id) => apiCall(() async {
        final r = await _dio.get('/workshop/orders/$id');
        return WorkOrder.fromJson(r.data as Map<String, dynamic>);
      });

  Future<WorkOrder> open({
    required String customerId,
    required String vehicleId,
    String? complaint,
    int? kmIn,
    String? fuelLevel,
    Map<String, dynamic> checklist = const {},
    String? mechanicId,
    DateTime? promisedAt,
  }) =>
      apiCall(() async {
        final r = await _dio.post('/workshop/orders', data: {
          'customerId': customerId,
          'vehicleId': vehicleId,
          'complaint': complaint,
          'kmIn': kmIn,
          'fuelLevel': fuelLevel,
          'checklist': checklist,
          'mechanicId': mechanicId,
          'promisedAt': promisedAt?.toUtc().toIso8601String(),
        });
        return WorkOrder.fromJson(r.data as Map<String, dynamic>);
      });

  Future<WorkOrder> save(WorkOrder o) => apiCall(() async {
        final r = await _dio.put('/workshop/orders/${o.id}', data: o.toUpdateJson());
        return WorkOrder.fromJson(r.data as Map<String, dynamic>);
      });

  Future<WorkOrder> setStatus(String id, OsStatus s, {String? note}) => apiCall(() async {
        final r = await _dio.post('/workshop/orders/$id/status', data: {'status': s.api, if (note != null) 'note': note});
        return WorkOrder.fromJson(r.data as Map<String, dynamic>);
      });

  /// Recebe no caixa e entrega. Retorna o id da venda (para o cupom).
  Future<String> close(String id, {required List<Payment> payments, int dueDays = 30, DateTime? nextServiceDate, int? nextServiceKm}) =>
      apiCall(() async {
        final r = await _dio.post('/workshop/orders/$id/close', data: {
          'payments': [for (final p in payments) p.toJson()],
          'dueDays': dueDays,
          if (nextServiceDate != null) 'nextServiceDate': isoDate(nextServiceDate),
          if (nextServiceKm != null) 'nextServiceKm': nextServiceKm,
        });
        return r.data['saleId'] as String;
      });

  Future<Receipt> receipt(String saleId) => apiCall(() async {
        final r = await _dio.get('/pos/sales/$saleId');
        return Receipt.fromJson(r.data as Map<String, dynamic>);
      });

  // ---- gestão
  Future<List<Commission>> commissions({DateTime? from, DateTime? to}) => apiCall(() async {
        final r = await _dio.get('/workshop/commissions', queryParameters: {
          if (from != null) 'from': isoDate(from),
          if (to != null) 'to': isoDate(to),
        });
        return (r.data as List).map((e) => Commission.fromJson(e as Map<String, dynamic>)).toList();
      });

  Future<List<Reminder>> reminders({int days = 15}) => apiCall(() async {
        final r = await _dio.get('/workshop/reminders', queryParameters: {'days': days});
        return (r.data as List).map((e) => Reminder.fromJson(e as Map<String, dynamic>)).toList();
      });
}
