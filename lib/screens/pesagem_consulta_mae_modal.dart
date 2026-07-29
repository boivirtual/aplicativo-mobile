import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../repositories/animal_repository.dart';
import '../services/connectivity_service.dart';

class PesagemConsultaMaeModal extends StatefulWidget {
  final String cnpj;
  final String fazendaAtualNome;
  final Function(String idAnimal, String codigoAnimal)? onFilhoSelecionado;

  const PesagemConsultaMaeModal({
    super.key,
    required this.cnpj,
    required this.fazendaAtualNome,
    this.onFilhoSelecionado,
  });

  @override
  State<PesagemConsultaMaeModal> createState() =>
      _PesagemConsultaMaeModalState();
}

class _PesagemConsultaMaeModalState extends State<PesagemConsultaMaeModal> {
  final TextEditingController _buscaController = TextEditingController();
  final FocusNode _focoBusca = FocusNode();

  List<dynamic> sugestoesAnimais = [];
  bool mostrandoSugestoes = false;
  bool carregando = false;
  bool _semInternet = false;
  Map<String, dynamic>? infoMae;
  String? cnpjSeguro;
  Timer? _debounce;
  Timer? _timerTeclado;

  @override
  void initState() {
    super.initState();
    _carregarDados();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _timerTeclado?.cancel();
    _buscaController.dispose();
    _focoBusca.dispose();
    super.dispose();
  }

  Future<void> _carregarDados() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => cnpjSeguro = prefs.getString('userCNPJ') ?? widget.cnpj);
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

  Future<void> _buscarAnimal(String termo) async {
    if (termo.isEmpty) {
      setState(() {
        sugestoesAnimais = [];
        mostrandoSugestoes = false;
        _semInternet = false;
      });
      return;
    }

    // Consulta por mãe busca em todas as fazendas do usuário (cache-first,
    // igual à busca da fazenda atual). Só falta mesmo internet quando ainda
    // não existe cache de fazenda nenhuma (ex: primeiro login, sem nunca
    // ter ficado online) — nesse caso avisa em vez de parecer "não
    // encontrado".
    final temCache = await AnimalRepository.instance.temCacheDeAlgumaFazenda();
    if (!temCache && !ConnectivityService.instance.temInternetReal) {
      setState(() {
        sugestoesAnimais = [];
        mostrandoSugestoes = false;
        _semInternet = true;
      });
      return;
    }

    setState(() => _semInternet = false);

    try {
      final lista = await AnimalRepository.instance.buscarMaePorCodigo(
        termo: termo,
        bd: cnpjSeguro,
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

  Future<void> _buscarDetalhesMae(Map<String, dynamic> animal) async {
    setState(() {
      carregando = true;
      mostrandoSugestoes = false;
      infoMae = null;
      _buscaController.text = animal['codigo_limpo'];
    });
    try {
      final resultado = await AnimalRepository.instance.buscarDetalhesMae(
        id: animal['id'].toString(),
        bd: cnpjSeguro,
      );
      setState(() => infoMae = resultado);
    } finally {
      setState(() => carregando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFFF5F5F5),
      title: const Text(
        "Consulta Animais pela Mãe",
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.7,
        child: SingleChildScrollView(
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
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.left,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: const InputDecoration(
                    labelText: "Nº da Mãe",
                    labelStyle: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.normal,
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                  ),
                  onTap: () {
                    setState(() {
                      _buscaController.clear();
                      infoMae = null;
                      sugestoesAnimais = [];
                      mostrandoSugestoes = false;
                    });
                  },
                  onChanged: (val) {
                    _timerTeclado?.cancel();
                    if (val.isNotEmpty) {
                      _timerTeclado = Timer(const Duration(seconds: 2), () {
                        if (mounted && _focoBusca.hasFocus) {
                          _focoBusca.unfocus();
                        }
                      });
                    }
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 400), () {
                      _buscarAnimal(val);
                    });
                  },
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
                  child: _buildListaSugestoes(),
                ),
              if (_semInternet)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.cloud_off, color: Colors.grey.shade600, size: 18),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          "Sem internet — a consulta por mãe precisa de conexão.",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 15),
              if (carregando) const CircularProgressIndicator(),
              if (infoMae != null && !mostrandoSugestoes)
                _buildResultadosFilhos(),
            ],
          ),
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
                _buscarDetalhesMae(a);
              },
            ),
          )
          .toList(),
    );
  }

  Widget _buildResultadosFilhos() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (infoMae!['filhos'] != null)
          ...infoMae!['filhos'].map<Widget>((f) {
            String codFilho = _limparCodigo(f['codigo'].toString());
            String fazendaDoFilho =
                f['local_nome']?.toString().toUpperCase() ?? "NÃO INF.";

            bool mesmaFazenda =
                fazendaDoFilho == widget.fazendaAtualNome.toUpperCase();

            Color corTextoPrincipal = mesmaFazenda
                ? Colors.black87
                : Colors.grey.shade400;
            Color corSubtitulo = mesmaFazenda
                ? Colors.grey.shade700
                : Colors.grey.shade400;
            Color corFazenda = mesmaFazenda
                ? Colors.black54
                : Colors.grey.shade400;
            // CORREÇÃO AQUI: withValues em vez de withOpacity
            Color corFundo = mesmaFazenda
                ? Colors.transparent
                : Colors.grey.withValues(alpha: 0.05);

            return InkWell(
              onTap: mesmaFazenda
                  ? () {
                      if (widget.onFilhoSelecionado != null) {
                        Navigator.pop(context);
                        widget.onFilhoSelecionado!(
                          f['id'].toString(),
                          codFilho,
                        );
                      }
                    }
                  : null,
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: corFundo,
                  border: Border(
                    bottom: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          codFilho,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: corTextoPrincipal,
                          ),
                        ),
                        Text(
                          fazendaDoFilho,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: corFazenda,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Sexo: ${f['sexo']} | ${f['raca']} | ${f['pelagem']}",
                      style: TextStyle(fontSize: 13, color: corSubtitulo),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
      ],
    );
  }
}
