import 'package:flutter/material.dart';
import '../services/sync_service.dart';

/// Aviso central e discreto de "Sincronizando dados..." — some sozinho
/// quando a sincronização termina. Não bloqueia toques na tela (não tem
/// barreira por trás), então não atrapalha quem estiver digitando enquanto
/// isso acontece em segundo plano.
class IndicadorSincronizandoWidget extends StatelessWidget {
  const IndicadorSincronizandoWidget({super.key});

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
                horizontal: 20,
                vertical: 14,
              ),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(width: 12),
                  Text(
                    "Sincronizando dados...",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
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
