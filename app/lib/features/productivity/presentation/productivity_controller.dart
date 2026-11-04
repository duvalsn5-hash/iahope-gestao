import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../data/productivity_repository.dart';
import '../domain/productivity.dart';

final productivityDayProvider = StateProvider.autoDispose<DateTime>((_) => DateTime.now());

/// Painel "em tempo real": recarrega a cada [AppConfig.productivityRefresh]
/// (somente quando o dia selecionado é hoje) sem piscar a tela.
final productivityControllerProvider =
    AsyncNotifierProvider.autoDispose<ProductivityController, ProductivityDashboardData>(ProductivityController.new);

class ProductivityController extends AutoDisposeAsyncNotifier<ProductivityDashboardData> {
  Timer? _timer;

  @override
  Future<ProductivityDashboardData> build() async {
    final day = ref.watch(productivityDayProvider);
    _timer?.cancel();
    final now = DateTime.now();
    final isToday = day.year == now.year && day.month == now.month && day.day == now.day;
    if (isToday) {
      _timer = Timer.periodic(AppConfig.productivityRefresh, (_) => silentRefresh());
    }
    ref.onDispose(() => _timer?.cancel());
    return ref.read(productivityRepositoryProvider).dashboard(day);
  }

  Future<void> silentRefresh() async {
    try {
      final data = await ref.read(productivityRepositoryProvider).dashboard(ref.read(productivityDayProvider));
      state = AsyncData(data);
    } catch (_) {
      // mantém os últimos dados; o interceptor trata sessão expirada
    }
  }

  Future<void> record(ProductivityEntry e) async {
    await ref.read(productivityRepositoryProvider).record(e);
    await silentRefresh();
  }

  Future<void> createOrder({required String number, String? carrier, String? plate, String? dock, int expected = 0}) async {
    await ref.read(productivityRepositoryProvider)
        .createOrder(number: number, carrier: carrier, plate: plate, dock: dock, expected: expected);
    await silentRefresh();
  }

  Future<void> setOrderStatus(String id, String status) async {
    await ref.read(productivityRepositoryProvider).setOrderStatus(id, status);
    await silentRefresh();
  }
}
