import 'package:flutter/material.dart';

import '../../../core/utils/formatters.dart';

double _d(Object? v) => (v as num? ?? 0).toDouble();

/// Andamento da OS, na ordem do fluxo.
enum OsStatus { aberta, orcamento, aprovada, emExecucao, pronta, entregue, cancelada }

OsStatus osStatusFromApi(String v) => switch (v) {
      'ORCAMENTO' => OsStatus.orcamento,
      'APROVADA' => OsStatus.aprovada,
      'EM_EXECUCAO' => OsStatus.emExecucao,
      'PRONTA' => OsStatus.pronta,
      'ENTREGUE' => OsStatus.entregue,
      'CANCELADA' => OsStatus.cancelada,
      _ => OsStatus.aberta,
    };

extension OsStatusX on OsStatus {
  String get api => switch (this) {
        OsStatus.aberta => 'ABERTA',
        OsStatus.orcamento => 'ORCAMENTO',
        OsStatus.aprovada => 'APROVADA',
        OsStatus.emExecucao => 'EM_EXECUCAO',
        OsStatus.pronta => 'PRONTA',
        OsStatus.entregue => 'ENTREGUE',
        OsStatus.cancelada => 'CANCELADA',
      };

  String get label => switch (this) {
        OsStatus.aberta => 'Recebida',
        OsStatus.orcamento => 'Orçamento enviado',
        OsStatus.aprovada => 'Aprovada',
        OsStatus.emExecucao => 'Em execução',
        OsStatus.pronta => 'Pronta p/ retirar',
        OsStatus.entregue => 'Entregue',
        OsStatus.cancelada => 'Cancelada',
      };

  IconData get icon => switch (this) {
        OsStatus.aberta => Icons.login,
        OsStatus.orcamento => Icons.request_quote_outlined,
        OsStatus.aprovada => Icons.thumb_up_alt_outlined,
        OsStatus.emExecucao => Icons.build_outlined,
        OsStatus.pronta => Icons.check_circle_outline,
        OsStatus.entregue => Icons.two_wheeler,
        OsStatus.cancelada => Icons.cancel_outlined,
      };

  Color color(ColorScheme c) => switch (this) {
        OsStatus.aberta => c.outline,
        OsStatus.orcamento => Colors.orange.shade800,
        OsStatus.aprovada => Colors.blue.shade700,
        OsStatus.emExecucao => Colors.indigo.shade600,
        OsStatus.pronta => Colors.green.shade700,
        OsStatus.entregue => c.outline,
        OsStatus.cancelada => c.error,
      };

  bool get isFinal => this == OsStatus.entregue || this == OsStatus.cancelada;

  /// Próximo passo sugerido no fluxo (o botão grande da OS).
  OsStatus? get next => switch (this) {
        OsStatus.aberta => OsStatus.orcamento,
        OsStatus.orcamento => OsStatus.aprovada,
        OsStatus.aprovada => OsStatus.emExecucao,
        OsStatus.emExecucao => OsStatus.pronta,
        _ => null,
      };

  String get nextAction => switch (this) {
        OsStatus.aberta => 'Enviar orçamento',
        OsStatus.orcamento => 'Cliente aprovou',
        OsStatus.aprovada => 'Iniciar serviço',
        OsStatus.emExecucao => 'Moto pronta',
        _ => '',
      };
}

/// Fluxo exibido no guia e na OS.
const kOsFlow = [OsStatus.aberta, OsStatus.orcamento, OsStatus.aprovada, OsStatus.emExecucao, OsStatus.pronta, OsStatus.entregue];

/// Itens do checklist de entrada (marcados = conferidos/presentes).
const kChecklist = [
  'Retrovisores',
  'Chave',
  'Documento',
  'Capacete',
  'Faróis e lanternas',
  'Setas',
  'Buzina',
  'Painel funcionando',
  'Bateria',
  'Pneus',
];

