import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/utils/formatters.dart';
import '../domain/session.dart';

final authRepositoryProvider = Provider((ref) => AuthRepository(ref.watch(dioProvider)));

class AuthRepository {
  AuthRepository(this._dio);
  final Dio _dio;

  Future<TenantBranding> branding(String cnpj) => apiCall(() async {
        final r = await _dio.get('/auth/branding/${onlyDigits(cnpj)}');
        return TenantBranding.fromJson(r.data as Map<String, dynamic>);
      });

  Future<Session> login({required String cnpj, required String username, required String password}) =>
      apiCall(() async {
        final r = await _dio.post('/auth/login', data: {
          'cnpj': onlyDigits(cnpj),
          'username': username.trim(),
          'password': password,
        });
        return Session.fromJson(r.data as Map<String, dynamic>);
      });

  /// Recarrega usuário/empresa (status, logo) usando o token atual.
  Future<Session> me(String token) => apiCall(() async {
        final r = await _dio.get('/auth/me');
        return Session.fromJson({...(r.data as Map<String, dynamic>), 'token': token});
      });
}
