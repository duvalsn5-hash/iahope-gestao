import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/purchase.dart';

final purchasesRepositoryProvider = Provider((ref) => PurchasesRepository(ref.watch(dioProvider)));

class PurchasesRepository {
  PurchasesRepository(this._dio);
  final Dio _dio;

  /// Envia o XML da NF-e e recebe a conferência (produtos sugeridos por item).
  Future<NfePreview> preview(Uint8List bytes, String fileName) => apiCall(() async {
        final form = FormData.fromMap({
          'xml': MultipartFile.fromBytes(bytes, filename: fileName, contentType: DioMediaType('text', 'xml')),
        });
        final r = await _dio.post('/purchases/preview', data: form);
        return NfePreview.fromJson(r.data as Map<String, dynamic>);
      });

  Future<String> register(NfePreview p) => apiCall(() async {
        final r = await _dio.post('/purchases', data: p.toRegisterJson());
        return r.data['id'] as String;
      });

  Future<List<PurchaseRow>> list() => apiCall(() async {
        final r = await _dio.get('/purchases');
        return (r.data as List).map((e) => PurchaseRow.fromJson(e as Map<String, dynamic>)).toList();
      });
}
