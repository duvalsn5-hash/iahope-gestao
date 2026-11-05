/// Configuração global do app.
///
/// A URL da API é definida na compilação, sem alterar código:
///   flutter build windows --dart-define=API_URL=http://192.168.0.10:3000
///   flutter build apk     --dart-define=API_URL=https://api.suaempresa.com.br
///   flutter build web     --dart-define=API_URL=https://api.suaempresa.com.br
class AppConfig {
  AppConfig._();

  static const String apiUrl = String.fromEnvironment(
    'API_URL',
    // Emulador Android enxerga o PC em 10.0.2.2; Windows/Web usam localhost.
    defaultValue: 'http://localhost:3000',
  );

  static const String appName = 'IaHope Gestão';

  /// Endereços que o Master envia ao cliente na mensagem de boas-vindas.
  static const String webAppUrl = String.fromEnvironment('WEB_URL', defaultValue: 'https://duvalsn5-hash.github.io/iahope-gestao/');
  static const String downloadsUrl =
      String.fromEnvironment('DOWNLOADS_URL', defaultValue: 'https://github.com/duvalsn5-hash/iahope-gestao/releases/latest');

  /// Crédito obrigatório (login, sobre e rodapé principal).
  static const String credits = 'Desenvolvido por Edivaldo.Nascimento - IaHope-Technology';

  /// Intervalo de atualização do painel de produtividade "em tempo real".
  static const Duration productivityRefresh = Duration(seconds: 20);
}
