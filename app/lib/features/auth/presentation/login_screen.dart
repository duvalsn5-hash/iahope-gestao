import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/storage/session_storage.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../data/auth_repository.dart';
import '../domain/session.dart';
import 'session_controller.dart';

/// Login por CNPJ + usuário + senha.
/// Ao completar um CNPJ válido, busca e exibe a logo/nome da empresa (White-Label).
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _cnpj = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _userFocus = FocusNode();
  final _passFocus = FocusNode();

  TenantBranding? _branding;
  String? _brandingError;
  bool _loadingBranding = false;
  bool _submitting = false;
  bool _obscure = true;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    final last = ref.read(sessionStorageProvider).lastCnpj;
    if (last != null) {
      _cnpj.text = formatCnpj(last);
      _loadBranding(last);
      WidgetsBinding.instance.addPostFrameCallback((_) => _userFocus.requestFocus());
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final c in [_cnpj, _user, _pass]) {
      c.dispose();
    }
    _userFocus.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  void _onCnpjChanged(String v) {
    _debounce?.cancel();
    final d = onlyDigits(v);
    if (d.length < 14) {
      if (_branding != null || _brandingError != null) {
        setState(() {
          _branding = null;
          _brandingError = null;
        });
      }
      return;
    }
    if (!isValidCnpj(d)) {
      setState(() {
        _branding = null;
        _brandingError = 'CNPJ inválido';
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 250), () => _loadBranding(d));
  }

  Future<void> _loadBranding(String cnpj) async {
    setState(() {
        _loadingBranding = true;
        _brandingError = null;
      });
    try {
      final b = await ref.read(authRepositoryProvider).branding(cnpj);
      if (!mounted) return;
      setState(() => _branding = b);
      if (_user.text.isEmpty) _userFocus.requestFocus();
    } catch (e) {
      if (mounted) {
        setState(() {
          _branding = null;
          _brandingError = e.toString();
        });
      }
    } finally {
      if (mounted) setState(() => _loadingBranding = false);
    }
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      await ref.read(sessionControllerProvider.notifier).login(
            cnpj: _cnpj.text,
            username: _user.text,
            password: _pass.text,
          );
      // o router redireciona sozinho para a tela inicial do perfil
    } catch (e) {
      if (mounted) {
        showError(context, e);
        _pass.clear();
        _passFocus.requestFocus();
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final serverMessage = ref.watch(sessionMessageProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Card(
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Form(
                        key: _form,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _Header(branding: _branding, loading: _loadingBranding),
                            const SizedBox(height: 24),
                            if (serverMessage != null) ...[
                              MaterialBanner(
                                content: Text(serverMessage),
                                leading: const Icon(Icons.lock_outline),
                                backgroundColor: t.colorScheme.errorContainer,
                                actions: [
                                  TextButton(
                                    onPressed: () => ref.read(sessionMessageProvider.notifier).state = null,
                                    child: const Text('OK'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                            ],
                            TextFormField(
                              controller: _cnpj,
                              autofocus: _cnpj.text.isEmpty,
                              keyboardType: TextInputType.number,
                              inputFormatters: [CnpjInputFormatter()],
                              textInputAction: TextInputAction.next,
                              decoration: InputDecoration(
                                labelText: 'CNPJ da empresa',
                                hintText: '00.000.000/0000-00',
                                prefixIcon: const Icon(Icons.business),
                                errorText: _brandingError,
                              ),
                              onChanged: _onCnpjChanged,
                              onFieldSubmitted: (_) => _userFocus.requestFocus(),
                              validator: (v) => isValidCnpj(v ?? '') ? null : 'Informe um CNPJ válido',
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _user,
                              focusNode: _userFocus,
                              textInputAction: TextInputAction.next,
                              autofillHints: const [AutofillHints.username],
                              decoration: const InputDecoration(labelText: 'Usuário', prefixIcon: Icon(Icons.person)),
                              onFieldSubmitted: (_) => _passFocus.requestFocus(),
                              validator: (v) => (v ?? '').trim().isEmpty ? 'Informe o usuário' : null,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _pass,
                              focusNode: _passFocus,
                              obscureText: _obscure,
                              autofillHints: const [AutofillHints.password],
                              decoration: InputDecoration(
                                labelText: 'Senha',
                                prefixIcon: const Icon(Icons.lock),
                                suffixIcon: IconButton(
                                  icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                                  onPressed: () => setState(() => _obscure = !_obscure),
                                ),
                              ),
                              onFieldSubmitted: (_) => _submit(),
                              validator: (v) => (v ?? '').isEmpty ? 'Informe a senha' : null,
                            ),
                            const SizedBox(height: 24),
                            FilledButton.icon(
                              onPressed: _submitting ? null : _submit,
                              icon: _submitting
                                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.login),
                              label: const Text('Entrar'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const CreditsFooter(),
        ]),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.branding, required this.loading});
  final TenantBranding? branding;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: loading
          ? const SizedBox(key: ValueKey('l'), height: 120, child: Center(child: CircularProgressIndicator()))
          : branding != null
              ? Column(key: ValueKey(branding!.cnpj), children: [
                  CompanyLogo(url: branding!.logoUrl, name: branding!.nomeFantasia, size: 96),
                  const SizedBox(height: 12),
                  Text(branding!.nomeFantasia, style: t.textTheme.titleLarge, textAlign: TextAlign.center),
                  Text(formatCnpj(branding!.cnpj), style: t.textTheme.bodySmall),
                ])
              : Column(key: const ValueKey('default'), children: [
                  Icon(Icons.hub_outlined, size: 72, color: t.colorScheme.primary),
                  const SizedBox(height: 12),
                  Text(AppConfig.appName, style: t.textTheme.titleLarge),
                  Text('Operação · Logística · PDV', style: t.textTheme.bodySmall),
                ]),
    );
  }
}
