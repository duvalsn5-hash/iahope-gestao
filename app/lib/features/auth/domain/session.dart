enum UserRole { superAdmin, admin, gerente, operador, caixa, mecanico }

UserRole roleFromApi(String v) => switch (v) {
      'SUPER_ADMIN' => UserRole.superAdmin,
      'ADMIN' => UserRole.admin,
      'GERENTE' => UserRole.gerente,
      'CAIXA' => UserRole.caixa,
      'MECANICO' => UserRole.mecanico,
      _ => UserRole.operador,
    };

String roleToApi(UserRole r) => switch (r) {
      UserRole.superAdmin => 'SUPER_ADMIN',
      UserRole.admin => 'ADMIN',
      UserRole.gerente => 'GERENTE',
      UserRole.caixa => 'CAIXA',
      UserRole.operador => 'OPERADOR',
      UserRole.mecanico => 'MECANICO',
    };

String roleLabel(UserRole r) => switch (r) {
      UserRole.superAdmin => 'Administrador Master',
      UserRole.admin => 'Administrador',
      UserRole.gerente => 'Gerente',
      UserRole.caixa => 'Caixa',
      UserRole.operador => 'Operador',
      UserRole.mecanico => 'Mecânico',
    };

/// Dados de marca exibidos na tela de login (antes de autenticar).
class TenantBranding {
  const TenantBranding({required this.cnpj, required this.nomeFantasia, this.logoUrl, this.primaryColor});

  final String cnpj;
  final String nomeFantasia;
  final String? logoUrl;
  final String? primaryColor;

  factory TenantBranding.fromJson(Map<String, dynamic> j) => TenantBranding(
        cnpj: j['cnpj'] as String,
        nomeFantasia: (j['nomeFantasia'] ?? '') as String,
        logoUrl: j['logoUrl'] as String?,
        primaryColor: j['primaryColor'] as String?,
      );
}

class SessionUser {
  const SessionUser({required this.id, required this.username, required this.fullName, required this.role});

  final String id;
  final String username;
  final String fullName;
  final UserRole role;

  factory SessionUser.fromJson(Map<String, dynamic> j) => SessionUser(
        id: j['id'] as String,
        username: j['username'] as String,
        fullName: j['fullName'] as String,
        role: roleFromApi(j['role'] as String),
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'username': username, 'fullName': fullName, 'role': roleToApi(role)};
}

class SessionTenant {
  const SessionTenant({
    required this.id,
    required this.cnpj,
    required this.nomeFantasia,
    required this.razaoSocial,
    this.logoUrl,
    this.primaryColor,
    this.licenseExpiresAt,
    this.modules = const [],
  });

  final String id;
  final String cnpj;
  final String nomeFantasia;
  final String razaoSocial;
  final String? logoUrl;
  final String? primaryColor;
  final DateTime? licenseExpiresAt;

  /// Módulos contratados: PDV, PRODUTIVIDADE, FINANCEIRO, COMPRAS, BALANCA.
  final List<String> modules;

  factory SessionTenant.fromJson(Map<String, dynamic> j) => SessionTenant(
        id: j['id'] as String,
        cnpj: j['cnpj'] as String,
        nomeFantasia: (j['nomeFantasia'] ?? j['razaoSocial'] ?? '') as String,
        razaoSocial: (j['razaoSocial'] ?? '') as String,
        logoUrl: j['logoUrl'] as String?,
        primaryColor: j['primaryColor'] as String?,
        licenseExpiresAt: DateTime.tryParse('${j['licenseExpiresAt']}'),
        modules: [for (final m in (j['modules'] as List? ?? const [])) m.toString()],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'cnpj': cnpj,
        'nomeFantasia': nomeFantasia,
        'razaoSocial': razaoSocial,
        'logoUrl': logoUrl,
        'primaryColor': primaryColor,
        'licenseExpiresAt': licenseExpiresAt?.toIso8601String().substring(0, 10),
        'modules': modules,
      };

  SessionTenant copyWith({String? logoUrl, bool clearLogo = false, String? nomeFantasia, String? primaryColor}) =>
      SessionTenant(
        id: id,
        cnpj: cnpj,
        razaoSocial: razaoSocial,
        nomeFantasia: nomeFantasia ?? this.nomeFantasia,
        logoUrl: clearLogo ? null : (logoUrl ?? this.logoUrl),
        primaryColor: primaryColor ?? this.primaryColor,
        licenseExpiresAt: licenseExpiresAt,
        modules: modules,
      );
}

class Session {
  const Session({required this.token, required this.user, required this.tenant});

  final String token;
  final SessionUser user;
  final SessionTenant tenant;

  bool get isSuperAdmin => user.role == UserRole.superAdmin;
  bool get isManager => const {UserRole.admin, UserRole.gerente}.contains(user.role);
  bool hasModule(String m) => tenant.modules.contains(m);
  bool get canManageCompany => user.role == UserRole.admin || isSuperAdmin;
  bool get canSell => hasModule('PDV') && const {UserRole.admin, UserRole.gerente, UserRole.caixa}.contains(user.role);
  bool get canSeeProductivity =>
      hasModule('PRODUTIVIDADE') && const {UserRole.admin, UserRole.gerente, UserRole.operador}.contains(user.role);
  bool get canRecordProductivity => canSeeProductivity;
  bool get canUseFinance => hasModule('FINANCEIRO') && isManager;
  bool get canUsePurchases => hasModule('COMPRAS') && isManager;
  bool get canEditProducts => isManager;
  bool get canSeePartners => const {UserRole.admin, UserRole.gerente, UserRole.caixa}.contains(user.role);
  bool get canUseWorkshop => hasModule('OFICINA') && !isSuperAdmin;
  bool get canCloseWorkOrder => canUseWorkshop && const {UserRole.admin, UserRole.gerente, UserRole.caixa}.contains(user.role);
  bool get canManageUsers => user.role == UserRole.admin;

  /// Dias até vencer a licença (null para tenant sem data).
  int? get licenseDaysLeft {
    final d = tenant.licenseExpiresAt;
    if (d == null) return null;
    final today = DateTime.now();
    return DateTime(d.year, d.month, d.day).difference(DateTime(today.year, today.month, today.day)).inDays;
  }

  factory Session.fromJson(Map<String, dynamic> j) => Session(
        token: j['token'] as String,
        user: SessionUser.fromJson(j['user'] as Map<String, dynamic>),
        tenant: SessionTenant.fromJson(j['tenant'] as Map<String, dynamic>),
      );

  Map<String, dynamic> toJson() => {'token': token, 'user': user.toJson(), 'tenant': tenant.toJson()};

  Session copyWith({SessionTenant? tenant}) => Session(token: token, user: user, tenant: tenant ?? this.tenant);
}
