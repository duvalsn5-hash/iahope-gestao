/// IaHope Gestão — Operação, Logística e PDV (Android · Windows · Web)
/// Desenvolvido por Edivaldo.Nascimento - IaHope-Technology
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/storage/session_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('pt_BR');
  final prefs = await SharedPreferences.getInstance();

  runApp(ProviderScope(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
    child: const IaHopeApp(),
  ));
}
