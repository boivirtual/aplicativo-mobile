import 'package:flutter/material.dart';
import '../services/sync_service.dart';

/// Aviso central de "Sincronizando dados..." — some sozinho quando a
/// sincronização termina. Pílula sólida com sombra leve (fundo transparente
/// puro não tinha contraste suficiente pra ler em cima de qualquer
/// conteúdo). Não bloqueia toque na tela.
class IndicadorSincronizandoWidget extends StatelessWidget {
  const IndicadorSincronizandoWidget({super.key});

  static const _corTexto = Color(0xFF18385F);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: SyncService.instance.sincronizando,
      builder: (context, sincronizando, _) {
        if (!sincronizando) return const SizedBox.shrink();

        return IgnorePointer(
          child: Align(
            alignment: const Alignment(0, -0.6),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: _corTexto,
                    ),
                  ),
                  SizedBox(width: 10),
                  Text(
                    "Sincronizando dados...",
                    style: TextStyle(
                      color: _corTexto,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
