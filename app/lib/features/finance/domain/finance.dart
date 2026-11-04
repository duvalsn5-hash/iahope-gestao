import '../../../core/utils/formatters.dart';

double _d(Object? v) => (v as num? ?? 0).toDouble();

class FinEntry {
  const FinEntry({
    required this.id,
    required this.kind,
    this.partnerId,
    this.partnerName,
    required this.description,
    this.category,
    this.document,
    this.issueDate,
    required this.dueDate,
    required this.amount,
    required this.paidAmount,
    required this.status,
    required this.origin,
    this.paymentMethod,
  });

  final String id;
  final String kind; // PAGAR | RECEBER
  final String? partnerId;
  final String? partnerName;
  final String description;
  final String? category;
  final String? document;
  final DateTime? issueDate;
  final DateTime dueDate;
  final double amount;
  final double paidAmount;

  /// ABERTO | PARCIAL | VENCIDO | PAGO | CANCELADO
  final String status;

  /// MANUAL | VENDA | COMPRA
  final String origin;
  final String? paymentMethod;

  double get balance => amount - paidAmount;
  bool get isOpen => status == 'ABERTO' || status == 'PARCIAL' || status == 'VENCIDO';

  factory FinEntry.fromJson(Map<String, dynamic> j) => FinEntry(
        id: j['id'] as String,
        kind: j['kind'] as String,
        partnerId: j['partnerId'] as String?,
        partnerName: j['partnerName'] as String?,
        description: j['description'] as String,
        category: j['category'] as String?,
        document: j['document'] as String?,
        issueDate: parseIsoDate(j['issueDate'] as String?),
        dueDate: parseIsoDate(j['dueDate'] as String?) ?? DateTime.now(),
        amount: _d(j['amount']),
        paidAmount: _d(j['paidAmount']),
        status: j['status'] as String,
        origin: j['origin'] as String,
        paymentMethod: j['paymentMethod'] as String?,
      );
}

class FinTotals {
  const FinTotals({this.open = 0, this.overdue = 0, this.dueToday = 0, this.next7 = 0});
  final double open, overdue, dueToday, next7;

  factory FinTotals.fromJson(Map<String, dynamic> j) => FinTotals(
        open: _d(j['open']),
        overdue: _d(j['overdue']),
        dueToday: _d(j['dueToday']),
        next7: _d(j['next7']),
      );
}

class FinSummary {
  const FinSummary({this.receivable = const FinTotals(), this.payable = const FinTotals()});
  final FinTotals receivable, payable;

  factory FinSummary.fromJson(Map<String, dynamic> j) => FinSummary(
        receivable: FinTotals.fromJson(j['receivable'] as Map<String, dynamic>),
        payable: FinTotals.fromJson(j['payable'] as Map<String, dynamic>),
      );
}

class NewFinEntry {
  const NewFinEntry({
    required this.kind,
    this.partnerId,
    required this.description,
    this.category,
    this.document,
    required this.dueDate,
    required this.amount,
    this.installments = 1,
  });

  final String kind;
  final String? partnerId;
  final String description;
  final String? category;
  final String? document;
  final DateTime dueDate;
  final double amount;
  final int installments;

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'partnerId': partnerId,
        'description': description,
        'category': category,
        'document': document,
        'dueDate': isoDate(dueDate),
        'amount': amount,
        'installments': installments,
      };
}
