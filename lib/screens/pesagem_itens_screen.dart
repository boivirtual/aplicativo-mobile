import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/animal_cache_service.dart';
import '../services/sync_service.dart';
import '../widgets/indicador_conectividade_widget.dart';
import '../repositories/pesagem_repository.dart';
import '../repositories/animal_repository.dart';
import 'pesagem_consulta_mae_modal.dart';
import 'package:boivirtual/widgets/lista_itens_pesagem.dart';
import 'package:boivirtual/widgets/resumo_pesagem_widget.dart';
import 'package:boivirtual/widgets/rodape_apartacao_widget.dart';
import 'package:boivirtual/widgets/filtro_ativo_pesagem_widget.dart';
import 'package:boivirtual/widgets/info_animal_card_widget.dart';
import 'package:boivirtual/widgets/confirm_button_pesagem_widget.dart';
import 'package:boivirtual/widgets/input_apartacao_pesagem_widget.dart';
import 'package:boivirtual/widgets/observacao_toggle_pesagem_widget.dart';
import 'package:boivirtual/widgets/formulario_pesagem_topo_widget.dart';
import 'package:boivirtual/widgets/teclado_peso_widget.dart';
import 'pesagem_edicao_modal.dart';
import 'package:boivirtual/utils/app_alert.dart';
import 'package:boivirtual/utils/calculadora_peso.dart';

class PesagemItensScreen extends StatefulWidget {
  final String fazendaSelecionada;
  final String motivoSelecionado;
  final String descricaoLote;
  final String qtdAPesar;
  final List<String> criteriosApartacao;
  final int? idPesagemExistente;
  final VoidCallback onBack;

  const PesagemItensScreen({
    super.key,
    required this.fazendaSelecionada,
    required this.motivoSelecionado,
    required this.descricaoLote,
    required this.qtdAPesar,
    required this.criteriosApartacao,
    this.idPesagemExistente,
    required this.onBack,
  });

  @override
  State<PesagemItensScreen> createState() => _PesagemItensScreenState();
}

class _PesagemItensScreenState extends State<PesagemItensScreen> {
  late String fazendaSelecionada;
  late String motivoSelecionado;

  late String _fazendaSelecionadaAtual;
  late String _motivoSelecionadoAtual;
  late String _descricaoLoteAtual;
  late String _qtdAPesarAtual;

  String? cnpjParaBanco;
  int _idPesagemServer = 0;

  List<dynamic> fazendasCarregadas = [];
  bool mostrarObs = false;
  bool carregandoAnimal = false;
  bool carregandoItensIniciais = false;
  bool _jaConfirmouDuplicidade = false;
  bool _mensagemLimiteExibida = false;
  bool _processandoBusca = false;
  bool _destacarCampoAnimal = false;
  List<dynamic> sugestoesAnimais = [];
  bool mostrandoSugestoes = false;
  bool _salvandoItem = false;
  Map<String, dynamic>? infoAnimal;

  final List<Map<String, dynamic>> _itensPesados = [];
  int? _indexSendoEditado;

  final TextEditingController _noAnimalController = TextEditingController();
  final TextEditingController _pesoController = TextEditingController();
  final TextEditingController _obsController = TextEditingController();
  final TextEditingController _criterioController = TextEditingController();
  final TextEditingController _sizePesoController = TextEditingController();

  final FocusNode _focoNoAnimal = FocusNode();
  final FocusNode _focoNoPeso = FocusNode();
  final FocusNode _focoNaObs = FocusNode();
  final FocusNode _focoNoCriterio = FocusNode();
  int _qtdPesado = 0;

  late List<String> _listaCriteriosDinamica;

  Timer? _debounce;
  Timer? _timerTeclado;
  OverlayEntry? _overlayEntry;
  OverlayEntry? _tarjaPesoOverlay;

  bool _pesoBloqueado = true;
  VoidCallback? _onOverlayClose;

  /// true enquanto o campo Peso está com foco — controla a exibição do
  /// TecladoPesoWidget (o campo nunca abre o teclado do sistema).
  bool _focoPesoAtivo = false;

  final Color corDoRotulo = Colors.blueGrey[800]!;
  int? _itemExpandidoIndex;

  final Map<String, String> motivos = {
    '011': 'Controle Ganho de Peso',
    '002': 'Desmama',
    '016': 'MÃE de desmama',
    '003': 'Venda',
    '005': 'Tranferência',
    '012': 'Machos acima 8 meses',
    '013': 'Femeas 08 a 24 meses',
  };

  bool _animalInvalidoParaDesmama(dynamic nascimento) {
    if (nascimento == null) return false;

    final texto = nascimento.toString().trim();
    if (texto.isEmpty) return false;

    DateTime? dataNascimento;

    try {
      if (texto.contains('/')) {
        final partes = texto.split('/');
        if (partes.length == 3) {
          dataNascimento = DateTime(
            int.parse(partes[2]),
            int.parse(partes[1]),
            int.parse(partes[0]),
          );
        }
      } else if (texto.contains('-')) {
        dataNascimento = DateTime.tryParse(texto.split(' ').first);
      }
    } catch (_) {
      dataNascimento = null;
    }

    if (dataNascimento == null) return false;

    final hoje = DateTime.now();

    int meses =
        (hoje.year - dataNascimento.year) * 12 +
        (hoje.month - dataNascimento.month);

    if (hoje.day < dataNascimento.day) {
      meses--;
    }

    return meses > 12;
  }

  void _limparCampoAnimalEDestacar() {
    if (!mounted) return;

    _removerTarjaPeso();

    setState(() {
      _noAnimalController.clear();
      _pesoController.clear();
      infoAnimal = null;
      mostrandoSugestoes = false;
      _pesoBloqueado = true;

      _destacarCampoAnimal = true; // 👈 NOVO
    });
  }

  Future<void> _mostrarErroDesmamaERefocar() async {
    if (!mounted) return;

    FocusManager.instance.primaryFocus?.unfocus();

    await AppAlert.erro(context, 'Idade do animal inválida para Desmama');

    if (!mounted) return;

    _limparCampoAnimalEDestacar(); // 👈 TROCA AQUI
  }

  Future<void> _abrirModalEdicaoPesagem() async {
    final resultado = await showDialog<PesagemEdicaoResultado>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PesagemEdicaoModal(
        fazendaSelecionada: _fazendaSelecionadaAtual,
        motivoSelecionado: _motivoSelecionadoAtual,
        descricaoLote: _descricaoLoteAtual,
        qtdAPesar: _qtdAPesarAtual,
        criteriosApartacao: _listaCriteriosDinamica,
        fazendasCarregadas: fazendasCarregadas,
        motivos: motivos,
        bloquearFazenda: _itensPesados.isNotEmpty,
      ),
    );

