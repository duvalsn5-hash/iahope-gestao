import 'package:flutter/material.dart';

double _d(Object? v) => (v as num? ?? 0).toDouble();
DateTime? _date(Object? v) => v == null ? null : DateTime.tryParse(v.toString());

/// Técnicas de personalização.
const kTechniques = [
  ('DTF', 'DTF'),
  ('SERIGRAFIA', 'Serigrafia (silk)'),
  ('SUBLIMACAO', 'Sublimação'),
  ('BORDADO', 'Bordado'),
  ('VINIL', 'Vinil / transfer'),
  ('LASER', 'Laser / gravação'),
  ('OUTRO', 'Outra'),
];

String techniqueLabel(String code) => kTechniques.firstWhere((t) => t.$1 == code, orElse: () => (code, code)).$2;

/// Grades de tamanho prontas para o pedido.
const kOrderSizePresets = [
  ('Adulto', ['PP', 'P', 'M', 'G', 'GG', 'XG']),
  ('Baby look', ['BL-P', 'BL-M', 'BL-G', 'BL-GG']),
  ('Infantil', ['2', '4', '6', '8', '10', '12', '14']),
  ('Único', ['U']),
];

/// Andamento do pedido.
enum OrderStatus {
  orcamento('ORCAMENTO', 'Orçamento', Icons.request_quote_outlined, Colors.blueGrey),
  aprovado('APROVADO', 'Aprovado', Icons.thumb_up_alt_outlined, Colors.indigo),
  producao('PRODUCAO', 'Em produção', Icons.precision_manufacturing_outlined, Colors.orange),
  pronto('PRONTO', 'Pronto', Icons.inventory_outlined, Colors.green),
  entregue('ENTREGUE', 'Entregue', Icons.verified_outlined, Colors.teal),
  cancelado('CANCELADO', 'Cancelado', Icons.cancel_outlined, Colors.red);

  const OrderStatus(this.api, this.label, this.icon, this.color);
  final String api, label;
  final IconData icon;
  final Color color;

  /// Próximo passo do quadro (ENTREGUE só pelo caixa).
  OrderStatus? get next => switch (this) {
        OrderStatus.orcamento => OrderStatus.aprovado,
        OrderStatus.aprovado => OrderStatus.producao,
        OrderStatus.producao => OrderStatus.pronto,
        _ => null,
      };

  String? get nextAction => switch (this) {
        OrderStatus.orcamento => 'Cliente aprovou',
        OrderStatus.aprovado => 'Iniciar produção',
        OrderStatus.producao => 'Marcar como pronto',
        _ => null,
      };

  bool get isOpen => this != OrderStatus.entregue && this != OrderStatus.cancelado;
}

OrderStatus orderStatusFromApi(String v) => OrderStatus.values.firstWhere((s) => s.api == v, orElse: () => OrderStatus.orcamento);

const kBoard = [OrderStatus.orcamento, OrderStatus.aprovado, OrderStatus.producao, OrderStatus.pronto];

class OrderRow {
  const OrderRow({
    required this.id,
    required this.number,
    required this.customerName,
    this.customerPhone,
    required this.title,
    required this.technique,
    required this.status,
    this.dueDate,
    required this.pieces,
    required this.total,
    required this.deposit,
    this.artUrl,
  });
  final String id, customerName, title, technique;
  final int number;
  final String? customerPhone, artUrl;
  final OrderStatus status;
  final DateTime? dueDate;
  final double pieces, total, deposit;

  bool get late {
    if (dueDate == null || !status.isOpen || status == OrderStatus.pronto) return false;
    final n = DateTime.now();
    return dueDate!.isBefore(DateTime(n.year, n.month, n.day));
  }

  factory OrderRow.fromJson(Map<String, dynamic> j) => OrderRow(
        id: j['id'] as String,
        number: (j['number'] as num).toInt(),
        customerName: (j['customerName'] ?? '') as String,
        customerPhone: j['customerPhone'] as String?,
        title: j['title'] as String,
        technique: j['technique'] as String,
        status: orderStatusFromApi(j['status'] as String),
        dueDate: _date(j['dueDate']),
        pieces: _d(j['pieces']),
        total: _d(j['total']),
        deposit: _d(j['deposit']),
        artUrl: j['artUrl'] as String?,
      );
}

class OrderItem {
  OrderItem({
    this.productId,
    this.productName,
    this.imageUrl,
    this.stockQty,
    required this.description,
    this.color,
    Map<String, double>? sizes,
    this.qty = 1,
    this.unitPrice = 0,
  }) : sizes = sizes ?? {};

  String? productId, productName, imageUrl, color;
  double? stockQty;
  String description;
  Map<String, double> sizes;
  double qty, unitPrice;

