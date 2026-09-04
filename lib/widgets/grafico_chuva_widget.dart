import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// Gráfico de "mm Chuva x Dias Chuvosos" — barras e linha no MESMO
/// gráfico (2 eixos, igual à home do sistema web), com tooltip ao tocar.
///
/// Técnica: dois widgets do fl_chart (BarChart + LineChart) sobrepostos
/// num Stack, com titlesData configurado pra reservar o MESMO espaço nas
/// bordas dos dois — assim a área de plotagem fica pixel-a-pixel igual e a
/// linha cai exatamente por cima das barras. A camada da linha fica com
/// `IgnorePointer` (só visual); quem responde ao toque é a camada de
/// barras, com um tooltip único mostrando mm e dias chuvosos juntos — no
/// celular, acertar o toque bem em cima da bolinha da linha (como no mouse
/// do navegador) não é confiável, então um toque em qualquer parte da
/// coluna já mostra as duas informações.
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
  static const _azulBarraTopo = Color(0xFF6FA8F5);
  static const _azulBarraBase = Color(0xFF2F6FD9);
  static const _corLinha = Color(0xFFE05252);
  static const _alturaGrafico = 220.0;
  static const _reservadoEsquerda = 36.0;
  static const _reservadoDireita = 34.0;
  static const _reservadoBaixo = 26.0;

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
    final tetoMm = _tetoAgradavel(maxMm, const [
      10, 20, 30, 50, 75, 100, 150, 200, 300, 400, 500, 750, 1000, 1500, 2000, 3000,
    ]);
    final tetoDias = _tetoAgradavel(maxDias, const [5, 10, 15, 20, 25, 31]);
    final largBarra = mm.length > 6 ? 14.0 : 24.0;

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

    Widget rotuloOculto(double valor, TitleMeta meta) => const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 12, 10),
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
          const SizedBox(height: 4),
          const Text(
            'Toque numa coluna para ver os valores',
            style: TextStyle(fontSize: 10, color: Colors.grey),
          ),
          const SizedBox(height: 10),
          const Row(
            children: [
              _ItemLegenda(cor: _azulBarraBase, formato: _FormatoLegenda.quadrado, texto: 'mm Chuva'),
              SizedBox(width: 16),
              _ItemLegenda(cor: _corLinha, formato: _FormatoLegenda.linha, texto: 'Dias Chuvosos'),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: _alturaGrafico,
            child: Stack(
              children: [
                // Camada de baixo: as barras — é ela quem responde ao toque.
                BarChart(
                  BarChartData(
                    maxY: tetoMm,
                    minY: 0,
                    // spaceEvenly (não spaceBetween): cada categoria fica
                    // dona de uma "fatia" igual da largura, com a barra
                    // centralizada nela — é exatamente essa mesma divisão
                    // (fatia i vai de i a i+1) que o LineChart de cima usa
                    // (minX:-0.5, maxX:n-0.5), então os dois batem.
                    alignment: BarChartAlignment.spaceEvenly,
                    barTouchData: BarTouchData(
                      enabled: true,
                      touchTooltipData: BarTouchTooltipData(
                        getTooltipColor: (_) => _azulEscuro,
                        tooltipRoundedRadius: 8,
                        getTooltipItem: (group, groupIndex, rod, rodIndex) {
                          final diasValor = groupIndex < dias.length
                              ? dias[groupIndex].toStringAsFixed(0)
                              : '0';
                          final rotulo = groupIndex < rotulos.length
                              ? rotulos[groupIndex]
                              : '';
                          return BarTooltipItem(
                            '$rotulo\n',
                            const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                            children: [
                              TextSpan(
                                text: 'mm Chuva: ${rod.toY.toStringAsFixed(0)}\n',
                                style: const TextStyle(color: Colors.white, fontSize: 11),
                              ),
                              TextSpan(
                                text: 'Dias Chuvosos: $diasValor',
                                style: const TextStyle(color: Colors.white, fontSize: 11),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
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
                      rightTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: _reservadoDireita,
                          getTitlesWidget: rotuloOculto,
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: _reservadoBaixo,
                          getTitlesWidget: rotuloEixoX,
                        ),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: _reservadoEsquerda,
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
                              width: largBarra,
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                              gradient: const LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [_azulBarraTopo, _azulBarraBase],
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                // "Pele" 3D das barras — o fl_chart não desenha faces
                // laterais nem brilho de topo (BarChartRodData não tem
                // sombra/relevo nativo), então desenhamos por cima, na
                // mesma posição/altura de cada barra: uma tira clara no
                // topo (luz batendo) e uma tira escura na lateral direita
                // (sombra), pra ler como um prisma em vez de um retângulo
                // chapado. Só visual — IgnorePointer pra não atrapalhar o
                // toque que já funciona na camada de baixo.
                IgnorePointer(
                  child: Padding(
                    padding: const EdgeInsets.only(
                      left: _reservadoEsquerda,
                      right: _reservadoDireita,
                      bottom: _reservadoBaixo,
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final n = mm.length;
                        if (n == 0 || constraints.maxWidth <= 0) {
                          return const SizedBox.shrink();
                        }
                        final fatia = constraints.maxWidth / n;
                        final alturaPlot = constraints.maxHeight;
                        return Stack(
                          children: [
                            for (var i = 0; i < n; i++)
                              if (mm[i] > 0)
                                Builder(builder: (context) {
                                  final altura =
                                      ((mm[i] / tetoMm).clamp(0.0, 1.0)) * alturaPlot;
                                  final esquerda = i * fatia + fatia / 2 - largBarra / 2;
                                  return Positioned(
                                    left: esquerda,
                                    bottom: 0,
                                    width: largBarra,
                                    height: altura,
                                    child: Stack(
                                      children: [
                                        // face lateral direita, mais escura
                                        Positioned(
                                          right: 0,
                                          top: 3,
                                          bottom: 0,
                                          width: 3,
                                          child: Container(
                                            color: const Color(0xFF1F4FA8).withValues(alpha: 0.55),
                                          ),
                                        ),
                                        // brilho no topo
                                        Positioned(
                                          left: 0,
                                          right: 0,
                                          top: 0,
                                          height: 3,
                                          child: Container(
                                            decoration: BoxDecoration(
                                              color: Colors.white.withValues(alpha: 0.65),
                                              borderRadius: const BorderRadius.vertical(
                                                top: Radius.circular(4),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                          ],
                        );
                      },
                    ),
                  ),
                ),
                // Camada de cima: só a linha (visual) — não recebe toque,
                // pra não disputar o gesto com as barras.
                IgnorePointer(
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
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: _reservadoBaixo,
                            getTitlesWidget: rotuloOculto,
                          ),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: _reservadoEsquerda,
                            getTitlesWidget: rotuloOculto,
                          ),
                        ),
                        rightTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: _reservadoDireita,
                            interval: tetoDias / 4 <= 0 ? 1 : tetoDias / 4,
                            getTitlesWidget: (v, meta) => Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: Text(
                                v.toInt().toString(),
                                style: const TextStyle(fontSize: 10, color: _corLinha),
                              ),
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
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: cor, borderRadius: BorderRadius.circular(2)),
          )
        else
          Container(width: 14, height: 2, color: cor),
        const SizedBox(width: 6),
        Text(texto, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }
}
