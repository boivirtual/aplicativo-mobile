import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/api_config.dart';

/// Tarja vermelha "TESTE" na barra do título, antes dos botões dela: uma
/// faixa na diagonal que encosta em cima e embaixo da barra. Só no APK que
/// aponta para o servidor de teste (ver ApiConfig); no de produção não
/// aparece nada. Já vem junto do IndicadorConectividadeWidget; nas barras
/// sem o indicador, entra direto nas actions.
class SeloTesteWidget extends StatelessWidget {
  const SeloTesteWidget({super.key});

  /// Largura que a tarja ocupa na barra e largura da faixa (na horizontal).
  static const _largura = 46.0;
  static const _faixa = 20.0;

  @override
  Widget build(BuildContext context) {
    if (!ApiConfig.ehTeste) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, c) {
        // altura da barra (a tarja vai de borda a borda)
        final altura = c.maxHeight.isFinite ? c.maxHeight : kToolbarHeight;
        // inclinação da faixa: do canto de cima à esquerda até o de baixo
        // à direita
        final angulo = math.atan2(altura, _largura - _faixa);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: SizedBox(
            width: _largura,
            height: altura,
            child: ClipPath(
              clipper: _Faixa(_faixa),
              child: ColoredBox(
                color: const Color(0xFFE53935),
                child: Center(
                  child: Transform.rotate(
                    angle: angulo,
                    child: const Text(
                      'TESTE',
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.visible,
                      style: TextStyle(
                        fontSize: 9,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                        height: 1,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Paralelogramo: em cima, do começo até [faixa]; embaixo, do fim menos
/// [faixa] até o fim.
class _Faixa extends CustomClipper<Path> {
  final double faixa;
  const _Faixa(this.faixa);

  @override
  Path getClip(Size s) => Path()
    ..moveTo(0, 0)
    ..lineTo(faixa, 0)
    ..lineTo(s.width, s.height)
    ..lineTo(s.width - faixa, s.height)
    ..close();

  @override
  bool shouldReclip(_Faixa antigo) => antigo.faixa != faixa;
}
