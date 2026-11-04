import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/partner.dart';

final partnersRepositoryProvider = Provider((ref) => PartnersRepository(ref.watch(dioProvider)));

class PartnersRepository {
  PartnersRepository(this._dio);
  final Dio _dio;

  /// kind: CLIENTE | FORNECEDOR | null (todos)
  Future<List<Partner>> search(String q, {String? kind, bool all = false}) => apiCall(() async {
        final r = await _dio.get('/partners', queryParameters: {
          'q': q,
          if (kind != null) 'kind': kind,
          if (all) 'all': '1',
        });
        return (r.data as List).map((e) => Partner.fromJson(e as Map<String, dynamic>)).toList();
      });

  Future<Partner> create(Partner p) => apiCall(() async {
        final r = await _dio.post('/partners', data: p.toJson());
        return Partner.fromJson(r.data as Map<String, dynamic>);
      });

  Future<Partner> update(String id, Partner p) => apiCall(() async {
        final r = await _dio.put('/partners/$id', data: p.toJson());
        return Partner.fromJson(r.data as Map<String, dynamic>);
      });
}
