import '../../auth/domain/session.dart';

class AppUser {
  const AppUser({
    required this.id,
    required this.fullName,
    this.username,
    this.email,
    required this.role,
    this.isActive = true,
    this.commissionPct = 0,
    this.lastLoginAt,
  });

  final String id;
  final String fullName;
  final String? username;
  final String? email;
  final UserRole role;
  final bool isActive;
  final double commissionPct;
  final DateTime? lastLoginAt;

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: j['id'] as String,
        fullName: j['fullName'] as String,
        username: j['username'] as String?,
        email: j['email'] as String?,
        role: roleFromApi(j['role'] as String),
        isActive: j['isActive'] as bool? ?? true,
        commissionPct: (j['commissionPct'] as num? ?? 0).toDouble(),
        lastLoginAt: DateTime.tryParse('${j['lastLoginAt']}'),
      );
}

class UsersPage {
  const UsersPage({required this.users, required this.maxUsers, required this.activeCount});
  final List<AppUser> users;
  final int maxUsers;
  final int activeCount;

  factory UsersPage.fromJson(Map<String, dynamic> j) => UsersPage(
        users: [for (final u in j['users'] as List) AppUser.fromJson(u as Map<String, dynamic>)],
        maxUsers: (j['maxUsers'] as num? ?? 0).toInt(),
        activeCount: (j['activeCount'] as num? ?? 0).toInt(),
      );
}

/// Perfis que o administrador da empresa pode dar.
const kAssignableRoles = [UserRole.admin, UserRole.gerente, UserRole.caixa, UserRole.mecanico, UserRole.operador];

String roleHelp(UserRole r) => switch (r) {
      UserRole.admin => 'Tudo da empresa: usuários, logo, cadastros, financeiro',
      UserRole.gerente => 'Cadastros, financeiro, compras, cancelamentos',
      UserRole.caixa => 'PDV, caixa, clientes e fechamento de OS',
      UserRole.mecanico => 'Só a oficina: vê e atualiza as OS dele',
      UserRole.operador => 'Produtividade logística e estoque',
      UserRole.superAdmin => 'Administrador da plataforma',
    };
