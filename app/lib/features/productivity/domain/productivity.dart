class HourPoint {
  const HourPoint({required this.hour, required this.volumes, required this.weightKg, required this.pallets, required this.target, required this.team});
  final int hour, volumes, pallets, target, team;
  final double weightKg;

  factory HourPoint.fromJson(Map<String, dynamic> j) => HourPoint(
        hour: (j['hour'] as num).toInt(),
        volumes: (j['volumes'] as num).toInt(),
        weightKg: (j['weight_kg'] as num).toDouble(),
        pallets: (j['pallets'] as num).toInt(),
        target: (j['target'] as num).toInt(),
        team: (j['team'] as num).toInt(),
      );
}

class DockTotal {
  const DockTotal({required this.dock, required this.volumes, required this.weightKg, required this.target, this.lastHour});
  final String dock;
  final int volumes, target;
  final double weightKg;
  final DateTime? lastHour;

  factory DockTotal.fromJson(Map<String, dynamic> j) => DockTotal(
        dock: j['dock'] as String,
        volumes: (j['volumes'] as num).toInt(),
        weightKg: (j['weight_kg'] as num).toDouble(),
        target: (j['target'] as num? ?? 0).toInt(),
        lastHour: DateTime.tryParse('${j['last_hour']}'),
      );
}

class OpenOrder {
  const OpenOrder({
    required this.id,
    required this.orderNumber,
    this.carrier,
    this.vehiclePlate,
    this.dock,
    required this.status,
    required this.expected,
    required this.unloaded,
  });
  final String id, orderNumber, status;
  final String? carrier, vehiclePlate, dock;
  final int expected, unloaded;

  double get progress => expected == 0 ? 0 : (unloaded / expected).clamp(0, 1).toDouble();

  factory OpenOrder.fromJson(Map<String, dynamic> j) => OpenOrder(
        id: j['id'] as String,
        orderNumber: j['order_number'] as String,
        carrier: j['carrier'] as String?,
        vehiclePlate: j['vehicle_plate'] as String?,
        dock: j['dock'] as String?,
        status: j['status'] as String,
        expected: (j['expected_volumes'] as num).toInt(),
        unloaded: (j['unloaded_volumes'] as num).toInt(),
      );
}

class ProductivityDashboardData {
  const ProductivityDashboardData({
    required this.hours,
    required this.docks,
    required this.orders,
    required this.totalVolumes,
    required this.totalWeightKg,
    required this.targetVolumes,
    this.pctTarget,
    required this.avgPerHour,
    this.peakHour,
    required this.loadedAt,
  });

  final List<HourPoint> hours;
  final List<DockTotal> docks;
  final List<OpenOrder> orders;
  final int totalVolumes, targetVolumes, avgPerHour;
  final double totalWeightKg;
  final double? pctTarget;
  final int? peakHour;
  final DateTime loadedAt;

  factory ProductivityDashboardData.fromJson(Map<String, dynamic> j) {
    final s = j['summary'] as Map<String, dynamic>;
    return ProductivityDashboardData(
      hours: (j['hours'] as List).map((e) => HourPoint.fromJson(e as Map<String, dynamic>)).toList(),
      docks: (j['docks'] as List).map((e) => DockTotal.fromJson(e as Map<String, dynamic>)).toList(),
      orders: (j['orders'] as List).map((e) => OpenOrder.fromJson(e as Map<String, dynamic>)).toList(),
      totalVolumes: (s['totalVolumes'] as num).toInt(),
      totalWeightKg: (s['totalWeightKg'] as num).toDouble(),
      targetVolumes: (s['targetVolumes'] as num).toInt(),
      pctTarget: (s['pctTarget'] as num?)?.toDouble(),
      avgPerHour: (s['avgPerHour'] as num).toInt(),
      peakHour: (s['peakHour'] as num?)?.toInt(),
      loadedAt: DateTime.now(),
    );
  }
}

class ProductivityEntry {
  const ProductivityEntry({
    required this.dock,
    required this.volumes,
    this.weightKg = 0,
    this.pallets = 0,
    this.teamSize = 1,
    this.targetVolumes = 0,
    this.orderId,
  });
  final String dock;
  final int volumes, pallets, teamSize, targetVolumes;
  final double weightKg;
  final String? orderId;

  Map<String, dynamic> toJson() => {
        'dock': dock,
        'volumes': volumes,
        'weightKg': weightKg,
        'pallets': pallets,
        'teamSize': teamSize,
        'targetVolumes': targetVolumes,
        if (orderId != null) 'orderId': orderId,
        'mode': 'add',
      };
}
