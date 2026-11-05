import 'package:flutter/material.dart';

import 'business_category.dart';

/// Cartões para escolher o ramo de negócio (um toque).
class BusinessCategoryPicker extends StatelessWidget {
  const BusinessCategoryPicker({super.key, required this.selected, required this.onSelected});
  final String selected;
  final ValueChanged<BusinessCategory> onSelected;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return LayoutBuilder(builder: (context, box) {
      final cols = box.maxWidth >= 460 ? 2 : 1;
      final w = (box.maxWidth - (cols - 1) * 8) / cols;
      return Wrap(spacing: 8, runSpacing: 8, children: [
        for (final c in kBusinessCategories)
          SizedBox(
            width: w,
            child: _Card(
              c: c,
              selected: c.code == selected,
              onTap: () => onSelected(c),
              theme: t,
            ),
          ),
      ]);
    });
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.c, required this.selected, required this.onTap, required this.theme});
  final BusinessCategory c;
  final bool selected;
  final VoidCallback onTap;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final cs = theme.colorScheme;
    return Material(
      color: selected ? cs.primaryContainer : cs.surfaceContainerHighest.withValues(alpha: .5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: selected ? cs.primary : Colors.transparent, width: 2),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(c.icon, color: selected ? cs.primary : cs.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.label, style: theme.textTheme.titleSmall),
                Text(c.description, style: theme.textTheme.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
              ]),
            ),
            if (selected) Icon(Icons.check_circle, size: 18, color: cs.primary),
          ]),
        ),
      ),
    );
  }
}

/// Selo pequeno com ícone + nome do ramo (listas do Master, tela Empresa).
class BusinessCategoryBadge extends StatelessWidget {
  const BusinessCategoryBadge(this.category, {super.key});
  final BusinessCategory category;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: cs.secondaryContainer, borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(category.icon, size: 14, color: cs.onSecondaryContainer),
        const SizedBox(width: 4),
        Text(category.label, style: TextStyle(fontSize: 12, color: cs.onSecondaryContainer)),
      ]),
    );
  }
}
