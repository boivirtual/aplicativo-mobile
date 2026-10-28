import 'package:flutter/material.dart';

/// Padrões visuais do aplicativo (cores, bordas). Toda tela nova usa estes
/// valores em vez de cores soltas, para o app ficar igual em todo lugar.
class EstiloApp {
  EstiloApp._();

  /// Azul escuro das barras (AppBar, rodapé selecionado, títulos).
  static const azulBarra = Color(0xFF18385F);

  /// Azul dos ícones (cards da Home, opções, editar/excluir).
  static const azulIcone = Color(0xFF228cb9);

  /// Azul do btn-primary do web (Bootstrap 3).
  static const azulPrimario = Color(0xFF337AB7);

  /// Verde dos botões de confirmar/gravar.
  static const verdeConfirmar = Color(0xFF4CAF50);

  /// Borda do campo em edição: azul bem clarinho (o mesmo do destaque do
  /// Nº do Animal da Pesagem).
  static const azulBordaFoco = Color(0xFF81D4FA);

  /// Negrito do app: a fonte (FuturaStd) só tem a versão fina, então o
  /// traço é engrossado com "sombras" da mesma cor (FontWeight.bold sozinho
  /// não muda nada na tela).
  static TextStyle negrito(double tamanho, Color cor) => TextStyle(
    fontSize: tamanho,
    color: cor,
    fontWeight: FontWeight.w900,
    shadows: [
      Shadow(color: cor, offset: const Offset(0.4, 0)),
      Shadow(color: cor, offset: const Offset(-0.4, 0)),
      Shadow(color: cor, offset: const Offset(0, 0.4)),
    ],
  );

  /// Tarja azul clara do topo (fazenda e pasto): o nome do pasto em negrito.
  static Widget textoTarjaPasto(String fazenda, String pasto) => Text.rich(
    TextSpan(
      style: const TextStyle(fontSize: 13, color: Colors.blue),
      children: [
        TextSpan(text: '$fazenda  -  '),
        TextSpan(text: pasto, style: negrito(13, Colors.blue)),
      ],
    ),
    maxLines: 1,
    softWrap: false,
  );

  /// Moldura de um campo: transparente sem foco, azul claro com foco (ou
  /// destacado), vermelha com erro. Sempre usada como foregroundDecoration
  /// (por cima), só mudando a cor — uma borda que aparece e some muda a
  /// estrutura por dentro e o Flutter recria o campo de texto (o cursor
  /// sumia e a digitação se perdia).
  static BoxDecoration molduraCampo({
    required bool ativo,
    bool erro = false,
    double raio = 8,
  }) => BoxDecoration(
    borderRadius: BorderRadius.circular(raio),
    border: Border.all(
      color: erro
          ? Colors.red
          : ativo
          ? azulBordaFoco
          : Colors.transparent,
      width: erro ? 1 : 1.2,
    ),
  );
}

/// Envolve a caixa de um campo de texto e desenha a borda azul clara
/// enquanto algum campo lá dentro estiver em edição (padrão de todas as
/// telas). Não precisa de FocusNode: percebe o foco de quem está dentro.
class MolduraFoco extends StatefulWidget {
  final Widget child;
  final double raio;

  /// Borda azul mesmo sem o foco (ex.: campo destacado para começar).
  final bool destacado;

  const MolduraFoco({
    super.key,
    required this.child,
    this.raio = 8,
    this.destacado = false,
  });

  @override
  State<MolduraFoco> createState() => _MolduraFocoState();
}

class _MolduraFocoState extends State<MolduraFoco> {
  bool _foco = false;

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onFocusChange: (f) => setState(() => _foco = f),
    child: DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: EstiloApp.molduraCampo(
        ativo: _foco || widget.destacado,
        raio: widget.raio,
      ),
      child: widget.child,
    ),
  );
}
