import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/session_controller.dart';
import '../config/app_config.dart';
import 'api_exception.dart';

/// Cliente HTTP único do app.
/// - injeta o JWT da sessão em toda requisição
/// - se a API responder EMPRESA_BLOQUEADA / LICENCA_EXPIRADA / token inválido,
///   encerra a sessão e volta para o login com a mensagem
final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(BaseOptions(
    baseUrl: AppConfig.apiUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 20),
    headers: {'Accept': 'application/json'},
  ));

  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (options, handler) {
      // leitura preguiçosa (ref.read) evita dependência circular com a sessão
      final token = ref.read(sessionControllerProvider)?.token;
      if (token != null) options.headers['Authorization'] = 'Bearer $token';
      handler.next(options);
    },
    onError: (e, handler) {
      final api = ApiException.fromDio(e);
      final hadToken = e.requestOptions.headers.containsKey('Authorization');
      if (hadToken && api.endsSession) {
        ref.read(sessionControllerProvider.notifier).expire(api.message);
      }
      handler.next(e);
    },
  ));
  return dio;
});

/// Executa a chamada convertendo DioException → ApiException (mensagem amigável).
Future<T> apiCall<T>(Future<T> Function() fn) async {
  try {
    return await fn();
  } on DioException catch (e) {
    throw ApiException.fromDio(e);
  }
}
