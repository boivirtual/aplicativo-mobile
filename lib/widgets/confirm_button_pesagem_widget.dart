import 'package:flutter/material.dart';

class ConfirmButtonPesagemWidget extends StatelessWidget {
  final int? indexSendoEditado;
  final VoidCallback onConfirmar;
  final VoidCallback onVoltar;
  final bool carregando;

  const ConfirmButtonPesagemWidget({
    super.key,
    required this.indexSendoEditado,
    required this.onConfirmar,
    required this.onVoltar,
    this.carregando = false,
  });

  @override
  Widget build(BuildContext context) {
    Widget loadingWidget() {
      return const SizedBox(
        height: 24,
        width: 24,
        child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
      );
    }

    return SizedBox(
      width: double.infinity,
      height: 54,
      child: indexSendoEditado == null
          ? ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4CAF50),
                disabledBackgroundColor: const Color(0xFF4CAF50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: carregando ? null : onConfirmar,
              child: carregando
                  ? loadingWidget()
                  : const Text(
                      "Confirma",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            )
          : Row(
              children: [
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4CAF50),
                      disabledBackgroundColor: const Color(0xFF4CAF50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: carregando ? null : onConfirmar,
                    child: carregando
                        ? loadingWidget()
                        : const Text(
                            "Atualizar",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 1,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4BBAEB),
                      disabledBackgroundColor: const Color(0xFF4BBAEB),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: carregando ? null : onVoltar,
                    child: const Text(
                      "Voltar",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
