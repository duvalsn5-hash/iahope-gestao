import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

final companyRepositoryProvider = Provider((ref) => CompanyRepository(ref.watch(dioProvider)));

class CompanyRepository {
  CompanyRepository(this._dio);
  final Dio _dio;

  /// Envia a logo (PNG/JPG/WEBP, até 2 MB) e retorna a URL pública.
  /// Usa bytes para funcionar igual em Android, Windows e Web.
  Future<String> uploadLogo(Uint8List bytes, String fileName) => apiCall(() async {
        final ext = fileName.split('.').last.toLowerCase();
        final sub = switch (ext) { 'jpg' || 'jpeg' => 'jpeg', 'webp' => 'webp', _ => 'png' };
        final form = FormData.fromMap({
          'logo': MultipartFile.fromBytes(bytes, filename: fileName, contentType: DioMediaType('image', sub)),
        });
        final r = await _dio.post('/company/logo', data: form);
        return r.data['logoUrl'] as String;
      });

  Future<void> removeLogo() => apiCall(() => _dio.delete('/company/logo'));

  /// Dados da empresa (inclui scaleConfig da etiqueta de balança).
  Future<Map<String, dynamic>> fetch() => apiCall(() async {
        final r = await _dio.get('/company');
        return r.data as Map<String, dynamic>;
      });

  /// {prefix, codeLength, valueLength, valueType: PRECO|PESO}
  Future<void> saveScale(Map<String, dynamic> cfg) => apiCall(() => _dio.put('/company/scale', data: cfg));

  Future<Map<String, dynamic>> updateBrand({String? nomeFantasia, String? primaryColor}) => apiCall(() async {
        final r = await _dio.patch('/company', data: {
          if (nomeFantasia != null) 'nomeFantasia': nomeFantasia,
          if (primaryColor != null) 'primaryColor': primaryColor,
        });
        return r.data as Map<String, dynamic>;
      });
}
