import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Campos no padrão dos campos da Pesagem ("Nº do Animal"): caixa branca,
/// cantos 8; vazio, o rótulo fica no meio da caixa; preenchido (ou
/// digitando), o rótulo vai para o topo e o valor aparece embaixo, em
/// negrito. Usado nos modais e telas do Mapa de Gado (Nutrição, Morte,
/// Nascimento e Mudar Animais de Pasto).

const _estiloValor = TextStyle(
  fontSize: 14,
  fontWeight: FontWeight.bold,
  color: Colors.black87,
);

/// Topo do rótulo quando ele sobe, e onde começa o valor embaixo dele.
const _topoRotulo = 10.0;
const _topoValor = 24.0;

/// Campo digitável.
class CampoTextoTopo extends StatefulWidget {
  final String rotulo;
  final Color corRotulo;
  final TextEditingController controller;
  final FocusNode? focusNode;

  /// Altura da caixa; null = campo de várias linhas ([linhas]).
  final double? altura;
  final int linhas;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization textCapitalization;
  final bool enabled;
  final bool erro;
  final VoidCallback? onTap;
  final ValueChanged<String>? onChanged;

  /// Parte do rótulo em negrito (ex.: "Esperados").
  final String? rotuloNegrito;

  /// Texto de exemplo dentro do campo vazio (campo de várias linhas).
  final String? dica;

  /// Complemento do rótulo em fonte menor e cinza (ex.: "(opcional)").
  final String? rotuloComplemento;

  const CampoTextoTopo({
    super.key,
    required this.rotulo,
    required this.corRotulo,
    required this.controller,
    this.focusNode,
    this.altura = 56,
    this.linhas = 3,
    this.keyboardType,
    this.inputFormatters,
    this.textCapitalization = TextCapitalization.none,
    this.enabled = true,
    this.erro = false,
    this.onTap,
    this.onChanged,
    this.rotuloNegrito,
    this.dica,
    this.rotuloComplemento,
  });

  @override
  State<CampoTextoTopo> createState() => _CampoTextoTopoState();
}

class _CampoTextoTopoState extends State<CampoTextoTopo> {
  FocusNode? _focoProprio;
  FocusNode get _foco => widget.focusNode ?? (_focoProprio ??= FocusNode());

  @override
  void initState() {
    super.initState();
    // borda azul enquanto o campo está em edição (ou só marcado, sem
    // teclado — ex.: o Nº Mãe do Nascimento)
    _foco.addListener(_aoMudarFoco);
  }

