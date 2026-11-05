import '../../../core/business/business_category.dart';

enum TenantStatus { ativo, bloqueado }

class Tenant {
  const Tenant({
    required this.id,
    required this.cnpj,
    required this.razaoSocial,
    this.nomeFantasia,
    this.logoUrl,
    required this.status,
    this.blockedReason,
    required this.licenseExpiresAt,
    required this.maxUsers,
    required this.usersCount,
    required this.isPlatform,
    this.modules = const [],
    this.adminUsername,
    this.businessCategory = 'OUTRO',
  });

  final String id;
  final String cnpj;
  final String razaoSocial;
  final String? nomeFantasia;
  final String? logoUrl;
  final TenantStatus status;
  final String? blockedReason;
  final DateTime licenseExpiresAt;
  final int maxUsers;
  final int usersCount;
  final bool isPlatform;
  final List<String> modules;
  final String? adminUsername;
  final String businessCategory;

  BusinessCategory get business => businessCategoryOf(businessCategory);

  String get displayName => (nomeFantasia?.isNotEmpty ?? false) ? nomeFantasia! : razaoSocial;
  bool get isBlocked => status == TenantStatus.bloqueado;

  int get daysLeft {
    final now = DateTime.now();
    return licenseExpiresAt.difference(DateTime(now.year, now.month, now.day)).inDays;
  }

  bool get isExpired => daysLeft < 0;

  factory Tenant.fromJson(Map<String, dynamic> j) => Tenant(
        id: j['id'] as String,
        cnpj: j['cnpj'] as String,
        razaoSocial: j['razaoSocial'] as String,
        nomeFantasia: j['nomeFantasia'] as String?,
        logoUrl: j['logoUrl'] as String?,
        status: j['status'] == 'BLOQUEADO' ? TenantStatus.bloqueado : TenantStatus.ativo,
        blockedReason: j['blockedReason'] as String?,
        licenseExpiresAt: DateTime.parse(j['licenseExpiresAt'] as String),
        maxUsers: (j['maxUsers'] as num).toInt(),
        usersCount: (j['usersCount'] as num? ?? 0).toInt(),
        isPlatform: j['isPlatform'] as bool? ?? false,
        modules: [for (final m in (j['modules'] as List? ?? const [])) m.toString()],
        adminUsername: j['adminUsername'] as String?,
        businessCategory: (j['businessCategory'] as String?) ?? 'OUTRO',
      );
}

class AdminStats {
  const AdminStats({this.total = 0, this.ativos = 0, this.bloqueados = 0, this.vencidos = 0, this.vencendo7d = 0});
  final int total, ativos, bloqueados, vencidos, vencendo7d;

  factory AdminStats.fromJson(Map<String, dynamic> j) => AdminStats(
        total: (j['total'] as num).toInt(),
        ativos: (j['ativos'] as num).toInt(),
        bloqueados: (j['bloqueados'] as num).toInt(),
        vencidos: (j['vencidos'] as num).toInt(),
        vencendo7d: (j['vencendo_7d'] as num).toInt(),
      );
}

class NewTenantInput {
  const NewTenantInput({
    required this.cnpj,
    required this.razaoSocial,
    this.nomeFantasia,
    required this.licenseExpiresAt,
    required this.maxUsers,
    required this.adminUsername,
    required this.adminFullName,
    required this.adminPassword,
    this.modules,
    this.businessCategory = 'OUTRO',
  });

  final String cnpj, razaoSocial;
  final String? nomeFantasia;
  final DateTime licenseExpiresAt;
  final int maxUsers;
  final String adminUsername, adminFullName, adminPassword;
  final List<String>? modules;
  final String businessCategory;

  Map<String, dynamic> toJson() => {
        'cnpj': cnpj,
        'razaoSocial': razaoSocial,
        if (nomeFantasia != null && nomeFantasia!.isNotEmpty) 'nomeFantasia': nomeFantasia,
        'licenseExpiresAt': licenseExpiresAt.toIso8601String().substring(0, 10),
        'maxUsers': maxUsers,
        if (modules != null) 'modules': modules,
        'businessCategory': businessCategory,
        'admin': {'username': adminUsername, 'fullName': adminFullName, 'password': adminPassword},
      };
}

/// Catálogo de módulos contratáveis (o núcleo — produtos, clientes, empresa — está sempre ativo).
const kModules = [
  ('PDV', 'PDV e caixa', 'Frente de caixa, abertura/fechamento, cupom'),
  ('PRODUTIVIDADE', 'Produtividade logística', 'Descarga hora a hora, docas e cargas'),
  ('FINANCEIRO', 'Financeiro', 'Contas a pagar e a receber, venda a prazo'),
  ('COMPRAS', 'Compras por XML', 'Entrada de NF-e com estoque, custo e duplicatas'),
  ('BALANCA', 'Balança', 'Leitura de etiqueta de balança no PDV'),
  ('OFICINA', 'Oficina de motos', 'Ordens de serviço, motos, mão de obra, comissões e revisões'),
];

