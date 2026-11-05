import 'package:url_launcher/url_launcher.dart';

import 'formatters.dart';

/// Abre o WhatsApp com a mensagem pronta. Sem telefone, o WhatsApp pede o contato.
/// Telefone brasileiro com DDD (10 ou 11 dígitos) ganha o 55 automaticamente.
Future<bool> openWhatsApp(String? phone, String message) async {
  var d = onlyDigits(phone ?? '');
  if (d.length == 10 || d.length == 11) d = '55$d';
  final uri = Uri.parse('https://wa.me/${d.isEmpty ? '' : d}?text=${Uri.encodeComponent(message)}');
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}
