import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Inicializado no main() antes do runApp.
final sharedPrefsProvider = Provider<SharedPreferences>(
  (_) => throw UnimplementedError('sharedPrefsProvider deve ser sobrescrito no main()'),
);

final sessionStorageProvider = Provider((ref) => SessionStorage(ref.watch(sharedPrefsProvider)));

class SessionStorage {
  SessionStorage(this._prefs);
  final SharedPreferences _prefs;

  static const _kSession = 'session';
  static const _kLastCnpj = 'last_cnpj';

  Map<String, dynamic>? readSession() {
    final raw = _prefs.getString(_kSession);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveSession(Map<String, dynamic> json) => _prefs.setString(_kSession, jsonEncode(json));
  Future<void> clearSession() => _prefs.remove(_kSession);

  String? get lastCnpj => _prefs.getString(_kLastCnpj);
  Future<void> saveLastCnpj(String cnpj) => _prefs.setString(_kLastCnpj, cnpj);
}
