import 'package:flutter/material.dart';
import '../services/sync_service.dart';

/// Aviso central de "Sincronizando dados..." — some sozinho quando a
/// sincronização termina. Fundo totalmente transparente (sem caixa/cor por
/// trás) e sem bloquear toque na tela, então não atrapalha quem estiver
/// digitando enquanto isso acontece em segundo plano.
class IndicadorSincronizandoWidget extends StatelessWidget {
  const IndicadorSincronizandoWidget({super.key});

  static const _corTexto = Color(0xFF18385F);
  static const _sombraLegibilidade = [
    Shadow(color: Colors.white, blurRadius: 6),
  ];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: SyncService.instance.sincronizando,
      builder: (context, sincronizando, _) {
        if (!sincronizando) return const SizedBox.shrink();

        return const IgnorePointer(
          child: Align(
            alignment: Alignment(0, -0.5),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 30,
                  height: 30,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: _corTexto,
                  ),
                ),
                SizedBox(height: 10),
                Text(
                  "Sincronizando dados...",
                  style: TextStyle(
                    color: _corTexto,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    shadows: _sombraLegibilidade,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
