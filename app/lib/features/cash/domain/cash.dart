double _d(Object? v) => (v as num? ?? 0).toDouble();

class CashSummary {
  const CashSummary({
    required this.sessionId,
    required this.status,
    this.openedAt,
    this.closedAt,
    required this.opening,
    required this.salesCount,
    required this.salesTotal,
    required this.byMethod,
    required this.change,
    required this.supply,
    required this.withdrawal,
    required this.received,
    required this.paidOut,
    required this.expectedCash,
    this.counted,
    this.difference,
  });

  final String sessionId;
  final String status;
  final DateTime? openedAt;
  final DateTime? closedAt;
  final double opening;
  final int salesCount;
  final double salesTotal;

  /// Total por forma de pagamento: DINHEIRO, PIX, DEBITO, CREDITO, PRAZO…
  final Map<String, double> byMethod;
  final double change;
  final double supply;
  final double withdrawal;
  final double received;
  final double paidOut;

  /// Dinheiro que deveria estar na gaveta agora.
  final double expectedCash;
  final double? counted;
  final double? difference;

  factory CashSummary.fromJson(Map<String, dynamic> j) => CashSummary(
        sessionId: j['sessionId'] as String,
        status: (j['status'] ?? 'ABERTO') as String,
        openedAt: DateTime.tryParse('${j['openedAt']}'),
        closedAt: DateTime.tryParse('${j['closedAt']}'),
        opening: _d(j['opening']),
        salesCount: (j['salesCount'] as num? ?? 0).toInt(),
        salesTotal: _d(j['salesTotal']),
        byMethod: {
          for (final e in ((j['byMethod'] as Map?) ?? const {}).entries) e.key.toString(): _d(e.value),
        },
        change: _d(j['change']),
        supply: _d(j['supply']),
        withdrawal: _d(j['withdrawal']),
        received: _d(j['received']),
        paidOut: _d(j['paidOut']),
        expectedCash: _d(j['expectedCash']),
        counted: (j['counted'] as num?)?.toDouble(),
        difference: (j['difference'] as num?)?.toDouble(),
      );
}

class CashMovement {
  const CashMovement({required this.kind, required this.amount, this.reason, required this.createdAt});
  final String kind;
  final double amount;
  final String? reason;
  final DateTime createdAt;

  factory CashMovement.fromJson(Map<String, dynamic> j) => CashMovement(
        kind: j['kind'] as String,
        amount: _d(j['amount']),
        reason: j['reason'] as String?,
        createdAt: DateTime.parse(j['createdAt'] as String),
      );
}

/// Estado do caixa do operador logado.
class CashState {
  const CashState({required this.open, this.summary, this.movements = const []});
  final bool open;
  final CashSummary? summary;
  final List<CashMovement> movements;

  factory CashState.fromJson(Map<String, dynamic> j) => CashState(
        open: j['open'] as bool? ?? false,
        summary: j['summary'] == null ? null : CashSummary.fromJson(j['summary'] as Map<String, dynamic>),
        movements: [for (final m in (j['movements'] as List? ?? const [])) CashMovement.fromJson(m as Map<String, dynamic>)],
      );
}

/// Linha do histórico de caixas (gestão).
class CashSessionRow {
  const CashSessionRow({
    required this.id,
    required this.status,
    required this.operator,
    required this.openedAt,
    this.closedAt,
    required this.opening,
    this.expectedCash,
    this.counted,
    this.difference,
    required this.salesTotal,
    required this.salesCount,
  });

  final String id;
  final String status;
  final String operator;
  final DateTime openedAt;
  final DateTime? closedAt;
  final double opening;
  final double? expectedCash;
  final double? counted;
  final double? difference;
  final double salesTotal;
  final int salesCount;

  factory CashSessionRow.fromJson(Map<String, dynamic> j) => CashSessionRow(
        id: j['id'] as String,
        status: j['status'] as String,
        operator: j['operator'] as String,
        openedAt: DateTime.parse(j['openedAt'] as String),
        closedAt: DateTime.tryParse('${j['closedAt']}'),
        opening: _d(j['opening']),
        expectedCash: (j['expectedCash'] as num?)?.toDouble(),
        counted: (j['counted'] as num?)?.toDouble(),
        difference: (j['difference'] as num?)?.toDouble(),
        salesTotal: _d(j['salesTotal']),
        salesCount: (j['salesCount'] as num? ?? 0).toInt(),
      );
}
