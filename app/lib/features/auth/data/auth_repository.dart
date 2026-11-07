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

  /// 1º passo do login. Com verificação em 2 etapas ligada, devolve só o ticket.
  Future<({Session? session, String? ticket})> login({required String cnpj, required String username, required String password}) =>
      apiCall(() async {
        final r = await _dio.post('/auth/login', data: {
          'cnpj': onlyDigits(cnpj),
          'username': username.trim(),
          'password': password,
        });
        final d = r.data as Map<String, dynamic>;
        if (d['needsTotp'] == true) return (session: null, ticket: d['ticket'] as String);
        return (session: Session.fromJson(d), ticket: null);
      });

  /// 2º passo: código de 6 dígitos do aplicativo autenticador.
  Future<Session> loginTotp(String ticket, String code) => apiCall(() async {
        final r = await _dio.post('/auth/login/totp', data: {'ticket': ticket, 'code': code.trim()});
        return Session.fromJson(r.data as Map<String, dynamic>);
      });

  Future<({String secret, String url})> totpSetup() => apiCall(() async {
        final r = await _dio.post('/auth/totp/setup');
        return (secret: r.data['secret'] as String, url: r.data['otpauthUrl'] as String);
      });

  /// Liga/desliga as 2 etapas → token novo (a versão da sessão muda).
  Future<String> totpEnable(String code) => apiCall(() async {
        final r = await _dio.post('/auth/totp/enable', data: {'code': code.trim()});
        return r.data['token'] as String;
      });

  Future<String> totpDisable(String password) => apiCall(() async {
        final r = await _dio.post('/auth/totp/disable', data: {'password': password});
        return r.data['token'] as String;
      });

  Future<void> logoutAll() => apiCall(() => _dio.post('/auth/logout-all'));

  /// Gerente autoriza uma ação do caixa → token de 3 minutos.
  Future<({String token, String name})> supervisor(String username, String password, String action) => apiCall(() async {
        final r = await _dio.post('/auth/supervisor', data: {'username': username.trim(), 'password': password, 'action': action});
        return (token: r.data['token'] as String, name: (r.data['name'] ?? '') as String);
      });

  /// Recarrega usuário/empresa (status, logo) usando o token atual.
  Future<Session> me(String token) => apiCall(() async {
        final r = await _dio.get('/auth/me');
        return Session.fromJson({...(r.data as Map<String, dynamic>), 'token': token});
      });
}
