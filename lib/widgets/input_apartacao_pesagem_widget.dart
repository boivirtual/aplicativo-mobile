import 'package:flutter/material.dart';

class InputApartacaoPesagemWidget extends StatelessWidget {
  final bool habilitado;
  final TextEditingController criterioController;
  final FocusNode focoNoCriterio;
  final List<String> listaCriteriosDinamica;
  final Color corDoRotulo;
  final VoidCallback onAbrirLista;

  const InputApartacaoPesagemWidget({
    super.key,
    required this.habilitado,
    required this.criterioController,
    required this.focoNoCriterio,
    required this.listaCriteriosDinamica,
    required this.corDoRotulo,
    required this.onAbrirLista,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: habilitado ? Colors.white : Colors.grey[200],
        borderRadius: BorderRadius.circular(8),
      ),
      child: TextFormField(
        controller: criterioController,
        focusNode: focoNoCriterio,
        readOnly: true,
        enabled: true,
        style: TextStyle(
          fontSize: 16,
          color: habilitado ? Colors.black : Colors.grey,
        ),
        onTap: habilitado ? onAbrirLista : null,
        decoration: InputDecoration(
          labelText: "Critério de Apartação",
          labelStyle: TextStyle(
            fontSize: 14,
            color: habilitado ? corDoRotulo : Colors.grey,
          ),
          hintText: habilitado ? "Selecione" : "",
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 22,
          ),
          suffixIcon: Icon(
            Icons.arrow_drop_down,
            color: habilitado ? Colors.blueGrey : Colors.grey,
            size: 28,
          ),
        ),
      ),
    );
  }
}
