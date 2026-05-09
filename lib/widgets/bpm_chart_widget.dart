import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/practice_session.dart';

class BpmChartWidget extends StatelessWidget {
  final List<PracticeSession> sessions;

  const BpmChartWidget({super.key, required this.sessions});

  @override
  Widget build(BuildContext context) {
    if (sessions.isEmpty) {
      return Center(
        child: Text(
          'Nenhuma sessão registrada',
          style: TextStyle(color: Colors.grey[500]),
        ),
      );
    }

    final reversed = sessions.reversed.toList();
    final spots = <FlSpot>[];
    for (int i = 0; i < reversed.length; i++) {
      spots.add(FlSpot(i.toDouble(), reversed[i].finalBPM.toDouble()));
    }

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          horizontalInterval: 20,
          getDrawingHorizontalLine: (value) => FlLine(
            color: Colors.brown.withValues(alpha: 0.1),
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) => Text(
                '${value.toInt()}',
                style: TextStyle(fontSize: 10, color: Colors.grey[600]),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                if (idx < 0 || idx >= reversed.length) return const SizedBox();
                final date = reversed[idx].date;
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${date.day}/${date.month}',
                    style: TextStyle(fontSize: 8, color: Colors.grey[600]),
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        minX: 0,
        maxX: (spots.length - 1).toDouble(),
        minY: 0,
        maxY: 200,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: Colors.green,
            barWidth: 3,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) =>
                FlDotCirclePainter(
                  radius: 4,
                  color: Colors.green,
                  strokeWidth: 2,
                  strokeColor: Colors.white,
                ),
            ),
            belowBarData: BarAreaData(
              show: true,
              color: Colors.green.withValues(alpha: 0.1),
            ),
          ),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touchedSpots) => touchedSpots.map((spot) {
              final session = reversed[spot.spotIndex];
              return LineTooltipItem(
                '${spot.y.toInt()} BPM\n${session.date.day}/${session.date.month}',
                TextStyle(color: Colors.white, fontSize: 12),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}
