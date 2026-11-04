import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/session_storage.dart';
import '../data/auth_repository.dart';
import '../domain/session.dart';

/// Estado global da sessão (null = deslogado). Persistido em SharedPreferences.
final sessionControllerProvider = NotifierProvider<SessionController, Session?>(SessionController.new);

/// Mensagem exibida no login quando a sessão é encerrada pelo servidor
/// (empresa bloqueada, licença vencida...).
final sessionMessageProvider = StateProvider<String?>((_) => null);

class SessionController extends Notifier<Session?> {
  @override
  Session? build() {
    final json = ref.read(sessionStorageProvider).readSession();
    if (json == null) return null;
    try {
      final s = Session.fromJson(json);
      // valida no servidor em segundo plano (empresa pode ter sido bloqueada)
      Future.microtask(refresh);
      return s;
    } catch (_) {
      return null;
    }
  }

  Future<void> login({required String cnpj, required String username, required String password}) async {
    final session = await ref.read(authRepositoryProvider).login(cnpj: cnpj, username: username, password: password);
    final storage = ref.read(sessionStorageProvider);
    await storage.saveSession(session.toJson());
    await storage.saveLastCnpj(session.tenant.cnpj);
    ref.read(sessionMessageProvider.notifier).state = null;
    state = session;
  }

  Future<void> refresh() async {
    final current = state;
    if (current == null) return;
    try {
      final s = await ref.read(authRepositoryProvider).me(current.token);
      state = s;
      await ref.read(sessionStorageProvider).saveSession(s.toJson());
    } catch (_) {
      // erros de sessão já chamam expire() via interceptor; falha de rede mantém offline
    }
  }

  /// Atualiza só a parte de marca (após upload da logo).
  Future<void> updateTenant(SessionTenant tenant) async {
    final s = state;
    if (s == null) return;
    state = s.copyWith(tenant: tenant);
    await ref.read(sessionStorageProvider).saveSession(state!.toJson());
  }

  Future<void> logout() async {
    await ref.read(sessionStorageProvider).clearSession();
    state = null;
  }

  /// Chamado pelo interceptor quando a API recusa a sessão.
  void expire(String message) {
    if (state == null) return;
    ref.read(sessionMessageProvider.notifier).state = message;
    logout();
  }
}