  void _aoMudarFoco() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _foco.removeListener(_aoMudarFoco);
    _focoProprio?.dispose();
    super.dispose();
  }

  Widget _texto() => TextField(
    controller: widget.controller,
    focusNode: _foco,
    enabled: widget.enabled,
    keyboardType: widget.keyboardType,
    inputFormatters: widget.inputFormatters,
    textCapitalization: widget.textCapitalization,
    autocorrect: false,
    enableSuggestions: false,
    minLines: widget.altura == null ? widget.linhas : 1,
    maxLines: widget.altura == null ? widget.linhas : 1,
    style: _estiloValor,
    decoration: InputDecoration.collapsed(
      // o exemplo só aparece com o campo em edição (vazio e sem foco ele se
      // misturava com o rótulo)
      hintText: _foco.hasFocus ? widget.dica ?? '' : '',
      hintStyle: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.normal,
        color: Colors.grey[500],
      ),
    ),
    onTap: widget.onTap,
    onChanged: widget.onChanged,
  );

  /// O rótulo, com [CampoTextoTopo.rotuloNegrito] em negrito.
  Widget _rotulo(double tamanho) {
    final estilo = TextStyle(fontSize: tamanho, color: widget.corRotulo);
    final negrito = widget.rotuloNegrito;
    final i = negrito == null ? -1 : widget.rotulo.indexOf(negrito);
    final complemento = widget.rotuloComplemento;
    if (complemento != null) {
      return Text.rich(
        TextSpan(
          style: estilo,
          children: [
            TextSpan(text: widget.rotulo),
            TextSpan(
              text: ' $complemento',
              style: TextStyle(
                fontSize: tamanho - 2,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      );
    }
    if (i < 0) return Text(widget.rotulo, style: estilo);
    return Text.rich(
      TextSpan(
        style: estilo,
        children: [
          TextSpan(text: widget.rotulo.substring(0, i)),
          TextSpan(
            text: negrito,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          TextSpan(text: widget.rotulo.substring(i + negrito!.length)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (!widget.enabled) return;
        // já marcado (foco sem teclado, ex.: Nº Mãe do Nascimento): o toque
        // abre o teclado
        if (_foco.hasFocus) {
          SystemChannels.textInput.invokeMethod('TextInput.show');
        }
        _foco.requestFocus();
        widget.onTap?.call();
      },
      child: Container(
        height: widget.altura,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: widget.erro ? Border.all(color: Colors.red) : null,
          boxShadow: !widget.erro && _foco.hasFocus
              ? const [BoxShadow(color: Color(0x5566AFE9), blurRadius: 6)]
              : null,
        ),
        // A borda do foco vai por cima (foregroundDecoration): como borda
        // normal ela mudava o recuo interno do campo ao ganhar o foco e o
        // cursor sumia.
        foregroundDecoration: !widget.erro && _foco.hasFocus
            // mesmo azul claro do campo em foco do web (Bootstrap 3)
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF66AFE9), width: 1.5),
              )
            : null,
        child: ListenableBuilder(
          listenable: Listenable.merge([widget.controller, _foco]),
          builder: (context, _) {
            final aberto = widget.controller.text.isNotEmpty || _foco.hasFocus;
            final rotuloTopo = _rotulo(11);
            final rotuloMeio = _rotulo(14);

            if (widget.altura == null) {
              // várias linhas: rótulo em cima e o texto embaixo
              return Padding(
                padding: const EdgeInsets.fromLTRB(12, _topoRotulo, 12, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    aberto ? rotuloTopo : rotuloMeio,
                    const SizedBox(height: 4),
                    _texto(),
                  ],
                ),
              );
            }

            // O campo fica sempre montado (o foco não se perde); só o
            // rótulo muda de lugar.
            return Stack(
              children: [
                Positioned(
                  left: 12,
                  right: 8,
                  top: _topoValor,
                  bottom: 0,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _texto(),
                  ),
                ),
                if (aberto)
                  Positioned(left: 12, top: _topoRotulo, child: rotuloTopo)
                else
                  Positioned.fill(
                    left: 12,
                    child: IgnorePointer(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: rotuloMeio,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Campo só de leitura (data, lote...): mesmo desenho do [CampoTextoTopo].
/// [valor] vazio = só o rótulo, no meio da caixa.
class CampoValorTopo extends StatelessWidget {
  final String rotulo;
  final Color corRotulo;
  final String valor;
  final Widget? icone;
  final double altura;
  final VoidCallback? onTap;

  const CampoValorTopo({
    super.key,
    required this.rotulo,
    required this.corRotulo,
    required this.valor,
    this.icone,
    this.altura = 56,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: altura,
        padding: EdgeInsets.only(
          left: 12,
          right: 6,
          top: valor.isEmpty ? 0 : _topoRotulo,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Expanded(
              child: valor.isEmpty
                  ? Text(
                      rotulo,
                      style: TextStyle(fontSize: 14, color: corRotulo),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          rotulo,
                          style: TextStyle(fontSize: 11, color: corRotulo),
                        ),
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            // encolhe um pouco se não couber (ex: a data)
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                valor,
                                maxLines: 1,
                                style: _estiloValor,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
            if (icone != null) icone!,
          ],
        ),
      ),
    );
  }
}
