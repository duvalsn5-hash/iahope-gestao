enum PartnerKind { cliente, fornecedor, ambos }

PartnerKind partnerKindFromApi(String v) => switch (v) {
      'FORNECEDOR' => PartnerKind.fornecedor,
      'AMBOS' => PartnerKind.ambos,
      _ => PartnerKind.cliente,
    };

String partnerKindToApi(PartnerKind k) => switch (k) {
      PartnerKind.cliente => 'CLIENTE',
      PartnerKind.fornecedor => 'FORNECEDOR',
      PartnerKind.ambos => 'AMBOS',
    };

String partnerKindLabel(PartnerKind k) => switch (k) {
      PartnerKind.cliente => 'Cliente',
      PartnerKind.fornecedor => 'Fornecedor',
      PartnerKind.ambos => 'Cliente e fornecedor',
    };

class Partner {
  const Partner({
    required this.id,
    required this.kind,
    this.doc,
    required this.name,
    this.tradeName,
    this.ie,
    this.phone,
    this.email,
    this.zip,
    this.street,
    this.number,
    this.district,
    this.city,
    this.state,
    this.creditLimit = 0,
    this.notes,
    this.isActive = true,
    this.openReceivable = 0,
  });

  final String id;
  final PartnerKind kind;
  final String? doc;
  final String name;
  final String? tradeName;
  final String? ie;
  final String? phone;
  final String? email;
  final String? zip;
  final String? street;
  final String? number;
  final String? district;
  final String? city;
  final String? state;
  final double creditLimit;
  final String? notes;
  final bool isActive;

  /// Saldo em aberto no "a receber" (fiado).
  final double openReceivable;

  String get displayName => (tradeName?.isNotEmpty ?? false) ? '$name ($tradeName)' : name;

  String get cityState => [city, state].where((e) => e != null && e.isNotEmpty).join('/');

  factory Partner.fromJson(Map<String, dynamic> j) => Partner(
        id: j['id'] as String,
        kind: partnerKindFromApi(j['kind'] as String),
        doc: j['doc'] as String?,
        name: j['name'] as String,
        tradeName: j['tradeName'] as String?,
        ie: j['ie'] as String?,
        phone: j['phone'] as String?,
        email: j['email'] as String?,
        zip: j['zip'] as String?,
        street: j['street'] as String?,
        number: j['number'] as String?,
        district: j['district'] as String?,
        city: j['city'] as String?,
        state: j['state'] as String?,
        creditLimit: (j['creditLimit'] as num? ?? 0).toDouble(),
        notes: j['notes'] as String?,
        isActive: j['isActive'] as bool? ?? true,
        openReceivable: (j['openReceivable'] as num? ?? 0).toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'kind': partnerKindToApi(kind),
        'doc': doc,
        'name': name,
        'tradeName': tradeName,
        'ie': ie,
        'phone': phone,
        'email': email,
        'zip': zip,
        'street': street,
        'number': number,
        'district': district,
        'city': city,
        'state': state,
        'creditLimit': creditLimit,
        'notes': notes,
        'isActive': isActive,
      };
}
