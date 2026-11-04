import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../products/data/products_repository.dart';
import '../../products/domain/product.dart';
import '../data/pos_repository.dart';
import '../domain/pos_models.dart';

final posControllerProvider = NotifierProvider<PosController, PosState>(PosController.new);

final posSummaryProvider = FutureProvider.autoDispose((ref) => ref.read(posRepositoryProvider).todaySummary());

/// Resultado de uma leitura/digitação no campo do PDV.
sealed class ScanResult {}

class ScanAdded extends ScanResult {
  ScanAdded(this.item);
  final CartItem item;
}

class ScanMultiplierSet extends ScanResult {
  ScanMultiplierSet(this.qty);
  final double qty;
}

class ScanChoices extends ScanResult {
  ScanChoices(this.products);
  final List<Product> products;
}

class ScanNotFound extends ScanResult {
  ScanNotFound(this.query);
  final String query;
}

class PosController extends Notifier<PosState> {
  @override
  PosState build() => const PosState();

  // "3*7891000100103" → 3 un do produto · "3*" → próxima leitura sai com 3
  static final _multiplier = RegExp(r'^(\d+(?:[.,]\d+)?)\s*[*xX]\s*(.*)$');

  /// Processa o que veio do leitor de código de barras (teclado/câmera) ou digitado.
  Future<ScanResult> handleInput(String raw) async {
    var text = raw.trim();
    double? qty;
    final m = _multiplier.firstMatch(text);
    if (m != null) {
      qty = double.parse(m.group(1)!.replaceAll(',', '.'));
      text = m.group(2)!.trim();
      if (text.isEmpty) {
        state = state.copyWith(pendingQty: qty);
        return ScanMultiplierSet(qty);
      }
    }

    final repo = ref.read(productsRepositoryProvider);
    // Códigos numéricos/SKU: busca exata primeiro (leitura do scanner é instantânea)
    if (!text.contains(' ')) {
      final p = await repo.byCode(text);
      if (p != null) return ScanAdded(add(p, qty: qty));
    }
    final list = await repo.search(text);
    if (list.length == 1) return ScanAdded(add(list.first, qty: qty));
    if (list.isEmpty) return ScanNotFound(text);
    if (qty != null) state = state.copyWith(pendingQty: qty);
    return ScanChoices(list);
  }

  /// Adiciona (ou soma ao item existente) e seleciona a linha.
  CartItem add(Product p, {double? qty}) {
    final q = qty ?? state.pendingQty ?? 1;
    final items = [...state.items];
    final idx = items.indexWhere((i) => i.product.id == p.id);
    if (idx >= 0) {
      items[idx] = items[idx].copyWith(qty: items[idx].qty + q);
    } else {
      items.add(CartItem(product: p, qty: q));
    }
    final sel = idx >= 0 ? idx : items.length - 1;
    state = state.copyWith(items: items, clearPending: true, selected: sel);
    return items[sel];
  }

  void select(int? index) => state = index == null ? state.copyWith(clearSelected: true) : state.copyWith(selected: index);

  void setQty(int index, double qty) {
    if (index < 0 || index >= state.items.length) return;
    if (qty <= 0) return remove(index);
    final items = [...state.items]..[index] = state.items[index].copyWith(qty: qty);
    state = state.copyWith(items: items);
  }

  void increment(int index, [double by = 1]) {
    if (index < 0 || index >= state.items.length) return;
    setQty(index, state.items[index].qty + by);
  }

  void remove(int index) {
    if (index < 0 || index >= state.items.length) return;
    final items = [...state.items]..removeAt(index);
    state = PosState(
      items: items,
      discount: items.isEmpty ? 0 : state.discount,
      selected: items.isEmpty ? null : (index >= items.length ? items.length - 1 : index),
    );
  }

  void setDiscount(double v) => state = state.copyWith(discount: v.clamp(0, state.subtotal).toDouble());

  void clear() => state = const PosState();

  Future<Receipt> finish(List<Payment> payments, {String? customerDoc}) async {
    final receipt = await ref.read(posRepositoryProvider).closeSale(
          items: state.items,
          payments: payments,
          discount: state.discount,
          customerDoc: customerDoc,
        );
    clear();
    ref.invalidate(posSummaryProvider);
    return receipt;
  }
}
