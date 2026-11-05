import 'package:flutter/material.dart';

import '../config/app_config.dart';

/// Breakpoints de layout: Android (compacto) x Windows/Web (amplo).
class Breakpoints {
  static const double medium = 700;
  static const double expanded = 1100;

  static bool isCompact(BuildContext c) => MediaQuery.sizeOf(c).width < medium;
  static bool isExpanded(BuildContext c) => MediaQuery.sizeOf(c).width >= expanded;
}

/// Logo da empresa (White-Label) com fallback para as iniciais.
class CompanyLogo extends StatelessWidget {
  const CompanyLogo({super.key, required this.url, required this.name, this.size = 48});

  final String? url;
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final initials = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2).map((w) => w[0]).join().toUpperCase();
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(size * .2)),
      child: Text(initials.isEmpty ? '?' : initials,
          style: TextStyle(fontSize: size * .38, fontWeight: FontWeight.bold, color: scheme.onPrimaryContainer)),
    );
    if (url == null || url!.isEmpty) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * .2),
      child: Image.network(
        url!,
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => fallback,
        loadingBuilder: (c, child, p) => p == null ? child : SizedBox(width: size, height: size),
      ),
    );
  }
}

/// Miniatura da foto do produto (ícone quando não há foto).
class ProductThumb extends StatelessWidget {
  const ProductThumb({super.key, required this.url, this.size = 40, this.icon = Icons.inventory_2_outlined});
  final String? url;
  final double size;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)),
      child: Icon(icon, size: size * .5, color: scheme.outline),
    );
    if (url == null || url!.isEmpty) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        url!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: (size * 3).round(),
        errorBuilder: (_, __, ___) => fallback,
        loadingBuilder: (c, child, p) => p == null ? child : SizedBox(width: size, height: size),
      ),
    );
  }
}

/// Crédito obrigatório em login, sobre e rodapé.
class CreditsFooter extends StatelessWidget {
  const CreditsFooter({super.key, this.dense = false});
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: dense ? 4 : 12, horizontal: 12),
      child: Text(
        AppConfig.credits,
        textAlign: TextAlign.center,
        style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
      ),
    );
  }
}

/// Bloco "chave: valor" usado nos cards de indicadores.
class KpiCard extends StatelessWidget {
  const KpiCard({super.key, required this.label, required this.value, this.icon, this.color, this.subtitle});

  final String label;
  final String value;
  final IconData? icon;
  final Color? color;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              if (icon != null) Icon(icon, size: 18, color: color ?? t.colorScheme.primary),
              if (icon != null) const SizedBox(width: 6),
              Expanded(child: Text(label, style: t.textTheme.labelMedium, overflow: TextOverflow.ellipsis)),
            ]),
            const SizedBox(height: 8),
            Text(value, style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: color)),
            if (subtitle != null) Text(subtitle!, style: t.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// Grade responsiva de cards: 2 colunas no celular, até [maxColumns] no desktop.
class ResponsiveGrid extends StatelessWidget {
  const ResponsiveGrid({super.key, required this.children, this.maxColumns = 4, this.spacing = 12});

  final List<Widget> children;
  final int maxColumns;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final cols = (c.maxWidth / 220).floor().clamp(2, maxColumns).toInt();
      final w = (c.maxWidth - spacing * (cols - 1)) / cols;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [for (final child in children) SizedBox(width: w, child: child)],
      );
    });
  }
}

void showError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(error.toString()),
      backgroundColor: Theme.of(context).colorScheme.error,
      behavior: SnackBarBehavior.floating,
    ));
}

void showOk(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
}
