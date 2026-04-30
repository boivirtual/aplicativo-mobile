import 'package:flutter/material.dart';

class ResumoPesagemWidget extends StatelessWidget {
  final int qtdPesado;
  final int pesoTotal;

  const ResumoPesagemWidget({
    super.key,
    required this.qtdPesado,
    required this.pesoTotal,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            "Animais Pesados: $qtdPesado",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.blue[300],
            ),
          ),
          Text(
            "Peso Total: $pesoTotal Kg",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.blue[300],
            ),
          ),
        ],
      ),
    );
  }
}
