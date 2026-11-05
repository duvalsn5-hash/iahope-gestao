import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/admin_repository.dart';
import '../domain/tenant.dart';

class TenantFilter {
  const TenantFilter({this.q = '', this.status = '', this.category = ''});
  final String q;
  final String status; // '', 'ATIVO', 'BLOQUEADO'
  final String category; // '' = todos os ramos

  TenantFilter copyWith({String? q, String? status, String? category}) =>
      TenantFilter(q: q ?? this.q, status: status ?? this.status, category: category ?? this.category);
}

final tenantFilterProvider = StateProvider<TenantFilter>((_) => const TenantFilter());

final adminStatsProvider = FutureProvider.autoDispose<AdminStats>((ref) {
  ref.watch(tenantsControllerProvider); // recarrega números quando a lista muda
  return ref.read(adminRepositoryProvider).stats();
});

final tenantsControllerProvider =
    AsyncNotifierProvider.autoDispose<TenantsController, List<Tenant>>(TenantsController.new);

class TenantsController extends AutoDisposeAsyncNotifier<List<Tenant>> {
  @override
  Future<List<Tenant>> build() {
    final f = ref.watch(tenantFilterProvider);
    return ref.read(adminRepositoryProvider).list(q: f.q, status: f.status, category: f.category);
  }

  void _replace(Tenant t) {
    final list = state.valueOrNull ?? const [];
    state = AsyncData([for (final x in list) x.id == t.id ? t : x]);
  }

  Future<void> toggleStatus(Tenant t, {String? reason}) async {
    final updated = await ref.read(adminRepositoryProvider).setStatus(t.id, active: t.isBlocked, reason: reason);
    _replace(updated);
  }

  Future<void> renew(Tenant t, DateTime until, {int? maxUsers}) async {
    _replace(await ref.read(adminRepositoryProvider).renew(t.id, until, maxUsers: maxUsers));
  }

  Future<void> setModules(Tenant t, List<String> modules) async {
    _replace(await ref.read(adminRepositoryProvider).setModules(t.id, modules));
  }

  Future<void> setCategory(Tenant t, String category, List<String> modules) async {
    _replace(await ref.read(adminRepositoryProvider).setCategory(t.id, category, modules));
  }

  Future<void> create(NewTenantInput input) async {
    await ref.read(adminRepositoryProvider).create(input);
    ref.invalidateSelf();
  }
}
