import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../repositories/animal_repository.dart';
import '../repositories/pesagem_repository.dart';
import '../widgets/teclado_peso_widget.dart';

/// Consulta, 100% local, em qual(is) lote(s) ainda em aberto (pesagens sem
/// finalizar) um animal já foi pesado neste aparelho — acessível pela
/// última linha da lista de "Pesagens sem finalizar" na tela inicial de
/// Pesagem. Mesmo padrão visual/interação da "Consultar Mãe"
/// (pesagem_consulta_mae_modal.dart): busca por código com teclado próprio,
/// sugestões, e resultado exibido ao selecionar uma sugestão.
class PesagemConsultaAnimaisPesadosModal extends StatefulWidget {
  final String bd;
  final List<dynamic> fazendasCarregadas;

  const PesagemConsultaAnimaisPesadosModal({
    super.key,
    required this.bd,
    required this.fazendasCarregadas,
  });

  @override
  State<PesagemConsultaAnimaisPesadosModal> createState() =>
      _PesagemConsultaAnimaisPesadosModalState();
}

class _PesagemConsultaAnimaisPesadosModalState
    extends State<PesagemConsultaAnimaisPesadosModal> {
  final TextEditingController _buscaController = TextEditingController();
  final FocusNode _focoBusca = FocusNode();

  List<dynamic> sugestoesAnimais = [];
  bool mostrandoSugestoes = false;
  bool carregando = false;
  bool _semCache = false;
  bool _naoEncontrado = false;
  List<Map<String, dynamic>>? resultadosLotes;
  Timer? _debounce;
  Timer? _timerTeclado;

  /// true enquanto o campo Nº do Animal está com foco — controla a exibição
  /// do TecladoPesoWidget (modo apenas dígitos), igual à "Consultar Mãe".
  bool _focoAtivo = false;

  @override
  void initState() {
    super.initState();
    _focoBusca.addListener(() {
      if (mounted) setState(() => _focoAtivo = _focoBusca.hasFocus);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _timerTeclado?.cancel();
    _buscaController.dispose();
    _focoBusca.dispose();
    super.dispose();
  }

  String _limparCodigo(String cod) {
    if (cod.contains('-')) {
      var partes = cod.split('-');
      String num = partes[1].replaceFirst(RegExp(r'^0+'), '');
      return "${partes[0]}-${num.isEmpty ? "0" : num}";
    }
    return cod.replaceFirst(RegExp(r'^0+'), '').isEmpty
        ? "0"
        : cod.replaceFirst(RegExp(r'^0+'), '');
  }

  String _getNomeFazenda(String id) {
    final fazenda = widget.fazendasCarregadas.firstWhere(
      (f) => f['id'].toString() == id,
      orElse: () => {'nome': id},
    );
    return fazenda['nome'].toString().toUpperCase();
  }

  Future<void> _buscarAnimal(String termo) async {
    if (termo.isEmpty) {
      setState(() {
        sugestoesAnimais = [];
        mostrandoSugestoes = false;
        _semCache = false;
      });
      return;
    }

    final temCache = await AnimalRepository.instance.temCacheDeAlgumaFazenda();
    if (!temCache) {
      setState(() {
        sugestoesAnimais = [];
        mostrandoSugestoes = false;
        _semCache = true;
      });
      return;
    }

    setState(() => _semCache = false);

    try {
      final lista = await AnimalRepository.instance.buscarPorCodigoGlobal(
        termo: termo,
      );
      setState(() {
        sugestoesAnimais = lista.map((item) {
          final mapa = Map<String, dynamic>.from(item as Map);
          mapa['codigo_limpo'] = _limparCodigo(mapa['codigo'].toString());
          return mapa;
        }).toList();
        mostrandoSugestoes = sugestoesAnimais.isNotEmpty;
      });
    } catch (e) {
      debugPrint("Erro busca: $e");
    }
  }

  void _aoAlterarTexto(String val) {
    _timerTeclado?.cancel();
    if (val.isNotEmpty) {
      // 4s (era 2s) — o teclado numérico customizado é mais lento de
      // digitar que o do sistema, 2s fechava o teclado sozinho antes do
      // usuário terminar.
      _timerTeclado = Timer(const Duration(seconds: 4), () {
        if (mounted && _focoBusca.hasFocus) {
          _focoBusca.unfocus();
        }
      });
    }
    // 800ms (era 400ms) — mesmo motivo: quem realmente disparava a busca
    // (e a mensagem de "não encontrado"/lista de sugestões) no meio da
    // digitação era este debounce, não o timer acima. Visar cada botão do
    // teclado customizado é mais lento que digitar de cabeça no teclado do
    // sistema, e 400ms era pouco pro intervalo natural entre dois toques.
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 800),
      () => _buscarAnimal(val),
    );
  }

  void _inserirCaractere(String caractere) {
    final texto = _buscaController.text + caractere;
    setState(() {
      _buscaController.value = TextEditingValue(
        text: texto,
        selection: TextSelection.collapsed(offset: texto.length),
      );
    });
    _aoAlterarTexto(texto);
  }

  void _apagarCaractere() {
    final texto = _buscaController.text;
    if (texto.isEmpty) return;
    final novoTexto = texto.substring(0, texto.length - 1);
    setState(() {
      _buscaController.value = TextEditingValue(
        text: novoTexto,
        selection: TextSelection.collapsed(offset: novoTexto.length),
      );
    });
    _aoAlterarTexto(novoTexto);
  }

  void _confirmarTeclado() {
    _timerTeclado?.cancel();
    _debounce?.cancel();
    _buscarAnimal(_buscaController.text);
    _focoBusca.unfocus();
  }

  Future<void> _buscarLotesDoAnimal(Map<String, dynamic> animal) async {
    setState(() {
      carregando = true;
      mostrandoSugestoes = false;
      resultadosLotes = null;
      _buscaController.text = animal['codigo_limpo'];
    });
    try {
      final lotes = await PesagemRepository.instance.buscarLotesAbertosPorAnimal(
        idAnimal: animal['id'].toString(),
        bd: widget.bd,
      );
      setState(() => resultadosLotes = lotes);
    } finally {
      setState(() => carregando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFFF5F5F5),
      title: const Text(
        "Consulta Animais Pesados",
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final double alturaSugestoes = (constraints.maxHeight - 90)
                      .clamp(80.0, 500.0);
                  return SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: TextField(
                            controller: _buscaController,
                            focusNode: _focoBusca,
                            // SEMPRE readOnly — mesma razão do Nº da Mãe:
                            // toda escrita acontece programaticamente via
                            // TecladoPesoWidget, sem conexão residual com o
                            // teclado do sistema.
                            readOnly: true,
                            keyboardType: TextInputType.none,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            textAlign: TextAlign.left,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                            decoration: const InputDecoration(
                              labelText: "Nº do Animal",
                              labelStyle: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.normal,
                              ),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(
                                vertical: 10,
                              ),
                            ),
                            onTap: () {
                              setState(() {
                                _buscaController.clear();
                                resultadosLotes = null;
                                sugestoesAnimais = [];
                                mostrandoSugestoes = false;
                              });
                            },
                            onChanged: _aoAlterarTexto,
                          ),
                        ),
                        if (mostrandoSugestoes)
                          Container(
                            margin: const EdgeInsets.only(top: 5),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxHeight: alturaSugestoes,
                              ),
                              child: SingleChildScrollView(
                                child: _buildListaSugestoes(),
                              ),
                            ),
                          ),
                        if (_semCache)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.cloud_off,
                                  color: Colors.grey.shade600,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    "Cadastro de animais ainda não baixado neste aparelho — conecte à internet uma vez para habilitar a consulta.",
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.grey.shade700,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 15),
                        if (carregando) const CircularProgressIndicator(),
                        if (resultadosLotes != null && !mostrandoSugestoes)
                          _buildResultadosLotes(),
                      ],
                    ),
                  );
                },
              ),
            ),
            if (_focoAtivo)
              TecladoPesoWidget(
                mostrarOperadores: false,
                onCaractere: _inserirCaractere,
                onApagar: _apagarCaractere,
                onConfirmar: _confirmarTeclado,
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(
            "FECHAR",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  Widget _buildListaSugestoes() {
    return Column(
      children: sugestoesAnimais
          .map(
            (a) => ListTile(
              dense: true,
              title: Text(
                a['codigo_limpo'],
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              onTap: () {
                _focoBusca.unfocus();
                _buscarLotesDoAnimal(a);
              },
            ),
          )
          .toList(),
    );
  }

  Widget _buildResultadosLotes() {
    if (resultadosLotes!.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          "Este animal ainda não foi pesado em nenhum lote em aberto.",
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
        ),
      );
    }

    // Descrição do lote é a informação principal, sozinha na primeira linha
    // (negrito, igual ao código na lista de filhos da "Consulta Mãe");
    // peso e fazenda vão juntos na linha de baixo.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: resultadosLotes!.map<Widget>((l) {
        final String lote = (l['lote']?.toString().trim().isEmpty ?? true)
            ? 'Sem Lote'
            : l['lote'].toString();
        final String fazenda = _getNomeFazenda(l['fazenda_id'].toString());
        final int pesoInteiro =
            (double.tryParse(l['peso']?.toString() ?? '') ?? 0).toInt();

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Lote: $lote",
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(
                    "Peso: $pesoInteiro Kg",
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF18385F),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      fazenda,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.black54,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
