import 'package:flutter/material.dart';
import 'package:boivirtual/widgets/input_minimal_pesagem_widget.dart';

class ObservacaoTogglePesagemWidget extends StatelessWidget {
  final Widget campoApartacao;
  final bool mostrarObs;
  final bool habilitado;
  final TextEditingController obsController;
  final FocusNode focoNaObs;
  final Color corDoRotulo;
  final VoidCallback onToggleObs;

  const ObservacaoTogglePesagemWidget({
    super.key,
    required this.campoApartacao,
    required this.mostrarObs,
    required this.habilitado,
    required this.obsController,
    required this.focoNaObs,
    required this.corDoRotulo,
    required this.onToggleObs,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(child: campoApartacao),
              if (mostrarObs) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: IgnorePointer(
                    ignoring: !habilitado,
                    child: Opacity(
                      opacity: habilitado ? 1.0 : 0.65,
                      child: InputMinimalPesagemWidget(
                        label: "Observação",
                        controller: obsController,
                        focusNode: focoNaObs,
                        containerHeight: 80,
                        corDoRotulo: habilitado ? corDoRotulo : Colors.grey,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 5),
        IconButton(
          icon: Icon(
            Icons.comment_outlined,
            color: !habilitado
                ? Colors.grey[400]
                : (mostrarObs ? Colors.blue : Colors.grey),
          ),
          onPressed: habilitado ? onToggleObs : null,
        ),
      ],
    );
  }
}
