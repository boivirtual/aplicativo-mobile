import 'package:flutter/material.dart';

import '../config/api_config.dart';

/// Selo vermelho "TESTE" na barra do título, antes dos botões dela: só no
/// APK que aponta para o servidor de teste (ver ApiConfig); no de produção
/// não aparece nada. Já vem junto do IndicadorConectividadeWidget; nas
/// barras sem o indicador, entra direto nas actions.
class SeloTesteWidget extends StatelessWidget {
  const SeloTesteWidget({super.key});

  @override
  Widget build(BuildContext context) {
    if (!ApiConfig.ehTeste) return const SizedBox.shrink();
    return Center(
      child: Container(
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFFE53935),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Text(
          'TESTE',
          style: TextStyle(
            fontSize: 10,
            color: Colors.white,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
            height: 1.2,
          ),
        ),
      ),
    );
  }
}
