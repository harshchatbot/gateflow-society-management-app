import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../ui/app_colors.dart';

/// Lightweight bar chart showing visitor counts for the last 7 days.
/// [countsByDay] must have length 7: [day-6, day-5, ..., today].
/// Used on Guard (and optionally Admin) dashboard; no backend logic changes.
class VisitorsChart extends StatelessWidget {
  final List<int> countsByDay;
  final Color? barColor;

  const VisitorsChart({
    super.key,
    required this.countsByDay,
    this.barColor,
  }) : assert(countsByDay.length == 7, 'countsByDay must have 7 elements');

  @override
  Widget build(BuildContext context) {
    final color = barColor ?? AppColors.primary;
    final maxY = countsByDay.isEmpty
        ? 1.0
        : (countsByDay.reduce((a, b) => a > b ? a : b).toDouble() + 1).clamp(1.0, double.infinity);

    final barGroups = List.generate(7, (i) {
      final value = (i < countsByDay.length ? countsByDay[i] : 0).toDouble();
      return BarChartGroupData(
        x: i,
        barRods: [
          BarChartRodData(
            toY: value,
            color: color,
            width: 12,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          ),
        ],
        showingTooltipIndicators: [],
      );
    });

    final now = DateTime.now();
    final dayLabels = List.generate(7, (i) {
      final d = now.subtract(Duration(days: 6 - i));
      const week = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return week[d.weekday - 1];
    });

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border.withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 12),
            child: Text(
              'Visitors (last 7 days)',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppColors.text2,
              ),
            ),
          ),
          SizedBox(
            height: 160,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxY,
                barGroups: barGroups,
                groupsSpace: 8,
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final i = value.toInt();
                        if (i >= 0 && i < dayLabels.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              dayLabels[i],
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: AppColors.text2,
                              ),
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                      reservedSize: 24,
                      interval: 1,
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          value.toInt().toString(),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppColors.text2,
                          ),
                        );
                      },
                      interval: maxY > 5 ? (maxY / 5).ceilToDouble() : 1,
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: maxY > 5 ? (maxY / 5) : 1,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: AppColors.border.withOpacity(0.3),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => color.withOpacity(0.9),
                    tooltipRoundedRadius: 6,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final i = group.x;
                      final count = i < countsByDay.length ? countsByDay[i] : 0;
                      return BarTooltipItem(
                        '$count visitor${count == 1 ? '' : 's'}',
                        const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      );
                    },
                  ),
                ),
              ),
              duration: const Duration(milliseconds: 300),
            ),
          ),
        ],
      ),
    );
  }
}