const kFuelLevels = ['RESERVA', '1/4', '1/2', '3/4', 'CHEIO'];

class Vehicle {
  const Vehicle({
    required this.id,
    required this.customerId,
    this.customerName,
    this.customerPhone,
    required this.plate,
    this.brand,
    required this.model,
    this.year,
    this.color,
    this.km,
    this.chassis,
    this.notes,
    this.lastServiceAt,
    this.openOrders = 0,
  });

  final String id;
  final String customerId;
  final String? customerName;
  final String? customerPhone;
  final String plate;
  final String? brand;
  final String model;
  final int? year;
  final String? color;
  final int? km;
  final String? chassis;
  final String? notes;
  final DateTime? lastServiceAt;
  final int openOrders;

  /// ABC1D23 → ABC-1D23
  String get plateFmt => plate.length == 7 ? '${plate.substring(0, 3)}-${plate.substring(3)}' : plate;
  String get label => [brand, model, if (year != null) '$year'].where((e) => e != null && e.isNotEmpty).join(' ');

  factory Vehicle.fromJson(Map<String, dynamic> j) => Vehicle(
        id: j['id'] as String,
        customerId: j['customerId'] as String,
        customerName: j['customerName'] as String?,
        customerPhone: j['customerPhone'] as String?,
        plate: j['plate'] as String,
        brand: j['brand'] as String?,
        model: j['model'] as String,
        year: (j['year'] as num?)?.toInt(),
        color: j['color'] as String?,
        km: (j['km'] as num?)?.toInt(),
        chassis: j['chassis'] as String?,
        notes: j['notes'] as String?,
        lastServiceAt: DateTime.tryParse('${j['lastServiceAt']}'),
        openOrders: (j['openOrders'] as num? ?? 0).toInt(),
      );

  Map<String, dynamic> toJson() => {
        'customerId': customerId,
        'plate': plate,
        'brand': brand,
        'model': model,
        'year': year,
        'color': color,
        'km': km,
        'chassis': chassis,
        'notes': notes,
      };
}

class LaborService {
  const LaborService({required this.id, required this.name, required this.price, this.estMinutes, this.isActive = true});
  final String id;
  final String name;
  final double price;
  final int? estMinutes;
  final bool isActive;

  factory LaborService.fromJson(Map<String, dynamic> j) => LaborService(
        id: j['id'] as String,
        name: j['name'] as String,
        price: _d(j['price']),
        estMinutes: (j['estMinutes'] as num?)?.toInt(),
        isActive: j['isActive'] as bool? ?? true,
      );
}

/// Linha da lista de OS.
class WorkOrderRow {
  const WorkOrderRow({
    required this.id,
    required this.number,
    required this.status,
    required this.customerName,
    this.customerPhone,
    required this.plate,
    required this.vehicleLabel,
    this.mechanicName,
    this.complaint,
    this.total,
    required this.openedAt,
    this.promisedAt,
  });

  final String id;
  final int number;
  final OsStatus status;
  final String customerName;
  final String? customerPhone;
  final String plate;
  final String vehicleLabel;
  final String? mechanicName;
  final String? complaint;
  final double? total;
  final DateTime openedAt;
  final DateTime? promisedAt;

  bool get late => promisedAt != null && !status.isFinal && promisedAt!.isBefore(DateTime.now());

  factory WorkOrderRow.fromJson(Map<String, dynamic> j) => WorkOrderRow(
        id: j['id'] as String,
        number: (j['number'] as num).toInt(),
        status: osStatusFromApi(j['status'] as String),
        customerName: j['customerName'] as String,
        customerPhone: j['customerPhone'] as String?,
        plate: j['plate'] as String,
        vehicleLabel: (j['vehicleLabel'] ?? '') as String,
        mechanicName: j['mechanicName'] as String?,
        complaint: j['complaint'] as String?,
        total: (j['total'] as num?)?.toDouble(),
        openedAt: DateTime.parse(j['openedAt'] as String),
        promisedAt: DateTime.tryParse('${j['promisedAt']}'),
      );
}

