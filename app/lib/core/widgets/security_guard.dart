import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/session_controller.dart';
import '../../features/users/presentation/change_password_dialog.dart';

/// Camadas de segurança da tela logada:
/// • sai sozinho depois de [idle] sem mexer no app (computador do balcão esquecido aberto)
/// • obriga a trocar a senha provisória antes de usar o sistema
class SecurityGuard extends ConsumerStatefulWidget {
  const SecurityGuard({super.key, required this.child, this.idle = const Duration(minutes: 30)});
  final Widget child;
  final Duration idle;

  @override
  ConsumerState<SecurityGuard> createState() => _SecurityGuardState();
}

class _SecurityGuardState extends ConsumerState<SecurityGuard> with WidgetsBindingObserver {
  Timer? _timer;
  DateTime _last = DateTime.now();
  bool _askingPassword = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_onKey);
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _check());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(_onKey);
    _timer?.cancel();
    super.dispose();
  }

  bool _onKey(KeyEvent _) {
    _last = DateTime.now();
    return false; // não consome a tecla
  }

  // app voltou do segundo plano (celular): confere o tempo parado
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  void _check() {
    if (DateTime.now().difference(_last) >= widget.idle) {
      ref.read(sessionControllerProvider.notifier).expire('Sessão encerrada por inatividade (${widget.idle.inMinutes} min).');
    }
  }

  void _forcePasswordChange() {
    if (_askingPassword) return;
    _askingPassword = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await showChangePasswordDialog(context, forced: true);
      _askingPassword = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final mustChange = ref.watch(sessionControllerProvider.select((s) => s?.user.mustChangePassword ?? false));
    if (mustChange) _forcePasswordChange();
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _last = DateTime.now(),
      onPointerSignal: (_) => _last = DateTime.now(),
      child: widget.child,
    );
  }
}
