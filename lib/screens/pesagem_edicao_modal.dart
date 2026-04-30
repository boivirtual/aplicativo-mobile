import 'package:flutter/material.dart';
import 'package:boivirtual/utils/app_alert.dart';

class PesagemEdicaoResultado {
  final String fazendaSelecionada;
  final String motivoSelecionado;
  final String descricaoLote;
  final String qtdAPesar;
  final List<String> criteriosApartacao;

  PesagemEdicaoResultado({
    required this.fazendaSelecionada,
    required this.motivoSelecionado,
    required this.descricaoLote,
    required this.qtdAPesar,
    required this.criteriosApartacao,
  });
}

class PesagemEdicaoModal extends StatefulWidget {
  final String fazendaSelecionada;
  final String motivoSelecionado;
  final String descricaoLote;
  final String qtdAPesar;
  final List<String> criteriosApartacao;
  final List<dynamic> fazendasCarregadas;
  final Map<String, String> motivos;
  final bool bloquearFazenda;

  const PesagemEdicaoModal({
    super.key,
    required this.fazendaSelecionada,
    required this.motivoSelecionado,
    required this.descricaoLote,
    required this.qtdAPesar,
    required this.criteriosApartacao,
    required this.fazendasCarregadas,
    required this.motivos,
    required this.bloquearFazenda,
  });

  @override
  State<PesagemEdicaoModal> createState() => _PesagemEdicaoModalState();
}

class _PesagemEdicaoModalState extends State<PesagemEdicaoModal> {
  late String _fazendaSelecionada;
  late String _motivoSelecionado;
  late TextEditingController _descricaoController;
  late TextEditingController _qtdAPesarController;
  late TextEditingController _criterioController;
  late List<String> _criterios;

  final Color corDoRotulo = Colors.blueGrey.shade800;
  final Color azulCabecalho = const Color(0xFF18385F);
  final Color azulBotao = const Color(0xFF007AFF);

  @override
  void initState() {
    super.initState();
    _fazendaSelecionada = widget.fazendaSelecionada;
    _motivoSelecionado = widget.motivoSelecionado;
    _descricaoController = TextEditingController(text: widget.descricaoLote);
    _qtdAPesarController = TextEditingController(text: widget.qtdAPesar);
    _criterioController = TextEditingController();
    _criterios = List<String>.from(widget.criteriosApartacao);
  }

  @override
  void dispose() {
    _descricaoController.dispose();
    _qtdAPesarController.dispose();
    _criterioController.dispose();
    super.dispose();
  }

  void _adicionarCriterio() {
    final texto = _criterioController.text.trim();
    if (texto.isEmpty) return;

    if (!_criterios.contains(texto)) {
      setState(() {
        _criterios.add(texto);
      });
    }

    _criterioController.clear();
  }

  void _removerCriterio(String criterio) {
    setState(() {
      _criterios.remove(criterio);
    });
  }

