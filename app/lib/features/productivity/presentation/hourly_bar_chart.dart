import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/utils/formatters.dart';
import '../domain/productivity.dart';

/// Gráfico de colunas hora a hora com marcador de meta.
/// Feito com widgets puros (sem dependências) → idêntico em Android, Windows e Web.
/// Cores: verde ≥ meta · âmbar ≥ 80% · vermelho < 80% · cor da marca sem meta.
class HourlyBarChart extends StatelessWidget {
  const HourlyBarChart({super.key, required this.hours, this.height = 240, this.highlightHour});

  final List<HourPoint> hours;
  final double height;
  final int? highlightHour;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final active = hours.where((h) => h.volumes > 0 || h.target > 0).map((h) => h.hour);
    final from = math.min(6, active.isEmpty ? 6 : active.reduce(math.min));
    final to = math.max(22, active.isEmpty ? 22 : active.reduce(math.max));
    final visible = hours.where((h) => h.hour >= from && h.hour <= to).toList();
    final maxY = visible.fold<int>(1, (m, h) => math.max(m, math.max(h.volumes, h.target))).toDouble();

    Color colorFor(HourPoint h) {
      if (h.target <= 0) return t.colorScheme.primary;
      final pct = h.volumes / h.target;
      if (pct >= 1) return Colors.green.shade600;
      if (pct >= .8) return Colors.amber.shade700;
      return t.colorScheme.error;
    }

    return LayoutBuilder(builder: (context, c) {
      const minBarSlot = 28.0;
      final slot = math.max(minBarSlot, c.maxWidth / visible.length);
      final chartWidth = slot * visible.length;
      final plotH = height - 40;

      final chart = SizedBox(
        width: chartWidth,
        height: height,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final h in visible)
              SizedBox(
                width: slot,
                child: Tooltip(
                  message: '${h.hour.toString().padLeft(2, '0')}h — ${number(h.volumes)} vol'
                      '${h.target > 0 ? ' / meta ${number(h.target)}' : ''}'
                      '\n${number(h.weightKg)} kg · ${h.pallets} pallets · equipe ${h.team}',
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (h.volumes > 0)
                        Text(number(h.volumes), style: t.textTheme.labelSmall, maxLines: 1, overflow: TextOverflow.visible),
                      SizedBox(
                        height: plotH - 16,
                        child: Stack(
                          alignment: Alignment.bottomCenter,
                          clipBehavior: Clip.none,
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 400),
                              curve: Curves.easeOut,
                              width: slot * .62,
                              height: (plotH - 16) * (h.volumes / maxY),
                              decoration: BoxDecoration(
                                color: colorFor(h).withValues(alpha: h.hour == highlightHour ? 1 : .85),
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                                border: h.hour == highlightHour ? Border.all(color: t.colorScheme.onSurface, width: 1.5) : null,
                              ),
                            ),
                            if (h.target > 0)
                              Positioned(
                                bottom: (plotH - 16) * (h.target / maxY) - 1,
                                child: Container(width: slot * .85, height: 2, color: t.colorScheme.onSurface.withValues(alpha: .6)),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${h.hour.toString().padLeft(2, '0')}h',
                        style: t.textTheme.labelSmall?.copyWith(
                          fontWeight: h.hour == highlightHour ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );

      return chartWidth > c.maxWidth
          ? SingleChildScrollView(scrollDirection: Axis.horizontal, reverse: true, child: chart)
          : chart;
    });
  }
}
