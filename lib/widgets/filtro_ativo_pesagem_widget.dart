import 'package:flutter/material.dart';

class FiltroAtivoPesagemWidget extends StatelessWidget {
  final String nomeFazenda;
  final String nomeMotivo;
  final String descricaoLote;
  final String qtdAPesar;
  final bool itensPesadosVazio;
  final VoidCallback onEditarTap;

  const FiltroAtivoPesagemWidget({
    super.key,
    required this.nomeFazenda,
    required this.nomeMotivo,
    required this.descricaoLote,
    required this.qtdAPesar,
    required this.itensPesadosVazio,
    required this.onEditarTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "$nomeFazenda ➔ $nomeMotivo",
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.blue,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  "Lote: $descricaoLote  |  Qtde a Pesar: $qtdAPesar",
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.blue,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onEditarTap,
            icon: const Icon(Icons.edit_note, color: Colors.blue, size: 22),
            tooltip: 'Editar pesagem',
          ),
        ],
      ),
    );
  }
}
