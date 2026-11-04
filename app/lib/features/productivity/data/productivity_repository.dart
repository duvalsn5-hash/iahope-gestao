import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/productivity.dart';

final productivityRepositoryProvider = Provider((ref) => ProductivityRepository(ref.watch(dioProvider)));

class ProductivityRepository {
  ProductivityRepository(this._dio);
  final Dio _dio;

  Future<ProductivityDashboardData> dashboard(DateTime day) => apiCall(() async {
        final r = await _dio.get('/productivity/dashboard',
            queryParameters: {'date': day.toIso8601String().substring(0, 10)});
        return ProductivityDashboardData.fromJson(r.data as Map<String, dynamic>);
      });

  Future<void> record(ProductivityEntry e) => apiCall(() => _dio.post('/productivity/hourly', data: e.toJson()));

  Future<void> createOrder({required String number, String? carrier, String? plate, String? dock, int expected = 0}) =>
      apiCall(() => _dio.post('/productivity/orders', data: {
            'orderNumber': number,
            if (carrier != null && carrier.isNotEmpty) 'carrier': carrier,
            if (plate != null && plate.isNotEmpty) 'vehiclePlate': plate,
            if (dock != null && dock.isNotEmpty) 'dock': dock,
            'expectedVolumes': expected,
          }));

  Future<void> setOrderStatus(String id, String status) =>
      apiCall(() => _dio.patch('/productivity/orders/$id/status', data: {'status': status}));
}
