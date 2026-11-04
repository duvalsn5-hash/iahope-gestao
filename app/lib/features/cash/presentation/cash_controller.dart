import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/cash_repository.dart';
import '../domain/cash.dart';

/// Caixa do operador logado (aberto/fechado + resumo). Usado pelo PDV.
final cashControllerProvider = AsyncNotifierProvider.autoDispose<CashController, CashState>(CashController.new);

class CashController extends AutoDisposeAsyncNotifier<CashState> {
  @override
  Future<CashState> build() => ref.read(cashRepositoryProvider).current();

  Future<void> reload() async {
    state = AsyncData(await ref.read(cashRepositoryProvider).current());
  }

  Future<void> open(double amount) async {
    await ref.read(cashRepositoryProvider).open(amount);
    await reload();
  }

  Future<void> movement(String kind, double amount, String? reason) async {
    await ref.read(cashRepositoryProvider).movement(kind, amount, reason);
    await reload();
  }

  Future<CashSummary> close(double counted, String? notes) async {
    final s = await ref.read(cashRepositoryProvider).close(counted, notes);
    state = const AsyncData(CashState(open: false));
    return s;
  }
}