class OsItem {
  OsItem({
    required this.kind,
    this.productId,
    this.serviceId,
    required this.description,
    required this.qty,
    required this.unitPrice,
    this.mechanicId,
    this.imageUrl,
    this.stockQty,
    this.unit,
  });

  final String kind; // PECA | SERVICO
  final String? productId;
  final String? serviceId;
  String description;
  double qty;
  double unitPrice;
  String? mechanicId;
  final String? imageUrl;
  final double? stockQty;
  final String? unit;

  bool get isPart => kind == 'PECA';
  double get total => (qty * unitPrice * 100).roundToDouble() / 100;
  bool get missingStock => isPart && stockQty != null && qty > stockQty!;

  factory OsItem.fromJson(Map<String, dynamic> j) => OsItem(
        kind: j['kind'] as String,
        productId: j['productId'] as String?,
        serviceId: j['serviceId'] as String?,
        description: j['description'] as String,
        qty: _d(j['qty']),
        unitPrice: _d(j['unitPrice']),
        mechanicId: j['mechanicId'] as String?,
        imageUrl: j['imageUrl'] as String?,
        stockQty: (j['stockQty'] as num?)?.toDouble(),
        unit: j['unit'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'productId': productId,
        'serviceId': serviceId,
        'description': description,
        'qty': qty,
        'unitPrice': unitPrice,
        'mechanicId': mechanicId,
      };
}

class OsEvent {
  const OsEvent({required this.status, this.note, required this.createdAt, this.user});
  final OsStatus status;
  final String? note;
  final DateTime createdAt;
  final String? user;

  factory OsEvent.fromJson(Map<String, dynamic> j) => OsEvent(
        status: osStatusFromApi(j['status'] as String),
        note: j['note'] as String?,
        createdAt: DateTime.parse(j['createdAt'] as String),
        user: j['user'] as String?,
      );
}

/// OS completa (tela de detalhe).
class WorkOrder {
  WorkOrder({
    required this.id,
    required this.number,
    required this.status,
    required this.customerId,
    required this.customerName,
    this.customerPhone,
    this.customerDoc,
    required this.vehicle,
    this.mechanicId,
    this.mechanicName,
    this.complaint,
    this.diagnosis,
    this.kmIn,
    this.fuelLevel,
    required this.checklist,
    this.promisedAt,
    required this.discount,
    required this.warrantyDays,
    this.nextServiceDate,
    this.nextServiceKm,
    this.notes,
    this.saleId,
    required this.items,
    required this.events,
    required this.openedAt,
    this.deliveredAt,
  });

  final String id;
  final int number;
  OsStatus status;
  final String customerId;
  final String customerName;
  final String? customerPhone;
  final String? customerDoc;
  final Vehicle vehicle;
  String? mechanicId;
  final String? mechanicName;
  String? complaint;
  String? diagnosis;
  int? kmIn;
  String? fuelLevel;
  Map<String, dynamic> checklist;
  DateTime? promisedAt;
  double discount;
  int warrantyDays;
  final DateTime? nextServiceDate;
  final int? nextServiceKm;
  String? notes;
  final String? saleId;
  final List<OsItem> items;
  final List<OsEvent> events;
  final DateTime openedAt;
  final DateTime? deliveredAt;

  double get partsTotal => items.where((i) => i.isPart).fold<double>(0, (a, i) => a + i.total);
  double get laborTotal => items.where((i) => !i.isPart).fold<double>(0, (a, i) => a + i.total);
  double get subtotal => partsTotal + laborTotal;
  double get total => ((subtotal - discount) * 100).roundToDouble() / 100;

