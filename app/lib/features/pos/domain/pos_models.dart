import '../../partners/domain/partner.dart';
import '../../products/domain/product.dart';

class CartItem {
  const CartItem({required this.product, required this.qty});
  final Product product;
  final double qty;

  double get total => _round2(product.price * qty);
  CartItem copyWith({double? qty}) => CartItem(product: product, qty: qty ?? this.qty);
}

double _round2(double v) => (v * 100).roundToDouble() / 100;

enum PaymentMethod { dinheiro, pix, debito, credito, prazo, vale }

extension PaymentMethodX on PaymentMethod {
  String get api => switch (this) {
        PaymentMethod.dinheiro => 'DINHEIRO',
        PaymentMethod.pix => 'PIX',
        PaymentMethod.debito => 'DEBITO',
        PaymentMethod.credito => 'CREDITO',
        PaymentMethod.prazo => 'PRAZO',
        PaymentMethod.vale => 'VALE',
      };

  String get label => switch (this) {
        PaymentMethod.dinheiro => 'Dinheiro',
        PaymentMethod.pix => 'PIX',
        PaymentMethod.debito => 'Débito',
        PaymentMethod.credito => 'Crédito',
        PaymentMethod.prazo => 'A prazo',
        PaymentMethod.vale => 'Vale-troca',
      };
}

String paymentLabel(String api) => switch (api) {
      'DINHEIRO' => 'Dinheiro',
      'PIX' => 'PIX',
      'DEBITO' => 'Cartão de débito',
      'CREDITO' => 'Cartão de crédito',
      'PRAZO' => 'A prazo',
      'VALE' => 'Vale-troca',
      'SINAL' => 'Sinal (já pago)',
      _ => 'Outros',
    };

class Payment {
  const Payment(this.method, this.amount, {this.voucher});
  final PaymentMethod method;
  final double amount;

  /// Código do vale-troca (quando method = vale).
  final String? voucher;

  Map<String, dynamic> toJson() => {'method': method.api, 'amount': amount, if (voucher != null) 'voucher': voucher};
}

/// Vale-troca conferido no servidor.
typedef VoucherInfo = ({String code, double balance});

/// Estado do PDV (imutável).
class PosState {
  const PosState({this.items = const [], this.discount = 0, this.pendingQty, this.selected, this.customer});

  final List<CartItem> items;

  /// Cliente identificado (obrigatório para venda a prazo).
  final Partner? customer;
  final double discount;
  final double? pendingQty; // quantidade digitada antes do código (ex.: "3*")
  final int? selected; // item selecionado no carrinho

  double get subtotal => _round2(items.fold<double>(0, (a, i) => a + i.total));
  double get total => _round2((subtotal - discount).clamp(0, double.infinity).toDouble());
  int get itemCount => items.length;
  double get unitCount => items.fold<double>(0, (a, i) => a + i.qty);
  bool get isEmpty => items.isEmpty;

  PosState copyWith({
    List<CartItem>? items,
    double? discount,
    double? pendingQty,
    bool clearPending = false,
    int? selected,
    bool clearSelected = false,
    Partner? customer,
    bool clearCustomer = false,
  }) =>
      PosState(
        items: items ?? this.items,
        discount: discount ?? this.discount,
        pendingQty: clearPending ? null : (pendingQty ?? this.pendingQty),
        selected: clearSelected ? null : (selected ?? this.selected),
        customer: clearCustomer ? null : (customer ?? this.customer),
      );
}

class ReceiptLine {
  const ReceiptLine(this.description, this.qty, this.unitPrice, this.total);
  final String description;
  final double qty, unitPrice, total;
}

class Receipt {
  const Receipt({
    required this.id,
    required this.number,
    required this.createdAt,
    this.cashier,
    required this.companyName,
    required this.razaoSocial,
    required this.cnpj,
    this.logoUrl,
    required this.items,
    required this.payments,
    required this.subtotal,
    required this.discount,
    required this.total,
    required this.paid,
    required this.change,
    required this.footer,
    this.customerName,
  });

  final String id;
  final int number;
  final DateTime createdAt;
  final String? cashier;
  final String companyName, razaoSocial, cnpj;
  final String? logoUrl;
  final List<ReceiptLine> items;
  final List<(String, double)> payments;
  final double subtotal, discount, total, paid, change;
  final String footer;
  final String? customerName;

  factory Receipt.fromJson(Map<String, dynamic> j) {
    final c = j['company'] as Map<String, dynamic>;
    return Receipt(
      id: j['id'] as String,
      number: (j['number'] as num).toInt(),
      createdAt: DateTime.parse(j['createdAt'] as String),
      cashier: j['cashier'] as String?,
      companyName: c['name'] as String,
      razaoSocial: c['razaoSocial'] as String,
      cnpj: c['cnpj'] as String,
      logoUrl: c['logoUrl'] as String?,
      items: [
        for (final i in j['items'] as List)
          ReceiptLine(i['description'] as String, (i['qty'] as num).toDouble(), (i['unitPrice'] as num).toDouble(),
              (i['total'] as num).toDouble()),
      ],
      payments: [for (final p in j['payments'] as List) (p['method'] as String, (p['amount'] as num).toDouble())],
      subtotal: (j['subtotal'] as num).toDouble(),
      discount: (j['discount'] as num).toDouble(),
      total: (j['total'] as num).toDouble(),
      paid: (j['paid'] as num).toDouble(),
      change: (j['change'] as num).toDouble(),
      footer: j['footer'] as String,
      customerName: (j['customer'] as Map?)?['name'] as String?,
    );
  }
}