  void _validarESalvar() {
    if (_fazendaSelecionada.trim().isEmpty) {
      AppAlert.erro(context, 'Informe o campo Fazenda');
      return;
    }

    if (_motivoSelecionado.trim().isEmpty) {
      AppAlert.erro(context, 'Informe o campo Motivo');
      return;
    }

    if (_descricaoController.text.trim().isEmpty) {
      AppAlert.erro(context, 'Informe o campo Descrição do Lote');
      return;
    }

    if (_qtdAPesarController.text.trim().isEmpty) {
      AppAlert.erro(context, 'Informe o campo Qtde a Pesar');
      return;
    }

    Navigator.pop(
      context,
      PesagemEdicaoResultado(
        fazendaSelecionada: _fazendaSelecionada,
        motivoSelecionado: _motivoSelecionado,
        descricaoLote: _descricaoController.text.trim(),
        qtdAPesar: _qtdAPesarController.text.trim(),
        criteriosApartacao: _criterios,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: SingleChildScrollView(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Text(
                  'Editar Pesagem',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: azulCabecalho,
                  ),
                ),
              ),
              const SizedBox(height: 14),

              _buildDropdownMinimal(
                "Fazenda",
                _fazendaSelecionada,
                widget.fazendasCarregadas
                    .map(
                      (f) => {
                        'id': f['id'].toString(),
                        'nome': f['nome'].toString(),
                      },
                    )
                    .toList(),
                widget.bloquearFazenda
                    ? null
                    : (val) {
                        if (val != null) {
                          setState(() => _fazendaSelecionada = val);
                        }
                      },
              ),
              const SizedBox(height: 8),

              _buildDropdownMinimal(
                "Motivo",
                _motivoSelecionado,
                widget.motivos.entries
                    .map((e) => {'id': e.key, 'nome': e.value})
                    .toList(),
                (val) {
                  if (val != null) {
                    setState(() => _motivoSelecionado = val);
                  }
                },
              ),
              const SizedBox(height: 8),

              _buildTextFieldMinimal(
                "Descrição do Lote",
                _descricaoController,
                (val) => setState(() {}),
              ),
              const SizedBox(height: 8),

              _buildCriteriosField(),
              const SizedBox(height: 8),

              _buildTextFieldMinimal(
                "Qtde a Pesar",
                _qtdAPesarController,
                (val) => setState(() {}),
                isNumber: true,
              ),

              /*if (widget.bloquearFazenda) ...[
                const SizedBox(height: 10),
                const Text(
                  'A fazenda não pode ser alterada porque já existem itens digitados.',
                  style: TextStyle(
                    color: Colors.red,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],*/
              const SizedBox(height: 14),

              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 45,
                      child: ElevatedButton(
                        onPressed: _validarESalvar,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: azulBotao,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text(
                          "Salvar Edição",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 45,
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.grey),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text(
                          "Fechar",
                          style: TextStyle(
                            color: Colors.grey,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextFieldMinimal(
    String label,
    TextEditingController controller,
    Function(String) onChanged, {
    bool isNumber = false,
  }) {
    return Container(
      height: 55,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: TextFormField(
        controller: controller,
        onChanged: onChanged,
        keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: corDoRotulo, fontSize: 13),
          border: InputBorder.none,
          floatingLabelBehavior: FloatingLabelBehavior.auto,
        ),
      ),
    );
  }

  Widget _buildDropdownMinimal(
    String label,
    String? value,
    List<Map<String, String>> items,
    Function(String?)? onChanged,
  ) {
    return Container(
      height: 55,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: onChanged == null ? Colors.grey[300] : Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButtonFormField<String>(
          initialValue: value,
          isExpanded: true,
          onChanged: onChanged,
          decoration: InputDecoration(
            labelText: label,
            labelStyle: TextStyle(color: corDoRotulo, fontSize: 13),
            border: InputBorder.none,
          ),
          items: items
              .map(
                (item) => DropdownMenuItem<String>(
                  value: item['id'],
                  child: Text(
                    item['nome'] ?? '',
                    style: const TextStyle(fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  Widget _buildCriteriosField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 55,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
          ),
          child: TextField(
            controller: _criterioController,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              labelText: "Critérios de Apartação",
              labelStyle: TextStyle(color: corDoRotulo, fontSize: 13),
              border: InputBorder.none,
              suffixIcon: IconButton(
                icon: const Icon(
                  Icons.add_circle,
                  color: Color(0xFF18385F),
                  size: 22,
                ),
                onPressed: _adicionarCriterio,
              ),
            ),
            onSubmitted: (_) => _adicionarCriterio(),
          ),
        ),
        if (_criterios.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Wrap(
              spacing: 6,
              runSpacing: -6,
              children: _criterios
                  .map(
                    (tag) => Chip(
                      backgroundColor: Colors.blue[50],
                      label: Text(
                        tag,
                        style: TextStyle(fontSize: 11, color: Colors.blue[900]),
                      ),
                      deleteIcon: const Icon(Icons.close, size: 14),
                      onDeleted: () => _removerCriterio(tag),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
      ],
    );
  }
}
