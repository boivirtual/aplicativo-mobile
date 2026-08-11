import 'package:flutter/material.dart';

/// Teclado numérico customizado pro campo Peso — desenhado do zero em vez
/// de usar o teclado do sistema, pra ficar idêntico no Android e no iOS e
/// pra permitir digitar fórmula (+, -, =) sem precisar trocar de layout de
/// teclado no meio da digitação. Botões grandes de propósito (uso no
/// curral, com a mão suja ou de luva).
class TecladoPesoWidget extends StatelessWidget {
  final void Function(String caractere) onCaractere;
  final VoidCallback onApagar;
  final VoidCallback onConfirmar;

  const TecladoPesoWidget({
    super.key,
    required this.onCaractere,
    required this.onApagar,
    required this.onConfirmar,
  });

  static const _corOperador = Color(0xFF185FA5);
  static const _fundoOperador = Color(0xFFE6F1FB);
  static const _corDigito = Color(0xFF2C2C2A);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _botaoDigito('1'),
              _botaoDigito('2'),
              _botaoDigito('3'),
              _botaoOperador('+'),
            ],
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              _botaoDigito('4'),
              _botaoDigito('5'),
              _botaoDigito('6'),
              _botaoOperador('-'),
            ],
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              _botaoDigito('7'),
              _botaoDigito('8'),
              _botaoDigito('9'),
              _botaoOperador('='),
            ],
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              _botaoDigito(','),
              _botaoDigito('0'),
              _botaoApagar(),
              _botaoConfirmar(),
            ],
          ),
        ],
      ),
    );
  }

  // Altura enxuta de propósito: esse teclado divide a tela com o
  // formulário inteiro (nº do animal, peso, apartação, ficha do animal,
  // botão Confirma) — uma altura maior estourava o layout (RenderFlex
  // overflow) em telas menores. Largura continua generosa (cada botão
  // ocupa 1/4 da largura da tela), que é o que mais importa pra acertar
  // o toque com a mão suja/luva.
  Widget _celula({required Widget child}) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: SizedBox(height: 42, child: child),
      ),
    );
  }

  Widget _botaoDigito(String texto) {
    return _celula(
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => onCaractere(texto),
          child: Center(
            child: Text(
              texto,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w500,
                color: _corDigito,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _botaoOperador(String texto) {
    return _celula(
      child: Material(
        color: _fundoOperador,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => onCaractere(texto),
          child: Center(
            child: Text(
              texto,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: _corOperador,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _botaoApagar() {
    return _celula(
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onApagar,
          child: const Center(
            child: Icon(Icons.backspace_outlined, size: 22, color: Colors.grey),
          ),
        ),
      ),
    );
  }

  Widget _botaoConfirmar() {
    return _celula(
      child: Material(
        color: Colors.blue,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onConfirmar,
          child: const Center(
            child: Text(
              "OK",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
