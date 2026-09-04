import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// Gráfico de "mm Chuva x Dias Chuvosos" da tela de Chuva — mesma
/// informação dos dois gráficos da home do sistema web
/// (form_lista_registro_chuva_rel_dashboard.php: barras de precipitação +
/// linha de dias chuvosos), só que como dois mini-gráficos empilhados em
/// vez de sobrepostos com eixo duplo — mais legível em tela de celular e
/// sem depender de alinhamento pixel-a-pixel entre dois widgets
/// independentes.
class GraficoChuvaWidget extends StatelessWidget {
  final String titulo;
  final List<String> rotulos;
  final List<double> mm;
  final List<double> dias;

  const GraficoChuvaWidget({
    super.key,
    required this.titulo,
    required this.rotulos,
    required this.mm,
    required this.dias,
  });

  static const _azulEscuro = Color(0xFF18385F);
  static const _corBarra = Color(0xFFB9C6E8);
  static const _corLinha = Color(0xFFE05252);

  double _tetoAgradavel(double valor, List<double> passos) {
    if (valor <= 0) return passos.first;
    for (final p in passos) {
      if (valor <= p) return p;
    }
    return (valor * 1.2).ceilToDouble();
  }

  @override
  Widget build(BuildContext context) {
    final maxMm = mm.fold<double>(0, (p, v) => v > p ? v : p);
    final maxDias = dias.fold<double>(0, (p, v) => v > p ? v : p);
    final tetoMm = _tetoAgradavel(maxMm, const [10, 20, 30, 50, 75, 100, 150, 200, 300, 400, 500, 750, 1000, 1500, 2000, 3000]);
    final tetoDias = _tetoAgradavel(maxDias, const [5, 10, 15, 20, 25, 31]);

    Widget rotuloEixoX(double valor, TitleMeta meta) {
      final i = valor.round();
      if (i < 0 || i >= rotulos.length) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          rotulos[i],
          style: const TextStyle(fontSize: 10, color: Colors.grey),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 16, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: _azulEscuro,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: const [
              _ItemLegenda(cor: _corBarra, formato: _FormatoLegenda.quadrado, texto: 'mm Chuva'),
              SizedBox(width: 16),
              _ItemLegenda(cor: _corLinha, formato: _FormatoLegenda.linha, texto: 'Dias Chuvosos'),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 130,
            child: BarChart(
              BarChartData(
                maxY: tetoMm,
                minY: 0,
                barTouchData: BarTouchData(enabled: false),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: tetoMm / 4,
                  getDrawingHorizontalLine: (_) =>
                      const FlLine(color: Color(0xFFEEEEEE), strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: true, reservedSize: 26, getTitlesWidget: rotuloEixoX),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 34,
                      getTitlesWidget: (v, meta) => Text(
                        v.toInt().toString(),
                        style: const TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                    ),
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < mm.length; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: mm[i],
                          color: _corBarra,
                          width: mm.length > 6 ? 12 : 22,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 90,
            child: LineChart(
              LineChartData(
                minX: -0.5,
                maxX: mm.length - 0.5,
                minY: 0,
                maxY: tetoDias,
                lineTouchData: const LineTouchData(enabled: false),
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: true, reservedSize: 26, getTitlesWidget: rotuloEixoX),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 34,
                      interval: tetoDias / 4 <= 0 ? 1 : tetoDias / 4,
                      getTitlesWidget: (v, meta) => Text(
                        v.toInt().toString(),
                        style: const TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                    ),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: [for (var i = 0; i < dias.length; i++) FlSpot(i.toDouble(), dias[i])],
                    isCurved: false,
                    color: _corLinha,
                    barWidth: 2,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, pct, bar, index) =>
                          FlDotCirclePainter(radius: 2.5, color: _corLinha, strokeWidth: 0),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _FormatoLegenda { quadrado, linha }

class _ItemLegenda extends StatelessWidget {
  final Color cor;
  final _FormatoLegenda formato;
  final String texto;

  const _ItemLegenda({required this.cor, required this.formato, required this.texto});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (formato == _FormatoLegenda.quadrado)
          Container(width: 10, height: 10, color: cor)
        else
          Container(width: 14, height: 2, color: cor),
        const SizedBox(width: 6),
        Text(texto, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }
}