  factory WorkOrder.fromJson(Map<String, dynamic> j) {
    final v = j['vehicle'] as Map<String, dynamic>;
    return WorkOrder(
      id: j['id'] as String,
      number: (j['number'] as num).toInt(),
      status: osStatusFromApi(j['status'] as String),
      customerId: j['customerId'] as String,
      customerName: j['customerName'] as String,
      customerPhone: j['customerPhone'] as String?,
      customerDoc: j['customerDoc'] as String?,
      vehicle: Vehicle(
        id: v['id'] as String,
        customerId: j['customerId'] as String,
        plate: v['plate'] as String,
        brand: v['brand'] as String?,
        model: v['model'] as String,
        year: (v['year'] as num?)?.toInt(),
        color: v['color'] as String?,
        km: (v['km'] as num?)?.toInt(),
      ),
      mechanicId: j['mechanicId'] as String?,
      mechanicName: j['mechanicName'] as String?,
      complaint: j['complaint'] as String?,
      diagnosis: j['diagnosis'] as String?,
      kmIn: (j['kmIn'] as num?)?.toInt(),
      fuelLevel: j['fuelLevel'] as String?,
      checklist: Map<String, dynamic>.from((j['checklist'] as Map?) ?? const {}),
      promisedAt: DateTime.tryParse('${j['promisedAt']}'),
      discount: _d(j['discount']),
      warrantyDays: (j['warrantyDays'] as num? ?? 90).toInt(),
      nextServiceDate: parseIsoDate(j['nextServiceDate'] as String?),
      nextServiceKm: (j['nextServiceKm'] as num?)?.toInt(),
      notes: j['notes'] as String?,
      saleId: j['saleId'] as String?,
      items: [for (final i in j['items'] as List) OsItem.fromJson(i as Map<String, dynamic>)],
      events: [for (final e in j['events'] as List) OsEvent.fromJson(e as Map<String, dynamic>)],
      openedAt: DateTime.parse(j['openedAt'] as String),
      deliveredAt: DateTime.tryParse('${j['deliveredAt']}'),
    );
  }

  Map<String, dynamic> toUpdateJson() => {
        'complaint': complaint,
        'diagnosis': diagnosis,
        'kmIn': kmIn,
        'fuelLevel': fuelLevel,
        'checklist': checklist,
        'mechanicId': mechanicId,
        'promisedAt': promisedAt?.toUtc().toIso8601String(),
        'discount': discount,
        'warrantyDays': warrantyDays,
        'notes': notes,
        'items': [for (final i in items) i.toJson()],
      };
}

class Commission {
  const Commission({required this.name, required this.pct, required this.orders, required this.labor, required this.commission});
  final String name;
  final double pct;
  final int orders;
  final double labor;
  final double commission;

  factory Commission.fromJson(Map<String, dynamic> j) => Commission(
        name: j['name'] as String,
        pct: _d(j['commissionPct']),
        orders: (j['orders'] as num).toInt(),
        labor: _d(j['labor']),
        commission: _d(j['commission']),
      );
}

class Reminder {
  const Reminder({
    required this.vehicleId,
    required this.plate,
    required this.vehicleLabel,
    this.km,
    required this.customerName,
    this.customerPhone,
    required this.nextServiceDate,
    this.nextServiceKm,
  });

  final String vehicleId;
  final String plate;
  final String vehicleLabel;
  final int? km;
  final String customerName;
  final String? customerPhone;
  final DateTime nextServiceDate;
  final int? nextServiceKm;

  factory Reminder.fromJson(Map<String, dynamic> j) => Reminder(
        vehicleId: j['vehicleId'] as String,
        plate: j['plate'] as String,
        vehicleLabel: (j['vehicleLabel'] ?? '') as String,
        km: (j['km'] as num?)?.toInt(),
        customerName: j['customerName'] as String,
        customerPhone: j['customerPhone'] as String?,
        nextServiceDate: parseIsoDate(j['nextServiceDate'] as String?) ?? DateTime.now(),
        nextServiceKm: (j['nextServiceKm'] as num?)?.toInt(),
      );
}
