import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class FormularioPesagemTopoWidget extends StatelessWidget {
  final Widget filtroAtivoWidget;

  final int? indexSendoEditado;
  final TextEditingController noAnimalController;
  final FocusNode focoNoAnimal;
  final bool carregandoAnimal;
  final void Function(String) onNoAnimalChanged;

  final bool mostrandoSugestoes;
  final List<dynamic> sugestoesAnimais;
  final List<Map<String, dynamic>> itensPesados;
  final void Function(dynamic animal) onSugestaoTap;

  final Map<String, dynamic>? infoAnimal;
  final bool pesoBloqueado;
  final bool camposLiberados;
  final TextEditingController pesoController;
  final FocusNode focoNoPeso;

  final Widget observacaoToggleWidget;
  final Widget infoAnimalCardWidget;
  final Widget confirmButtonWidget;

  final Color corDoRotulo;
  final bool destacarCampoAnimal;
  final bool mostrarCursorFake;
  final VoidCallback onTapNoAnimal;

  const FormularioPesagemTopoWidget({
    super.key,
    required this.filtroAtivoWidget,
    required this.indexSendoEditado,
    required this.noAnimalController,
    required this.focoNoAnimal,
    required this.carregandoAnimal,
    required this.onNoAnimalChanged,
    required this.mostrandoSugestoes,
    required this.sugestoesAnimais,
    required this.itensPesados,
    required this.onSugestaoTap,
    required this.infoAnimal,
    required this.pesoBloqueado,
    required this.camposLiberados,
    required this.pesoController,
    required this.focoNoPeso,
    required this.observacaoToggleWidget,
    required this.infoAnimalCardWidget,
    required this.confirmButtonWidget,
    required this.corDoRotulo,
    required this.destacarCampoAnimal,
    required this.mostrarCursorFake,
    required this.onTapNoAnimal,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 4.0),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            filtroAtivoWidget,
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 1,
                  child: Column(
                    children: [
                      Container(
                        height: 80,
                        decoration: BoxDecoration(
                          color: indexSendoEditado != null
                              ? Colors.grey[200]
                              : Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: destacarCampoAnimal
                              ? Border.all(
                                  color: Colors.lightBlue.shade200,
                                  width: 1,
                                )
                              : null,
                        ),
                        child: Stack(
                          children: [
                            TextField(
                              controller: noAnimalController,
                              focusNode: focoNoAnimal,
                              readOnly: indexSendoEditado != null,
                              // Igual ao campo Peso: nunca abre o teclado do
                              // sistema — a digitação acontece pelo
                              // TecladoPesoWidget (modo apenas dígitos), que
                              // fica idêntico no Android e no iOS.
                              // inputFormatters é trava extra contra colar
                              // texto por fora.
                              keyboardType: TextInputType.none,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                              decoration: InputDecoration(
                                labelText: "Nº do Animal",
                                labelStyle: TextStyle(
                                  fontSize: 14,
                                  color: corDoRotulo,
                                ),
                                suffixIcon: carregandoAnimal
                                    ? const Padding(
                                        padding: EdgeInsets.all(25),
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : null,
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 15,
                                  horizontal: 12,
                                ),
                              ),
                              onChanged: onNoAnimalChanged,
                              onTap: onTapNoAnimal,
                              showCursor:
                                  indexSendoEditado == null &&
                                  !mostrarCursorFake,
                            ),
                            if (mostrarCursorFake)
                              const Positioned.fill(
                                child: IgnorePointer(
                                  child: Center(child: _CursorFakePiscando()),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (mostrandoSugestoes)
                        Container(
                          margin: const EdgeInsets.only(top: 2),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: const [
                              BoxShadow(color: Colors.black12, blurRadius: 4),
                            ],
                          ),
                          // Altura limitada e rolagem própria: com a busca
                          // trazendo até 6 sugestões, essa lista sem limite
                          // (shrinkWrap puro) podia estourar o espaço da tela
                          // quando o teclado também estava aberto.
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 220),
                            child: ListView.builder(
                              shrinkWrap: true,
                              itemCount: sugestoesAnimais.length,
                              itemBuilder: (context, index) {
                                final animal = sugestoesAnimais[index];
                                return ListTile(
                                  dense: true,
                                  title: Text(
                                    animal['exibicao'] ?? 'Sem ID',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  onTap: () => onSugestaoTap(animal),
                                );
                              },
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 1,
                  child: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: pesoController,
                    builder: (context, valor, _) {
                      final emModoFormula = valor.text.trim().startsWith('=');
                      return Container(
                        height: 80,
                        decoration: BoxDecoration(
                          color: emModoFormula
                              ? Colors.blue.shade50
                              : (camposLiberados
                                  ? Colors.white
                                  : Colors.grey[200]),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: TextFormField(
                          controller: pesoController,
                          focusNode: focoNoPeso,
                          readOnly: !camposLiberados,
                          enabled: infoAnimal != null,
                          showCursor: true,
                          // Nunca abre o teclado do sistema — a digitação
                          // acontece só pelo TecladoPesoWidget (customizado),
                          // que fica idêntico no Android e no iOS e já
                          // inclui "=" e os operadores pra usar o campo como
                          // fórmula (ex: "=34+10,5"). inputFormatters fica
                          // como trava extra contra colar texto por fora.
                          keyboardType: TextInputType.none,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9,.+\-*/()=]'),
                            ),
                          ],
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                          decoration: InputDecoration(
                            labelText: "Peso (Kg)",
                            labelStyle: TextStyle(
                              fontSize: 14,
                              color:
                                  camposLiberados ? corDoRotulo : Colors.grey,
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 15,
                              horizontal: 12,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            observacaoToggleWidget,
            const SizedBox(height: 8),
            infoAnimalCardWidget,
            const SizedBox(height: 4),
            confirmButtonWidget,
          ],
        ),
      ),
    );
  }
}

class _CursorFakePiscando extends StatefulWidget {
  const _CursorFakePiscando();

  @override
  State<_CursorFakePiscando> createState() => _CursorFakePiscandoState();
}

class _CursorFakePiscandoState extends State<_CursorFakePiscando>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 1, end: 0).animate(_controller),
      child: Container(
        width: 2,
        height: 26,
        margin: const EdgeInsets.only(top: 10),
        decoration: BoxDecoration(
          color: Colors.lightBlue.shade300,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}