  double get effectiveQty => sizes.values.fold<double>(0, (a, v) => a + v) > 0 ? sizes.values.fold<double>(0, (a, v) => a + v) : qty;
  double get total => (effectiveQty * unitPrice * 100).roundToDouble() / 100;
  bool get missingStock => productId != null && stockQty != null && effectiveQty > stockQty!;
  String get sizesText => sizes.entries.where((e) => e.value > 0).map((e) => '${e.key}:${e.value.toStringAsFixed(0)}').join('  ');

  factory OrderItem.fromJson(Map<String, dynamic> j) => OrderItem(
        productId: j['productId'] as String?,
        productName: j['productName'] as String?,
        imageUrl: j['imageUrl'] as String?,
        stockQty: (j['stockQty'] as num?)?.toDouble(),
        description: j['description'] as String,
        color: j['color'] as String?,
        sizes: {for (final e in (j['sizes'] as Map? ?? const {}).entries) e.key.toString(): (e.value as num).toDouble()},
        qty: _d(j['qty']),
        unitPrice: _d(j['unitPrice']),
      );

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'description': description,
        'color': (color?.isEmpty ?? true) ? null : color,
        'sizes': {for (final e in sizes.entries) if (e.value > 0) e.key: e.value},
        'qty': effectiveQty,
        'unitPrice': unitPrice,
      };
}

class OrderArt {
  const OrderArt({required this.id, this.name, required this.url});
  final String id;
  final String? name;
  final String url;
}

class OrderEvent {
  const OrderEvent({required this.status, this.note, this.user, required this.at});
  final String status;
  final String? note, user;
  final DateTime at;
}

class CustomOrder {
  CustomOrder({
    required this.id,
    required this.number,
    required this.customerId,
    required this.customerName,
    this.customerPhone,
    required this.title,
    required this.technique,
    required this.status,
    this.dueDate,
    this.artNotes,
    this.notes,
    required this.discount,
    required this.deposit,
    required this.items,
    required this.payments,
    required this.events,
    required this.arts,
    required this.createdAt,
    this.saleId,
  });

  final String id, customerId;
  final int number;
  String customerName;
  String? customerPhone;
  String title, technique;
  OrderStatus status;
  DateTime? dueDate;
  String? artNotes, notes, saleId;
  double discount, deposit;
  List<OrderItem> items;
  final List<(String, double, DateTime)> payments;
  final List<OrderEvent> events;
  List<OrderArt> arts;
  final DateTime createdAt;

  double get itemsTotal => items.fold<double>(0, (a, i) => a + i.total);
  double get total => ((itemsTotal - discount) * 100).roundToDouble() / 100;
  double get balance => ((total - deposit) * 100).roundToDouble() / 100;
  double get pieces => items.fold<double>(0, (a, i) => a + i.effectiveQty);
  bool get editable => status.isOpen;

  factory CustomOrder.fromJson(Map<String, dynamic> j) => CustomOrder(
        id: j['id'] as String,
        number: (j['number'] as num).toInt(),
        customerId: j['customerId'] as String,
        customerName: (j['customerName'] ?? '') as String,
        customerPhone: j['customerPhone'] as String?,
        title: j['title'] as String,
        technique: j['technique'] as String,
        status: orderStatusFromApi(j['status'] as String),
        dueDate: _date(j['dueDate']),
        artNotes: j['artNotes'] as String?,
        notes: j['notes'] as String?,
        discount: _d(j['discount']),
        deposit: _d(j['deposit']),
        saleId: j['saleId'] as String?,
        items: [for (final i in j['items'] as List? ?? const []) OrderItem.fromJson(i as Map<String, dynamic>)],
        payments: [
          for (final p in j['payments'] as List? ?? const [])
            (p['method'] as String, _d(p['amount']), DateTime.parse(p['createdAt'] as String)),
        ],
        events: [
          for (final e in j['events'] as List? ?? const [])
            OrderEvent(
              status: e['status'] as String,
              note: e['note'] as String?,
              user: e['user'] as String?,
              at: DateTime.parse(e['at'] as String),
            ),
        ],
        arts: [
          for (final a in j['arts'] as List? ?? const [])
            OrderArt(id: a['id'] as String, name: a['name'] as String?, url: a['url'] as String),
        ],
        createdAt: DateTime.parse(j['createdAt'] as String),
      );

  Map<String, dynamic> toJson() => {
        'customerId': customerId,
        'title': title,
        'technique': technique,
        'dueDate': dueDate == null ? null : '${dueDate!.year}-${dueDate!.month.toString().padLeft(2, '0')}-${dueDate!.day.toString().padLeft(2, '0')}',
        'artNotes': (artNotes?.isEmpty ?? true) ? null : artNotes,
        'notes': (notes?.isEmpty ?? true) ? null : notes,
        'discount': discount,
        'items': [for (final i in items) i.toJson()],
      };
}

class PrintshopSummary {
  const PrintshopSummary(this.m);
  final Map<String, num> m;
  int of(String k) => (m[k] ?? 0).toInt();
  double get deposits => (m['sinais'] ?? 0).toDouble();
}
