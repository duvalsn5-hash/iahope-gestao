import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/tenant.dart';

final adminRepositoryProvider = Provider((ref) => AdminRepository(ref.watch(dioProvider)));

class AdminRepository {
  AdminRepository(this._dio);
  final Dio _dio;

  Future<List<Tenant>> list({String q = '', String status = ''}) => apiCall(() async {
        final r = await _dio.get('/admin/tenants', queryParameters: {'q': q, 'status': status});
        return (r.data as List).map((e) => Tenant.fromJson(e as Map<String, dynamic>)).toList();
      });

  Future<AdminStats> stats() => apiCall(() async {
        final r = await _dio.get('/admin/stats');
        return AdminStats.fromJson(r.data as Map<String, dynamic>);
      });

  Future<Tenant> create(NewTenantInput input) => apiCall(() async {
        final r = await _dio.post('/admin/tenants', data: input.toJson());
        return Tenant.fromJson(r.data as Map<String, dynamic>);
      });

  Future<Tenant> setStatus(String id, {required bool active, String? reason}) => apiCall(() async {
        final r = await _dio.patch('/admin/tenants/$id/status', data: {
          'status': active ? 'ATIVO' : 'BLOQUEADO',
          if (reason != null && reason.isNotEmpty) 'reason': reason,
        });
        return Tenant.fromJson(r.data as Map<String, dynamic>);
      });

  Future<Tenant> setModules(String id, List<String> modules) => apiCall(() async {
        final r = await _dio.patch('/admin/tenants/$id/modules', data: {'modules': modules});
        return Tenant.fromJson(r.data as Map<String, dynamic>);
      });

  Future<Tenant> renew(String id, DateTime until, {int? maxUsers}) => apiCall(() async {
        final r = await _dio.patch('/admin/tenants/$id', data: {
          'licenseExpiresAt': until.toIso8601String().substring(0, 10),
          if (maxUsers != null) 'maxUsers': maxUsers,
        });
        return Tenant.fromJson(r.data as Map<String, dynamic>);
      });
}
