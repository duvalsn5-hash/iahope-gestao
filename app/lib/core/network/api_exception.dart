import 'package:dio/dio.dart';

/// Erro padronizado vindo da API ({ error, message }).
class ApiException implements Exception {
  ApiException(this.message, {this.code, this.status});

  final String message;
  final String? code;
  final int? status;

  /// Códigos que encerram a sessão imediatamente.
  static const sessionKillers = {
    'TOKEN_INVALIDO',
    'NAO_AUTENTICADO',
    'EMPRESA_BLOQUEADA',
    'LICENCA_EXPIRADA',
    'USUARIO_INATIVO',
    'USUARIO_INEXISTENTE',
    'SESSAO_ENCERRADA',
  };

  bool get endsSession => code != null && sessionKillers.contains(code);

  factory ApiException.fromDio(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['message'] != null) {
      return ApiException(
        data['message'].toString(),
        code: data['error']?.toString(),
        status: e.response?.statusCode,
      );
    }
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return ApiException('Servidor demorou a responder. Verifique a conexão.');
      case DioExceptionType.connectionError:
        return ApiException('Sem conexão com o servidor.');
      default:
        return ApiException('Falha na comunicação (${e.response?.statusCode ?? 'rede'}).',
            status: e.response?.statusCode);
    }
  }

  @override
  String toString() => message;
}