    if (resultado == null) return;

    await _salvarEdicaoPesagem(resultado);
  }

  Future<void> _salvarEdicaoPesagem(PesagemEdicaoResultado dados) async {
    final bool ok = await _atualizarPesagemNoServidor(dados);

    if (!ok) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível salvar a edição da pesagem.'),
        ),
      );
      return;
    }

    if (!mounted) return;

    setState(() {
      _fazendaSelecionadaAtual = dados.fazendaSelecionada;
      _motivoSelecionadoAtual = dados.motivoSelecionado;
      _descricaoLoteAtual = dados.descricaoLote;
      _qtdAPesarAtual = dados.qtdAPesar;
      _listaCriteriosDinamica = List<String>.from(dados.criteriosApartacao);

      fazendaSelecionada = _fazendaSelecionadaAtual;
      motivoSelecionado = _motivoSelecionadoAtual;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Pesagem atualizada com sucesso.')),
    );
  }

  Future<bool> _atualizarPesagemNoServidor(PesagemEdicaoResultado dados) async {
    try {
      final bodyMap = {
        "bd": cnpjParaBanco,
        "pesagem_id": _idPesagemServer,
        "local_id": dados.fazendaSelecionada,
        "epoca_id": dados.motivoSelecionado,
        "lote": dados.descricaoLote,
        "qtd_a_pesar": dados.qtdAPesar,
        "criterios_lista": dados.criteriosApartacao,
        "filtro_desc":
            "${_getNomeFazenda(dados.fazendaSelecionada)} ➔ ${motivos[dados.motivoSelecionado]}",
        "bloquear_fazenda": _itensPesados.isNotEmpty,
      };

      debugPrint("JSON UPDATE PESAGEM: ${json.encode(bodyMap)}");

      final resJson = await PesagemRepository.instance.atualizarPesagem(
        bodyMap,
      );

      debugPrint("RESULTADO UPDATE PESAGEM: $resJson");

      return resJson['success'] == true;
    } catch (e) {
      debugPrint("Erro ao atualizar pesagem: $e");
      return false;
    }
  }

  @override
  void initState() {
    super.initState();

    // Suprime o overlay global "Sincronizando dados..." enquanto o usuário
    // está nesta tela — com sinal intermitente, o SyncService tenta
    // sincronizar em segundo plano com frequência, e o aviso piscando por
    // cima atrapalha a digitação rápida de peso. A sincronização em si
    // continua rodando normal.
    SyncService.instance.suprimirIndicador.value = true;

    _fazendaSelecionadaAtual = widget.fazendaSelecionada;
    _motivoSelecionadoAtual = widget.motivoSelecionado;
    _descricaoLoteAtual = widget.descricaoLote;
    _qtdAPesarAtual = widget.qtdAPesar;
    _listaCriteriosDinamica = List.from(widget.criteriosApartacao);

    fazendaSelecionada = _fazendaSelecionadaAtual;
    motivoSelecionado = _motivoSelecionadoAtual;

    if (widget.idPesagemExistente != null) {
      _idPesagemServer = widget.idPesagemExistente!;
    }

    _carregarDadosBase();

    _focoNoAnimal.addListener(() {
      if (_focoNoAnimal.hasFocus) {
        _removerErroOverlay();
        if (_indexSendoEditado == null) {
          setState(() {
            infoAnimal = null;
            mostrandoSugestoes = false;
            _pesoBloqueado = true;
            _destacarCampoAnimal = false;
            _noAnimalController.clear();
            _pesoController.clear();
            _removerTarjaPeso();
          });
        }
      }
    });

    _focoNoPeso.addListener(() {
      if (mounted) setState(() => _focoPesoAtivo = _focoNoPeso.hasFocus);

      if (_focoNoPeso.hasFocus) {
        if (infoAnimal != null && _pesoController.text.isEmpty) {
          _exibirTarjaPeso();
        }
      } else {
        _removerTarjaPeso();
        _resolverFormulaDoPeso();
      }
    });
  }

  void _inserirCaracterePeso(String caractere) {
    final texto = _pesoController.text + caractere;
    setState(() {
      _pesoController.value = TextEditingValue(
        text: texto,
        selection: TextSelection.collapsed(offset: texto.length),
      );
    });
  }

  void _apagarCaracterePeso() {
    final texto = _pesoController.text;
    if (texto.isEmpty) return;
    final novoTexto = texto.substring(0, texto.length - 1);
    setState(() {
      _pesoController.value = TextEditingValue(
        text: novoTexto,
        selection: TextSelection.collapsed(offset: novoTexto.length),
      );
    });
  }

  void _confirmarTecladoPeso() => _focoNoPeso.unfocus();

  /// Se o campo Peso tiver sido digitado como fórmula (ex: "=34+10,5"),
  /// calcula e substitui pelo resultado — igual ao Excel, o cálculo só
  /// aparece quando o usuário sai do campo. Devolve false (e avisa o
  /// usuário) se a fórmula for inválida, pra quem chamou poder impedir que
  /// o item seja salvo com um peso que não faz sentido.
  bool _resolverFormulaDoPeso() {
    final texto = _pesoController.text;
    if (texto.trim().startsWith('=')) {
      try {
        final resultado = resolverFormulaPeso(texto);
        setState(() => _pesoController.text = resultado);
        return true;
      } on FormatException {
        _exibirMensagemErro(
          "Fórmula de peso inválida.",
          onClose: _limparPesoEFocar,
        );
        return false;
      }
    }
    if (texto.isNotEmpty && !pesoEhNumeroValido(texto)) {
      _exibirMensagemErro(
        "Peso inválido. Pra usar fórmula, comece com \"=\".",
        onClose: _limparPesoEFocar,
      );
      return false;
    }
    return true;
  }

  @override
  void dispose() {
    SyncService.instance.suprimirIndicador.value = false;
    _debounce?.cancel();
    _timerTeclado?.cancel();
    _removerErroOverlay();
    _removerTarjaPeso();
    _focoNoAnimal.dispose();
    _focoNoPeso.dispose();
    _focoNaObs.dispose();
    _focoNoCriterio.dispose();
    _noAnimalController.dispose();
    _pesoController.dispose();
    _obsController.dispose();
    _criterioController.dispose();
    _sizePesoController.dispose();
    super.dispose();
  }

  void _exibirTarjaPeso() {
    _removerTarjaPeso();
    String rawPeso = infoAnimal?['ultimoPeso']?.toString() ?? "0";
    String pesoLimpo = double.tryParse(rawPeso)?.toInt().toString() ?? "0";
    String rawData = infoAnimal?['DataUltimo']?.toString() ?? "";
    String dataFormatada = "--/--/----";
    if (rawData.isNotEmpty) {
      try {
        List<String> partes = rawData.split(' ')[0].split('-');
        if (partes.length == 3) {
          dataFormatada = "${partes[2]}/${partes[1]}/${partes[0]}";
        }
      } catch (_) {}
    }

    _tarjaPesoOverlay = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).size.height * 0.34,
        right: 17,
        width: MediaQuery.of(context).size.width * 0.45,
        child: Material(
          elevation: 20,
          borderRadius: BorderRadius.circular(8),
          color: Colors.green[600],
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                    children: [
                      const TextSpan(text: "Último Peso: "),
                      TextSpan(
                        text: "$pesoLimpo Kg",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  dataFormatada,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_tarjaPesoOverlay!);
  }

  void _removerTarjaPeso() {
    if (_tarjaPesoOverlay != null) {
      _tarjaPesoOverlay!.remove();
      _tarjaPesoOverlay = null;
    }
  }

  void _exibirMensagemOverlay(
    String msg, {
    bool isError = true,
    VoidCallback? onClose,
    VoidCallback? onCancel,
    bool mostrarSimNao = false,
  }) {
    _removerErroOverlay();
    _onOverlayClose = onClose;

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).size.height * 0.35,
        left: 30,
        right: 30,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 25, 10, 10),
            decoration: BoxDecoration(
              color: isError
                  ? Colors.red[900]!.withValues(alpha: 0.95)
                  : Colors.green[800]!.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      isError
                          ? Icons.error_outline
                          : Icons.check_circle_outline,
                      color: Colors.white,
                      size: 28,
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Text(
                        msg,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                Align(
                  alignment: Alignment.bottomRight,
                  child: mostrarSimNao
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () {
                                _removerErroOverlay(); // Fecha o aviso

                                if (onCancel != null) {
                                  // Se passamos uma instrução personalizada (como nos 4 pontos que ajustamos)
                                  onCancel();
                                } else {
                                  // Caso contrário, faz a limpeza padrão que já estava aí
                                  setState(() {
                                    _noAnimalController.clear();
                                    _pesoBloqueado = true;
                                  });
                                  _focoNoAnimal.requestFocus();
                                }
                              },
                              child: const Text(
                                "NÃO",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            TextButton(
                              onPressed: () {
                                _removerErroOverlay();
                                // IMPORTANTE: Libera o peso antes de qualquer coisa
                                setState(() => _pesoBloqueado = false);

                                // Se houver uma ação específica (como buscar detalhes), executa agora
                                if (onClose != null) onClose();

                                // Dá o foco por último
                                _focarNoPesoComDelay();
                              },
                              child: const Text(
                                "SIM",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ],
                        )
                      : TextButton(
                          onPressed: () {
                            // Já dispara onClose (via _onOverlayClose), se
                            // quem chamou tiver passado um. Só cai no
                            // comportamento padrão (limpar Nº do Animal e
                            // focar nele) quando ninguém pediu algo
                            // específico — sem essa checagem, um onClose
                            // customizado (ex: limpar só o Peso) rodava
                            // junto com esse padrão em vez de no lugar dele.
                            _removerErroOverlay();

                            if (onClose == null) {
                              _noAnimalController.clear();

                              setState(() {
                                sugestoesAnimais = [];
                                mostrandoSugestoes = false;
                                _destacarCampoAnimal = false;
                              });

                              Future.delayed(
                                const Duration(milliseconds: 120),
                                () {
                                  if (!mounted) return;
                                  _focoNoAnimal.requestFocus();
                                },
                              );
                            }
                          },
                          child: const Text(
                            "FECHAR",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _exibirMensagemErro(String msg, {VoidCallback? onClose}) =>
      _exibirMensagemOverlay(msg, isError: true, onClose: onClose);

  /// Limpa só o Peso e devolve o foco nele — usado quando o erro é
  /// especificamente do peso (fórmula/número inválido), pra não obrigar o
  /// usuário a redigitar o Nº do Animal que já estava certo.
  void _limparPesoEFocar() {
    setState(() => _pesoController.clear());
    _focarNoPesoComDelay();
  }

  void _removerErroOverlay() {
    if (_overlayEntry != null) {
      _overlayEntry!.remove();
      _overlayEntry = null;

      if (_onOverlayClose != null) {
        _onOverlayClose!();
        _onOverlayClose = null;
      }
    }
  }

  void _focarNoPesoComDelay() {
    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted && _focoNoPeso.canRequestFocus) {
        _focoNoPeso.requestFocus();
      }
    });
  }

  Future<void> _abrirListaCriteriosApartacao() async {
    if (infoAnimal == null || _pesoBloqueado) {
      return;
    }

    FocusScope.of(context).unfocus();

    final String? selecionado = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        final TextEditingController novoController = TextEditingController();
        bool modoNovo = false;

        return StatefulBuilder(
          builder: (context, setModalState) {
            final bottomInset = MediaQuery.of(context).viewInsets.bottom;

            final List<String> criteriosOrdenados = _listaCriteriosDinamica
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList();
            return AnimatedPadding(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              padding: EdgeInsets.only(bottom: bottomInset),
              child: FractionallySizedBox(
                heightFactor: modoNovo ? 0.50 : 0.60,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Center(
                            child: Container(
                              width: 42,
                              height: 4,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade400,
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            modoNovo
                                ? "Novo Critério de Apartação"
                                : "Selecione o Critério de Apartação",
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),

                          if (!modoNovo) ...[
                            ListTile(
                              leading: const Icon(
                                Icons.add_circle_outline,
                                color: Colors.blue,
                              ),
                              title: const Text(
                                "Novo critério",
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                              onTap: () {
                                setModalState(() {
                                  modoNovo = true;
                                });
                              },
                            ),
                            const Divider(height: 1),
                            const SizedBox(height: 4),

                            if (criteriosOrdenados.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 30),
                                child: Center(
                                  child: Text(
                                    "Nenhum critério cadastrado.",
                                    style: TextStyle(fontSize: 15),
                                  ),
                                ),
                              )
                            else
                              SizedBox(
                                height: 260,
                                child: ListView.separated(
                                  itemCount: criteriosOrdenados.length,
                                  separatorBuilder: (_, __) =>
                                      const Divider(height: 1),
                                  itemBuilder: (_, index) {
                                    final criterio = criteriosOrdenados[index];
                                    return ListTile(
                                      title: Text(criterio),
                                      onTap: () {
                                        FocusScope.of(sheetContext).unfocus();
                                        Navigator.of(
                                          sheetContext,
                                        ).pop(criterio);
                                      },
                                    );
                                  },
                                ),
                              ),
                          ] else ...[
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF4F4F4),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                                child: TextField(
                                  controller: novoController,
                                  autofocus: true,
                                  textCapitalization:
                                      TextCapitalization.sentences,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    color: Colors.black87,
                                  ),
                                  decoration: const InputDecoration(
                                    hintText: "Digite o novo critério",
                                    hintStyle: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 15,
                                    ),
                                    border: InputBorder.none,
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 14,
                                    ),
                                  ),
                                  onSubmitted: (value) {
                                    final texto = value.trim();

                                    if (texto.isEmpty) {
                                      return;
                                    }

                                    FocusScope.of(sheetContext).unfocus();
                                    Navigator.of(sheetContext).pop(texto);
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: SizedBox(
                                    height: 44,
                                    child: ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(
                                          0xFF0D86FF,
                                        ),
                                        foregroundColor: Colors.white,
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                      ),
                                      onPressed: () {
                                        final texto = novoController.text
                                            .trim();

                                        if (texto.isEmpty) {
                                          return;
                                        }

                                        FocusScope.of(sheetContext).unfocus();
                                        Navigator.of(sheetContext).pop(texto);
                                      },
                                      child: const Text(
                                        "Salvar",
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: SizedBox(
                                    height: 44,
                                    child: OutlinedButton(
                                      style: OutlinedButton.styleFrom(
                                        side: BorderSide(
                                          color: Colors.grey.shade400,
                                        ),
                                        backgroundColor: Colors.grey.shade100,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                      ),
                                      onPressed: () {
                                        FocusScope.of(sheetContext).unfocus();

                                        setModalState(() {
                                          modoNovo = false;
                                          novoController.clear();
                                        });
                                      },
                                      child: const Text(
                                        "Fechar",
                                        style: TextStyle(
                                          color: Colors.grey,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (!mounted) {
      return;
    }

    if (selecionado == null || selecionado.trim().isEmpty) {
      return;
    }

    final String textoFinal = selecionado.trim();

    setState(() {
      final bool jaExiste = _listaCriteriosDinamica.any(
        (c) => c.trim().toLowerCase() == textoFinal.toLowerCase(),
      );

      if (!jaExiste) {
        _listaCriteriosDinamica.add(textoFinal);
      }

      _criterioController.text = textoFinal;
    });
  }

  Future<void> _carregarDadosBase() async {
    final prefs = await SharedPreferences.getInstance();
    cnpjParaBanco = prefs.getString('userCNPJ');
    final String? fazendasJson = prefs.getString('userFazendas');
    if (fazendasJson != null) {
      setState(() => fazendasCarregadas = json.decode(fazendasJson));
    }
    AnimalCacheService.instance.garantirCacheDaFazenda(
      _fazendaSelecionadaAtual,
      cnpjParaBanco,
      nomeFazenda: _getNomeFazenda(_fazendaSelecionadaAtual),
    );
    // id > 0: pesagem já sincronizada; id < 0: ainda só existe localmente
    // (offline). Nos dois casos há itens locais a carregar; só id == 0
    // (nunca deveria acontecer neste ponto) não dispara a busca.
    //
    // reconciliar: true só aqui (abertura da tela) — confirma com o
    // servidor se algum item já sincronizado foi excluído por fora do app
    // (sistema web ou outro dispositivo) desde a última vez que este
    // aparelho olhou essa pesagem. Não passamos isso na atualização rápida
    // pós-salvar (linha ~1480) pra não acrescentar uma chamada de rede
    // extra a cada peso digitado.
    if (_idPesagemServer != 0) {
      _carregarItensDoServidor(reconciliar: true);
    }
  }

  Future<void> _carregarItensDoServidor({bool reconciliar = false}) async {
    setState(() => carregandoItensIniciais = true);
    try {
      final data = await PesagemRepository.instance.buscarPesagemCompleta(
        bd: cnpjParaBanco,
        idPesagem: _idPesagemServer,
        reconciliar: reconciliar,
      );
      if (data['success'] == true) {
        final List itensBanco = data['itens'];
        setState(() {
          _itensPesados.clear();
          for (var item in itensBanco) {
            int pesoInteiro =
                (double.tryParse(item['tbl_ite_pesagem_peso'].toString()) ??
                        0)
                    .toInt();
            _itensPesados.add({
              'id': item['tbl_ite_pesagem_codigo_id_animal'],
              'numeroItem': int.parse(
                item['tbl_ite_pesagem_numero_item'].toString(),
              ),
              'alfaNumerico': item['tbl_ite_pesagem_codigo_animal'],
              'peso': pesoInteiro.toString(),
              'sexo': item['tbl_ite_pesagem_sexo'] == 'Macho' ? 'M' : 'F',
              'nascimento': item['tbl_ite_pesagem_nascimento'],
              'raca': item['tbl_ite_pesagem_raca'],
              'pelagem': item['tbl_ite_pesagem_pelagem'],
              'maeBrinco': item['tbl_ite_pesagem_mae'],
              'obs': item['tbl_ite_pesagem_observacao'] ?? '',
              'mensRepetido': item['tbl_ite_pesagem_mens_repetido'] ?? '',
              'idPesagemRepetido':
                  item['tbl_ite_pesagem_id_repetido']?.toString() ?? '',
              'criterio': item['tbl_ite_pesagem_criterio_apartacao'] ?? '',
            });
          }
          _qtdPesado = _itensPesados.length;
          carregandoItensIniciais = false;
        });
      } else {
        setState(() => carregandoItensIniciais = false);
      }
    } catch (e) {
      setState(() => carregandoItensIniciais = false);
    }
  }

  Future<void> _buscarAnimal(String termo) async {
    if (termo.trim().isEmpty) {
      setState(() {
        infoAnimal = null;
        sugestoesAnimais = [];
        mostrandoSugestoes = false;
      });
      return;
    }
    try {
      List<dynamic> lista = await AnimalRepository.instance.buscarPorCodigo(
        termo: termo,
        local: fazendaSelecionada,
        bd: cnpjParaBanco,
      );
      if (lista.isEmpty) {
        _exibirMensagemErro("Cód $termo não encontrado!");
        _noAnimalController.clear();
        setState(() {
          sugestoesAnimais = [];
          mostrandoSugestoes = false;
        });
        return;
      }
      String formatarCodigo(String cod) {
        if (cod.contains('-')) {
          var partes = cod.split('-');
          String num = partes[1].replaceFirst(RegExp(r'^0+'), '');
          return "${partes[0]}-${num.isEmpty ? "0" : num}";
        }
        return cod.replaceFirst(RegExp(r'^0+'), '').isEmpty
            ? "0"
            : cod.replaceFirst(RegExp(r'^0+'), '');
      }

      setState(() {
        sugestoesAnimais = lista.take(6).map((item) {
          item['exibicao'] = formatarCodigo(item['codigo'].toString());
          return item;
        }).toList();
        mostrandoSugestoes =
            sugestoesAnimais.isNotEmpty &&
            _noAnimalController.text.isNotEmpty;
      });
    } catch (e) {
      debugPrint("Erro: $e");
    }
  }

  String _limparZeros(dynamic codigo) {
    if (codigo == null) return "";
    String s = codigo.toString().trim();

    // Caso 1: Formato "B-00000987" -> Transforma em "B-987"
    if (s.contains('-')) {
      List<String> partes = s.split('-');
      String prefixo = partes[0];
      String numero = partes[1].replaceFirst(RegExp(r'^0+'), '');
      if (numero.isEmpty) {
        numero = "0";
      } // Garante que não fique vazio se for "B-000"
      return "$prefixo-$numero";
    }

    // Caso 2: Formato "00000987" -> Transforma em "987"
    String limpo = s.replaceFirst(RegExp(r'^0+'), '');
    return limpo.isEmpty ? "0" : limpo;
  }

  Future<void> _buscarDetalhesAnimal(
    String idInterno, {
    bool ignorarValidacao = false,
    String? codigoFormatado,
  }) async {
    if (idInterno.isEmpty || _processandoBusca) return;
    _processandoBusca = true;

    // Limpa o código que vem por parâmetro
    if (codigoFormatado != null && codigoFormatado.isNotEmpty) {
      _noAnimalController.text = _limparZeros(codigoFormatado);
    }

    try {
      final itemLocal = sugestoesAnimais.firstWhere(
        (a) => a['id'].toString() == idInterno.toString(),
        orElse: () => {},
      );
      if (itemLocal.isNotEmpty) {
        // Limpa o código vindo da lista local de sugestões
        _noAnimalController.text = _limparZeros(itemLocal['codigo']);
      }
    } catch (_) {}

    // --- ALERTA 1: DUPLICIDADE LOCAL ---
    if (!ignorarValidacao &&
        _itensPesados.any((it) => it['id'].toString() == idInterno)) {
      String n = _noAnimalController.text; // Já está limpo aqui
      _exibirMensagemOverlay(
        "Animal $n já está na lista! Confirma?",
        isError: true,
        mostrarSimNao: true,
        onClose: () {
          _processandoBusca = false;
          _buscarDetalhesAnimal(idInterno, ignorarValidacao: true);
        },
        onCancel: () {
          setState(() {
            _noAnimalController.clear();
            infoAnimal = null;
            mostrandoSugestoes = false;
          });
          _processandoBusca = false;
          _focoNoAnimal.requestFocus();
        },
      );
      return;
    }

    setState(() {
      carregandoAnimal = true;
      mostrandoSugestoes = false;
    });

    try {
      final data = await AnimalRepository.instance.buscarDetalhes(
        id: idInterno,
        local: fazendaSelecionada,
        bd: cnpjParaBanco,
      );

      if (data.isNotEmpty) {
        if (_noAnimalController.text.isEmpty) {
          _processandoBusca = false;
          setState(() => carregandoAnimal = false);
          return;
        }

        if (_motivoSelecionadoAtual == '002' &&
            _animalInvalidoParaDesmama(data['nascimento'])) {
          setState(() {
            carregandoAnimal = false;
            _processandoBusca = false;
          });

          await _mostrarErroDesmamaERefocar();
          return;
        }
        // Alerta de "animal repetido em outro lote": checado 100% local,
        // sem depender de rede. Um animal só existe numa fazenda (nunca
        // duplicado entre locais), e os lotes em andamento daquela fazenda
        // estão sempre neste aparelho no momento da pesagem (mesmo quando
        // uma pesagem pendente é retomada depois em outro celular, os itens
        // são reimportados nele antes de continuar) — então o que já está
        // salvo localmente é a fonte de verdade, sem precisar de uma volta
        // ao servidor pra cada animal (o vaqueiro precisa de resposta
        // rápida, o bicho já está estressado na baia).
        final conflito = await PesagemRepository.instance
            .buscarLoteAbertoPorAnimal(
              idAnimal: idInterno,
              idPesagemDeTela: _idPesagemServer,
            );
        final bool temAlertaServidor = conflito != null;
        final Map<String, dynamic> dataComConflito = Map<String, dynamic>.from(
          data,
        );
        dataComConflito['loteAberto'] = conflito?['lote'];
        dataComConflito['pesagemIdLoteAberto'] = conflito?['id_servidor'];

        setState(() {
          infoAnimal = dataComConflito;
          carregandoAnimal = false;
          // Limpa o código vindo do Servidor
          if (_noAnimalController.text.isEmpty ||
              _noAnimalController.text.contains('000')) {
            _noAnimalController.text = _limparZeros(data['codigo']);
          }
        });

        if (temAlertaServidor) {
          if (_noAnimalController.text.isNotEmpty) {
            final String nMensagem = _limparZeros(data['codigo']);
            final String loteRepetido = conflito['lote'].toString().trim();

            _exibirMensagemOverlay(
              "ALERTA: Nº do Animal ($nMensagem) repetido no lote: $loteRepetido. Confirma?",
              isError: true,
              mostrarSimNao: true,
              onClose: () {
                setState(() {
                  _pesoBloqueado = false;
                  _jaConfirmouDuplicidade = true;
                });

                _processandoBusca = false;
                _focarNoPesoComDelay();
              },
              onCancel: () {
                setState(() {
                  _noAnimalController.clear();
                  infoAnimal = null;
                  mostrandoSugestoes = false;
                });
                _processandoBusca = false;
                _focoNoAnimal.requestFocus();
              },
            );
          } else {
            _processandoBusca = false;
          }
        } else {
          setState(() {
            _pesoBloqueado = false;
            _jaConfirmouDuplicidade = true;
          });
          _processandoBusca = false;
          _focarNoPesoComDelay();
        }
      } else {
        setState(() => carregandoAnimal = false);
        _processandoBusca = false;
      }
    } catch (e) {
      setState(() => carregandoAnimal = false);
      _processandoBusca = false;
    }
  }

  Future<bool> _enviarItemParaServidor(Map<String, dynamic> itemLocal) async {
    try {
      // 🔥 SEMPRE pega o usuário atualizado direto do SharedPreferences
      final prefs = await SharedPreferences.getInstance();

      final String usuarioAtual =
          prefs.getString('userName')?.trim().isNotEmpty == true
          ? prefs.getString('userName')!.trim()
          : "App User";

      debugPrint("USUÁRIO ENVIADO NA PESAGEM: $usuarioAtual");

      final body = {
        "bd": cnpjParaBanco,
        "pesagem_id": _idPesagemServer,
        "local_id": fazendaSelecionada,
        "epoca_id": motivoSelecionado,
        "lote": _descricaoLoteAtual,
        "filtro_desc":
            "${_getNomeFazenda(fazendaSelecionada)} ➔ ${motivos[motivoSelecionado]}",
        "usuario": usuarioAtual, // 👈 AQUI ESTÁ O AJUSTE PRINCIPAL
        "qtd_a_pesar": _qtdAPesarAtual,
        "criterios_lista": _listaCriteriosDinamica,
        "item": {
          "id_animal": itemLocal['id'],
          "codigo_animal": itemLocal['alfaNumerico'],
          "peso": itemLocal['peso'],
          "ultimo_peso": itemLocal['ultimoPeso'] ?? 0,
          "sexo": itemLocal['sexo'],
          "nascimento": itemLocal['nascimento'],
          "raca": itemLocal['raca'],
          "pelagem": itemLocal['pelagem'],
          "mae": itemLocal['maeBrinco'],
          "obs": itemLocal['obs'],
          "mens_repetido": itemLocal['mensRepetido'] ?? '',
          "id_pesagem_repetido": itemLocal['idPesagemRepetido'] ?? 0,
          "criterio_apartacao": itemLocal['criterio'],
        },
      };

      debugPrint("JSON ENVIADO SAVE ITEM: ${json.encode(body)}");

      final resJson = await PesagemRepository.instance.salvarItem(body);

      if (resJson['success'] == true) {
        setState(() {
          _idPesagemServer = int.parse(resJson['pesagem_id'].toString());
        });
        return true;
      }
      return false;
    } catch (e) {
      debugPrint("Erro salvar: $e");
      return false;
    }
  }

  Future<void> _excluirItemNoServidor(int numeroItem) async {
    try {
      await PesagemRepository.instance.excluirItem({
        "bd": cnpjParaBanco,
        "pesagem_id": _idPesagemServer,
        "numero_item": numeroItem,
      });
    } catch (e) {
      debugPrint("Erro ao excluir: $e");
    }
  }

  /*  Future<void> _atualizarObsItemRepetidoRemoto({
    required int pesagemIdRemota,
    required String idAnimal,
    required String mensRepetido,
    required int idPesagemRepetido,
  }) async {
    try {
      final response = await http.post(
        Uri.parse(
          "${ApiConfig.baseUrl}/rest/pesagem/update_obs_item_repetido.php",
        ),
        headers: {"Content-Type": "application/json"},
        body: json.encode({
          "bd": cnpjParaBanco,
          "pesagem_id": pesagemIdRemota,
          "id_animal": idAnimal,
          "mens_repetido": mensRepetido,
          "id_pesagem_repetido": idPesagemRepetido,
        }),
      );

      debugPrint("STATUS UPDATE OBS ITEM REPETIDO: ${response.statusCode}");
      debugPrint("BODY UPDATE OBS ITEM REPETIDO: ${response.body}");
    } catch (e) {
      debugPrint("Erro ao atualizar obs do item repetido remoto: $e");
    }
  }*/

  Future<void> _alterarItemNoServidor(
    int numeroItem,
    String peso,
    String obs,
    String criterio,
  ) async {
    try {
      final String critLimpo = criterio.trim();
      if (critLimpo.isNotEmpty &&
          !_listaCriteriosDinamica.contains(critLimpo)) {
        setState(() => _listaCriteriosDinamica.add(critLimpo));
      }
      await PesagemRepository.instance.alterarItem({
        "bd": cnpjParaBanco,
        "pesagem_id": _idPesagemServer,
        "numero_item": numeroItem,
        "peso": peso,
        "obs": obs,
        "criterio_apartacao": critLimpo,
        "criterios_lista": _listaCriteriosDinamica,
      });
    } catch (e) {
      _exibirMensagemErro("Sem resposta do servidor.");
    }
  }

  void _prepararEdicao(int index) {
    final item = _itensPesados[index];
    setState(() {
      _indexSendoEditado = index;
      _destacarCampoAnimal = false; // <- apaga a borda azul ao entrar em edição

      _noAnimalController.text = item['alfaNumerico'];
      _pesoController.text = item['peso'];
      _obsController.text = item['obs'];
      _criterioController.text = item['criterio'] ?? '';
      mostrarObs = item['obs'].toString().isNotEmpty;
      _pesoBloqueado = false;

      infoAnimal = {
        'id': item['id'],
        'sexo': item['sexo'],
        'nascimento': item['nascimento'],
        'raca': item['raca'],
        'pelagem': item['pelagem'],
        'brincoMae': item['maeBrinco'],
      };
    });

    _focoNoPeso.requestFocus();
  }

  String _getNomeFazenda(String id) {
    final fazenda = fazendasCarregadas.firstWhere(
      (f) => f['id'].toString() == id,
      orElse: () => {'nome': '...'},
    );
    return fazenda['nome'].toString().toUpperCase();
  }

  Future<void> _confirmarExclusao(int index, String identificacao) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final bool? confirmar = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text(
          "Excluir Item",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text(
          "Confirma a exclusão da pesagem do animal $identificacao?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(
              "NÃO",
              style: TextStyle(
                color: Colors.blue,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              "SIM",
              style: TextStyle(color: Colors.blue, fontSize: 16),
            ),
          ),
        ],
      ),
    );
    if (confirmar == true) {
      final itemRemovido = _itensPesados[index];

      setState(() {
        _itensPesados.removeAt(index);
        _qtdPesado--;
      });

      _limparCampos();

      if (_idPesagemServer > 0 && itemRemovido['numeroItem'] != null) {
        _excluirItemNoServidor(itemRemovido['numeroItem']);
      }
    }
  }

  void _limparCampos() {
    _noAnimalController.clear();
    _pesoController.clear();
    _sizePesoController.clear();
    _obsController.clear();
    _criterioController.clear();
    _removerTarjaPeso();

    setState(() {
      infoAnimal = null;
      _indexSendoEditado = null;
      mostrarObs = false;
      _pesoBloqueado = true;
      mostrandoSugestoes = false;
      _destacarCampoAnimal = true; // <- destaca o Nº do Animal
    });
  }

  Future<void> _executarAcaoPrincipal() async {
    if (_salvandoItem) return;

    if (!_resolverFormulaDoPeso()) return;

    if (_noAnimalController.text.isEmpty || _pesoController.text.isEmpty) {
      _exibirMensagemErro("Preencha Nº Animal e Peso!");
      return;
    }

    final String idAtual = infoAnimal?['id']?.toString() ?? "";

    if (_indexSendoEditado == null &&
        idAtual.isNotEmpty &&
        !_jaConfirmouDuplicidade &&
        _itensPesados.any((it) => it['id'].toString() == idAtual)) {
      String n = _noAnimalController.text;
      _exibirMensagemOverlay(
        "Animal2 $n já está na lista! Confirma?",
        isError: true,
        mostrarSimNao: true,
      );
      return;
    }

    setState(() {
      _salvandoItem = true;
    });

    try {
      final String critDigitado = _criterioController.text.trim();

      if (critDigitado.isNotEmpty &&
          !_listaCriteriosDinamica.contains(critDigitado)) {
        setState(() => _listaCriteriosDinamica.add(critDigitado));
      }

      FocusScope.of(context).requestFocus(FocusNode());

      if (_indexSendoEditado != null) {
        final itemOriginal = _itensPesados[_indexSendoEditado!];

        setState(() {
          _itensPesados[_indexSendoEditado!] = {
            ...itemOriginal,
            'peso': _pesoController.text,
            'obs': _obsController.text,
            'criterio': critDigitado,
          };
        });

        await _alterarItemNoServidor(
          itemOriginal['numeroItem'],
          _pesoController.text,
          _obsController.text,
          critDigitado,
        );

        _limparCampos();
        return;
      }

      int proximoNum = _itensPesados.isEmpty
          ? 1
          : _itensPesados
                    .map((e) => e['numeroItem'] as int)
                    .reduce((a, b) => a > b ? a : b) +
                1;

      // loteAberto só vem preenchido quando a checagem local (feita em
      // _buscarDetalhesAnimal) já confirmou que é OUTRA pesagem em aberto —
      // não precisa comparar nome de lote aqui de novo.
      final bool animalRepetido =
          infoAnimal?['loteAberto'] != null &&
          infoAnimal!['loteAberto'].toString().trim().isNotEmpty;

      final String mensRepetido = animalRepetido
          ? 'Repetido em: ${infoAnimal?['loteAberto'].toString().trim() ?? ''}'
          : '';

      final int idPesagemRepetido = animalRepetido
          ? int.tryParse(
                  infoAnimal?['pesagemIdLoteAberto']?.toString() ?? '0',
                ) ??
                0
          : 0;

      final dados = {
        'id': infoAnimal?['id'],
        'numeroItem': proximoNum,
        'alfaNumerico': _noAnimalController.text,
        'peso': _pesoController.text,
        'ultimoPeso': infoAnimal?['ultimoPeso'] ?? 0,
        'sexo': (infoAnimal?['sexo'] == 'M' || infoAnimal?['sexo'] == 'Macho')
            ? 'M'
            : 'F',
        'nascimento': infoAnimal?['nascimento'] ?? '--',
        'raca': infoAnimal?['raca'] ?? '',
        'pelagem': infoAnimal?['pelagem'] ?? '',
        'maeBrinco': infoAnimal?['brincoMae'] ?? 'Não inf.',
        'obs': _obsController.text,
        'mensRepetido': mensRepetido,
        'idPesagemRepetido': idPesagemRepetido,
        'criterio': critDigitado,
      };
      setState(() {
        _itensPesados.insert(0, dados);
        _qtdPesado++;
      });

      final bool salvou = await _enviarItemParaServidor(dados);

      if (!salvou) {
        setState(() {
          _itensPesados.remove(dados);
          _qtdPesado--;
        });

        _exibirMensagemErro(
          "Não foi possível salvar a pesagem. Tente novamente.",
        );
        return;
      }

      if (_idPesagemServer > 0) {
        await _carregarItensDoServidor();
      }

      int limite = int.tryParse(_qtdAPesarAtual) ?? 0;
      if (!_mensagemLimiteExibida && limite > 0 && _qtdPesado > limite) {
        _mensagemLimiteExibida = true;
        _exibirMensagemOverlay(
          "Qtde de Animais Pesados maior que Qtde de Animais a Pesar",
        );
      }

      _limparCampos();
    } finally {
      if (mounted) {
        setState(() {
          _salvandoItem = false;
        });
      }
    }
  }

  int _calcularPesoTotal() {
    int total = 0;
    for (var item in _itensPesados) {
      total += int.tryParse(item['peso'].toString()) ?? 0;
    }
    return total;
  }

  void _exibirModalResumoApartacao() {
    Map<String, int> contagem = {};
    for (var crit in _listaCriteriosDinamica) {
      contagem[crit] = 0;
    }
    for (var item in _itensPesados) {
      String apartacao = item['criterio'].toString().trim();
      if (apartacao.isNotEmpty) {
        contagem[apartacao] = (contagem[apartacao] ?? 0) + 1;
      }
    }
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Center(
          child: Text(
            "Quantidade de Animais por Apartação",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: _listaCriteriosDinamica.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              String crit = _listaCriteriosDinamica[index];
              int total = contagem[crit] ?? 0;
              return ListTile(
                dense: true,
                title: Text(
                  crit,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                trailing: Text(
                  total.toString(),
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.blue,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              );
            },
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool camposLiberados = infoAnimal != null && !_pesoBloqueado;
    // O campo Peso nunca abre o teclado do sistema (TecladoPesoWidget cobre
    // esse papel) — por isso tecladoVisivel também considera o foco nele,
    // pra esconder o rodapé do jeito que já acontecia com o teclado nativo.
    final bool mostrarTecladoPeso = _focoPesoAtivo && camposLiberados;
    bool tecladoVisivel =
        MediaQuery.of(context).viewInsets.bottom > 0 || mostrarTecladoPeso;
    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: false,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(45.0),
        child: AppBar(
          backgroundColor: const Color(0xFF18385F),
          foregroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, size: 24),
            onPressed: widget.onBack,
          ),
          title: const Text('Pesagem', style: TextStyle(fontSize: 18)),
          actions: const [
            IndicadorConectividadeWidget(),
            SizedBox(width: 4),
          ],
        ),
      ),
      body: SafeArea(
        child: GestureDetector(
          onTap: () {
            FocusScope.of(context).unfocus();

            setState(() {
              mostrandoSugestoes = false;

              if (_indexSendoEditado == null && _pesoBloqueado) {
                _destacarCampoAnimal = true;
              }
            });
          },
          child: Column(
            children: [
              FormularioPesagemTopoWidget(
                filtroAtivoWidget: FiltroAtivoPesagemWidget(
                  nomeFazenda: _getNomeFazenda(_fazendaSelecionadaAtual),
                  nomeMotivo: motivos[_motivoSelecionadoAtual] ?? '',
                  descricaoLote: _descricaoLoteAtual,
                  qtdAPesar: _qtdAPesarAtual,
                  itensPesadosVazio: _itensPesados.isEmpty,
                  onEditarTap: _abrirModalEdicaoPesagem,
                ),
                indexSendoEditado: _indexSendoEditado,
                noAnimalController: _noAnimalController,
                focoNoAnimal: _focoNoAnimal,
                carregandoAnimal: carregandoAnimal,

                onNoAnimalChanged: (val) {
                  if (_indexSendoEditado != null) return;

                  _debounce?.cancel();
                  _debounce = Timer(
                    const Duration(milliseconds: 400),
                    () => _buscarAnimal(val),
                  );

                  _timerTeclado?.cancel();
                  if (val.isNotEmpty) {
                    _timerTeclado = Timer(const Duration(seconds: 2), () {
                      if (mounted && _focoNoAnimal.hasFocus) {
                        FocusScope.of(context).unfocus();
                      }
                    });
                  }
                },

                mostrandoSugestoes: mostrandoSugestoes,
                sugestoesAnimais: sugestoesAnimais,
                itensPesados: _itensPesados,

                onSugestaoTap: (animal) {
                  final String idSel = animal['id'].toString();
                  final String n = animal['exibicao'] ?? animal['codigo'];
                  final dynamic nascimento = animal['nascimento'];

                  setState(() {
                    _noAnimalController.text = n;
                    mostrandoSugestoes = false;
                  });

                  if (_motivoSelecionadoAtual == '002' &&
                      _animalInvalidoParaDesmama(nascimento)) {
                    setState(() {
                      infoAnimal = null;
                      _pesoController.clear();
                      _pesoBloqueado = true;
                      mostrandoSugestoes = false;
                    });

                    _mostrarErroDesmamaERefocar();
                    return;
                  }

                  if (_itensPesados.any((it) => it['id'].toString() == idSel)) {
                    _exibirMensagemOverlay(
                      "Animal3 $n já está na lista! Confirma?",
                      isError: true,
                      mostrarSimNao: true,
                      onClose: () {
                        setState(() {
                          _noAnimalController.text = n;
                          _pesoBloqueado = false;
                          _jaConfirmouDuplicidade = true;
                        });
                        _buscarDetalhesAnimal(
                          idSel,
                          ignorarValidacao: true,
                          codigoFormatado: n,
                        );
                      },
                      onCancel: () {
                        setState(() {
                          _noAnimalController.clear();
                          infoAnimal = null;
                          _pesoController.clear();
                          mostrandoSugestoes = false;
                        });
                        _focoNoAnimal.requestFocus();
                        return;
                      },
                    );
                  } else {
                    _buscarDetalhesAnimal(idSel, ignorarValidacao: true);
                  }
                },

                infoAnimal: infoAnimal,
                pesoBloqueado: _pesoBloqueado,
                camposLiberados: camposLiberados,
                pesoController: _pesoController,
                focoNoPeso: _focoNoPeso,

                observacaoToggleWidget: ObservacaoTogglePesagemWidget(
                  habilitado: camposLiberados,
                  campoApartacao: InputApartacaoPesagemWidget(
                    habilitado: camposLiberados,
                    criterioController: _criterioController,
                    focoNoCriterio: _focoNoCriterio,
                    listaCriteriosDinamica: _listaCriteriosDinamica,
                    corDoRotulo: corDoRotulo,
                    onAbrirLista: _abrirListaCriteriosApartacao,
                  ),
                  mostrarObs: mostrarObs,
                  obsController: _obsController,
                  focoNaObs: _focoNaObs,
                  corDoRotulo: corDoRotulo,
                  onToggleObs: () {
                    if (!camposLiberados) return;

                    setState(() => mostrarObs = !mostrarObs);

                    if (mostrarObs) {
                      Future.delayed(const Duration(milliseconds: 100), () {
                        if (_focoNaObs.canRequestFocus) {
                          _focoNaObs.requestFocus();
                        }
                      });
                    }
                  },
                ),

                infoAnimalCardWidget: InfoAnimalCardWidget(
                  infoAnimal: infoAnimal,
                ),

                confirmButtonWidget: ConfirmButtonPesagemWidget(
                  indexSendoEditado: _indexSendoEditado,
                  onConfirmar: _executarAcaoPrincipal,
                  onVoltar: _limparCampos,
                  carregando: _salvandoItem,
                ),

                corDoRotulo: corDoRotulo,

                destacarCampoAnimal: _destacarCampoAnimal,

                mostrarCursorFake:
                    _destacarCampoAnimal && _indexSendoEditado == null,

                onTapNoAnimal: () {
                  setState(() {
                    _destacarCampoAnimal = false;
                  });
                },
              ),
              ResumoPesagemWidget(
                qtdPesado: _qtdPesado,
                pesoTotal: _calcularPesoTotal(),
              ),
              Expanded(
                child: carregandoItensIniciais
                    ? const Center(child: CircularProgressIndicator())
                    : _itensPesados.isEmpty
                    ? Center(
                        child: Text(
                          "Nenhum animal pesado",
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      )
                    : ListaItensPesagem(
                        itensPesados: _itensPesados,
                        indexSendoEditado: _indexSendoEditado,
                        itemExpandidoIndex: _itemExpandidoIndex,
                        onEditar: (index) {
                          _prepararEdicao(index);
                        },
                        onExcluir: (index, identificacao) {
                          _confirmarExclusao(index, identificacao);
                        },
                        onExpansionChanged: (index) {
                          setState(() => _itemExpandidoIndex = index);
                        },
                      ),
              ),
              if (!tecladoVisivel && !mostrandoSugestoes)
                RodapeApartacaoWidget(
                  onFiltroApartacaoTap: _exibirModalResumoApartacao,
                  onConsultarMaeTap: () {
                    showDialog(
                      context: context,
                      builder: (context) => PesagemConsultaMaeModal(
                        cnpj: cnpjParaBanco ?? "",
                        fazendaAtualNome: _getNomeFazenda(fazendaSelecionada),
                        onFilhoSelecionado: (idAnimal, codigoAnimal) {
                          Future.delayed(
                            const Duration(milliseconds: 250),
                            () async {
                              if (!mounted) return;

                              setState(() {
                                infoAnimal = null;
                                _noAnimalController.text = _limparZeros(
                                  codigoAnimal,
                                );
                                _pesoController.clear();
                                mostrandoSugestoes = false;
                                _pesoBloqueado = true;
                                _removerTarjaPeso();
                              });

                              await _buscarDetalhesAnimal(idAnimal);
                            },
                          );
                        },
                      ),
                    );
                  },
                ),
              if (mostrarTecladoPeso)
                TecladoPesoWidget(
                  onCaractere: _inserirCaracterePeso,
                  onApagar: _apagarCaracterePeso,
                  onConfirmar: _confirmarTecladoPeso,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// Ultima versao: 16/03/2026 08:07
