import 'package:flutter/material.dart';

/// Teclado numérico customizado — desenhado do zero em vez de usar o
/// teclado do sistema, pra ficar idêntico no Android e no iOS. Usado no
/// campo Peso (com fórmula: +, -, =, vírgula) e também no Nº do Animal
/// (apenas dígitos, via [mostrarOperadores] = false). Botões grandes de
/// propósito (uso no curral, com a mão suja ou de luva).
class TecladoPesoWidget extends StatelessWidget {
  final void Function(String caractere) onCaractere;
  final VoidCallback onApagar;
  final VoidCallback onConfirmar;
  final bool mostrarOperadores;

  /// Fecha o teclado sem confirmar nem cancelar nada — só tira o foco do
  /// campo. Pedido do George: começar a digitar um número, mudar de ideia
  /// (ex: quer editar um item que ficou escondido embaixo do teclado) e não
  /// ter um jeito óbvio de simplesmente esconder o teclado sem precisar
  /// digitar algo primeiro. `null` esconde o botão (uso opcional).
  final VoidCallback? onFechar;

  const TecladoPesoWidget({
    super.key,
    required this.onCaractere,
    required this.onApagar,
    required this.onConfirmar,
    this.mostrarOperadores = true,
    this.onFechar,
  });

  static const _corOperador = Color(0xFF185FA5);
  static const _fundoOperador = Color(0xFFE6F1FB);
  static const _corDigito = Color(0xFF2C2C2A);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onFechar != null) _linhaFechar(),
          ...mostrarOperadores ? _linhasComOperadores() : _linhasApenasDigitos(),
        ],
      ),
    );
  }

  /// Linha fininha só com o botão de fechar, acima da grade de dígitos —
  /// não some espaço dos botões grandes, só ocupa uma tira estreita em
  /// cima.
  Widget _linhaFechar() {
    return Align(
      alignment: Alignment.centerRight,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onFechar,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.keyboard_hide_outlined, size: 18, color: Colors.grey),
              SizedBox(width: 4),
              Text(
                "Fechar",
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Espaço bem enxuto entre linhas de propósito: é área "morta" de verdade
  // (não pertence a nenhum botão) — diferente do espaço entre botões da
  // mesma linha, que agora faz parte da área clicável do botão vizinho
  // (ver _celula). Menor esse valor, menor a chance de um toque cair bem
  // no meio, entre uma linha e outra, sem acertar nenhum botão.
  static const double _espacoEntreLinhas = 3;

  List<Widget> _linhasComOperadores() {
    return [
      Row(
        children: [
          _botaoDigito('1'),
          _botaoDigito('2'),
          _botaoDigito('3'),
          _botaoOperador('+'),
        ],
      ),
      const SizedBox(height: _espacoEntreLinhas),
      Row(
        children: [
          _botaoDigito('4'),
          _botaoDigito('5'),
          _botaoDigito('6'),
          _botaoOperador('-'),
        ],
      ),
      const SizedBox(height: _espacoEntreLinhas),
      Row(
        children: [
          _botaoDigito('7'),
          _botaoDigito('8'),
          _botaoDigito('9'),
          _botaoOperador('='),
        ],
      ),
      const SizedBox(height: _espacoEntreLinhas),
      Row(
        children: [
          _botaoDigito(','),
          _botaoDigito('0'),
          _botaoApagar(),
          _botaoConfirmar(),
        ],
      ),
    ];
  }

  List<Widget> _linhasApenasDigitos() {
    return [
      Row(
        children: [_botaoDigito('1'), _botaoDigito('2'), _botaoDigito('3')],
      ),
      const SizedBox(height: _espacoEntreLinhas),
      Row(
        children: [_botaoDigito('4'), _botaoDigito('5'), _botaoDigito('6')],
      ),
      const SizedBox(height: _espacoEntreLinhas),
      Row(
        children: [_botaoDigito('7'), _botaoDigito('8'), _botaoDigito('9')],
      ),
      const SizedBox(height: _espacoEntreLinhas),
      Row(
        children: [_botaoApagar(), _botaoDigito('0'), _botaoConfirmar()],
      ),
    ];
  }

  // Altura enxuta de propósito: esse teclado divide a tela com o
  // formulário inteiro (nº do animal, peso, apartação, ficha do animal,
  // botão Confirma) — uma altura maior estourava o layout (RenderFlex
  // overflow) em telas menores. Largura continua generosa (cada botão
  // ocupa 1/4 da largura da tela), que é o que mais importa pra acertar
  // o toque com a mão suja/luva.
  //
  // A célula inteira (sem "buracos" de padding) é a área clicável — quem
  // desenha o respiro visual entre os botões é o _pill() de cada um,
  // por dentro do InkWell, não um Padding por fora dele. Assim o botão
  // continua com a MESMA aparência de antes, mas responde ao toque numa
  // área maior (inclusive onde antes era só espaço morto entre um botão e
  // o vizinho) — bug real relatado: toque não registrava e parecia que o
  // teclado "não aceitava" o número, quando na real o dedo só não tinha
  // caído em cima de nenhum botão.
  Widget _celula({required Widget child}) {
    return Expanded(child: SizedBox(height: 46, child: child));
  }

  /// Desenho visual do botão (cor, cantos arredondados) — sempre um pouco
  /// menor que a célula inteira (ver _celula), porque tem um respiro
  /// (Padding) por dentro do InkWell, não por fora. O InkWell (com o
  /// mesmo borderRadius) ainda ocupa a célula toda, então o efeito de
  /// toque (ripple) fica limitado a essa forma arredondada mesmo tocando
  /// perto da borda da célula.
  Widget _pill({required Widget child, required Color cor}) {
    return Padding(
      padding: const EdgeInsets.all(2),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: cor,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(child: child),
      ),
    );
  }

  Widget _botaoDigito(String texto) {
    return _celula(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => onCaractere(texto),
        child: _pill(
          cor: Colors.white,
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
    );
  }

  Widget _botaoOperador(String texto) {
    return _celula(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => onCaractere(texto),
        child: _pill(
          cor: _fundoOperador,
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
    );
  }

  Widget _botaoApagar() {
    return _celula(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onApagar,
        child: _pill(
          cor: Colors.white,
          child: const Icon(
            Icons.backspace_outlined,
            size: 22,
            color: Colors.grey,
          ),
        ),
      ),
    );
  }

  Widget _botaoConfirmar() {
    return _celula(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onConfirmar,
        child: _pill(
          cor: Colors.blue,
          child: const Text(
            "OK",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
