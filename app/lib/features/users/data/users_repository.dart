import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../auth/domain/session.dart';
import '../domain/app_user.dart';

final usersRepositoryProvider = Provider((ref) => UsersRepository(ref.watch(dioProvider)));

class UsersRepository {
  UsersRepository(this._dio);
  final Dio _dio;

  Future<UsersPage> list({String? role}) => apiCall(() async {
        final r = await _dio.get('/users', queryParameters: {if (role != null) 'role': role});
        return UsersPage.fromJson(r.data as Map<String, dynamic>);
      });

  Future<void> create({
    required String username,
    required String fullName,
    String? email,
    required UserRole role,
    required String password,
    double commissionPct = 0,
  }) =>
      apiCall(() => _dio.post('/users', data: {
            'username': username,
            'fullName': fullName,
            'email': email,
            'role': roleToApi(role),
            'password': password,
            'commissionPct': commissionPct,
          }));

  Future<void> update(String id, {
    required String fullName,
    String? email,
    required UserRole role,
    required bool isActive,
    double commissionPct = 0,
    String? newPassword,
    bool unlock = false,
    bool resetTotp = false,
  }) =>
      apiCall(() => _dio.put('/users/$id', data: {
            'unlock': unlock,
            'resetTotp': resetTotp,
            'fullName': fullName,
            'email': email,
            'role': roleToApi(role),
            'isActive': isActive,
            'commissionPct': commissionPct,
            'newPassword': newPassword,
          }));

  /// Troca a própria senha → token novo (as outras sessões caem).
  Future<String> changeMyPassword(String current, String next) => apiCall(() async {
        final r = await _dio.put('/users/me/password', data: {'current': current, 'next': next});
        return r.data['token'] as String;
      });
}
